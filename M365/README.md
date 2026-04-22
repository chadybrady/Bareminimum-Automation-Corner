# ☁️ Microsoft 365

PowerShell scripts for managing **Microsoft 365** workloads including Viva/Copilot feature management and OneDrive for Business administration.

---

## 📂 Contents

| Folder | Description |
|---|---|
| [`Copilot and Viva/`](./Copilot%20and%20Viva/) | Disable or configure Microsoft Viva and Copilot features across the tenant |
| [`M365 Permission inventory tool/`](./M365%20Permission%20inventory%20tool/) | Tenant-wide, read-only permissions inventory across Entra roles, enterprise apps, OAuth2 grants, Teams, SharePoint/OneDrive, Exchange, distribution groups, Conditional Access, and PIM |
| [`Onedrive/`](./Onedrive/) | OneDrive for Business maintenance scripts: KFM cleanup, folder remediation, and locked site unlocking |

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later (PowerShell 7.0+ required for the permissions inventory tool)
- `Microsoft.Graph` PowerShell SDK — `Install-Module Microsoft.Graph`
- `ExchangeOnlineManagement` module — `Install-Module ExchangeOnlineManagement`
- `MicrosoftTeams` module (for Viva feature management)
- SharePoint / OneDrive Administrator role (for OneDrive scripts)
- Exchange Administrator role (for Viva feature management)

---

## 🔗 Related Links

- [Microsoft Viva Documentation](https://learn.microsoft.com/en-us/viva/)
- [Microsoft Copilot for Microsoft 365](https://learn.microsoft.com/en-us/copilot/microsoft-365/)
- [OneDrive for Business Administration](https://learn.microsoft.com/en-us/sharepoint/onedrive-admin)
