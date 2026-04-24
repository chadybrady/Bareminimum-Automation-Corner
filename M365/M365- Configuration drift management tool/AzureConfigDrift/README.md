# 🔄 Azure Config Drift

Detects **configuration drift** across Microsoft Entra ID and Intune by taking snapshots, promoting a snapshot to a baseline, and then comparing future snapshots against that baseline. Supports interactive use, unattended/scheduled execution, and Azure Automation Runbooks via Managed Identity.

---

## 📄 Script

### `AzureConfigDrift.ps1`

| Mode | Description |
|---|---|
| `Snapshot` | Collect current state from selected endpoints and export to JSON |
| `SetBaseline` | Promote a snapshot run as the approved golden configuration |
| `CheckDrift` | Compare current state against a baseline and produce a drift report |
| `ListBaselines` | List available baselines (local + Azure Blob if configured) |

### Endpoints collected

| Endpoint | Area | What is captured |
|---|---|---|
| `EntraCA` | Entra ID | Conditional Access policies |
| `EntraDirectoryRoles` | Entra ID | Directory roles, assignments, PIM eligibility |
| `EntraEnterpriseApps` | Entra ID | Enterprise apps, app role assignments, OAuth2 grants |
| `EntraAuthMethods` | Entra ID | Authentication methods policy, named locations, authorization policy |
| `IntuneDeviceConfig` | Intune | Device configurations (legacy profiles + Settings Catalog) |
| `IntuneCompliance` | Intune | Compliance policies |
| `IntuneAppProtection` | Intune | App protection policies |
| `IntuneScripts` | Intune | Scripts and health scripts |
| `IntuneEnrollment` | Intune | Enrollment configurations |
| `IntuneAppAssignments` | Intune | App assignments |
| `IntuneSecurityBaselines` | Intune | Security baselines |

---

## ⚙️ Prerequisites

- **PowerShell 7.0+** (required)
- **Microsoft.Graph.Authentication** module — `Install-Module Microsoft.Graph.Authentication`
- **Az.Accounts** module (required for Managed Identity / Azure Automation) — `Install-Module Az.Accounts`
- **Az.Storage** module (required for Azure Blob upload) — `Install-Module Az.Storage`

### Required Microsoft Graph Permissions

| Permission | Required For |
|---|---|
| `Policy.Read.All` | Conditional Access, authorization policy |
| `RoleManagement.Read.Directory` | Directory roles and PIM |
| `Application.Read.All` | Enterprise apps |
| `Directory.Read.All` | General directory data |
| `DeviceManagementConfiguration.Read.All` | Intune device configs and compliance |
| `DeviceManagementApps.Read.All` | App protection and assignments |
| `DeviceManagementServiceConfig.Read.All` | Enrollment configurations |
| `DeviceManagementManagedDevices.Read.All` | Managed device data |
| `DeviceManagementScripts.Read.All` | Intune scripts |
| `AuditLog.Read.All` | Audit data for `ModifiedBy` field (optional, `-IncludeAuditData`) |

---

## 🚀 Usage

### Interactive (local)

```powershell
# Open an interactive menu — sign in via browser
.\AzureConfigDrift.ps1

# Use device code for headless / SSH sessions
.\AzureConfigDrift.ps1 -AuthMethod DeviceCode

# Target a specific tenant
.\AzureConfigDrift.ps1 -TenantId '00000000-0000-0000-0000-000000000000'
```

### Non-interactive (unattended / scheduled)

```powershell
# Take a snapshot of all endpoints
.\AzureConfigDrift.ps1 -Mode Snapshot -Unattended

# Promote a snapshot to baseline
.\AzureConfigDrift.ps1 -Mode SetBaseline -BaselineName 'April-2025' -BaselineDescription 'Post-hardening baseline' -Unattended

# Check for drift against a named baseline
.\AzureConfigDrift.ps1 -Mode CheckDrift -BaselineName 'April-2025' -Unattended

# Snapshot only selected endpoints
.\AzureConfigDrift.ps1 -Mode Snapshot -Endpoints EntraCA,IntuneCompliance -Unattended

# Upload snapshot to Azure Blob Storage
.\AzureConfigDrift.ps1 -Mode Snapshot -UploadToBlob -StorageAccountName 'mystorage' -Unattended
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `-Mode` | *(interactive menu)* | `Snapshot`, `SetBaseline`, `CheckDrift`, or `ListBaselines` |
| `-OutputPath` | `.\AzureConfigDrift` | Root folder for run output and local baselines |
| `-Endpoints` | *(all)* | Comma-separated list of endpoint names to include |
| `-BaselineName` | — | Baseline name for `SetBaseline` (save) or `CheckDrift` (load) |
| `-BaselineDescription` | `''` | Description stored in `baseline-meta.json` when setting a baseline |
| `-UploadToBlob` | `$false` | Upload the current run/baseline to Azure Blob Storage |
| `-StorageAccountName` | — | Azure Storage account name (required with `-UploadToBlob`) |
| `-ContainerName` | `drift-management` | Blob container name |
| `-Unattended` | `$false` | Suppress all interactive prompts; fail on missing required params |
| `-ManagedIdentityClientId` | — | Client ID of a user-assigned Managed Identity (omit for system-assigned) |
| `-AuthMethod` | `Interactive` | `Interactive` (browser) or `DeviceCode` (headless) |
| `-TenantId` | — | Entra tenant ID (useful for multi-tenant accounts) |
| `-IncludeAuditData` | `$false` | Populate `ModifiedBy` in drift rows using Entra and Intune audit logs |

---

## 📄 Output

All output is written under the `-OutputPath` folder (default: `.\AzureConfigDrift`):

```
AzureConfigDrift\
  runs\
    <timestamp>\
      EntraCA.json
      IntuneCompliance.json
      ... (one file per collected endpoint)
  baselines\
    <BaselineName>\
      baseline-meta.json
      EntraCA.json
      ...
  drift-reports\
    <timestamp>-vs-<BaselineName>.csv
```

---

## 🛡️ Notes

- The script is **read-only** — it does not make any changes to your Entra ID or Intune environment.
- When running as an **Azure Automation Runbook**, the script auto-detects the runbook context and authenticates via Managed Identity. Assign the required Graph API app roles to the Managed Identity and grant **Storage Blob Data Contributor** on the target storage account.
- PIM eligible assignment collection requires an **Entra ID P2** license. The script skips PIM collection gracefully if P2 is not available.

---

## 🔗 Related Links

- [Microsoft Graph PowerShell Authentication](https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands)
- [Azure Automation Managed Identity](https://learn.microsoft.com/en-us/azure/automation/enable-managed-identity-for-automation-account)
- [Intune Security Baselines](https://learn.microsoft.com/en-us/mem/intune/protect/security-baselines)
- [Conditional Access Overview](https://learn.microsoft.com/en-us/entra/identity/conditional-access/overview)
