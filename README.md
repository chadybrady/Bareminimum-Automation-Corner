# 🤖 Bareminimum Automation Corner

![GitHub stars](https://img.shields.io/github/stars/chadybrady/Bareminimum-Automation-Corner?style=flat-square)
![GitHub forks](https://img.shields.io/github/forks/chadybrady/Bareminimum-Automation-Corner?style=flat-square)
![GitHub last commit](https://img.shields.io/github/last-commit/chadybrady/Bareminimum-Automation-Corner?style=flat-square)
![PowerShell](https://img.shields.io/badge/language-PowerShell-5391FE?logo=powershell&logoColor=white&style=flat-square)

> A practical collection of PowerShell automation tools for Microsoft 365 administrators, focused on Entra ID, Intune, OneDrive, enterprise app governance, and tenant operations. Each folder groups scripts by workload so you can quickly find deployment, monitoring, and remediation utilities.

---

## 📂 Repository Structure

| Folder | Description |
|---|---|
| [`CodeTwo/`](./CodeTwo/) | CodeTwo deployment and setup automation for Microsoft 365 environments. |
| [`Entra/`](./Entra/) | Entra ID automation: admin account provisioning, break-glass workflows, Conditional Access, domain changes, and enterprise app governance. |
| [`Excel/`](./Excel/) | Utility tooling for CSV-to-Excel conversion and report formatting. |
| [`Intune/`](./Intune/) | Intune administration scripts for Android, Apple tokens, Win32 apps, DNS remediations, and configuration validation. |
| [`M365/`](./M365/) | Microsoft 365 automation for Viva/Copilot controls, permissions inventory, config drift checks, and OneDrive operations. |

---

## ⚙️ Prerequisites

Most scripts require:

- **PowerShell 5.1+** (PowerShell 7+ recommended for newer scripts)
- **Microsoft Graph PowerShell SDK** (`Install-Module Microsoft.Graph`)
- **Workload-specific modules** such as `Microsoft.Entra`, `ExchangeOnlineManagement`, or `ImportExcel` depending on the script
- An account with the **required Microsoft 365 / Entra / Intune admin roles** for each operation

> Always review the local README in each folder before running a script.

---

## 🚀 Getting Started

1. Clone this repository:

```powershell
git clone https://github.com/chadybrady/Bareminimum-Automation-Corner.git
cd Bareminimum-Automation-Corner
```

2. Open the folder for the workload you want to automate.
3. Review that folder's `README.md` for required modules, roles, and parameters.
4. Run the script from an elevated PowerShell session and use test/report-only mode when available.

---

## 🛡️ Security

- Never hardcode credentials, secrets, or tenant-sensitive values in scripts.
- Prefer least-privilege Graph scopes and role assignments.
- Test in lab/non-production first, then roll out in production with change control.
- Keep break-glass credentials and generated reports in secure storage.

---

## 🤝 Contributing

Contributions are welcome:

1. Fork the repository and create a branch for your change.
2. Place scripts in the correct workload folder.
3. Include or update `README.md` documentation for your folder.
4. Open a pull request with clear scope and validation notes.

---

## 📄 License

This repository is provided as-is for educational and operational use. Validate each script in your own environment before production use.

---

## 📜 Full Script Inventory

| Script | Description |
|---|---|
| [`CodeTwo/CodeTwo- Standard Setup- Tool/CodeTwoFramworkSetup.ps1`](./CodeTwo/CodeTwo-%20Standard%20Setup-%20Tool/CodeTwoFramworkSetup.ps1) | Deploys baseline CodeTwo group structure and app setup dependencies in Microsoft 365. |
| [`Entra/Admin accounts/Create ADM accounts with excel/Create-AdminUsers.ps1`](./Entra/Admin%20accounts/Create%20ADM%20accounts%20with%20excel/Create-AdminUsers.ps1) | Creates Entra admin accounts from an Excel input file, including role and group assignment support. |
| [`Entra/Admin accounts/Create ADM accounts with excel/_GenerateTemplate.ps1`](./Entra/Admin%20accounts/Create%20ADM%20accounts%20with%20excel/_GenerateTemplate.ps1) | Generates the Excel template used as input for bulk admin account creation. |
| [`Entra/Break the glass/Create-Break-Glass-Accounts/CreateEntraIDBreakTheGlass.ps1`](./Entra/Break%20the%20glass/Create-Break-Glass-Accounts/CreateEntraIDBreakTheGlass.ps1) | Creates emergency Break Glass accounts and applies hardened baseline configuration. |
| [`Entra/Conditional access/CA creation tools/Create-CABaselinev2.ps1`](./Entra/Conditional%20access/CA%20creation%20tools/Create-CABaselinev2.ps1) | Interactive tool that creates a customizable Conditional Access baseline with policy-by-policy control. |
| [`Entra/Conditional access/Create-CA-Baseline/CreateCaBaseline.ps1`](./Entra/Conditional%20access/Create-CA-Baseline/CreateCaBaseline.ps1) | Creates a predefined Conditional Access baseline policy set for Entra ID. |
| [`Entra/Domain change in bulk/EntraIdChangeDomainAllIdentites.ps1`](./Entra/Domain%20change%20in%20bulk/EntraIdChangeDomainAllIdentites.ps1) | Bulk-changes primary email domains across supported Entra ID and Exchange Online identities. |
| [`Entra/Enterprise Application/EA- Permisson and secret monitoring/enterpriseappmonitoringsecret.ps1`](./Entra/Enterprise%20Application/EA-%20Permisson%20and%20secret%20monitoring/enterpriseappmonitoringsecret.ps1) | Audits enterprise app credentials and permissions, highlighting expiring secrets and high-risk grants. |
| [`Entra/Enterprise Application/Enterprise App Testing Tool/Test-EnterpriseApplications.ps1`](./Entra/Enterprise%20Application/Enterprise%20App%20Testing%20Tool/Test-EnterpriseApplications.ps1) | Tests enterprise app posture and exports a governance-focused report. |
| [`Excel/ConvertCSVToExcel.ps1`](./Excel/ConvertCSVToExcel.ps1) | Converts CSV files into formatted Excel workbooks using ImportExcel. |
| [`Intune/Android/Rename Devices By groups/AndroidRenameByDeviceGroups.ps1`](./Intune/Android/Rename%20Devices%20By%20groups/AndroidRenameByDeviceGroups.ps1) | Renames Android devices in Intune based on group targeting and serial-based naming. |
| [`Intune/Apple-Token-Monitoring/applemonitoring.ps1`](./Intune/Apple-Token-Monitoring/applemonitoring.ps1) | Monitors Apple APNs, VPP, and DEP token expiry for Intune and reports status. |
| [`Intune/Application Management Tools/Automatic update of Win32 Apps/Check-Win32AppVersions.ps1`](./Intune/Application%20Management%20Tools/Automatic%20update%20of%20Win32%20Apps/Check-Win32AppVersions.ps1) | Checks newer Win32 app versions and updates SharePoint approval queue entries. |
| [`Intune/Application Management Tools/Automatic update of Win32 Apps/Deploy-Win32AppUpdate.ps1`](./Intune/Application%20Management%20Tools/Automatic%20update%20of%20Win32%20Apps/Deploy-Win32AppUpdate.ps1) | Packages or uploads approved Win32 app updates and deploys new content to Intune. |
| [`Intune/Intune Testing tool Sec/Test-IntuneConfiguration.ps1`](./Intune/Intune%20Testing%20tool%20Sec/Test-IntuneConfiguration.ps1) | Runs read-only checks against Intune configuration and reports baseline compliance. |
| [`Intune/Network Settings/Change-DNSServers.ps1`](./Intune/Network%20Settings/Change-DNSServers.ps1) | Remediation script for Intune that applies approved DNS server settings. |
| [`Intune/Network Settings/Detect-DNSServers.ps1`](./Intune/Network%20Settings/Detect-DNSServers.ps1) | Detection script for Intune remediation that checks DNS server compliance. |
| [`Intune/Win32/Win32-ForceReinstallApp/Win32ForceReinstallApp.ps1`](./Intune/Win32/Win32-ForceReinstallApp/Win32ForceReinstallApp.ps1) | Forces Win32 app reinstall by removing local detection artifacts. |
| [`M365/Copilot and Viva/Viva- Disable Apps and features/disableVivaFeatures.ps1`](./M365/Copilot%20and%20Viva/Viva-%20Disable%20Apps%20and%20features/disableVivaFeatures.ps1) | Disables selected Viva modules and feature surfaces in Microsoft 365. |
| [`M365/M365 Permission inventory tool/M365-Permissions-Inventory.ps1`](./M365/M365%20Permission%20inventory%20tool/M365-Permissions-Inventory.ps1) | Exports tenant-wide Microsoft 365 permission assignments for review and auditing. |
| [`M365/M365- Configuration drift management tool/AzureConfigDrift/AzureConfigDrift.ps1`](./M365/M365-%20Configuration%20drift%20management%20tool/AzureConfigDrift/AzureConfigDrift.ps1) | Captures configuration snapshots and detects drift across Entra ID and Intune. |
| [`M365/Onedrive/Detect-OneDriveOldFolders.ps1`](./M365/Onedrive/Detect-OneDriveOldFolders.ps1) | Detects leftover OneDrive .old folders for Intune Proactive Remediation. |
| [`M365/Onedrive/O4BUnlockLockedPersonalSites.ps1`](./M365/Onedrive/O4BUnlockLockedPersonalSites.ps1) | Unlocks OneDrive personal sites currently set to NoAccess lock state. |
| [`M365/Onedrive/Remediate-OneDriveOldFolders.ps1`](./M365/Onedrive/Remediate-OneDriveOldFolders.ps1) | Deletes detected OneDrive .old folders under user profiles. |
| [`M365/Onedrive/Remove-OneDriveKFMCloudFolders.ps1`](./M365/Onedrive/Remove-OneDriveKFMCloudFolders.ps1) | Removes KFM cloud folders from targeted OneDrive accounts via Microsoft Graph. |
