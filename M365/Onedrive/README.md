# ☁️ OneDrive for Business

PowerShell scripts for **OneDrive for Business** administration, covering Known Folder Move (KFM) cleanup, old folder remediation, and unlocking locked personal sites.

---

## 📄 Scripts

| Script | Type | Description |
|---|---|---|
| `Detect-OneDriveOldFolders.ps1` | Detection | Detects leftover `.old` OneDrive folders under `C:\Users` |
| `Remediate-OneDriveOldFolders.ps1` | Remediation | Removes leftover `.old` OneDrive folders |
| `Remove-OneDriveKFMCloudFolders.ps1` | Remediation | Removes cloud-backed KFM folders from local devices |
| `O4BUnlockLockedPersonalSites.ps1` | Admin | Unlocks locked OneDrive for Business personal sites |

---

## 📋 Overview

### Proactive Remediation Pair — OneDrive `.old` Folder Cleanup

`Detect-OneDriveOldFolders.ps1` + `Remediate-OneDriveOldFolders.ps1`

Deploy these as an **Intune Proactive Remediation** pair to automatically clean up remnant `.old` and `.old_<timestamp>` OneDrive folders left behind after KFM operations. These folders can confuse users and consume disk space.

**Detection logic:** Scans all user profiles under `C:\Users` for folders matching `OneDrive*.old` or `OneDrive*.old_*` patterns.

---

### Known Folder Move Cloud Folder Cleanup

`Remove-OneDriveKFMCloudFolders.ps1`

Removes KFM-redirected cloud folders from devices — useful during KFM policy rollback or when cleaning up devices for re-enrollment.

---

### Unlock Locked Personal Sites

`O4BUnlockLockedPersonalSites.ps1`

Unlocks OneDrive for Business personal sites that have been placed in a locked state (e.g., after a user licence change or compliance hold). Useful for administrators managing licence transitions at scale.

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- **Proactive Remediation scripts:** No additional modules; runs in SYSTEM context
- **O4BUnlockLockedPersonalSites:** SharePoint Online Management Shell or PnP.PowerShell
- SharePoint/OneDrive Administrator role (for personal site unlock)

---

## 🔧 Intune Deployment (Detect + Remediate)

1. Navigate to **Devices → Scripts and remediations → Remediations**
2. Create a new Remediation package
3. Upload `Detect-OneDriveOldFolders.ps1` as the **Detection script**
4. Upload `Remediate-OneDriveOldFolders.ps1` as the **Remediation script**
5. Run in **System** context
6. Configure a schedule and assign to the target device group

---

## 🔗 Related Links

- [OneDrive Known Folder Move](https://learn.microsoft.com/en-us/onedrive/redirect-known-folders)
- [Intune Proactive Remediations](https://learn.microsoft.com/en-us/mem/intune/fundamentals/remediations)
- [Manage OneDrive with PowerShell](https://learn.microsoft.com/en-us/onedrive/manage-onedrive-using-powershell)
