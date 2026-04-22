# 🤖 Android Device Management

Scripts for managing **Android devices** enrolled in Microsoft Intune, including automated bulk device renaming.

---

## 📂 Contents

| Folder | Description |
|---|---|
| [`Rename Devices By groups/`](./Rename%20Devices%20By%20groups/) | Bulk renames Android devices to a standardised `Android-<SERIAL>` format based on Entra ID group membership |

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `Microsoft.Graph.Beta` module — `Install-Module Microsoft.Graph.Beta`
- **Required Permissions:**
  - `DeviceManagementManagedDevices.PrivilegedOperations.All`
  - `Group.Read.All`
  - `GroupMember.Read.All`
  - `Device.Read.All`

---

## 🔗 Related Links

- [Intune Android Device Management](https://learn.microsoft.com/en-us/mem/intune/enrollment/android-enroll)
- [Microsoft Graph Beta — Managed Devices](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-manageddevice)
