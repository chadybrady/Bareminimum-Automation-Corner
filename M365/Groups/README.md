# 👥 M365 Groups

> Create Microsoft 365 groups with interactive controls for welcome email and SharePoint site provisioning behavior.

---

## 📂 Contents

| Script | Description |
|---|---|
| [`Create-M365Group-NoTeamNoSite.ps1`](./Create-M365Group-NoTeamNoSite.ps1) | Creates a Microsoft 365 group (Unified) and lets you choose options like `WelcomeEmailDisabled` and `ProvisionSiteOnDemand` interactively. |

---

## ✨ Features

- Uses `Microsoft.Entra` and `New-EntraGroup`
- Prompts for group name, alias, visibility, and optional behavior flags
- Can disable welcome emails (`WelcomeEmailDisabled`)
- Can set SharePoint provisioning to on-demand (`ProvisionSiteOnDemand`)
- Does **not** create a Teams team

---

## ⚙️ Prerequisites

- PowerShell 7+
- `Microsoft.Entra` PowerShell module
- Delegated Microsoft Graph permission: `Group.ReadWrite.All`
- An account permitted to create Microsoft 365 groups

---

## 🚀 Usage

```powershell
.\Create-M365Group-NoTeamNoSite.ps1
```

The script prompts for the display name, alias, visibility, welcome-email behavior, and on-demand SharePoint provisioning.

---

## ⚠️ SharePoint Provisioning

`ProvisionSiteOnDemand` defers site provisioning so a SharePoint site is not automatically created at group creation time. The site can still be created later when workloads require it.

---

---

## 🛡️ Security Notes

- Confirm the group name, alias, visibility, and provisioning choices before creation.
- Use least-privilege delegated permissions.
- The operation creates a tenant object even when SharePoint provisioning is deferred.

---

## 🔗 Related Links

- [Microsoft 365 Groups](https://learn.microsoft.com/en-us/microsoft-365/admin/create-groups/office-365-groups)
- [Microsoft Entra PowerShell](https://learn.microsoft.com/en-us/powershell/entra-powershell/)
