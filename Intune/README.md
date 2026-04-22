# 📱 Intune

PowerShell scripts for managing **Microsoft Intune** device management operations. This section covers Android device management, Apple connector monitoring, Win32 app deployment, network configuration, and Intune configuration testing.

---

## 📂 Contents

| Folder | Description |
|---|---|
| [`Android/`](./Android/) | Android device management scripts (e.g., bulk device renaming) |
| [`Apple-Token-Monitoring/`](./Apple-Token-Monitoring/) | Azure Automation runbook to monitor Apple MDM, VPP, and DEP token expiry |
| [`Intune Testing tool Sec/`](./Intune%20Testing%20tool%20Sec/) | Validate and audit Intune configuration and security posture |
| [`Network Settings/`](./Network%20Settings/) | Detect and change DNS server settings on managed devices |
| [`Win32/`](./Win32/) | Win32 app deployment utilities, including force-reinstall tooling |

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `Microsoft.Graph.Beta` module for device management operations
- `Microsoft.graph.intune` module (for Apple monitoring runbook)
- Azure Automation Account (for scheduled monitoring scripts)
- Intune Administrator or appropriate Graph API permissions

---

## 🛡️ Security Notes

- The Apple Token Monitoring script is designed to run as an **Azure Automation Runbook** — never hard-code credentials.
- Win32 force-reinstall operations require **local administrator privileges**.
- DNS change scripts may require **Intune Proactive Remediation** licensing (Microsoft Intune Plan 1 or higher).

---

## 🔗 Related Links

- [Microsoft Intune Documentation](https://learn.microsoft.com/en-us/mem/intune/)
- [Microsoft Graph Intune API](https://learn.microsoft.com/en-us/graph/api/resources/intune-graph-overview)
- [Intune Proactive Remediations](https://learn.microsoft.com/en-us/mem/intune/fundamentals/remediations)
