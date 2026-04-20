##Powershell Modules

# Install the required PowerShell modules if not already installed
$InstallModule = Read-Host "Do you want to install the required PowerShell modules? (Y/N)"
if ($InstallModule -eq "Y") {
    Write-Host "Installing required PowerShell modules..." -ForegroundColor Green
    Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber
    Install-Module -Name MicrosoftTeams -Force -AllowClobber
} else {
    Write-Host "Skipping module installation. Ensure you have the required modules installed." -ForegroundColor Yellow
}


Write-Host "Connecting to Exchange Online Management" -ForegroundColor Green
try {
    Connect-ExchangeOnline 
    Write-Host "Successfully connected to Exchange Online" -ForegroundColor Green
} catch {
    Write-Error "Failed to connect to Exchange Online. Please ensure you have the necessary permissions."
    exit 1
}
$FeatureIDs = @(
    "CustomizationControl", "PulseConversation", "CopilotInVivaPulse", 
    "PulseExpWithM365Copilot", "PulseDelegation", "CopilotInVivaGoals", 
    "CopilotInVivaGlint", "AISummarization", "CopilotInVivaEngage", 
    "Reflection", "CopilotDashboard", "DigestWelcomeEmail", 
    "AutoCxoIdentification", "MeetingCostAndQuality", "CopilotDashboardDelegation", 
    "AnalystReportPublish", "CopilotInVivaInsights", "AdvancedInsights", 
    "CopilotChatInVivaInsights"
)

$ModuleIDs = @(
    "VivaPulse", "VivaGoals", "VivaGlint", "VivaEngage", "VivaInsights"
)

# Get policies and keep full objects
$policiesToRemove = @()
foreach ($moduleId in $ModuleIDs) {
    $modulePolicies = Get-VivaModuleFeaturePolicy -ModuleId $moduleId
    $filtered = $modulePolicies | Where-Object { $_.FeatureId -in $FeatureIDs }
    $policiesToRemove += $filtered
}

# Remove each policy with ALL THREE required parameters
foreach ($policy in $policiesToRemove) {
    try {
        Remove-VivaModuleFeaturePolicy -PolicyId $policy.PolicyId -ModuleId $policy.ModuleId -FeatureId $policy.FeatureId -Confirm:$false
        Write-Host "Removed policy: $($policy.PolicyId)" -ForegroundColor Green
    } catch {
        Write-Error "Failed to remove policy: $($policy.PolicyId)"
    }
}
Write-Host "Configuring Viva policies to disable features..." -ForegroundColor Green
##Viva Pulse Features
Write-Host "Configuring Viva Pulse Features..." -ForegroundColor Green

Add-VivaModuleFeaturePolicy -ModuleId VivaPulse -FeatureId CustomizationControl -Name DisableFeatureForAllCustomizationControl -IsFeatureEnabled $false -Everyone -Confirm:$false
Add-VivaModuleFeaturePolicy -ModuleId VivaPulse -FeatureId PulseConversation -Name DisableFeatureForAllPulseConversation -IsFeatureEnabled $false -Everyone -Confirm:$false
Add-VivaModuleFeaturePolicy -ModuleId VivaPulse -FeatureId CopilotInVivaPulse -Name DisableFeatureForAllCopilotInVivaPulse -IsFeatureEnabled $false -Everyone -Confirm:$false
Add-VivaModuleFeaturePolicy -ModuleId VivaPulse -FeatureId PulseExpWithM365Copilot -Name DisableFeatureForAllPulseExpWithM365Copilot -IsFeatureEnabled $false -Everyone -Confirm:$false
Add-VivaModuleFeaturePolicy -ModuleId VivaPulse -FeatureId PulseDelegation -Name DisableFeatureForAllPulseDelegation -IsFeatureEnabled $false -Everyone -Confirm:$false
##Viva Goals Features
Write-Host "Configuring Viva Goals Features..." -ForegroundColor Green
Add-VivaModuleFeaturePolicy -ModuleId VivaGoals -FeatureId CopilotInVivaGoals -Name DisableFeatureForAllCopilotInVivaGoals -IsFeatureEnabled $false -Everyone -Confirm:$false 
##Viva Glint Features
Write-Host "Configuring Viva Glint Features..." -ForegroundColor Green
Add-VivaModuleFeaturePolicy -ModuleId VivaGlint -FeatureId CopilotInVivaGlint -Name DisableFeatureForAllCopilotInVivaGlint -IsFeatureEnabled $false -Everyone -Confirm:$false
##Viva Engage Features
Write-Host "Configuring Viva Engage Features..." -ForegroundColor Green
Add-VivaModuleFeaturePolicy -ModuleId VivaEngage -FeatureId AISummarization -Name DisableFeatureForAllAISummarization -IsFeatureEnabled $false -Everyone -Confirm:$false
Add-VivaModuleFeaturePolicy -ModuleId VivaEngage -FeatureId CopilotInVivaEngage -Name DisableFeatureForAllCopilotInVivaEngage -IsFeatureEnabled $false -Everyone -Confirm:$false
##Viva Insights Features
Write-Host "Configuring Viva Insights Features..." -ForegroundColor Green
Add-VivaModuleFeaturePolicy -ModuleId VivaInsights -FeatureId Reflection -Name DisableFeatureForAllReflection -IsFeatureEnabled $false -Everyone -Confirm:$false
Add-VivaModuleFeaturePolicy -ModuleId VivaInsights -FeatureId CopilotDashboard -Name DisableFeatureForAllCopilotDashboard -IsFeatureEnabled $false -Everyone -Confirm:$false
Add-VivaModuleFeaturePolicy -ModuleId VivaInsights -FeatureId DigestWelcomeEmail -Name DisableFeatureForAllDigestWelcomeEmail -IsFeatureEnabled $false -Everyone -Confirm:$false
Add-VivaModuleFeaturePolicy -ModuleId VivaInsights -FeatureId AutoCxoIdentification -Name DisableFeatureForAllAutoCxoIdentification -IsFeatureEnabled $false -Everyone -Confirm:$false
Add-VivaModuleFeaturePolicy -ModuleId VivaInsights -FeatureId MeetingCostAndQuality -Name DisableFeatureForAllMeetingCostAndQuality -IsFeatureEnabled $false -Everyone -Confirm:$false
Add-VivaModuleFeaturePolicy -ModuleId VivaInsights -FeatureId CopilotDashboardDelegation -Name DisableFeatureForAllCopilotDashboardDelegation -IsFeatureEnabled $false -Everyone -Confirm:$false
Add-VivaModuleFeaturePolicy -ModuleId VivaInsights -FeatureId AnalystReportPublish -Name DisableFeatureForAllAnalystReportPublish -IsFeatureEnabled $false -Everyone -Confirm:$false
Add-VivaModuleFeaturePolicy -ModuleId VivaInsights -FeatureId CopilotInVivaInsights -Name DisableFeatureForAllCopilotInVivaInsights -IsFeatureEnabled $false -Everyone -Confirm:$false
Add-VivaModuleFeaturePolicy -ModuleId VivaInsights -FeatureId AdvancedInsights -Name DisableFeatureForAllAdvancedInsights -IsFeatureEnabled $false -Everyone -Confirm:$false
Add-VivaModuleFeaturePolicy -ModuleId VivaInsights -FeatureId CopilotChatInVivaInsights -Name DisableFeatureForAllCopilotChatInVivaInsights -IsFeatureEnabled $false -Everyone -Confirm:$false


Write-Host "Connecting to Teams Online Management" -ForegroundColor Green
try {
    Connect-MicrosoftTeams
    Write-Host "Successfully connected to Teams Online" -ForegroundColor Green
} catch {
    Write-Error "Failed to connect to Teams Online. Please ensure you have the necessary permissions."
    exit 1
}

$VivaApps = @(
    "db5e5970-212f-477f-a3fc-2227dc7782bf" # Viva Engage
    "2fa1024a-0941-4143-a00d-d8a51529daf9" # Viva Glint
    "4b00bbbb-d524-419c-bb3b-9f42aee17424" # Viva Goals
    "57e078b5-6c0e-44a1-a83f-45f75b030d4a" # Viva Insights
    "2e3a628d-6f54-4100-9e7a-f00bc3621a85" # Viva Learning
    "380c7983-f2bd-40bf-9a1e-a5a68fd98702" # Viva Pulse
)
$CopilotApps = @(
    "b5abf2ae-c16b-4310-8f8a-d3bcdb52f162" #Copilot App
    "c92c289e-ceb4-4755-819d-0d1dffdab6fa" #Copilot for Sales
    "3f503e94-c32b-410b-afb3-8a4ea309c2bd" #Copilot for Service
    "1850b8bb-76ac-411c-9637-08f7d1812d35" #Copilot for Studio
)

# Block Viva Apps
Write-Host "Blocking Viva Apps in Teams..." -ForegroundColor Green
foreach ($appId in $VivaApps) {
    Write-Host "Blocking app with ID: $appId" -ForegroundColor Green
    try {
        Update-M365TeamsApp -Id $appId -IsBlocked $true
        Write-Host "Successfully blocked app with ID: $appId" -ForegroundColor Green
    } catch {
        Write-Error "Failed to block app with ID: $appId. Please ensure you have the necessary permissions."
    }
}

# Block Copilot Apps
Write-Host "Blocking Copilot Apps in Teams..." -ForegroundColor Green
foreach ($appId in $CopilotApps) {
    Write-Host "Blocking app with ID: $appId" -ForegroundColor Green
    try {
        Update-M365TeamsApp -Id $appId -IsBlocked $true
        Write-Host "Successfully blocked app with ID: $appId" -ForegroundColor Green
    } catch {
        Write-Error "Failed to block app with ID: $appId. Please ensure you have the necessary permissions."
    }
}
Write-Host "Script execution completed." -ForegroundColor Green


