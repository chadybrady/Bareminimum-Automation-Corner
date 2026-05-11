# 📦 Application Management Tools

Scripts and pipelines for managing the **lifecycle of applications deployed through Microsoft Intune**, including automated version detection, approval workflows, and Win32 app updates.

---

## 📂 Contents

| Folder | Description |
|---|---|
| [`Automatic update of Win32 Apps/`](./Automatic%20update%20of%20Win32%20Apps/) | End-to-end automated pipeline for detecting, approving, and deploying Win32 app updates via Azure Automation, Power Automate, and SharePoint |

---

## ⚙️ Prerequisites

- **PowerShell 7.2+** (Azure Automation runtime)
- **Azure Automation Account** with System-Assigned Managed Identity
- **Azure Blob Storage** container for Win32 package storage
- **SharePoint Online** list (`Win32-App-Updates`) for app tracking and approval state
- **Power Automate** with Premium connectors (Azure Automation, SharePoint, Teams, Outlook)
- **Microsoft Graph** app role permissions assigned to the Managed Identity:
  - `Sites.ReadWrite.All`
  - `DeviceManagementApps.ReadWrite.All`

---

## 🛡️ Security Notes

- All deployments require an explicit approval step via Teams adaptive card before any Intune content is modified.
- The Managed Identity is granted only the minimum permissions required — `DeviceManagementApps.ReadWrite.All` and `Sites.ReadWrite.All`.
- Never store credentials in runbook code; use Azure Automation Variables or Managed Identity authentication exclusively.

---

## 🔗 Related Links

- [Intune Win32 App Management](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management)
- [Azure Automation Runbooks](https://learn.microsoft.com/en-us/azure/automation/automation-runbook-types)
- [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
- [Power Automate Documentation](https://learn.microsoft.com/en-us/power-automate/)
