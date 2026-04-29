# 🔐 M365 Permissions Inventory Tool

A **tenant-wide, read-only permissions inventory** script that enumerates all principal-to-resource role assignments across Microsoft 365 services and exports the results to CSV/Excel/JSON.

---

## 📄 Script

### `M365-Permissions-Inventory.ps1`

An interactive PowerShell 7+ script that audits the following services (each section is opt-in at runtime):

| # | Section | Description |
|---|---|---|
| 1 | Entra Directory Roles | All built-in and custom directory role assignments |
| 2 | Enterprise App Role Assignments | Users/groups assigned to enterprise applications |
| 3 | OAuth2 Permission Grants | Delegated and admin-consented OAuth2 grants |
| 4 | Teams Memberships | Owners and members across all Teams |
| 5 | SharePoint Site Permissions | Site-level permissions (optionally includes OneDrive) |
| 5b | OneDrive Site Permissions | OneDrive personal site permissions (standalone) |
| 6 | Exchange Mailbox Permissions | FullAccess, SendAs, and SendOnBehalf assignments |
| 7 | Distribution & Mail-Enabled Security Groups | Members and on-premises sync status |
| 8 | Conditional Access Policy Assignments | Included/excluded users and groups in CA policies |
| 9 | PIM Role Assignments | All PIM assignments: eligible (not yet activated), active/permanent, and currently activated |
| AD | AD Enrichment | Optionally enriches AD-synced accounts with OU data (via RSAT or `ldapsearch`) |

---

## ⚙️ Prerequisites

- **PowerShell 7.0+** (required)
- **Microsoft.Graph PowerShell SDK** — `Install-Module Microsoft.Graph -Scope CurrentUser`
- **ExchangeOnlineManagement** module (optional, required for Exchange section) — `Install-Module ExchangeOnlineManagement -Scope CurrentUser`
- **ImportExcel** module (optional, recommended — enables Excel export with multiple worksheets) — `Install-Module ImportExcel -Scope CurrentUser`
- **ActiveDirectory RSAT module** (optional, Windows only — for AD enrichment)
- **`ldapsearch`** (optional, macOS/Linux — for AD enrichment)

---

## 🔐 Authentication

The script supports two authentication modes, selected interactively at startup.

### Option A — Delegated (interactive browser login)

Standard interactive login. Suitable for all sections **except SharePoint/OneDrive**, which require the signed-in account to have an explicit **SharePoint Administrator** role in addition to Global Admin.

> ⚠️ Even Global Admins may receive a **403 error** on `/beta/sites/getAllSites` when using delegated auth without the SharePoint Admin role explicitly assigned.

### Option B — App-only (client credentials) — **Required for SharePoint/OneDrive**

Uses an Entra App Registration with application permissions. This bypasses the SharePoint delegated-auth restriction and is the recommended mode when SharePoint or OneDrive sections are enabled.

#### One-time setup (per tenant)

1. Go to **Entra admin center** → **App registrations** → **New registration**
2. Give it a name (e.g. `M365PermissionsInventory`) and register
3. Go to **Certificates & secrets** → **Client secrets** → **New client secret** — copy the value immediately
4. Go to **API permissions** → **Add a permission** → **Microsoft Graph** → **Application permissions** — add the permissions below
5. Click **Grant admin consent for \<tenant\>**

#### Required application permissions

| Permission | Required For |
|---|---|
| `Directory.Read.All` | Directory roles, users, groups, service principals |
| `RoleManagement.Read.Directory` | Directory role assignments + PIM |
| `Application.Read.All` | Enterprise app role assignments, OAuth2 grants |
| `TeamMember.Read.All` | Teams memberships |
| `Sites.Read.All` | SharePoint and OneDrive site permissions |
| `Mail.Read` | Exchange (Graph-based lookups) |
| `Policy.Read.All` | Conditional Access policies *(only if section 8 selected)* |
| `RoleEligibilitySchedule.Read.Directory` | PIM eligible assignments *(only if section 9 selected)* |

> The script will print a reminder of which permissions are needed based on your selected sections when you choose app-only mode.

---

## 🚀 Usage

Run the script from a PowerShell 7+ session:

```powershell
# Run with default output path (.\M365-Permissions-Inventory)
.\M365-Permissions-Inventory.ps1

# Run with a custom output path
.\M365-Permissions-Inventory.ps1 -OutputPath "C:\Exports\PermissionsAudit"
```

At startup you will be prompted to:
1. Select which sections to include
2. Choose delegated or app-only authentication (credentials prompted if app-only)
3. Optionally enable on-prem AD enrichment

The script will then connect to Microsoft Graph (and Exchange Online if selected), enumerate all permissions, and export results to the output folder.

---

## 📤 Output

Each run creates a timestamped subfolder (e.g. `Run-20260428-143000`) containing:

| File | Contents |
|---|---|
| `PermissionsInventory.csv` | All permission rows (all services) |
| `PermissionsInventory.xlsx` | Excel workbook with one worksheet per service + Summary, Sync Analysis, and PIM Details tabs *(requires ImportExcel module)* |
| `SyncAnalysis.csv` | Per-principal, per-service sync analysis with recommendations |
| `PIMDetails.csv` | Full PIM assignment details (eligible + active + activated) *(only if PIM section selected)* |
| `Summary.json` | Run metadata and row counts |
| `audit.log` | Full transcript of the run |

### Excel worksheets

| Worksheet | Contents |
|---|---|
| All Permissions | Every row across all services |
| Entra / Exchange / Teams / … | One sheet per service |
| Summary | Per-service row counts and sync statistics |
| Sync Analysis | One row per principal per service — includes Origin (cloud/AD-synced), sync recommendation, privileged role flag, CA policy flag, PIM flag |
| PIM Details | Full PIM data: assignment category (Eligible/Active), type (Eligible/Assigned/Activated), permanence, start/end dates, status, member type, scope, principal identity and AD/cloud origin |

---

## 📝 Notes

- SharePoint **item-level** permissions (files/folders) are **not** enumerated — site-level only.
- Exchange **folder** permissions (calendar, inbox, etc.) are **not** included.
- The script is **read-only** — no changes are made to your tenant.
- AD enrichment warns when the domain controller appears to be throttling requests (3+ consecutive failures).

---

## 🔗 Related Links

- [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/)
- [Entra ID Role Assignments](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/view-assignments)
- [PIM Role Assignments](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-view-eligibility)
- [Exchange Online PowerShell](https://learn.microsoft.com/en-us/powershell/exchange/exchange-online-powershell)
- [ImportExcel module](https://github.com/dfinke/ImportExcel)
