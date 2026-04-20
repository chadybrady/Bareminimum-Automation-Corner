# ⚡ Get-PP-Flows — Power Automate Flow Inventory Export

Exports a complete inventory of **Power Automate flows** and their connectors across a selected Power Platform environment to a CSV file.

---

## 📄 Script

### `GetAllFlows.ps1`

Connects to Power Platform and Entra ID to:
1. Prompt for environment selection (All or specific)
2. Enumerate all Power Automate flows in the environment(s)
3. Resolve flow owner details (Display Name, UPN) from Entra ID
4. Export flow name, ID, connectors, state, owner, and dates to CSV

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `Microsoft.PowerApps.Administration.PowerShell` module (auto-installed if missing)
- `Microsoft.Entra` module (auto-installed if missing)
- **Power Platform Admin** or **Environment Admin** role

---

## 🚀 Usage

```powershell
# Default output to ./FlowsExport.csv
.\GetAllFlows.ps1

# Custom output path
.\GetAllFlows.ps1 -FilePath "C:\Reports\Flows.csv"
```

**Parameters:**

| Parameter | Description | Default |
|---|---|---|
| `-FilePath` | Path for the output CSV file | `./FlowsExport.csv` |

---

## 📋 CSV Columns

| Column | Description |
|---|---|
| Flow Name | Display name of the flow |
| Flow ID | Unique identifier |
| Environment | Environment the flow belongs to |
| State | Flow state (Started, Stopped, Suspended) |
| Owner Display Name | Owner's full name |
| Owner UPN | Owner's user principal name |
| Connectors | Comma-separated list of connectors used |
| Created | Flow creation date |
| Last Modified | Date of last modification |

---

## 🛡️ Notes

- Flows in a **Suspended** state may indicate licence issues or connector policy violations — review accordingly.
- Large tenants with many flows may take several minutes to export.

---

## 🔗 Related Links

- [Power Automate Administration](https://learn.microsoft.com/en-us/power-automate/admin-analytics-report)
- [PowerApps Administration PowerShell](https://learn.microsoft.com/en-us/power-platform/admin/powerapps-powershell)
