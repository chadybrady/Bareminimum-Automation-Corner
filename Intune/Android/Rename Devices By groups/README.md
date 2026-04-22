# 🤖 Rename Android Devices by Group

Bulk renames **Android devices** enrolled in Microsoft Intune to a standardised `Android-<SERIAL>` naming format, based on their **Entra ID device group membership**.

---

## 📄 Script

### `AndroidRenameByDeviceGroups.ps1`

Queries Intune via Microsoft Graph Beta for Android devices belonging to specified Entra ID groups, then renames each device using its serial number.

**Features:**
- Processes devices from one or more Entra ID groups
- Renames to format: `Android-<SerialNumber>`
- Skips devices that are already correctly named
- Tracks and reports success, failure, and skipped counts
- Provides detailed per-device logging

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `Microsoft.Graph.Beta` module

```powershell
Install-Module Microsoft.Graph.Beta -Force
Connect-MgBetaGraph -Scopes "DeviceManagementManagedDevices.PrivilegedOperations.All", "Group.Read.All", "GroupMember.Read.All", "Device.Read.All"
```

---

## 🚀 Configuration

Before running, edit the `$groupConfigs` array at the top of the script:

```powershell
$groupConfigs = @(
    @{ GroupId = "<your-group-id-1>"; Description = "Android Corporate Devices" }
    @{ GroupId = "<your-group-id-2>"; Description = "Android BYOD Devices" }
    # Add more groups as needed
)
```

**To find a group ID:**
```powershell
Get-MgGroup -Filter "displayName eq 'Your Group Name'" | Select-Object Id, DisplayName
```

---

## 🚀 Usage

```powershell
.\AndroidRenameByDeviceGroups.ps1
```

---

## 📋 Output Summary

At completion, the script outputs a summary:

```
=== Rename Summary ===
Successful: 42
Failed:      2
Skipped:     5
Total:       49
```

---

## ⚠️ Notes

- Only **Android** devices are processed; devices with other OS types are skipped.
- Devices without a serial number cannot be renamed and will be counted as skipped.
- Renaming is performed via the Intune Graph Beta API and may take a few minutes to reflect in the portal.

---

## 🔗 Related Links

- [Intune Device Rename via Graph](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-setdevicename)
- [Microsoft Graph Beta Managed Devices](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-manageddevice)
