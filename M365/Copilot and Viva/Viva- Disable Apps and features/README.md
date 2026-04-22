# 🚫 Viva — Disable Apps and Features

Bulk-disables a configurable set of **Microsoft Viva and Copilot features** across your Microsoft 365 tenant using Exchange Online Management.

---

## 📄 Script

### `disableVivaFeatures.ps1`

Connects to Exchange Online and disables a curated list of Viva and Copilot feature IDs tenant-wide. Useful for organisations that want to control which Viva capabilities are available to users.

**Features disabled by default:**

| Feature ID | Description |
|---|---|
| `CustomizationControl` | Custom Viva configuration controls |
| `PulseConversation` | Viva Pulse conversation features |
| `CopilotInVivaPulse` | Copilot integration in Viva Pulse |
| `PulseExpWithM365Copilot` | Pulse experience with M365 Copilot |
| `PulseDelegation` | Pulse delegation capabilities |
| `CopilotInVivaGoals` | Copilot in Viva Goals |
| `CopilotInVivaGlint` | Copilot in Viva Glint |
| `AISummarization` | AI summarisation features |
| `CopilotInVivaEngage` | Copilot in Viva Engage |
| `Reflection` | Viva Insights Reflection |
| `CopilotDashboard` | Copilot usage dashboard |
| `DigestWelcomeEmail` | Viva Insights digest welcome email |
| `AutoCxoIdentification` | Automated leader/CxO identification |
| `MeetingCostAndQuality` | Meeting cost and quality insights |
| `CopilotDashboardDelegation` | Copilot dashboard delegation |
| `AnalystReportPublish` | Analyst report publishing |
| `CopilotInVivaInsights` | Copilot in Viva Insights |
| `AdvancedInsights` | Advanced Viva Insights |
| `CopilotChatInVivaInsights` | Copilot chat within Viva Insights |

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `ExchangeOnlineManagement` module (auto-installed if missing)
- `MicrosoftTeams` module (auto-installed if missing)
- **Required Role:** Exchange Administrator

---

## 🚀 Usage

```powershell
.\disableVivaFeatures.ps1
```

The script will:
1. Prompt whether to install required modules
2. Connect to Exchange Online
3. Disable all features in the `$FeatureIDs` array

**To customise which features are disabled,** edit the `$FeatureIDs` array at the top of the script before running.

---

## 🛡️ Notes

- Changes apply **tenant-wide** — all users will be affected.
- Some features may require additional licences (e.g., Viva Insights P1/P2) to be present before they can be disabled.
- To re-enable a feature, use the corresponding `Enable-` command or remove it from the `$FeatureIDs` array.

---

## 🔗 Related Links

- [Manage Viva Feature Access Management](https://learn.microsoft.com/en-us/viva/feature-access-management)
- [ExchangeOnlineManagement Module](https://learn.microsoft.com/en-us/powershell/exchange/exchange-online-powershell-v2)
