# 🌐 Network Settings

**Intune Proactive Remediation** scripts for detecting and correcting DNS server configuration on managed Windows devices.

---

## 📂 Scripts

| Script | Type | Description |
|---|---|---|
| `Detect-DNSServers.ps1` | Detection | Checks whether DNS servers match the expected configuration |
| `Change-DNSServers.ps1` | Remediation | Updates DNS server settings to the required values |

---

## 📋 Overview

These scripts are designed to be deployed as an **Intune Proactive Remediation** pair. The detection script runs on a schedule to identify devices with incorrect DNS settings; if non-compliant, the remediation script automatically applies the correct configuration.

---

## ⚙️ Prerequisites

- Microsoft Intune with **Proactive Remediations** (requires Microsoft Intune Plan 1 or Microsoft 365 E3/E5)
- Windows 10 / Windows 11 managed devices
- Scripts run in the **System** or **User** context (configure as appropriate in Intune)

---

## 🔧 Intune Deployment

1. In the Intune portal, navigate to **Devices → Scripts and remediations → Remediations**
2. Create a new Remediation package
3. Upload `Detect-DNSServers.ps1` as the **Detection script**
4. Upload `Change-DNSServers.ps1` as the **Remediation script**
5. Configure the **schedule** and target **device group**
6. Assign and deploy

---

## 🛡️ Notes

- Customise the expected DNS server values within the scripts to match your environment before deploying.
- Test on a pilot device group before broad deployment.

---

## 🔗 Related Links

- [Intune Proactive Remediations](https://learn.microsoft.com/en-us/mem/intune/fundamentals/remediations)
- [Windows DNS Client Configuration](https://learn.microsoft.com/en-us/windows-server/networking/dns/dns-client-architecture)
