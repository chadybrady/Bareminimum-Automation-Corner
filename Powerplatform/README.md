# ⚡ Power Platform

PowerShell scripts for **Microsoft Power Platform** governance, inventory, and administration. These tools help administrators gain visibility into Power Apps and Power Automate flows across environments.

---

## 📂 Contents

| Folder | Description |
|---|---|
| [`PP- Inventory tools/`](./PP-%20Inventory%20tools/) | Export and inventory Power Apps, Power Automate flows, and system-level platform data |

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later (PowerShell 7+ recommended)
- `Microsoft.PowerApps.Administration.PowerShell` module
- `Microsoft.Entra` module (for user lookup)
- Power Platform Admin role or Environment Admin permissions

---

## 🛡️ Security Notes

- Scripts connect interactively to Power Platform — no credentials are hard-coded.
- Ensure your account has appropriate **Power Platform Admin** permissions before running inventory scripts.
- Output CSV files may contain sensitive data; handle and store them accordingly.

---

## 🔗 Related Links

- [Power Platform Admin Documentation](https://learn.microsoft.com/en-us/power-platform/admin/)
- [PowerApps Administration PowerShell](https://learn.microsoft.com/en-us/power-platform/admin/powerapps-powershell)
- [Power Automate Administration](https://learn.microsoft.com/en-us/power-automate/admin-analytics-report)
