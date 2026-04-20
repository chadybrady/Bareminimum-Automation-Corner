# 🍎 Apple Token Monitoring

An **Azure Automation Runbook** that proactively monitors **Apple MDM connector tokens** in Microsoft Intune and sends alerts to a Microsoft Teams channel before they expire.

---

## 📄 Script

### `applemonitoring.ps1`

Monitors three types of Apple connectors in Intune:

| Connector | Description |
|---|---|
| **Apple MDM Push Certificate** | Required for all Apple device management in Intune |
| **Apple VPP Tokens** | Volume Purchase Program tokens for app deployment |
| **Apple DEP Tokens** | Device Enrollment Program / Apple Business Manager tokens |

Alerts are sent as **Teams Message Cards** via an incoming webhook when a connector is expired or within the configured notification range.

---

## ⚙️ Prerequisites

### Azure Automation Account Variables

The following variables **must** be created in your Azure Automation Account:

| Variable Name | Description |
|---|---|
| `TenantName` | Tenant domain (e.g., `contoso.com`) |
| `msgraph-clientcred-appid` | App ID of the service principal |
| `msgraph-clientcred-appsecret` | Client secret for the service principal |
| `TeamsChannelUri` | Incoming webhook URL for your Teams channel |

### Required App (Service Principal) Permissions

| Permission | Type |
|---|---|
| `User.Read` | Delegated |
| `Directory.Read.All` | Application |
| `DeviceManagementServiceConfig.ReadWrite.All` | Application |
| `DeviceManagementConfiguration.ReadWrite.All` | Application |
| `DeviceManagementApps.Read.All` | Application |

### Required PowerShell Modules (Automation Account)

- `Microsoft.graph.intune`

---

## 🔧 Azure Automation Setup

1. Create an **Azure Automation Account**
2. Install the `Microsoft.graph.intune` module in the Automation Account
3. Create all required **Automation Variables** (see table above)
4. Create a new **Runbook** (PowerShell type) and paste the script
5. Create a **Schedule** (recommended: daily) and link it to the Runbook
6. Configure an **Incoming Webhook** in your Teams channel and store the URL as the `TeamsChannelUri` variable

---

## ⚙️ Configuration

Notification ranges are configured at the top of the script:

```powershell
$AppleMDMPushCertNotificationRange = '365'   # Days before expiry to alert
$AppleVPPTokenNotificationRange = '365'       # Days before expiry to alert
$AppleDEPTokenNotificationRange = '365'       # Days before expiry to alert
```

Adjust these values to match your organisation's renewal policies.

---

## 📣 Teams Alert Example

When a connector is expiring, the script posts a Teams Message Card containing:

- **Connector name** (e.g., Apple Push Notification Certificate)
- **Status** (e.g., "Expires in 30 days")
- **Apple ID** associated with the connector
- **Expiry date**

---

## 🔗 Related Links

- [Intune Apple MDM Push Certificate](https://learn.microsoft.com/en-us/mem/intune/enrollment/apple-mdm-push-certificate-get)
- [Apple VPP Tokens in Intune](https://learn.microsoft.com/en-us/mem/intune/apps/vpp-apps-ios)
- [Apple DEP / ADE Enrollment](https://learn.microsoft.com/en-us/mem/intune/enrollment/device-enrollment-program-enroll-ios)
- [Azure Automation Runbooks](https://learn.microsoft.com/en-us/azure/automation/automation-runbook-types)
- [Teams Incoming Webhooks](https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook)
