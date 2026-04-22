# 📧 CodeTwo

Scripts and tools for automating the deployment and standard configuration of **CodeTwo Email Signatures for Microsoft 365** within a tenant.

---

## 📂 Contents

| Folder | Description |
|---|---|
| [`CodeTwo- Standard Setup- Tool/`](./CodeTwo-%20Standard%20Setup-%20Tool/) | Automates the creation of standard Entra ID security groups and deployment of the CodeTwo Outlook add-in |

---

## 🔍 Overview

CodeTwo Email Signatures for Microsoft 365 requires specific security groups and add-in deployment to function correctly across a tenant. The scripts in this section handle that bootstrapping process using the **Microsoft Entra** and **Microsoft Teams** PowerShell modules.

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `Microsoft.Entra` module
- `MicrosoftTeams` module
- Global Administrator or appropriate delegated permissions to create groups and deploy apps

---

## 🔗 Related Links

- [CodeTwo Email Signatures for Microsoft 365](https://www.codetwo.com/email-signatures/office-365/)
- [Microsoft Entra PowerShell Module](https://learn.microsoft.com/en-us/powershell/entra-powershell/)
