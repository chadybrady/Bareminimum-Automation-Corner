# 🔒 Create CA Baseline

Creates a standard **Conditional Access policy baseline** (CA001–CA017) in Microsoft Entra ID using the `Microsoft.Entra` and `Microsoft.Graph` PowerShell modules.

---

## 📄 Script

### `CreateCaBaseline.ps1`

Deploys a set of foundational Conditional Access policies to protect your tenant. The script guides you through exclusion group setup and policy state selection before creating each policy.

---

## 📋 Policies Created

| Policy | Name | Requires |
|---|---|---|
| CA001 | Require MFA for administrators | Entra P1+ |
| CA002 | Require phishing-resistant MFA for administrators | Entra P1+ |
| CA005 | Block legacy authentication | Entra P1+ |
| CA007 | Require MFA for all users | Entra P1+ |
| CA008 | Require MFA for Azure management | Entra P1+ |
| CA009 | Sign-in risk-based MFA | **Entra ID P2** |
| CA010 | User risk-based password change | **Entra ID P2** |
| CA012 | Require compliant device | Entra P1+ |
| CA017 | Reauthentication on unmanaged devices | Entra P1+ |

> ℹ️ CA009 and CA010 are only created when you answer **Y** to the Entra ID P2 licence prompt.

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `Microsoft.Entra` module (auto-installed if missing)
- `Microsoft.Graph` module (auto-installed if missing)
- `Microsoft.Graph.Identity.SignIns` module (auto-installed if missing)
- **Required Permissions:**
  - `Policy.ReadWrite.ConditionalAccess`
  - `Policy.Read.All`
  - `Group.ReadWrite.All`

---

## 🚀 Usage

```powershell
.\CreateCaBaseline.ps1
```

The script will interactively prompt for:
1. Entra ID P2 licence availability
2. Exclusion group option (create new / use existing / skip)
3. Report-Only vs. Enforced mode for all policies

---

## 🛡️ Best Practices

- Run in **Report-Only** mode first: answer `Y` when prompted.
- Verify Break Glass accounts are in the exclusion group **before** enforcing policies.
- The script automatically disconnects from Entra ID and cleans up imported modules after completion.

---

## 🔗 Related Links

- [Conditional Access Policy Baseline](https://learn.microsoft.com/en-us/entra/identity/conditional-access/plan-conditional-access)
- [Entra ID Protection (P2)](https://learn.microsoft.com/en-us/entra/id-protection/)
