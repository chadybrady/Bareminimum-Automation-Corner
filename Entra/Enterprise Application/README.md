# 🏢 Enterprise Applications

Scripts for monitoring, testing, and governing **Enterprise Applications (Service Principals)** in Microsoft Entra ID.

---

## 📂 Contents

| Folder | Description |
|---|---|
| [`EA- Permisson and secret monitoring/`](./EA-%20Permisson%20and%20secret%20monitoring/) | Monitors enterprise app client secrets for upcoming expiry and permission changes |
| [`Enterprise App Testing Tool/`](./Enterprise%20App%20Testing%20Tool/) | Generates a comprehensive HTML governance report for all enterprise applications |

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `Microsoft.Graph` PowerShell SDK
- **Required Permissions:**
  - `Application.Read.All`
  - `Directory.Read.All`
  - `AuditLog.Read.All` (for usage/sign-in data)

---

## 🛡️ Security Notes

- Regularly rotating client secrets and certificates is a critical security hygiene practice.
- Applications with **expired credentials** may cause service disruptions — monitor proactively.
- Review applications with **highly privileged permissions** (e.g., `Directory.ReadWrite.All`) and validate they are still required.
- Identify and remove **stale or orphaned applications** that are no longer in use.

---

## 🔗 Related Links

- [Enterprise Applications in Entra ID](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/what-is-application-management)
- [Application Credential Best Practices](https://learn.microsoft.com/en-us/entra/identity-platform/security-best-practices-for-app-registration)
- [Microsoft Graph Application Permissions](https://learn.microsoft.com/en-us/graph/permissions-reference)
