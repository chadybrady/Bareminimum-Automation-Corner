# 👤 Create Admin Users from Excel

Bulk-creates **Entra ID admin accounts** from an Excel input file. Each account is provisioned with a structured UPN, a cryptographically secure password, optional group memberships, and optional permanent or PIM-eligible Entra role assignments.

---

## 📄 Script

### `Create-AdminUsers.ps1`

| Phase | Step | Action |
|---|---|---|
| 0 | 1 | Installs and imports required modules (`Microsoft.Graph.*`, `ImportExcel`) |
| 0 | 2 | Connects to Microsoft Graph with the required scopes |
| 1 | 3 | Accepts `-ExcelPath` and `-GlobalDomain` as parameters or prompts interactively |
| 1 | 4 | `-GenerateTemplate` switch creates a blank `.xlsx` template and exits |
| 2 | 5 | Imports Excel rows and validates required columns (`FirstName`, `LastName`) |
| 2 | 6 | Skips rows with empty `FirstName` or `LastName` with a warning |
| 3 | 7 | Builds UPN: `adm-<first3><last3>-<3digits>@domain` — re-rolls on collision |
| 3 | 8 | Generates a 24-character cryptographically secure password |
| 3 | 9 | Creates the user via Microsoft Graph (idempotent — skips if UPN already exists) |
| 3 | 10 | Adds the user to each group listed in the `Groups` column |
| 3 | 11 | Assigns permanent Entra roles from the `PermanentRoles` column |
| 3 | 12 | Creates PIM-eligible (no-expiry) role assignments from the `EligibleRoles` column |
| 3 | 13 | Sets the manager from the `Manager` column (UPN, display name, or object ID) |
| 4 | 14 | Prints a color-coded summary table to the console (UPN + password per user) |
| 4 | 15 | Exports all results to `AdminUsers-Results-<timestamp>.xlsx` in the same folder |

**Account settings applied:**

| Setting | Value |
|---|---|
| UPN format | `cadm-<first3_firstname><first3_lastname>-<3digits>@domain` |
| Password expiration | Disabled (`DisablePasswordExpiration`) |
| Force password change on first login | **Yes** |
| Account enabled | Yes |

---

## ⚙️ Prerequisites

- **PowerShell 7+**
- The following modules are **auto-installed** if missing:

| Module | Purpose |
|---|---|
| `Microsoft.Graph.Authentication` | `Connect-MgGraph` |
| `Microsoft.Graph.Users` | Create and query users |
| `Microsoft.Graph.Groups` | Query groups and add members |
| `Microsoft.Graph.Identity.Governance` | Permanent and PIM eligible role assignments |
| `ImportExcel` | Read input file and write results file |

- **Required Graph scopes** (prompted at sign-in):
  - `User.ReadWrite.All`
  - `Group.ReadWrite.All`
  - `GroupMember.ReadWrite.All`
  - `RoleManagement.ReadWrite.Directory`
  - `Directory.ReadWrite.All`

- **Entra ID P2 / Entra ID Governance** licence required for PIM eligible role assignments.

---

## 🚀 Usage

**Step 1 — Generate the input template**

```powershell
.\Create-AdminUsers.ps1 -GenerateTemplate -TemplatePath .\AdminUsers-Template.xlsx
```

**Step 2 — Fill in the template** (see column reference below), then run:

```powershell
# With parameters
.\Create-AdminUsers.ps1 -ExcelPath .\AdminUsers-Template.xlsx -GlobalDomain contoso.com

# Interactive (prompts for path and domain)
.\Create-AdminUsers.ps1
```

---

## 📊 Excel Column Reference

| Column | Required | Accepts | Notes |
|---|---|---|---|
| `FirstName` | ✅ | Text | Used to build the UPN prefix |
| `LastName` | ✅ | Text | Used to build the UPN prefix |
| `Domain` | — | e.g. `contoso.com` | Overrides `-GlobalDomain` for this row only |
| `DisplayName` | — | Text | Auto-built as `ADM - FirstName LastName` if blank |
| `Department` | — | Text | Set on the user object |
| `JobTitle` | — | Text | Set on the user object |
| `Manager` | — | UPN, display name, or object ID | Resolved and assigned to the user |
| `Groups` | — | Semicolon-separated names or GUIDs | e.g. `SG-Admins;AZ-CA-Exclude` |
| `PermanentRoles` | — | Semicolon-separated role display names | e.g. `Exchange Administrator` |
| `EligibleRoles` | — | Semicolon-separated role display names | Created as PIM eligible (no expiry) |

> **Multiple values** in `Groups`, `PermanentRoles`, and `EligibleRoles` must be separated with a semicolon (`;`).

---

## 📋 Example Console Output

```
▶ Processing: Jane Smith [@contoso.com]
✓   Created: cadm-jansmi-342@contoso.com
✓   Added to group: SG-Admins
✓   Permanent role: Exchange Administrator
✓   Eligible (PIM) role: Global Administrator
✓   Manager set: john.doe@contoso.com

─────────────────────────────────────────────────────────────────────
  ADMIN ACCOUNT SUMMARY
─────────────────────────────────────────────────────────────────────

  UPN        : cadm-jansmi-342@contoso.com
  Display    : CADM - Jane Smith
  Password   : X7#kLmQ2@nRpWv!9zTdA8&eC
  Groups     : SG-Admins
  Perm.Roles : Exchange Administrator
  PIM Roles  : Global Administrator

─────────────────────────────────────────────────────────────────────
  Results exported: C:\Scripts\AdminUsers-Results-20260511-143022.xlsx
─────────────────────────────────────────────────────────────────────

⚠  STORE PASSWORDS AND THE RESULTS FILE IN A SECURE LOCATION.
   The output Excel contains plaintext passwords.
```

---

## 📁 Output File

The results file `AdminUsers-Results-<yyyyMMdd-HHmmss>.xlsx` is saved to the **same folder as the input file** and contains one row per processed account:

| Column | Description |
|---|---|
| UPN | The generated `adm-...@domain` address |
| DisplayName | The display name set on the account |
| Password | The auto-generated password |
| Groups | Groups successfully joined |
| PermanentRoles | Permanent role assignments made |
| EligibleRoles | PIM eligible role assignments made |
| Status | `Created`, `Skipped`, or `Failed: <reason>` |

---

## ⚠️ Important

> 🔴 **Passwords are displayed once and exported to the results Excel.** Store the output file immediately in a secure, access-controlled location. Delete it after distributing credentials to account owners.

**Idempotency:** If a user with the generated UPN already exists in Entra ID, that row is skipped with a `⚠ Warning` — no changes are made to the existing account.

---

## 🔗 Related Links

- [Microsoft: Entra ID PIM – Assign eligible roles](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-add-role-to-user)
- [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/overview)
- [ImportExcel module](https://github.com/dfinke/ImportExcel)
- [Entra ID built-in roles reference](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference)
