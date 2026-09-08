# 🔄 Azure Configuration Drift

> Capture Microsoft Entra ID, Intune, SharePoint, OneDrive, Microsoft 365 Group governance, Teams tenant policies, and Microsoft security posture data; promote approved snapshots to baselines and report unauthorized or unintended drift.

> The Microsoft 365 collectors are tenant-policy focused. They capture the settings that govern all groups, Teams, SharePoint sites, and OneDrive accounts, without enumerating individual resources.

Supports interactive menu-driven use, fully unattended/scheduled execution, and native Azure Automation Runbook deployment via Managed Identity.


---

## 📂 Contents

| Item | Description |
|---|---|
| [`AzureConfigDrift.ps1`](./AzureConfigDrift.ps1) | Captures configuration snapshots and detects drift across Entra ID and Intune. |

## 📋 Contents

- [Modes](#-modes)
- [Coverage — What is collected](#-coverage--what-is-collected)
- [Parameters](#-parameters)
- [Prerequisites](#-prerequisites)
- [Drift Detection Logic](#-drift-detection-logic)
- [Output Files](#-output-files)
- [Folder Structure](#-folder-structure)
- [Usage Examples](#-usage-examples)
- [Azure Automation Runbook](#-azure-automation-runbook)
- [Known Limitations](#-known-limitations)
- [Contributing / Author](#-contributing--author)

---

## 🗂 Modes

| Mode | Description |
|---|---|
| `Snapshot` | Collect the current state from selected endpoints and export to JSON |
| `SetBaseline` | Promote a snapshot run as the approved golden configuration |
| `CheckDrift` | Compare the current state against a baseline; produce `DriftReport.json` and `DriftReport.csv` |
| `ListBaselines` | List all saved baselines (local and Azure Blob Storage) |

> When the script is run **without** a `-Mode` parameter, an interactive numbered menu is presented so the user can choose mode and options at runtime.

---

## 📡 Coverage — What is collected

| Endpoint key | Area | What is captured |
|---|---|---|
| `EntraCA` | Entra ID | Conditional Access policies — all settings, conditions, grant controls, and session controls |
| `EntraDirectoryRoles` | Entra ID | Directory role definitions, active assignments, and PIM eligible assignments |
| `EntraEnterpriseApps` | Entra ID | Service principals, app role assignments, and OAuth2 permission grants |
| `EntraAuthMethods` | Entra ID | Authentication Methods Policy, Named Locations, and Authorization Policy |
| `IntuneDeviceConfig` | Intune | Legacy device configuration profiles **and** Settings Catalog policies (full setting instances fetched per policy) |
| `IntuneCompliance` | Intune | Compliance policies |
| `IntuneAppProtection` | Intune | App protection (MAM) policies |
| `IntuneScripts` | Intune | Device management scripts and health scripts |
| `IntuneEnrollment` | Intune | Device enrollment configurations |
| `IntuneAppAssignments` | Intune | All mobile apps and their group assignments |
| `IntuneSecurityBaselines` | Intune | Security baseline intents with full per-setting values |
| `IntuneFeatureUpdateProfiles` | Intune | Windows Feature Update profiles and their group assignments |
| `IntuneQualityUpdateProfiles` | Intune | Windows Quality Update profiles and their group assignments |
| `SharePointOneDriveTenantSettings` | SharePoint / OneDrive | Tenant-level SharePoint and OneDrive settings |
| `M365GroupGovernance` | Microsoft 365 | Tenant-wide `Group.Unified*` directory settings and group lifecycle policies; does not enumerate individual groups |
| `TeamsTenantPolicies` | Microsoft Teams | Tenant configuration and all available `Get-CsTeams*Policy` / `Get-CsTeams*Configuration` policy objects, plus core tenant and external-access settings; does not enumerate individual Teams |
| `DefenderSecurityPosture` | Microsoft Defender | Microsoft Secure Score control profiles and each control's state metadata; this is security posture, not a full Defender product-policy export |

`IntuneDeviceConfig`, `IntuneCompliance`, `IntuneAppProtection`, `IntuneScripts`, `IntuneEnrollment`, and `IntuneSecurityBaselines` now also include their group/filter assignment objects. This detects targeting changes in addition to policy-content changes.

---

## ⚙️ Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Mode` | String | *(interactive menu)* | `Snapshot`, `SetBaseline`, `CheckDrift`, or `ListBaselines` |
| `-OutputPath` | String | `.\AzureConfigDrift` | Root folder for run output and local baselines |
| `-Endpoints` | String[] | *(all)* | Subset of endpoint keys to collect (comma-separated) |
| `-BaselineName` | String | — | Name for `SetBaseline` (save) or `CheckDrift` (load) |
| `-BaselineDescription` | String | — | Description stored in baseline metadata |
| `-UploadToBlob` | Switch | — | Upload the current run or baseline to Azure Blob Storage |
| `-StorageAccountName` | String | — | Storage account name (required with `-UploadToBlob`) |
| `-ContainerName` | String | `drift-management` | Blob container name |
| `-Unattended` | Switch | — | Suppress all prompts; fail on missing required parameters |
| `-ManagedIdentityClientId` | String | — | Client ID for a user-assigned Managed Identity |
| `-AuthMethod` | String | `Interactive` | `Interactive` (browser pop-up), `DeviceCode` (headless/SSH), or `ClientCredentials` (app-only via Enterprise Application client secret) |
| `-TenantId` | String | — | Target tenant ID. Required when `-AuthMethod ClientCredentials` |
| `-ClientId` | String | — | App Registration Application (client) ID. Required when `-AuthMethod ClientCredentials` |
| `-ClientSecret` | String | — | App Registration client secret. Required when `-AuthMethod ClientCredentials`. Pass via `$env:VAR` to avoid plain-text exposure |
| `-IncludeAuditData` | Switch | — | Fetch Intune and Entra audit logs to populate `ModifiedBy` in drift rows. Requires `AuditLog.Read.All` |

---

## ⚙️ Prerequisites

### PowerShell

- **PowerShell 7.0 or higher** is required.

### PowerShell Modules

| Module | Required when |
|---|---|
| `Microsoft.Graph.Authentication` | Always (auto-installed if missing) |
| `MicrosoftTeams` | `TeamsTenantPolicies` is selected; auto-installed if missing |
| `Az.Accounts` | Azure Automation (Managed Identity), `ClientCredentials` with `-StorageAccountName`, or blob operations |
| `Az.Storage` | Blob upload (`-UploadToBlob`) or downloading baselines from blob |

### Microsoft Graph Permissions

Grant the following as **app roles** (application permissions) for unattended/runbook use, or as **delegated scopes** for interactive use.

| Permission | Required for |
|---|---|
| `Policy.Read.All` | Conditional Access policies, Authorization Policy |
| `RoleManagement.Read.Directory` | Directory roles and PIM eligible assignments |
| `Application.Read.All` | Enterprise applications and OAuth2 grants |
| `Directory.Read.All` | General directory data |
| `DeviceManagementConfiguration.Read.All` | Intune device configuration and compliance |
| `DeviceManagementApps.Read.All` | App protection policies and app assignments |
| `DeviceManagementServiceConfig.Read.All` | Enrollment configurations |
| `DeviceManagementManagedDevices.Read.All` | Managed device data |
| `DeviceManagementScripts.Read.All` | Intune management scripts and health scripts |
| `SharePointTenantSettings.Read.All` | SharePoint and OneDrive tenant settings |
| `SecurityEvents.Read.All` | Microsoft Secure Score control profiles |
| `AuditLog.Read.All` | `ModifiedBy` population via audit logs *(only when `-IncludeAuditData` is used)* |

`M365GroupGovernance` uses Microsoft Graph beta `GET /settings` for the `Group.Unified*` directory settings and v1.0 `GET /groupLifecyclePolicies`. `Directory.Read.All` is already required by the Entra collectors; `GroupSettings.Read.All` is the least-privilege alternative for the group settings call. `TeamsTenantPolicies` uses the MicrosoftTeams PowerShell module, not Microsoft Graph. It requires an account with a Teams administrative role and supports only `Interactive` or `DeviceCode` authentication in this tool.

---

## 🔍 Drift Detection Logic

1. Each collected item is keyed by its `id` field.
2. Items present in the **current snapshot** but absent from the baseline → classified as **`Added`**.
3. Items present in the **baseline** but absent from the current snapshot → classified as **`Removed`**.
4. Items present in **both**, with differing content (compared by full deep JSON serialisation at depth 20) → classified as **`Modified`**.
5. Metadata-only fields (`lastModifiedDateTime`, `createdDateTime`, `modifiedDateTime`, `version`) are **excluded** from change detection to prevent false positives caused by routine system updates.
6. `ChangedProperties` lists only the **top-level properties** that have actual value differences.
7. `LastModified` is always populated from the item's own timestamp field.
8. `ModifiedBy` is populated from audit log data when `-IncludeAuditData` is specified, showing the UPN or app display name of whoever made the last recorded change to that resource.

---

## 📂 Output Files

All files are written to a timestamped run folder under `-OutputPath` (default: `.\AzureConfigDrift`).

| File | Description |
|---|---|
| `{Endpoint}.json` | Raw snapshot data for each collected endpoint |
| `Snapshot.json` | Combined snapshot of all collected endpoints |
| `DriftReport.json` | Drift rows as JSON (`CheckDrift` mode only) |
| `DriftReport.csv` | Drift rows as CSV, ready for Excel or reporting tools (`CheckDrift` mode only) |
| `audit.log` | PowerShell transcript of the complete run |

---

## 🗃 Folder Structure

The following shows the output directory layout after a full **Snapshot → SetBaseline → CheckDrift** workflow:

```
AzureConfigDrift\
├── runs\
│   └── 20260424-143000\               # Timestamped snapshot folder
│       ├── EntraCA.json
│       ├── EntraDirectoryRoles.json
│       ├── EntraEnterpriseApps.json
│       ├── EntraAuthMethods.json
│       ├── IntuneDeviceConfig.json
│       ├── IntuneCompliance.json
│       ├── IntuneAppProtection.json
│       ├── IntuneScripts.json
│       ├── IntuneEnrollment.json
│       ├── IntuneAppAssignments.json
│       ├── IntuneSecurityBaselines.json
│       ├── SharePointOneDriveTenantSettings.json
│       ├── M365GroupGovernance.json
│       ├── TeamsTenantPolicies.json
│       ├── DefenderSecurityPosture.json
│       ├── Snapshot.json              # Combined snapshot
│       └── audit.log
│
├── baselines\
│   └── April2026\                     # Named baseline folder
│       ├── baseline-meta.json         # Name, description, created timestamp
│       ├── EntraCA.json
│       ├── EntraDirectoryRoles.json
│       └── ...                        # One file per collected endpoint
│
└── drift-reports\
    └── 20260424-160000\               # Timestamped drift check folder
        ├── DriftReport.json
        ├── DriftReport.csv
        └── audit.log
```

---

## 🚀 Usage Examples

### Interactive (local machine)

```powershell
# Interactive run — browser sign-in, numbered menu
.\AzureConfigDrift.ps1

# Device code authentication — headless or SSH sessions
.\AzureConfigDrift.ps1 -AuthMethod DeviceCode

# Enterprise Application (app-only, client secret) — pipeline / unattended
.\AzureConfigDrift.ps1 -AuthMethod ClientCredentials `
    -TenantId  "00000000-0000-0000-0000-000000000000" `
    -ClientId  "11111111-0000-0000-0000-000000000000" `
    -ClientSecret ($env:APP_SECRET | ConvertTo-SecureString -AsPlainText -Force) `
    -Mode Snapshot -Unattended

# Target a specific tenant
.\AzureConfigDrift.ps1 -TenantId "00000000-0000-0000-0000-000000000000"
```

### Snapshot

```powershell
# Take a snapshot of all endpoints (unattended)
.\AzureConfigDrift.ps1 -Mode Snapshot -Unattended
```

### Baseline management

```powershell
# Promote a snapshot to a named baseline
.\AzureConfigDrift.ps1 -Mode SetBaseline -BaselineName "April2026" -BaselineDescription "Post-quarterly review"

# List all available baselines
.\AzureConfigDrift.ps1 -Mode ListBaselines
```

### Drift detection

```powershell
# Check drift against a named baseline with audit attribution
.\AzureConfigDrift.ps1 -Mode CheckDrift -BaselineName "April2026" -IncludeAuditData

# Check drift for Entra ID endpoints only
.\AzureConfigDrift.ps1 -Mode CheckDrift -BaselineName "April2026" -Endpoints EntraCA,EntraAuthMethods

# Capture settings governing all SharePoint sites, OneDrive accounts, M365 Groups,
# and Teams, without enumerating sites, drives, groups, or individual Teams
.\AzureConfigDrift.ps1 -Mode Snapshot `
    -Endpoints SharePointOneDriveTenantSettings,M365GroupGovernance,TeamsTenantPolicies,DefenderSecurityPosture

# Scheduled unattended drift check with upload to Azure Blob Storage
.\AzureConfigDrift.ps1 -Mode CheckDrift -BaselineName "April2026" -Unattended -UploadToBlob -StorageAccountName "mystorageaccount"
```

---

## ☁️ Azure Automation Runbook

The script automatically detects the Azure Automation context via `$PSPrivateMetadata.JobId` and switches to **unattended + Managed Identity** mode without any additional configuration.

### Required modules in the Automation Account

| Module | Source |
|---|---|
| `Microsoft.Graph.Authentication` | PowerShell Gallery |
| `Az.Accounts` | PowerShell Gallery |
| `Az.Storage` | PowerShell Gallery |

### Required RBAC on the Storage Account

| Role | Scope |
|---|---|
| `Storage Blob Data Contributor` | Target storage account or container |

Assign the required Microsoft Graph **app roles** to the Automation Account's Managed Identity via the Azure Portal or PowerShell before the first run.

---

## ⚠️ Known Limitations

| Limitation | Detail |
|---|---|
| **PIM eligibility requires Entra ID P2** | Eligible assignment collection under `EntraDirectoryRoles` requires an Entra ID P2 (or equivalent) licence. The script skips PIM collection gracefully if P2 is not available. |
| **Audit log lookback is 30 days** | Microsoft Graph audit logs retain data for a maximum of 30 days. `ModifiedBy` cannot be populated for changes older than this window. |
| **`ModifiedBy` is best-effort** | Audit log matching is performed by resource ID; the **last matching event** wins. If a resource was modified multiple times or by automated processes, the result may not reflect the most operationally relevant actor. |
| **No individual resource enumeration** | The M365 collectors intentionally don't enumerate individual SharePoint sites, OneDrive accounts, Microsoft 365 Groups, Teams, channels, or members. This keeps snapshots focused on the policies governing all of them. |
| **SharePoint / OneDrive Graph coverage** | The tenant settings endpoint doesn't expose all classic SharePoint administration properties, per-site settings, sharing links, item-level permissions, quotas, retention, or lock state. Use SharePoint Online Management Shell or PnP.PowerShell for those surfaces. |
| **Teams requires a second sign-in** | `TeamsTenantPolicies` opens a separate MicrosoftTeams PowerShell session. It is unavailable with `ClientCredentials` and in Azure Automation Runbooks, because this tool doesn't configure Teams certificate authentication. |
| **Teams feature availability varies** | The MicrosoftTeams module can expose policy cmdlets before their backing tenant feature is enabled. The tool warns and skips only the service's explicit `40003` “not currently enabled in flighting” response; permission and other API errors still fail the Teams collector. |
| **M365 Group settings use Graph beta** | `Group.Unified*` directory settings are not exposed through Microsoft Graph v1.0. The tool uses the beta endpoint and may require maintenance if Microsoft changes that contract. |
| **Defender coverage is security posture** | Secure Score control profiles do not replace Microsoft Defender for Office 365, Defender for Endpoint, Defender for Identity, or Defender for Cloud Apps policy exports. Those products require their own supported administration APIs or PowerShell modules. |
| **Exchange and Purview are not collected** | Mail flow, Exchange organization settings, retention, DLP, sensitivity labels, eDiscovery, and audit configuration require Exchange Online or Microsoft Purview administration interfaces. |
| **Read-only** | The script does not make any changes to the tenant. |

---

## 🤝 Contributing / Author

Developed and maintained by **[Bareminimum Automation](https://github.com/chadybrady)**.

Contributions, bug reports, and feature requests are welcome:

1. Fork the repository.
2. Create a new branch for your change.
3. Add your script or update with a clear description of the change.
4. Open a pull request.

---

## 🛡️ Security Notes

- Prefer managed identity for unattended Azure Automation runs.
- Store client secrets in a secure secret store and pass them as `SecureString` values.
- Grant only the Microsoft Graph read permissions required by the selected endpoints.
- Use a dedicated Teams Administrator account for `TeamsTenantPolicies`; it creates a separate delegated MicrosoftTeams session.
- Restrict and protect snapshots: tenant policy, group governance, and security posture data are tenant-sensitive.
- Protect snapshots, baselines, reports, and audit metadata as tenant-sensitive information.
- Review detected drift before making any remediation changes outside this tool.

---

## 🔗 Related Links

- [Microsoft Graph PowerShell Authentication](https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands)
- [Azure Automation Managed Identity](https://learn.microsoft.com/en-us/azure/automation/enable-managed-identity-for-automation-account)
- [Conditional Access Overview](https://learn.microsoft.com/en-us/entra/identity/conditional-access/overview)
- [Intune Security Baselines](https://learn.microsoft.com/en-us/mem/intune/protect/security-baselines)
- [Microsoft Graph API Permissions Reference](https://learn.microsoft.com/en-us/graph/permissions-reference)
- [SharePoint and OneDrive tenant settings](https://learn.microsoft.com/en-us/graph/api/sharepointsettings-get?view=graph-rest-1.0)
- [Microsoft Teams PowerShell](https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-overview)
- [Microsoft Secure Score control profiles](https://learn.microsoft.com/en-us/graph/api/security-list-securescorecontrolprofiles?view=graph-rest-1.0)
