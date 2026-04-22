# 🔐 M365 Permissions Inventory Tool

A **tenant-wide, read-only permissions inventory** script that enumerates all principal-to-resource role assignments across Microsoft 365 services and exports the results to CSV/JSON.

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
| 9 | PIM Eligible Role Assignments | Roles eligible but not yet activated via PIM |
| AD | AD Enrichment | Optionally enriches AD-synced accounts with OU data (via RSAT or `ldapsearch`) |

---

## ⚙️ Prerequisites

- **PowerShell 7.0+** (required)
- **Microsoft.Graph PowerShell SDK** — `Install-Module Microsoft.Graph`
- **ExchangeOnlineManagement** module (optional, required for Exchange section) — `Install-Module ExchangeOnlineManagement`
- **ActiveDirectory RSAT module** (optional, Windows only — for AD enrichment)
- **`ldapsearch`** (optional, macOS/Linux — for AD enrichment)

### Required Microsoft Graph Permissions

| Permission | Type | Required For |
|---|---|---|
| `Directory.Read.All` | Application or Delegated | Directory roles, enterprise apps, OAuth2 grants |
| `GroupMember.Read.All` | Application or Delegated | Teams, distribution groups |
| `Sites.Read.All` | Application or Delegated | SharePoint / OneDrive permissions |
| `Policy.Read.All` | Application or Delegated | Conditional Access policies |
| `PrivilegedAccess.Read.AzureAD` | Application or Delegated | PIM eligible assignments |
| `Mail.Read` (Exchange) | Delegated | Exchange mailbox permissions |

---

## 🚀 Usage

Run the script from a PowerShell 7+ session. You will be prompted to select which sections to include and whether to include AD enrichment.

```powershell
# Run with default output path (.\M365-Permissions-Inventory)
.\M365-Permissions-Inventory.ps1

# Run with a custom output path
.\M365-Permissions-Inventory.ps1 -OutputPath "C:\Exports\PermissionsAudit"
```

The script will:
1. Prompt for sections to include
2. Connect to Microsoft Graph (and Exchange Online if selected)
3. Enumerate all permissions across selected services
4. Export results as CSV and/or JSON to the specified output path

---

## 📝 Notes

- SharePoint **item-level** permissions (files/folders) are **not** enumerated.
- Exchange **folder** permissions (calendar, inbox, etc.) are **not** included.
- The script is **read-only** — no changes are made to your tenant.

---

## 🔗 Related Links

- [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/)
- [Entra ID Role Assignments](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/view-assignments)
- [PIM Role Assignments](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-view-eligibility)
- [Exchange Online PowerShell](https://learn.microsoft.com/en-us/powershell/exchange/exchange-online-powershell)
