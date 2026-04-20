# 🔒 Conditional Access

Scripts for deploying and managing **Conditional Access (CA) policies** in Microsoft Entra ID. Includes tools for creating a complete security baseline and an interactive v2 CA creation tool.

---

## 📂 Contents

| Folder | Description |
|---|---|
| [`Create-CA-Baseline/`](./Create-CA-Baseline/) | Creates a standard CA policy baseline (CA001–CA017) using the Entra PowerShell module |
| [`CA creation tools/`](./CA%20creation%20tools/) | Interactive v2 CA baseline creation tool with extended policy support and named locations |

---

## 📋 Policies Covered

| Policy ID | Name | Description |
|---|---|---|
| CA001 | Require MFA for administrators | MFA required for all privileged admin roles |
| CA002 | Require phishing-resistant MFA for administrators | Compliant device + MFA for admins |
| CA005 | Block legacy authentication | Blocks Exchange Active Sync and other legacy clients |
| CA007 | Require MFA for all users | MFA with 1-day sign-in frequency for all users |
| CA008 | Require MFA for Azure management | MFA for access to Azure portal and management APIs |
| CA009 | Sign-in risk-based MFA | Risk-based MFA (requires Entra ID P2) |
| CA010 | User risk-based password change | Forces password change for high/medium risk users (P2) |
| CA012 | Require compliant device | Device compliance required for browser and modern auth |
| CA017 | Reauthentication on unmanaged devices | 1-hour session + no persistent browser on unmanaged devices |

---

## ⚙️ Prerequisites

- PowerShell 5.1+ (PowerShell 7+ for the v2 tool)
- `Microsoft.Entra` module
- `Microsoft.Graph` module
- `Microsoft.Graph.Identity.SignIns` module
- **Required Permissions:**
  - `Policy.ReadWrite.ConditionalAccess`
  - `Policy.Read.All`
  - `Group.ReadWrite.All`
  - `Directory.Read.All`
  - `Application.Read.All`

---

## 🛡️ Best Practices

- Always create policies in **Report-Only mode** first and monitor impact in the Sign-in logs.
- Ensure Break Glass accounts are **excluded** from all CA policies before enforcing them.
- Use **named locations** for trusted IP ranges to reduce friction for on-premises users.

---

## 🔗 Related Links

- [Conditional Access Overview](https://learn.microsoft.com/en-us/entra/identity/conditional-access/overview)
- [Microsoft Entra CA Policy Templates](https://learn.microsoft.com/en-us/entra/identity/conditional-access/policy-migration-mfa)
- [Sign-in Risk Policies (P2)](https://learn.microsoft.com/en-us/entra/id-protection/concept-identity-protection-policies)
