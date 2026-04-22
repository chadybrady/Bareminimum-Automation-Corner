# 🔍 PP-GatherSystem — Combined Power Platform Export

Exports both **Power Apps** and **Power Automate flows** (with their connectors and ownership details) across a selected Power Platform environment into a single CSV file.

---

## 📄 Script

### `PP-GatherSystem.ps1`

A combined inventory script that in a single run:
1. Prompts for target environment selection
2. Exports all Power Apps with connector details
3. Exports all Power Automate flows with connector details
4. Resolves app/flow owner UPN from Entra ID
5. Writes all data to a unified CSV

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `Microsoft.PowerApps.Administration.PowerShell` module (auto-installed if missing)
- `Microsoft.Entra` module (auto-installed if missing)
- **Power Platform Admin** or **Environment Admin** role

---

## 🚀 Usage

```powershell
# Default output to ./PowerPlatformExport.csv
.\PP-GatherSystem.ps1

# Custom output path
.\PP-GatherSystem.ps1 -FilePath "C:\Reports\PowerPlatformExport.csv"
```

**Parameters:**

| Parameter | Description | Default |
|---|---|---|
| `-FilePath` | Path for the output CSV file | `./PowerPlatformExport.csv` |

---

## 🔗 Related Links

- [Power Platform Admin PowerShell](https://learn.microsoft.com/en-us/power-platform/admin/powerapps-powershell)
- [Power Platform Environments](https://learn.microsoft.com/en-us/power-platform/admin/environments-overview)
