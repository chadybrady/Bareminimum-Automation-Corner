# 🔐 Entra ID

PowerShell scripts for managing and securing **Microsoft Entra ID** (formerly Azure Active Directory). This section covers emergency access accounts, Conditional Access policy baselines, and Enterprise Application governance.

---

## 📂 Contents

| Folder | Description |
|---|---|
| [`Admin accounts/`](./Admin%20accounts/) | Bulk-provision Entra ID admin accounts from an Excel file, with group memberships and PIM-eligible role assignments |
| [`Break the glass/`](./Break%20the%20glass/) | Create and configure emergency Break Glass accounts |
| [`Conditional access/`](./Conditional%20access/) | Deploy and manage Conditional Access policy baselines |
| [`Domain change in bulk/`](./Domain%20change%20in%20bulk/) | Bulk-change the primary email domain across all Entra ID and Exchange Online identities |
| [`Enterprise Application/`](./Enterprise%20Application/) | Monitor, test, and govern Enterprise Applications (service principals) |

---

## ⚙️ Prerequisites

- PowerShell 5.1+ (PowerShell 7+ recommended)
- `Microsoft.Entra` PowerShell module — `Install-Module Microsoft.Entra`
- `Microsoft.Graph` PowerShell SDK — `Install-Module Microsoft.Graph`
- Appropriate Entra ID admin roles (see each subfolder for specifics)

---

## 🛡️ Security Notes

- Always test Conditional Access policies in **Report-Only** mode before enforcement.
- Break Glass account credentials must be stored in a **secure, offline vault**.
- Regularly audit Enterprise Application permissions and secrets.

---

## 🔗 Related Links

- [Microsoft Entra ID Documentation](https://learn.microsoft.com/en-us/entra/identity/)
- [Conditional Access Overview](https://learn.microsoft.com/en-us/entra/identity/conditional-access/overview)
- [Break Glass Accounts Best Practices](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access)
