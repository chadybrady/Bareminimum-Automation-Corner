# 🆘 Create Break Glass Accounts

Creates two **emergency access (Break Glass) accounts** in Microsoft Entra ID, assigns them the **Global Administrator** role, and optionally creates or assigns a Conditional Access exclusion group.

---

## 📄 Script

### `CreateEntraIDBreakTheGlass.ps1`

| Step | Action |
|---|---|
| 1 | Installs and imports the `Microsoft.Entra` module |
| 2 | Connects to Entra ID with required permissions |
| 3 | Prompts for the tenant domain |
| 4 | Generates two cryptographically secure 24-character passwords |
| 5 | Creates `breaktheglass1@<domain>` and `breaktheglass2@<domain>` |
| 6 | Assigns the **Global Administrator** role to both accounts |
| 7 | Optionally creates or uses an existing CA exclusion group |
| 8 | Displays account details — **store these immediately and securely** |

**Account settings applied:**
- Password expiration: **Disabled** (`DisablePasswordExpiration`)
- Force password change on next login: **Disabled**
- Account enabled: **Yes**

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `Microsoft.Entra` PowerShell module (auto-installed if missing)
- **Required Permissions:**
  - `User.ReadWrite.All`
  - `Group.ReadWrite.All`
  - `GroupMember.Read.All`
  - `RoleManagement.ReadWrite.Directory`
  - `Directory.ReadWrite.All`
  - `RoleManagementPolicy.ReadWrite.Directory`

---

## 🚀 Usage

```powershell
.\CreateEntraIDBreakTheGlass.ps1
```

The script will interactively prompt for:
1. **Domain** — e.g., `contoso.com`
2. **Group option** — create a new CA exclusion group, assign to an existing group, or skip

---

## 📋 Example Output

```
Break Glass Account Details:
================================
Account 1:
UPN: breaktheglass1@contoso.com
Password: <generated-secure-password>
Roles assigned: Global Administrator

Account 2:
UPN: breaktheglass2@contoso.com
Password: <generated-secure-password>
Roles assigned: Global Administrator

PLEASE STORE THESE CREDENTIALS SECURELY!
```

---

## ⚠️ Important

> 🔴 **The generated passwords are displayed only once.** Store them immediately in a secure, offline location (e.g., a physical safe or a certified password manager with offline access).

---

## 🔗 Related Links

- [Microsoft: Emergency access accounts](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access)
- [Global Administrator role](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference#global-administrator)
