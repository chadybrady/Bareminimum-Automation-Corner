# 🧪 Enterprise App Testing Tool

Generates a comprehensive **HTML governance report** for all Enterprise Applications (service principals) in Microsoft Entra ID. Designed to help IT administrators assess application security posture, identify stale or risky apps, and improve application lifecycle management.

---

## 📄 Script

### `Test-EnterpriseApplications.ps1`

Connects to Microsoft Graph and evaluates all enterprise applications against a range of governance criteria, then outputs a detailed HTML report.

**Report sections include:**

| Category | Details |
|---|---|
| 📋 Inventory | Full list of enterprise applications with metadata |
| 👤 Ownership | Applications without assigned owners |
| 🔑 Credential Hygiene | Expiring or expired client secrets and certificates |
| 📊 Usage | Stale applications with no recent sign-in activity |
| 🔐 Permissions | Apps with highly privileged or broad API permissions |
| 🏷️ Naming Standards | Applications that don't conform to naming conventions |
| ✅ Governance Recommendations | Prioritised action items |

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `Microsoft.Graph` PowerShell SDK — `Install-Module Microsoft.Graph`
- **Required Permissions:**
  - `Application.Read.All`
  - `Directory.Read.All`
  - `AuditLog.Read.All`

---

## 🚀 Usage

```powershell
# Basic usage — report saved to current directory
.\Test-EnterpriseApplications.ps1

# Specify output path
.\Test-EnterpriseApplications.ps1 -OutputPath "C:\Reports"

# With naming pattern validation
.\Test-EnterpriseApplications.ps1 -OutputPath "C:\Reports" -NamePattern "^(APP|ENT)-[A-Z0-9-]+$"

# Customise thresholds
.\Test-EnterpriseApplications.ps1 `
    -InactiveDaysThreshold 90 `
    -SecretWarningDays 60 `
    -SecretCriticalDays 14
```

**Parameters:**

| Parameter | Description | Default |
|---|---|---|
| `-OutputPath` | Directory for the HTML report | Current directory |
| `-TenantId` | Tenant ID for Graph connection | Prompt/current session |
| `-NamePattern` | Regex for validating app naming conventions | None |
| `-InactiveDaysThreshold` | Days without sign-in to flag as stale | 90 |
| `-SecretWarningDays` | Days before expiry to flag a warning | 60 |
| `-SecretCriticalDays` | Days before expiry to flag critical | 14 |

---

## 📄 Output

Produces a self-contained **HTML report** with colour-coded status indicators, filterable tables, and governance recommendations. Open the report in any modern web browser.

---

## 🔗 Related Links

- [Enterprise Application Governance](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/govern-enterprise-apps)
- [Application Credential Best Practices](https://learn.microsoft.com/en-us/entra/identity-platform/security-best-practices-for-app-registration)
- [Least-Privilege Application Permissions](https://learn.microsoft.com/en-us/entra/identity-platform/secure-least-privileged-access)
