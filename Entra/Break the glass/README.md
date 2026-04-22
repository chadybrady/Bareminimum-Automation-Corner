# 🆘 Break the Glass Accounts

Scripts for creating and configuring **emergency access (Break Glass) accounts** in Microsoft Entra ID. Break Glass accounts are privileged emergency accounts used when normal administrative access is unavailable (e.g., during MFA outages or misconfigured Conditional Access policies).

---

## 📂 Contents

| Folder | Description |
|---|---|
| [`Create-Break-Glass-Accounts/`](./Create-Break-Glass-Accounts/) | Creates two Break Glass accounts and assigns them the Global Administrator role |

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `Microsoft.Entra` PowerShell module
- **Required Permissions:**
  - `User.ReadWrite.All`
  - `Group.ReadWrite.All`
  - `RoleManagement.ReadWrite.Directory`
  - `Directory.ReadWrite.All`

---

## 🛡️ Best Practices

- Store Break Glass credentials in a **physical, offline secure location** (e.g., a safe).
- **Exclude** Break Glass accounts from all Conditional Access policies.
- Monitor sign-in activity for Break Glass accounts — any sign-in should trigger an alert.
- Use **cloud-only accounts** (not federated) for Break Glass accounts.
- Periodically verify that the accounts are accessible and credentials are still valid.

---

## 🔗 Related Links

- [Microsoft: Manage emergency access accounts](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access)
- [Break Glass Account Best Practices](https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-all-users-mfa#create-emergency-access-accounts)
