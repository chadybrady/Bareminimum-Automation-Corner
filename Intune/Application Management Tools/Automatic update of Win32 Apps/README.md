# Win32 App Update Automation

Automated monthly update pipeline for Intune Win32 apps.  
Combines Azure Automation runbooks, Power Automate flows, and a SharePoint list to detect, approve, and deploy app updates with minimal manual effort.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  DETECTION                                                                  │
│                                                                             │
│  [Winget apps]                      [Manual apps]                           │
│  Monthly recurrence trigger         File upload to Azure Blob Storage       │
│         │                                    │                              │
│         ▼                                    ▼                              │
│  Check-Win32AppVersions.ps1         Azure Event Grid (blob created)         │
│  (Azure Automation Runbook)                  │                              │
│         │                                    │                              │
│         └──────────────┬───────────────────┘                               │
│                         ▼                                                   │
│              SharePoint List: Win32-App-Updates                             │
│              Status → "Pending Approval"                                    │
└─────────────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  APPROVAL                                                                   │
│                                                                             │
│  Power Automate Flow 1a / 1b                                                │
│  ├── Teams adaptive card (Approve / Reject)                                 │
│  └── Email summary to team                                                  │
│                                                                             │
│  On Approve → Status = "Approved"                                           │
│  On Reject  → Status = "Rejected"  (no deployment)                         │
└─────────────────────────────────────────────────────────────────────────────┘
                          │ Approved
                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  DEPLOYMENT                                                                 │
│                                                                             │
│  Power Automate Flow 2                                                      │
│  └── Starts Deploy-Win32AppUpdate.ps1 (Azure Automation Runbook)           │
│                                                                             │
│  Winget path  : Download installer → IntuneWinAppUtil.exe → .intunewin     │
│  Manual path  : Download .intunewin from Blob Storage                      │
│                                                                             │
│  Upload new content version to Intune Win32LobApp via Graph API            │
│  Update SharePoint list → Status = "Deployed"                              │
│                                                                             │
│  ├── Success → Teams message + Email "✓ [App] updated to [version]"        │
│  └── Failure → Teams message + Email "✗ [App] deployment failed"           │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

| Resource | Details |
|---|---|
| Azure Automation Account | PS7 runtime, System-Assigned Managed Identity enabled |
| Azure Blob Storage | One container (e.g. `win32-packages`) |
| Azure Event Grid | System topic on the Blob Storage account |
| SharePoint Online | A site with a list named `Win32-App-Updates` |
| Power Automate | Premium connectors: Azure Automation, SharePoint, Teams, Outlook |
| Entra | Managed Identity assigned Graph app roles (see below) |

### Managed Identity — Graph API app roles

Assign these **application** permissions to the Automation Account's System-Assigned Managed Identity:

```
Sites.ReadWrite.All
DeviceManagementApps.ReadWrite.All
```

To assign in the portal: **Entra ID → Enterprise Applications → [Your Automation Account name] → Permissions → Grant admin consent**

Or via PowerShell:

```powershell
Connect-MgGraph -Scopes 'AppRoleAssignment.ReadWrite.All', 'Application.Read.All'

$mi          = Get-MgServicePrincipal -Filter "displayName eq '<AutomationAccountName>'"
$graphSp     = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

foreach ($roleName in @('Sites.ReadWrite.All', 'DeviceManagementApps.ReadWrite.All')) {
    $role = $graphSp.AppRoles | Where-Object { $_.Value -eq $roleName }
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $mi.Id -PrincipalId $mi.Id `
        -ResourceId $graphSp.Id -AppRoleId $role.Id
}
```

### Managed Identity — Azure RBAC

Assign **Storage Blob Data Reader** on the Blob Storage container to the Managed Identity.  
Portal: Storage account → Access Control (IAM) → Add role assignment

### Automation Account modules

Install these modules in the Automation Account (**Modules → Browse gallery**):

- `Microsoft.Graph.Authentication`

---

## SharePoint List Setup

Create a list named **`Win32-App-Updates`** with the following columns:

| Column name | Type | Notes |
|---|---|---|
| `Title` | Single line of text | Rename to `AppName` or use as display name |
| `AppName` | Single line of text | Friendly display name |
| `IntuneAppId` | Single line of text | Graph ID of the existing Win32LobApp in Intune |
| `Source` | Choice | Choices: `Winget`, `Manual` |
| `WingetPackageId` | Single line of text | Format: `Publisher.PackageName` e.g. `Mozilla.Firefox` |
| `ManualPackageUrl` | Single line of text | Azure Blob SAS URL to the .intunewin file (set automatically by Flow 1b) |
| `CurrentVersion` | Single line of text | Last successfully deployed version |
| `AvailableVersion` | Single line of text | Detected new version (set automatically) |
| `Status` | Choice | Choices: `Active`, `Pending Approval`, `Approved`, `Rejected`, `Deploying`, `Deployed`, `Failed` |
| `InstallCommand` | Single line of text | Silent install command e.g. `setup.exe /S` or `msiexec /i app.msi /qn` |
| `UninstallCommand` | Single line of text | Silent uninstall command |
| `Architecture` | Choice | Choices: `x64`, `x86`, `Neutral` (default: `x64`) |
| `AssignmentGroupId` | Single line of text | Entra group object ID for the Intune assignment |
| `ApprovedBy` | Person or Group | Filled in by the approval flow |
| `Notes` | Multiple lines of text | Error messages and operator notes |
| `LastUpdated` | Date and Time | Include Time, set to ISO 8601 format |

> **Tip:** Set all new items to `Status = Active` by default.

---

## Azure Blob Storage Setup

1. Create a container in your storage account, e.g. `win32-packages`
2. Create two folders inside it:
   - `tools/` — pre-stage `IntuneWinAppUtil.exe` here  
     Download from: https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/releases
   - `manual/` — upload manual `.intunewin` packages here (see naming convention below)

### Naming convention for manual uploads

Files must follow this exact pattern:

```
{AppName}_{Version}.intunewin
```

Examples:
```
SevenZip_24.09.intunewin
AdobeReader_24.002.20759.intunewin
Notepad++_8.7.1.intunewin
```

**`AppName` must match the `AppName` column in the SharePoint list exactly (case-insensitive).**

---

## Azure Automation Setup

### Import the runbooks

1. In the Automation Account, go to **Runbooks → Import a runbook**
2. Import `Check-Win32AppVersions.ps1` — Runtime: PowerShell 7.2
3. Import `Deploy-Win32AppUpdate.ps1` — Runtime: PowerShell 7.2
4. Publish both runbooks

### Create Automation Variables

Go to **Shared Resources → Variables** and create the following (all String type, not encrypted):

| Variable name | Value |
|---|---|
| `Win32Updates_TenantId` | Your Entra tenant ID (GUID) |
| `Win32Updates_SharePointSiteId` | SharePoint site ID (GUID) |
| `Win32Updates_ListId` | SharePoint list ID (GUID) |
| `Win32Updates_StorageAccountName` | Storage account name (not the full URL) |
| `Win32Updates_ContainerName` | Container name e.g. `win32-packages` |

**To find the SharePoint site ID:**
```
GET https://graph.microsoft.com/v1.0/sites/{hostname}:/sites/{siteName}
```
Use [Graph Explorer](https://developer.microsoft.com/en-us/graph/graph-explorer) with your tenant credentials.

**To find the SharePoint list ID:**
```
GET https://graph.microsoft.com/v1.0/sites/{siteId}/lists?$filter=displayName eq 'Win32-App-Updates'
```

---

## Power Automate Flows

### Flow 1a — Monthly Winget Check + Approval

**Trigger:** Recurrence — 1st of each month at 08:00

**Steps:**

1. **Recurrence** trigger — Interval: 1, Frequency: Month, Start: first day at 08:00
2. **Azure Automation — Create job** — Automation Account: [your account], Runbook: `Check-Win32AppVersions`, Wait for job: Yes
3. **Azure Automation — Get job output** — Job ID: from step 2
4. **Parse JSON** — Content: job output, Schema: array of `{ AppName, WingetPackageId, CurrentVersion, AvailableVersion, ListItemId }`
5. **Apply to each** (loop over parsed apps):
   - **Post adaptive card in a chat or channel (Teams)** — include AppName, CurrentVersion, AvailableVersion, and Approve/Reject action buttons
   - **Send an email (Outlook)** — Subject: `[Action Required] Win32 App Update: {AppName}`, Body: version details + link to SharePoint list
   - **Condition** — if Teams response = Approved:
     - **SharePoint — Update item** — Status: `Approved`, ApprovedBy: responding user
   - Else:
     - **SharePoint — Update item** — Status: `Rejected`

---

### Flow 1b — Blob Upload Detection + Approval

**Trigger:** When a resource event occurs (Event Grid) — Event type: `Microsoft.Storage.BlobCreated`, Filter suffix: `.intunewin`

> **Setup:** In Azure, go to the Storage account → Events → Create Event Subscription.  
> Endpoint type: Web Hook → provide the Power Automate HTTP trigger URL.

**Steps:**

1. **HTTP** trigger (or Event Grid connector trigger)
2. **Parse JSON** — parse the event body to extract `subject` (blob path)
3. **Compose** — extract filename from subject: `last(split(triggerBody()?['subject'], '/'))`
4. **Compose** — extract AppName: `first(split(outputs('Filename'), '_'))`
5. **Compose** — extract Version: `replace(last(split(outputs('Filename'), '_')), '.intunewin', '')`
6. **Compose** — build full Blob URL from event data
7. **SharePoint — Get items** — filter: `AppName eq '{AppName}'` (case-insensitive)
8. **Condition** — if item found:
   - **SharePoint — Update item** — AvailableVersion, ManualPackageUrl (blob URL), Status: `Pending Approval`
   - **Post adaptive card in Teams** — AppName, version details, Approve/Reject buttons
   - **Send email** — same as Flow 1a
   - **Condition** — Approve/Reject → update Status accordingly
9. Else:
   - **Send email** — "No matching app found in SharePoint list for filename {filename}"

---

### Flow 2 — Deploy on Approval + Notify

**Trigger:** SharePoint — When an item is modified — List: `Win32-App-Updates`

**Steps:**

1. **SharePoint — When an item is modified** trigger — List: `Win32-App-Updates`
2. **Condition** — if `Status` equals `Approved`:
3. **SharePoint — Update item** — Status: `Deploying`
4. **Azure Automation — Create job** — Runbook: `Deploy-Win32AppUpdate`, Parameters: `ListItemId` = modified item ID, Wait for job: Yes
5. **Azure Automation — Get job output** — Job ID: from step 4
6. **Parse JSON** — parse output: `{ Success, AppName, DeployedVersion, Error, ListItemId }`
7. **Condition** — if `Success` equals `true`:
   - **Post message in Teams** — `✓ {AppName} updated to version {DeployedVersion}`
   - **Send email** — Subject: `✓ Win32 App Deployed: {AppName} {DeployedVersion}`
8. Else:
   - **Post message in Teams** — `✗ {AppName} deployment failed: {Error}`
   - **Send email** — Subject: `✗ Win32 App Deployment Failed: {AppName}`, Body: error details + link to SharePoint item

---

## Adding a New App

### Winget-sourced app

1. Open the SharePoint list `Win32-App-Updates`
2. Add a new row:
   - **AppName**: friendly name (must match future file uploads if you ever switch to Manual)
   - **IntuneAppId**: copy from Intune portal → App → Properties → Graph ID (or use Graph Explorer)
   - **Source**: `Winget`
   - **WingetPackageId**: find with `winget search <appname>` e.g. `Mozilla.Firefox`
   - **InstallCommand**: e.g. `setup.exe /S` or `msiexec /i app.msi /qn REBOOT=ReallySuppress`
   - **UninstallCommand**: silent uninstall command
   - **Architecture**: `x64` (default)
   - **AssignmentGroupId**: Entra group GUID for the Intune deployment target
   - **Status**: `Active`
3. The next monthly run will detect the current version and begin the cycle

**To find the current version to pre-fill CurrentVersion:**  
Run `winget show <WingetPackageId>` locally, or leave it blank — the first run will mark it as Pending Approval and deploy the latest version.

### Manual-sourced app

1. Package the app with IntuneWinAppUtil.exe:
   ```
   IntuneWinAppUtil.exe -c .\SetupFolder -s setup.exe -o .\Output
   ```
2. Rename the output: `{AppName}_{Version}.intunewin` (must match SharePoint AppName exactly)
3. Upload to the `manual/` folder in the Blob Storage container
4. Flow 1b triggers automatically, finds the matching SharePoint row, and starts the approval process

> If the SharePoint row does not exist yet, add it first (steps same as Winget but Source = `Manual`).

---

## Troubleshooting

### Approval card not appearing in Teams

- Check Flow 1a/1b run history in Power Automate for errors
- Verify the runbook job completed — check **Azure Automation → Jobs**
- Confirm the job output stream contains valid JSON (not an empty string)

### Deployment fails with "azureStorageUri" timeout

- The Intune Graph API is occasionally slow to provision upload URIs
- The script waits 60 seconds max. If this is consistently failing, check Intune service health
- Check the Automation job output stream for the exact error

### "commitFileFailed" error

- Usually a mismatch between the encryption metadata in Detection.xml and the actual file
- Re-create the .intunewin using IntuneWinAppUtil.exe and upload again
- Ensure IntuneWinAppUtil.exe in Blob Storage is the latest release

### Winget version lookup returns wrong/old version

- The GitHub winget-pkgs repo can lag a few days behind official releases
- For critical updates, override by using the Manual path: package the new version yourself and upload to Blob

### IntuneAppId is wrong / app not found

- Go to Intune portal → Apps → Windows apps → select the app → copy the app ID from the URL
- Format: `https://intune.microsoft.com/.../apps/{AppId}`

### SharePoint filter returns no items

- OData filter is case-sensitive for choice columns — ensure `Status`, `Source` values match exactly
- Check that the Managed Identity has `Sites.ReadWrite.All` assigned

---

## Graph API Permissions Reference

| Permission | Runbook | Purpose |
|---|---|---|
| `Sites.ReadWrite.All` | Both | Read and update SharePoint list items |
| `DeviceManagementApps.ReadWrite.All` | Deploy only | Create content versions, upload packages to Intune |
