# 🤖 Copilot & Viva

Scripts for managing **Microsoft Copilot** and **Microsoft Viva** feature availability across your Microsoft 365 tenant.

---

## 📂 Contents

| Folder | Description |
|---|---|
| [`Viva- Disable Apps and features/`](./Viva-%20Disable%20Apps%20and%20features/) | Bulk-disables specified Microsoft Viva and Copilot features tenant-wide |

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `ExchangeOnlineManagement` module — `Install-Module ExchangeOnlineManagement`
- `MicrosoftTeams` module — `Install-Module MicrosoftTeams`
- **Exchange Administrator** role (for Viva feature management)

---

## 🔗 Related Links

- [Microsoft Viva Overview](https://learn.microsoft.com/en-us/viva/microsoft-viva-overview)
- [Manage Viva Feature Access](https://learn.microsoft.com/en-us/viva/feature-access-management)
- [Microsoft Copilot for Microsoft 365](https://learn.microsoft.com/en-us/copilot/microsoft-365/)

## 🚀 Usage

Review script parameters and run in a test environment first.
## 🛡️ Security Notes

- Use least-privilege permissions and avoid storing credentials in plaintext.
- Validate results in test/report-only mode before production rollout.
- Treat exported reports as potentially sensitive tenant data.
