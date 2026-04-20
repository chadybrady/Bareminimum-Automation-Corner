# 🔍 Enterprise App Permission & Secret Monitoring

An **Azure Automation runbook** that monitors Enterprise Application (service principal) client secrets and Apple-style connector expiry in Microsoft Intune, sending alerts to a Microsoft Teams channel before credentials expire.

---

## 📄 Script

### `enterpriseappmonitoringsecret.ps1`

Designed to run on a **scheduled Azure Automation Runbook**, this script:

1. Connects to Microsoft Graph using a service principal (client credentials)
2. Checks all enterprise application **client secrets** for upcoming expiry
3. Sends **Teams channel alerts** (via webhook) for secrets that are expiring or have expired
4. Logs results to the Azure Automation job output

---

## ⚙️ Prerequisites

### Azure Automation Account Variables

The following variables **must** be configured in your Azure Automation Account:

| Variable Name | Description |
|---|---|
| `TenantName` | Your tenant domain (e.g., `contoso.com`) |
| `msgraph-clientcred-appid` | App ID of the service principal used for authentication |
| `msgraph-clientcred-appsecret` | Client secret for the service principal |
| `TeamsChannelUri` | Incoming webhook URL for the Microsoft Teams channel |

### Required App Permissions (Enterprise App / Service Principal)

| Permission | Type |
|---|---|
| `User.Read` | Delegated |
| `Directory.Read.All` | Application |
| `Application.Read.All` | Application |

### Required PowerShell Modules (Automation Account)

- `Microsoft.graph.intune`

---

## 🔧 Azure Automation Setup

1. Create an **Azure Automation Account**
2. Create a **Runbook** (PowerShell type) and paste the script content
3. Add all required **variables** to the Automation Account
4. Install the `Microsoft.graph.intune` module in the Automation Account
5. Create a **Schedule** and link it to the Runbook
6. Configure an **Incoming Webhook** connector in your Teams channel and save the URL

---

## 🚀 Usage

This script is not intended to be run manually. Deploy it as a scheduled **Azure Automation Runbook**.

To test manually:

```powershell
# Set variables locally for testing
$TenantName = "contoso.com"
$AppID = "<your-app-id>"
$AppSecret = "<your-app-secret>"
$Uri = "<your-teams-webhook-url>"
.\enterpriseappmonitoringsecret.ps1
```

---

## 🔗 Related Links

- [Azure Automation Runbooks](https://learn.microsoft.com/en-us/azure/automation/automation-runbook-types)
- [Microsoft Teams Incoming Webhooks](https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook)
- [Enterprise Application Credential Management](https://learn.microsoft.com/en-us/entra/identity-platform/howto-create-service-principal-portal)
