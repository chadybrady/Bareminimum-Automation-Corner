# 🌐 SharePoint Online

> Repair and maintain SharePoint Online sites with focused, operator-driven PowerShell tools.

---

## 📂 Contents

| Script | Description |
|---|---|
| [`Repair-SharePointWelcomePage.ps1`](./Repair-SharePointWelcomePage.ps1) | Restores, recreates, and assigns a modern SharePoint site home page. |

---

## ✨ Features

`Repair-SharePointWelcomePage.ps1`:

1. Connects to the target site with `PnP.PowerShell`.
2. Reads the current `WelcomePage` value.
3. Checks whether the requested page exists in **Site Pages**.
4. Attempts to restore a matching page from the recycle bin.
5. Creates and publishes a new modern home page if restoration is not possible.
6. Assigns the page as the site home page and verifies the result.

---

## ⚙️ Prerequisites

- PowerShell 7+
- [`PnP.PowerShell`](https://pnp.github.io/powershell/)
- A Microsoft Entra app registration client ID supported by PnP interactive authentication
- SharePoint permissions sufficient to:
  - Read and create site pages
  - Read and restore recycle-bin items
  - update the site home page

Install the module if needed:

```powershell
Install-Module PnP.PowerShell -Scope CurrentUser
```

---

## 🚀 Usage

```powershell
.\Repair-SharePointWelcomePage.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/Operations" `
    -ClientId "00000000-0000-0000-0000-000000000000" `
    -HomePageName "Home.aspx"
```

| Parameter | Description |
|---|---|
| `SiteUrl` | Full URL of the SharePoint site to repair. |
| `ClientId` | Application ID used by `Connect-PnPOnline`. |
| `HomePageName` | Page filename, such as `Home.aspx`. |

If interactive authentication fails, the script prints an equivalent `-DeviceLogin` command for troubleshooting.

---

## 📤 Output

The script writes progress and validation results to the console. It reports whether the home page was:

- Already present
- Restored from the recycle bin
- Recreated and published

---

## 🛡️ Security Notes

- Test against a non-production site before repairing a business-critical home page.
- Confirm `SiteUrl` and `HomePageName` before running; the script can change the active site home page.
- Use a least-privilege app registration and do not embed secrets in the script.
- Review a restored or newly created page before announcing the site as repaired.

---

## 🔗 Related Links

- [PnP PowerShell documentation](https://pnp.github.io/powershell/)
- [SharePoint modern pages](https://learn.microsoft.com/en-us/sharepoint/dev/solution-guidance/modern-experience-customizations-customize-pages)
- [Microsoft 365 tools](../README.md)
