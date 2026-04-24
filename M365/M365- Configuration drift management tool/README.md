# 🔄 M365 Configuration Drift Management

PowerShell tooling for **detecting and reporting configuration drift** across Microsoft Entra ID and Intune. Snapshot your tenant's security and compliance settings, promote a snapshot to a baseline, and alert on any changes that deviate from the approved configuration.

---

## 📂 Contents

| Folder | Description |
|---|---|
| [`AzureConfigDrift/`](./AzureConfigDrift/) | Snapshot, baseline, and drift-detection tool covering Entra ID (CA, roles, apps, auth methods) and Intune (device config, compliance, scripts, app assignments, and more) |

---

## ⚙️ Prerequisites

- **PowerShell 7.0+**
- **Microsoft.Graph.Authentication** — `Install-Module Microsoft.Graph.Authentication`
- **Az.Accounts** (for Azure Automation / Managed Identity) — `Install-Module Az.Accounts`
- **Az.Storage** (for Azure Blob upload) — `Install-Module Az.Storage`
- Appropriate **Microsoft Graph read permissions** (see the tool README for the full list)

---

## 🔗 Related Links

- [Azure Config Drift Tool README](./AzureConfigDrift/README.md)
- [Microsoft Entra ID Documentation](https://learn.microsoft.com/en-us/entra/identity/)
- [Microsoft Intune Documentation](https://learn.microsoft.com/en-us/mem/intune/)
