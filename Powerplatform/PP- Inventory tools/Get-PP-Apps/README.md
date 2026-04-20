# 📱 Get-PP-Apps — Power Apps Inventory Export

Exports a complete inventory of **Power Apps** and their connectors across a selected Power Platform environment to a CSV file.

---

## 📄 Script

### `GetAllApps.ps1`

Connects to Power Platform and Entra ID to:
1. Prompt for environment selection (All or specific)
2. Enumerate all Power Apps in the environment(s)
3. Resolve app owner details (Display Name, UPN) from Entra ID
4. Export app name, ID, connectors, owner, and dates to CSV

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `Microsoft.PowerApps.Administration.PowerShell` module (auto-installed if missing)
- `Microsoft.Entra` module (auto-installed if missing)
- **Power Platform Admin** or **Environment Admin** role

---

## 🚀 Usage

```powershell
# Default output to ./PowerAppsConnectorExport.csv
.\GetAllApps.ps1

# Custom output path
.\GetAllApps.ps1 -FilePath "C:\Reports\PowerApps.csv"
```

**Parameters:**

| Parameter | Description | Default |
|---|---|---|
| `-FilePath` | Path for the output CSV file | `./PowerAppsConnectorExport.csv` |

---

## 📋 CSV Columns

| Column | Description |
|---|---|
| App Name | Display name of the Power App |
| App ID | Unique identifier |
| Environment | Environment the app belongs to |
| Owner Display Name | Owner's full name |
| Owner UPN | Owner's user principal name |
| Connectors | Comma-separated list of connectors used |
| Created | App creation date |
| Last Modified | Date of last modification |

---

## 🔗 Related Links

- [Power Apps Administration](https://learn.microsoft.com/en-us/power-platform/admin/admin-documentation)
- [PowerApps Administration PowerShell](https://learn.microsoft.com/en-us/power-platform/admin/powerapps-powershell)
