# 🔒 CA Creation Tools — Interactive Baseline v2

An interactive, menu-driven PowerShell tool for creating a **comprehensive Conditional Access policy baseline** in Microsoft Entra ID. Designed for operators who want full control over every configuration decision during deployment.

---

## 📄 Script

### `Create-CABaselinev2.ps1`

A PowerShell 7+ script that walks through the creation of CA policies following the **CA001–CA777 naming standard**, with support for:

- Exclusion group creation
- Named location configuration
- Per-policy selection (choose which policies to create)
- Policy state selection: **Report-Only**, **Enabled**, or **Disabled**
- Risk-based policies (requires Entra ID P2)

---

## ⚙️ Prerequisites

- **PowerShell 7.0 or later** (required — script uses `#Requires -Version 7.0`)
- `Microsoft.Graph` PowerShell SDK
- **Required Graph Permissions:**
  - `Policy.ReadWrite.ConditionalAccess`
  - `Policy.Read.All`
  - `Group.ReadWrite.All`
  - `Directory.Read.All`
  - `Application.Read.All`

---

## 🚀 Usage

```powershell
.\Create-CABaselinev2.ps1
```

The script is fully interactive — no parameters are required. You will be guided through each decision point.

---

## 📋 Policies Available

| Policy ID | Name |
|---|---|
| CA001 | Require MFA for administrators |
| CA002 | Require phishing-resistant MFA for administrators |
| CA005 | Block legacy authentication |
| CA007 | Require MFA for all users |
| CA008 | Require MFA for Azure management |
| CA009 | Sign-in risk-based MFA (P2 required) |
| CA010 | User risk-based password change (P2 required) |
| CA012 | Require compliant device |
| CA017 | Reauthentication on unmanaged devices |

---

## 🛡️ Best Practices

1. Always deploy policies in **Report-Only** mode first.
2. Monitor **Sign-in Logs** for at least 1–2 weeks before switching to Enforced.
3. Ensure Break Glass accounts are in the **exclusion group** before enforcing any policy.

---

## 🔗 Related Links

- [Conditional Access: Report-Only Mode](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-report-only)
- [CA Policy Design Guidance](https://learn.microsoft.com/en-us/entra/identity/conditional-access/plan-conditional-access)
