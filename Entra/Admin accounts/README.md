# 👤 Admin Accounts

Scripts for **bulk-provisioning Entra ID administrative accounts**, including structured UPN generation, secure password creation, group memberships, permanent Entra role assignments, and PIM-eligible role assignments — all driven from an Excel input file.

---

## 📂 Contents

| Folder | Description |
|---|---|
| [`Create ADM accounts with excel/`](./Create%20ADM%20accounts%20with%20excel/) | Bulk-creates admin accounts from an Excel template with optional group memberships, permanent roles, and PIM-eligible roles |

---

## ⚙️ Prerequisites

- **PowerShell 7+**
- `Microsoft.Graph` PowerShell SDK — `Install-Module Microsoft.Graph`
- `ImportExcel` module — `Install-Module ImportExcel`
- **Required Graph scopes:**
  - `User.ReadWrite.All`
  - `Group.ReadWrite.All`
  - `GroupMember.ReadWrite.All`
  - `RoleManagement.ReadWrite.Directory`
  - `Directory.ReadWrite.All`
- **Entra ID P2 / Entra ID Governance** licence required for PIM eligible role assignments

---

## 🛡️ Security Notes

- Generated passwords are displayed once and exported to a results Excel file — store it immediately in a secure, access-controlled location.
- Provisioned accounts are configured with `DisablePasswordExpiration` and will require a password change on first login.
- Use PIM-eligible roles wherever possible to reduce standing privileged access.

---

## 🔗 Related Links

- [Microsoft Entra ID Role Assignments](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference)
- [Privileged Identity Management (PIM)](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-add-role-to-user)
- [ImportExcel module](https://github.com/dfinke/ImportExcel)

## 🚀 Usage

Review script parameters and run in a test environment first.
