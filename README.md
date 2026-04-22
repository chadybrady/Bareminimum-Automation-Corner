# 🤖 Bareminimum Automation Corner

> A curated collection of PowerShell automation scripts for Microsoft 365, Entra ID, Intune, Power Platform, and more — built to help IT administrators and engineers deploy, manage, and secure their environments with minimal effort.

---

## 📂 Repository Structure

| Folder | Description |
|---|---|
| [`CodeTwo/`](./CodeTwo/) | Automated deployment and configuration of CodeTwo email signature solutions |
| [`Entra/`](./Entra/) | Microsoft Entra ID scripts: Break Glass accounts, Conditional Access baselines, Enterprise Application governance |
| [`Excel/`](./Excel/) | PowerShell utilities for Excel file processing and conversion |
| [`Intune/`](./Intune/) | Microsoft Intune scripts: Android management, Apple token monitoring, Win32 app tooling, network settings, and testing |
| [`M365/`](./M365/) | Microsoft 365 scripts: Copilot/Viva feature management, tenant-wide permissions inventory, and OneDrive administration |
| [`Powerplatform/`](./Powerplatform/) | Power Platform inventory and governance scripts for Power Apps and Power Automate |

---

## ⚙️ Prerequisites

Most scripts in this repository share the following requirements:

- **PowerShell 5.1+** (PowerShell 7+ recommended for newer scripts)
- **Microsoft Graph PowerShell SDK** — `Install-Module Microsoft.Graph`
- **Microsoft Entra PowerShell module** — `Install-Module Microsoft.Entra`
- Appropriate **Microsoft 365 / Azure AD admin permissions** for the targeted workload

> 💡 Each subfolder contains its own `README.md` with specific prerequisites, permissions, and usage instructions.

---

## 🚀 Getting Started

1. Clone or download this repository.
2. Navigate to the folder for the area you want to automate.
3. Read the local `README.md` for prerequisites and usage details.
4. Run the relevant `.ps1` script from an elevated PowerShell session.

```powershell
# Example: Clone the repo
git clone https://github.com/chadybrady/Bareminimum-Automation-Corner.git
cd Bareminimum-Automation-Corner
```

---

## 🛡️ Security & Best Practices

- **Never hard-code credentials** in scripts. Use Azure Automation Variables, Key Vault, or interactive prompts.
- Always test scripts in a **non-production environment** or in **Report-Only mode** (where applicable) before enforcing changes.
- Store Break Glass account credentials and sensitive outputs in a **secure vault** (e.g., Azure Key Vault or a password manager).
- Review required **Graph API permissions** before granting admin consent.

---

## 🤝 Contributing

Contributions are welcome! If you have a useful automation script that fits the theme of this repository:

1. Fork the repository.
2. Create a new branch for your feature.
3. Add your script(s) to the appropriate folder along with a `README.md`.
4. Open a pull request with a clear description of what the script does.

---

## 📄 License

This repository is provided as-is for educational and operational use. Always review scripts before running them in your environment.

---

*Created and maintained by [Tim Hjort / Bareminimum Solutions](https://github.com/chadybrady)*
