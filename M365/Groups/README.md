# 👥 M365 Groups

PowerShell tooling for creating Microsoft 365 groups with Entra module prompts for key behavior flags.

---

## 📂 Contents

| Script | Description |
|---|---|
| [`Create-M365Group-NoTeamNoSite.ps1`](./Create-M365Group-NoTeamNoSite.ps1) | Creates a Microsoft 365 group (Unified) and lets you choose options like `WelcomeEmailDisabled` and `ProvisionSiteOnDemand` interactively. |

---

## ⚙️ What this script does

- Uses `Microsoft.Entra` and `New-EntraGroup`
- Prompts for group name, alias, visibility, and optional behavior flags
- Can disable welcome emails (`WelcomeEmailDisabled`)
- Can set SharePoint provisioning to on-demand (`ProvisionSiteOnDemand`)
- Does **not** create a Teams team

---

## ⚠️ Important note on SharePoint

`ProvisionSiteOnDemand` defers site provisioning so a SharePoint site is not automatically created at group creation time. The site can still be created later when workloads require it.

---

## 🔐 Required permissions

- Delegated scope: `Group.ReadWrite.All` (used by `Connect-Entra`)

