# 📦 Win32 App Management

Scripts for managing **Win32 application deployments** in Microsoft Intune, including tools to force-reinstall apps that have failed to install correctly.

---

## 📂 Contents

| Folder | Description |
|---|---|
| [`Win32-ForceReinstallApp/`](./Win32-ForceReinstallApp/) | Clears Intune Win32 app registry entries and cache to trigger a forced reinstall |

---

## ⚙️ Prerequisites

- Local **Administrator** privileges on the target device
- Microsoft Intune-enrolled Windows device
- App ID (GUID) from the Intune portal

---

## 🔗 Related Links

- [Intune Win32 App Management](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management)
- [Troubleshoot Win32 App Installations](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-troubleshoot)

## 🚀 Usage

Review script parameters and run in a test environment first.

## 🛡️ Security Notes

- Validate package content and detection rules in pilot groups before broad assignment.
- Restrict write access to package sources, app metadata, and deployment automations.
- Use change control when replacing existing Win32 content versions to avoid unintended app impact.
