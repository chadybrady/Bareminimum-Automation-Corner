# 🔁 Win32 Force Reinstall App

Forces a complete **reinstall of a Win32 application** deployed via Microsoft Intune by clearing the associated registry entries, detection rule artifacts, and cached data — without requiring the device to unenroll or re-image.

---

## 📄 Script

### `Win32ForceReinstallApp.ps1`

Implements the latest techniques for forcing a Win32 app reinstall in Intune, including:

- **GRS (Global Re-evaluation Schedule) hash discovery** — resets Intune's evaluation state for the app
- **User SID-specific registry cleanup** — clears per-user installation tracking
- **Support for old and new Intune log formats**
- **Comprehensive file and folder cache cleanup**

> Credits: Techniques based on research by **Johan Arwidmark** (Deployment Research) and **Rudy Ooms** (@Mister_MDM / Call4Cloud).

---

## ⚙️ Prerequisites

- **Administrator privileges** on the target device (`#Requires -RunAsAdministrator`)
- The **App ID (GUID)** of the Win32 app — found in the Intune portal URL when viewing the app

---

## 🚀 Usage

```powershell
# Run as Administrator
.\Win32ForceReinstallApp.ps1 -AppId "12345678-1234-1234-1234-123456789012"
```

**Finding the App ID:**
1. Open the [Intune portal](https://intune.microsoft.com)
2. Navigate to **Apps → All Apps**
3. Click on your app — the GUID is in the URL: `.../apps/**<AppId>**/...`

---

## ⚠️ Important Post-Run Steps

After running the script, you **must also** remove any detection rule artifacts manually so Intune detects the app as not installed:

- **File/folder detection:** Delete the file or folder the rule checks for
- **Registry detection:** Remove the registry key used for detection
- **MSI detection:** Uninstall the MSI product

Once complete, Intune will re-evaluate the device on its next check-in and reinstall the app.

---

## 🛡️ Notes

- This script modifies registry keys and deletes cache files — always test in a non-production environment first.
- A device **restart** may be required after running the script for changes to take full effect.
- Version: **2.0**

---

## 🔗 Related Links

- [Johan Arwidmark — Force Win32 App Reinstall](https://www.deploymentresearch.com/force-application-reinstall-in-microsoft-intune-win32-apps/)
- [Rudy Ooms — Retry Failed Win32 App Installation](https://call4cloud.nl/retry-failed-win32app-installation/)
- [Intune Win32 App Troubleshooting](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-troubleshoot)
