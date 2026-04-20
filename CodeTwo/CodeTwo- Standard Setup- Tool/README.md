# 🔑 CodeTwo Standard Setup Tool

Automates the standard initial deployment of **CodeTwo Email Signatures for Microsoft 365**, including the creation of required security groups in Entra ID and deployment of the CodeTwo Outlook add-in across the tenant.

---

## 📄 Script

### `CodeTwoFramworkSetup.ps1`

Performs the full standard setup framework for a CodeTwo deployment:

| Step | Action |
|---|---|
| 1 | Installs required PowerShell modules (`Microsoft.Entra`, `MicrosoftTeams`) if not present |
| 2 | Connects to Microsoft Entra ID |
| 3 | Creates standard CodeTwo security groups (optional) |
| 4 | Connects to Microsoft Teams |
| 5 | Deploys the CodeTwo Signatures add-in for Outlook to the specified group |

**Groups created (optional):**

| Group Display Name | Purpose |
|---|---|
| `AZ-MDM-User-CodeTwoSignatureAdmins` | Admins who manage CodeTwo email signatures |
| `AZ-MDM-User-CodeTwoAdmins` | CodeTwo product administrators |
| `AZ-MDM-User-CodeTwoAddInDeploy` | Target group for Outlook add-in deployment |

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `Microsoft.Entra` PowerShell module
- `MicrosoftTeams` PowerShell module
- **Required Permissions:**
  - `Group.ReadWrite.All`
  - `Group.Create`
  - Teams admin access for add-in deployment

---

## 🚀 Usage

```powershell
.\CodeTwoFramworkSetup.ps1
```

The script will interactively prompt for:
1. Whether to install required PowerShell modules
2. Whether to create the standard security groups
3. Whether to deploy the CodeTwo Outlook add-in

---

## 📝 Notes

- If groups already exist, skip the group creation step and provide an existing group ID when prompted for add-in deployment.
- The CodeTwo add-in App ID used is `WA200003022` (Office Store ID for CodeTwo Signatures for Outlook).
- Ensure you have a valid **CodeTwo Email Signatures for Microsoft 365** licence before running this script.

---

## 🔗 Related Links

- [CodeTwo Email Signatures for Microsoft 365](https://www.codetwo.com/email-signatures/office-365/)
- [Microsoft Integrated Apps Deployment](https://learn.microsoft.com/en-us/microsoft-365/admin/manage/manage-addins-in-the-admin-center)
