# 📘 EntraIdChangeDomainAllIdentites

Bulk-changes the primary email domain on all identities in a Microsoft 365 tenant (Entra ID + Exchange Online). Designed for domain migrations or rebranding scenarios.


---

## 📂 Contents

| Item | Description |
|---|---|
| [`EntraIdChangeDomainAllIdentites.ps1`](./EntraIdChangeDomainAllIdentites.ps1) | Bulk-changes primary email domains across supported Entra ID and Exchange Online identities. |

## What it does

For every object whose primary SMTP address matches the source domain, the script:

1. Changes the primary address to the target domain
2. Removes **all** SMTP aliases (any domain) — leaving only the new primary
3. Non-SMTP proxy types (X500:, SIP:, etc.) are preserved

### Object types targeted

| Scope | Type |
|---|---|
| Entra ID | User accounts (UPN + mail attribute) |
| Entra ID | Microsoft 365 groups |
| Exchange Online | User mailboxes |
| Exchange Online | Shared mailboxes |
| Exchange Online | Distribution groups |
| Exchange Online | Mail-enabled security groups |
| Exchange Online | Microsoft 365 group mailboxes |
| Exchange Online | Mail contacts |

---

## ⚙️ Prerequisites

### PowerShell modules

Installed automatically if missing (current user scope):

| Module | Minimum version |
|---|---|
| `Microsoft.Graph.Users` | 2.0.0 |
| `Microsoft.Graph.Groups` | 2.0.0 |
| `Microsoft.Graph.Identity.DirectoryManagement` | 2.0.0 |
| `ExchangeOnlineManagement` | 3.0.0 |

### Permissions

| Service | Required permission / role |
|---|---|
| Microsoft Graph | `User.ReadWrite.All` |
| Microsoft Graph | `Group.ReadWrite.All` |
| Microsoft Graph | `Directory.ReadWrite.All` |
| Exchange Online | Exchange Administrator |

---

## 🚀 Usage

```powershell
# Dry run — shows what would change, makes no changes
.\EntraIdChangeDomainAllIdentites.ps1 -WhatIf

# Full run — connects, prompts for domain selection, then applies changes
.\EntraIdChangeDomainAllIdentites.ps1

# Skip Exchange Online (Entra ID only)
.\EntraIdChangeDomainAllIdentites.ps1 -SkipExchangeOnline

# Skip Entra ID (Exchange Online only)
.\EntraIdChangeDomainAllIdentites.ps1 -SkipEntraID
```

### Parameters

| Parameter | Type | Description |
|---|---|---|
| `-WhatIf` | Switch | Simulate the run. Connects and discovers objects, but makes no changes. |
| `-SkipExchangeOnline` | Switch | Skip all Exchange Online processing. |
| `-SkipEntraID` | Switch | Skip all Entra ID (Graph) processing. |

---

## 🚀 Usage

1. Open PowerShell 5.1 or later
2. Run the script with `-WhatIf` first and review the output
3. Verify the object counts and proposed changes look correct
4. Re-run without `-WhatIf` and type `YES` at the confirmation prompt

```
  Change FROM : @contoso.de
  Change TO   : @contoso.com

  Type YES to proceed (or anything else to abort): YES
```

---

## Output

- Progress is shown in the console with timestamps and colour-coded status
- A log file is saved in the same directory as the script on every run (including WhatIf runs):

```
DomainChange_contoso.de_to_contoso.com_20260302_210000.log
```

---

## 🛡️ Security Notes

- The script uses `ConsistencyLevel: eventual` for Microsoft Graph queries — required for `endsWith` filters to work correctly
- The confirmation prompt is skipped in `-WhatIf` mode
- Guest accounts and service principals are not in scope
- Running the script requires an interactive login to both Microsoft Graph and Exchange Online

## 🔗 Related Links

- https://learn.microsoft.com/en-us/entra/fundamentals/
- https://learn.microsoft.com/en-us/powershell/entra-powershell/
