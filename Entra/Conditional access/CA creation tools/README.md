# 📘 CA Creation Tools — Interactive Baseline v2

An interactive, menu-driven PowerShell tool for creating a **comprehensive Conditional Access policy baseline** in Microsoft Entra ID. Designed for operators who want full control over every configuration decision during deployment.

---

## 📂 Contents

| Item | Description |
|---|---|
| [`Create-CABaselinev2.ps1`](./Create-CABaselinev2.ps1) | Interactive tool that creates a customizable Conditional Access baseline with policy-by-policy control. |

### `Create-CABaselinev2.ps1`

A PowerShell 7+ script that walks through the creation of CA policies following the **HLD naming standard**:

```
[Persona]-[SeqNum]-[Action]-[TargetApp]-[Condition]
```

Persona prefixes and sequence ranges:

| Prefix | Persona | Sequence Range |
|--------|---------|---------------|
| `GLB` | All users (global) | 001–099 |
| `ADM` | Admin roles | 100–199 |
| `INT` | Internal users | 200–299 |
| `EXT` | External users | 300–399 |
| `GST` | Guests | 400–499 |
| `SVC` | Service accounts | 500–599 |
| `WLD` | Workload identities | 600–699 |

The script supports:

- Exclusion group creation (`CA-EXC-[Persona]-[SeqNum]-[Action]-[TargetApp]-[Condition]` per policy, plus `CA-EXC-Emergency-BreakGlass` globally)
- Named location configuration (Trusted IPs, Allowed Countries)
- Per-policy selection (choose which policies to create)
- Policy state selection per policy: **Report-Only**, **Enabled**, or **Disabled**
- Risk-based policies (requires Entra ID P2)

---

## ⚙️ Prerequisites

- **PowerShell 7.0 or later** (required — script uses `#Requires -Version 7.0`)
- `Microsoft.Graph` PowerShell SDK modules:
  - `Microsoft.Graph.Authentication`
  - `Microsoft.Graph.Identity.SignIns`
  - `Microsoft.Graph.Groups`
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

The script is fully interactive — no parameters required. You will be guided through each decision point.

---

## Policies Available

### Foundation (always included)

| Policy ID | Display Name | Description |
|-----------|-------------|-------------|
| `ADM-100` | `ADM-100-REQUIRE-AllApps-MFA-Always` | MFA for all users with admin directory roles |
| `ADM-101` | `ADM-101-SESSION-AllApps-NoPersistentSession` | 9-hour sign-in frequency, no persistent browser session for admins |
| `GLB-001` | `GLB-001-BLOCK-AllApps-LegacyAuth` | Block Basic Auth, POP, IMAP, SMTP |
| `GLB-002` | `GLB-002-REQUIRE-AllApps-MFA` | Enforce MFA for all users on all cloud apps |
| `GLB-003` | `GLB-003-BLOCK-AllApps-DeviceCodeFlow` | Block device code flow auth (deployed as Enabled, not Report-Only) |
| `GLB-006` | `GLB-006-BLOCK-SecurityInfoReg-UntrustedLocation` | Block MFA method registration from outside trusted locations |
| `GLB-007` | `GLB-007-REQUIRE-AzureMgmt-MFA` | MFA for Azure Portal, PowerShell, CLI, ARM API |
| `GLB-008` | `GLB-008-REQUIRE-AdminPortals-MFA` | MFA for all Microsoft admin portal access regardless of role |
| `GST-400` | `GST-400-REQUIRE-AllApps-MFA-Always` | Enforce MFA for all guest and external users |

### Advanced

| Policy ID | Display Name | Description |
|-----------|-------------|-------------|
| `GLB-004` | `GLB-004-BLOCK-AllApps-UnknownPlatform` | Block access from Linux, ChromeOS, and unknown OS platforms |
| `GLB-005` | `GLB-005-BLOCK-AllApps-BlockedCountry` | Block sign-ins from countries outside the Allowed Countries named location |
| `SVC-500` | `SVC-500-BLOCK-AllApps-UntrustedNetwork` | Service accounts may only authenticate from trusted IPs (requires `SG-ServiceAccounts`) |

### Risk-based (Entra ID P2 required)

| Policy ID | Display Name | Description |
|-----------|-------------|-------------|
| `GLB-009` | `GLB-009-REQUIRE-AllApps-MFA-MediumHighRiskSignIn` | MFA required on medium and high risk sign-ins |
| `GLB-010` | `GLB-010-REQUIRE-AllApps-MFA-PwChange-HighRiskUser` | MFA + forced password reset on high user risk |
| `GST-401` | `GST-401-BLOCK-AllApps-MediumHighRisk` | Block guest sign-ins with medium or high risk level |

### Optional

| Policy ID | Display Name | Description |
|-----------|-------------|-------------|
| `ADM-102` | `ADM-102-REQUIRE-AllApps-CompliantDevice` | Require Intune-compliant or hybrid-joined device for admin access |
| `ADM-103` | `ADM-103-REQUIRE-AllApps-PhishingResistantMFA` | Require FIDO2/WHfB authentication strength for admin accounts |

---

## Exclusion Groups

The script creates one security group per policy for emergency exclusions:

| Group Name | Purpose |
|-----------|---------|
| `CA-EXC-Emergency-BreakGlass` | Added to **all** policies as a global break-glass exclusion |
| `CA-EXC-[Persona]-[SeqNum]-[Action]-[TargetApp]-[Condition]` | Per-policy exclusion, mirrors the policy display name |
| `SG-ServiceAccounts` | Include group used in `SVC-500` (not an exclusion group) |

---

## 🛡️ Security Notes

1. Always deploy policies in **Report-Only** mode first (except `GLB-003` which is enabled by default).
2. Monitor **Sign-in Logs** for at least 1–2 weeks before switching to Enforced.
3. Ensure Break Glass accounts are in `CA-EXC-Emergency-BreakGlass` **before** enforcing any policy.
4. Populate `SG-ServiceAccounts` before enabling `SVC-500`.

---

## 🔗 Related Links

- [Conditional Access: Report-Only Mode](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-report-only)
- [CA Policy Design Guidance](https://learn.microsoft.com/en-us/entra/identity/conditional-access/plan-conditional-access)
- [Named Locations](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-assignment-network)
