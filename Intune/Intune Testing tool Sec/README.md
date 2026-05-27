# 🔬 Intune Configuration Testing Tool

A comprehensive **security and configuration audit script** for Microsoft Intune. Validates your Intune deployment against best practices and generates a detailed assessment report.


---

## 📂 Contents

| Item | Description |
|---|---|
| [`Test-IntuneConfiguration.ps1`](./Test-IntuneConfiguration.ps1) | Runs read-only checks against Intune configuration and reports baseline compliance. |

## 📄 Script

### `Test-IntuneConfiguration.ps1`

Connects to Microsoft Graph and evaluates the current Intune configuration across key security and management areas, including:

- Device compliance policies
- Configuration profiles
- Endpoint security settings
- App protection policies
- Enrollment configurations
- Role-based access control (RBAC)

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `Microsoft.Graph` PowerShell SDK — `Install-Module Microsoft.Graph`
- **Required Permissions:**
  - `DeviceManagementConfiguration.Read.All`
  - `DeviceManagementManagedDevices.Read.All`
  - `DeviceManagementApps.Read.All`
  - `DeviceManagementRBAC.Read.All`
  - `Directory.Read.All`

---

## 🚀 Usage

```powershell
.\Test-IntuneConfiguration.ps1
```

---

## 🛡️ Notes

- This script is **read-only** — it does not make any changes to your Intune environment.
- Run periodically as part of your security review cycle.
- Review the output against your organisation's security baseline requirements.

---

## 🔗 Related Links

- [Microsoft Intune Security Baseline](https://learn.microsoft.com/en-us/mem/intune/protect/security-baselines)
- [Intune Device Compliance Policies](https://learn.microsoft.com/en-us/mem/intune/protect/device-compliance-get-started)
- [Intune App Protection Policies](https://learn.microsoft.com/en-us/mem/intune/apps/app-protection-policy)

## 🛡️ Security Notes

- Use least-privilege permissions and avoid storing credentials in plaintext.
- Validate results in test/report-only mode before production rollout.
- Treat exported reports as potentially sensitive tenant data.
