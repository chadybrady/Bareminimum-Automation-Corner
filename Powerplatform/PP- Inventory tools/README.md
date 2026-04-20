# 📊 Power Platform Inventory Tools

Scripts for **inventorying and exporting** Power Platform resources — including Power Apps, Power Automate flows, and system-level platform data — across tenant environments.

---

## 📂 Contents

| Folder | Script | Description |
|---|---|---|
| [`Gather-System/`](./Gather-System/) | `PP-GatherSystem.ps1` | Combined export of Power Apps and flows with connector details |
| [`Get-PP-Apps/`](./Get-PP-Apps/) | `GetAllApps.ps1` | Exports all Power Apps and their connectors to CSV |
| [`Get-PP-Flows/`](./Get-PP-Flows/) | `GetAllFlows.ps1` | Exports all Power Automate flows and their connectors to CSV |

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later (PowerShell 7+ recommended)
- `Microsoft.PowerApps.Administration.PowerShell` module
- `Microsoft.Entra` module (for user/owner lookup)
- **Power Platform Admin** or **Environment Admin** role

```powershell
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Force
Install-Module -Name Microsoft.Entra -Force
```

---

## 🚀 Usage

Each script is interactive — it will prompt for your Power Platform environment selection. Output is exported to a CSV file in the working directory (or a path you specify).

```powershell
# Export all apps
.\GetAllApps.ps1

# Export all flows
.\GetAllFlows.ps1

# Combined system gather
.\PP-GatherSystem.ps1

# Specify a custom output path
.\GetAllApps.ps1 -FilePath "C:\Reports\PowerApps.csv"
.\GetAllFlows.ps1 -FilePath "C:\Reports\Flows.csv"
```

---

## 📋 CSV Output Columns

**Apps (`GetAllApps.ps1`):**
- App Name, App ID, Environment, Owner Display Name, Owner UPN, Connector Names, Created/Modified dates

**Flows (`GetAllFlows.ps1`):**
- Flow Name, Flow ID, Environment, Owner Display Name, Owner UPN, Connector Names, State, Created/Modified dates

---

## 🛡️ Notes

- Output CSV files may contain sensitive data about your organisation's apps and automation. Handle and store them securely.
- Scripts connect interactively — no credentials are stored or hard-coded.
- Ensure you have visibility into all required environments before running.

---

## 🔗 Related Links

- [Power Platform Admin Center](https://admin.powerplatform.microsoft.com/)
- [PowerApps Administration PowerShell](https://learn.microsoft.com/en-us/power-platform/admin/powerapps-powershell)
- [Power Automate Administration](https://learn.microsoft.com/en-us/power-automate/admin-analytics-report)
