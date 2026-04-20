<#
.SYNOPSIS
    Tests Microsoft Intune configuration and generates a comprehensive report.

.DESCRIPTION
    This script tests various aspects of Microsoft Intune configuration including:
    - Device Compliance and Configuration Profiles
    - Application management and deployment
    - Endpoint Security policies
    - Enrollment settings
    - Reports and monitoring capabilities

.PARAMETER OutputPath
    Path where the HTML report will be saved. Default is current directory.

.PARAMETER TenantId
    Azure AD Tenant ID (optional - will prompt for authentication)

.EXAMPLE
    .\Test-IntuneConfiguration.ps1 -OutputPath "C:\Reports"

.NOTES
    Author: Bareminimum Solutions
    Date: October 16, 2025
    Requires: Microsoft.Graph PowerShell modules
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".",
    
    [Parameter(Mandatory = $false)]
    [string]$TenantId
)

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement, Microsoft.Graph.DeviceManagement.Enrollment

# Import required modules
$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.DeviceManagement',
    'Microsoft.Graph.DeviceManagement.Enrollment'
)

Write-Host "Checking required modules..." -ForegroundColor Cyan
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing module: $module" -ForegroundColor Yellow
        Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $module -Force
}

# Connect to Microsoft Graph
function Connect-ToGraph {
    param(
        [string]$TenantId
    )
    
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    
    $scopes = @(
        "DeviceManagementConfiguration.Read.All",
        "DeviceManagementApps.Read.All",
        "DeviceManagementManagedDevices.Read.All",
        "DeviceManagementServiceConfig.Read.All",
        "DeviceManagementRBAC.Read.All",
        "Policy.Read.All"
    )
    
    if ($TenantId) {
        Connect-MgGraph -Scopes $scopes -TenantId $TenantId
    }
    else {
        Connect-MgGraph -Scopes $scopes
    }
    
    $context = Get-MgContext
    Write-Host "Connected to tenant: $($context.TenantId)" -ForegroundColor Green
}

# Test results object
$testResults = @{
    TestDate              = Get-Date
    TenantInfo            = @{}
    CompliancePolicies    = @{}
    ConfigurationProfiles = @{}
    Applications          = @{}
    EndpointSecurity      = @{}
    EnrollmentSettings    = @{}
    Monitoring            = @{}
    BestPractices         = @{}
    ConditionalAccess     = @{}
    AppProtection         = @{}
    AutopilotProfiles     = @{}
    DeviceFilters         = @{}
    Scripts               = @{}
    RBAC                  = @{}
    EnrollmentTokens      = @{}
    SoftwareUpdates       = @{}
    TenantConfiguration   = @{}
    ComplianceActions     = @{}
    WindowsHello          = @{}
    IntuneConnectors      = @{}
    DeviceInventory       = @{}
    Summary               = @{
        TotalTests   = 0
        PassedTests  = 0
        FailedTests  = 0
        WarningTests = 0
    }
}

# Helper function to add test result
function Add-TestResult {
    param(
        [string]$Category,
        [string]$TestName,
        [string]$Status,  # Pass, Fail, Warning
        [string]$Details,
        [object]$Data = $null
    )
    
    $result = @{
        TestName  = $TestName
        Status    = $Status
        Details   = $Details
        Data      = $Data
        Timestamp = Get-Date
    }
    
    if (-not $testResults[$Category].Tests) {
        $testResults[$Category].Tests = @()
    }
    
    $testResults[$Category].Tests += $result
    $testResults.Summary.TotalTests++
    
    switch ($Status) {
        "Pass" { $testResults.Summary.PassedTests++ }
        "Fail" { $testResults.Summary.FailedTests++ }
        "Warning" { $testResults.Summary.WarningTests++ }
    }
}

# Test 1: Device Compliance Policies
function Test-CompliancePolicies {
    Write-Host "`nTesting Device Compliance Policies..." -ForegroundColor Cyan
    
    try {
        $compliancePolicies = Get-MgDeviceManagementDeviceCompliancePolicy -All
        
        if ($compliancePolicies.Count -eq 0) {
            Add-TestResult -Category "CompliancePolicies" -TestName "Compliance Policies Exist" `
                -Status "Warning" -Details "No compliance policies found" -Data $null
        }
        else {
            Add-TestResult -Category "CompliancePolicies" -TestName "Compliance Policies Exist" `
                -Status "Pass" -Details "$($compliancePolicies.Count) compliance policies found" `
                -Data $compliancePolicies
            
            # Deep dive into each policy
            foreach ($policy in $compliancePolicies) {
                $policyDetails = $policy.AdditionalProperties
                $issues = @()
                $strengths = @()
                
                # Check assignment
                try {
                    $assignments = Get-MgDeviceManagementDeviceCompliancePolicyAssignment -DeviceCompliancePolicyId $policy.Id
                    
                    if ($assignments.Count -eq 0) {
                        $issues += "Not assigned to any groups"
                    }
                    else {
                        $strengths += "Assigned to $($assignments.Count) group(s)"
                    }
                }
                catch {
                    $issues += "Unable to check assignments"
                }
                
                # Analyze Windows 10 Compliance Settings
                if ($policy.AdditionalProperties.'@odata.type' -like '*windows10CompliancePolicy*') {
                    # Password settings
                    if ($policyDetails.passwordRequired -eq $true) {
                        $strengths += "Password required: Yes"
                        
                        if ($policyDetails.passwordMinimumLength -ge 8) {
                            $strengths += "Password minimum length: $($policyDetails.passwordMinimumLength) (Good)"
                        }
                        elseif ($policyDetails.passwordMinimumLength) {
                            $issues += "Password minimum length: $($policyDetails.passwordMinimumLength) (Recommended: 8+)"
                        }
                        
                        if ($policyDetails.passwordRequireToUnlockFromIdle -eq $true) {
                            $strengths += "Password required after idle: Yes"
                        }
                    }
                    else {
                        $issues += "Password not required (Best practice: Enable)"
                    }
                    
                    # BitLocker
                    if ($policyDetails.bitLockerEnabled -eq $true) {
                        $strengths += "BitLocker required: Yes"
                    }
                    else {
                        $issues += "BitLocker not required (Best practice: Enable for data protection)"
                    }
                    
                    # Secure Boot
                    if ($policyDetails.secureBootEnabled -eq $true) {
                        $strengths += "Secure Boot required: Yes"
                    }
                    else {
                        $issues += "Secure Boot not required (Best practice: Enable)"
                    }
                    
                    # TPM
                    if ($policyDetails.tpmRequired -eq $true) {
                        $strengths += "TPM required: Yes"
                    }
                    else {
                        $issues += "TPM not required (Best practice: Enable)"
                    }
                    
                    # OS Version
                    if ($policyDetails.osMinimumVersion) {
                        $strengths += "Minimum OS version enforced: $($policyDetails.osMinimumVersion)"
                    }
                    else {
                        $issues += "No minimum OS version enforced (Best practice: Require current versions)"
                    }
                    
                    # Antivirus
                    if ($policyDetails.antivirusRequired -eq $true) {
                        $strengths += "Antivirus required: Yes"
                    }
                    else {
                        $issues += "Antivirus not required (Best practice: Enable)"
                    }
                    
                    if ($policyDetails.antiSpywareRequired -eq $true) {
                        $strengths += "Anti-spyware required: Yes"
                    }
                    else {
                        $issues += "Anti-spyware not required (Best practice: Enable)"
                    }
                    
                    # Firewall
                    if ($policyDetails.firewallEnabled -eq $true) {
                        $strengths += "Firewall required: Yes"
                    }
                    else {
                        $issues += "Firewall not required (Best practice: Enable)"
                    }
                    
                    # Device Threat Protection
                    if ($policyDetails.deviceThreatProtectionEnabled -eq $true) {
                        $strengths += "Device Threat Protection enabled: Yes"
                        
                        if ($policyDetails.deviceThreatProtectionRequiredSecurityLevel) {
                            $strengths += "Required security level: $($policyDetails.deviceThreatProtectionRequiredSecurityLevel)"
                        }
                    }
                    else {
                        $issues += "Device Threat Protection not enabled (Consider enabling with Microsoft Defender for Endpoint)"
                    }
                    
                    # Code Integrity
                    if ($policyDetails.codeIntegrityEnabled -eq $true) {
                        $strengths += "Code Integrity required: Yes"
                    }
                }
                
                # Analyze iOS Compliance Settings
                if ($policy.AdditionalProperties.'@odata.type' -like '*iosCompliancePolicy*') {
                    # Passcode settings
                    if ($policyDetails.passcodeRequired -eq $true) {
                        $strengths += "Passcode required: Yes"
                        
                        if ($policyDetails.passcodeMinimumLength -ge 6) {
                            $strengths += "Passcode minimum length: $($policyDetails.passcodeMinimumLength) (Good)"
                        }
                        elseif ($policyDetails.passcodeMinimumLength) {
                            $issues += "Passcode minimum length: $($policyDetails.passcodeMinimumLength) (Recommended: 6+)"
                        }
                    }
                    else {
                        $issues += "Passcode not required (Best practice: Enable)"
                    }
                    
                    # OS Version
                    if ($policyDetails.osMinimumVersion) {
                        $strengths += "Minimum OS version enforced: $($policyDetails.osMinimumVersion)"
                    }
                    else {
                        $issues += "No minimum OS version enforced (Best practice: Require iOS 15+)"
                    }
                    
                    # Jailbreak detection
                    if ($policyDetails.securityBlockJailbrokenDevices -eq $true) {
                        $strengths += "Jailbroken devices blocked: Yes"
                    }
                    else {
                        $issues += "Jailbroken devices not blocked (Best practice: Enable)"
                    }
                }
                
                # Analyze Android Compliance Settings
                if ($policy.AdditionalProperties.'@odata.type' -like '*androidCompliancePolicy*' -or 
                    $policy.AdditionalProperties.'@odata.type' -like '*androidWorkProfileCompliancePolicy*') {
                    
                    # Password settings
                    if ($policyDetails.passwordRequired -eq $true) {
                        $strengths += "Password required: Yes"
                        
                        if ($policyDetails.passwordMinimumLength -ge 6) {
                            $strengths += "Password minimum length: $($policyDetails.passwordMinimumLength) (Good)"
                        }
                        elseif ($policyDetails.passwordMinimumLength) {
                            $issues += "Password minimum length: $($policyDetails.passwordMinimumLength) (Recommended: 6+)"
                        }
                    }
                    else {
                        $issues += "Password not required (Best practice: Enable)"
                    }
                    
                    # Encryption
                    if ($policyDetails.storageRequireEncryption -eq $true) {
                        $strengths += "Device encryption required: Yes"
                    }
                    else {
                        $issues += "Device encryption not required (Best practice: Enable)"
                    }
                    
                    # OS Version
                    if ($policyDetails.osMinimumVersion) {
                        $strengths += "Minimum OS version enforced: $($policyDetails.osMinimumVersion)"
                    }
                    else {
                        $issues += "No minimum OS version enforced (Best practice: Require Android 10+)"
                    }
                    
                    # Root detection
                    if ($policyDetails.securityBlockJailbrokenDevices -eq $true) {
                        $strengths += "Rooted devices blocked: Yes"
                    }
                    else {
                        $issues += "Rooted devices not blocked (Best practice: Enable)"
                    }
                }
                
                # Determine overall status
                $status = "Pass"
                $detailText = ""
                
                if ($issues.Count -gt 0) {
                    if ($issues.Count -gt 3) {
                        $status = "Fail"
                        $detailText = "Multiple best practice issues found"
                    }
                    else {
                        $status = "Warning"
                        $detailText = "Some best practice recommendations"
                    }
                }
                
                if ($strengths.Count -gt 0) {
                    $detailText += " | Strengths: $($strengths.Count)"
                }
                
                $detailText += "`n✓ Strengths: " + ($strengths -join "; ")
                if ($issues.Count -gt 0) {
                    $detailText += "`n⚠ Issues: " + ($issues -join "; ")
                }
                
                Add-TestResult -Category "CompliancePolicies" `
                    -TestName "Deep Analysis: $($policy.DisplayName)" `
                    -Status $status `
                    -Details $detailText `
                    -Data @{Policy = $policy; Strengths = $strengths; Issues = $issues }
            }
        }
        
        $testResults.CompliancePolicies.Summary = @{
            TotalPolicies = $compliancePolicies.Count
            Platforms     = ($compliancePolicies | Group-Object -Property '@odata.type' | Select-Object Name, Count)
        }
        
    }
    catch {
        Add-TestResult -Category "CompliancePolicies" -TestName "Compliance Policies Access" `
            -Status "Fail" -Details "Error accessing compliance policies: $($_.Exception.Message)"
    }
}

# Test 2: Configuration Profiles
function Test-ConfigurationProfiles {
    Write-Host "`nTesting Configuration Profiles..." -ForegroundColor Cyan
    
    try {
        $configProfiles = Get-MgDeviceManagementDeviceConfiguration -All
        
        if ($configProfiles.Count -eq 0) {
            Add-TestResult -Category "ConfigurationProfiles" -TestName "Configuration Profiles Exist" `
                -Status "Warning" -Details "No configuration profiles found"
        }
        else {
            Add-TestResult -Category "ConfigurationProfiles" -TestName "Configuration Profiles Exist" `
                -Status "Pass" -Details "$($configProfiles.Count) configuration profiles found" `
                -Data $configProfiles
            
            # Deep dive into each profile
            foreach ($profile in $configProfiles) {
                $profileDetails = $profile.AdditionalProperties
                $issues = @()
                $strengths = @()
                $recommendations = @()
                
                # Check assignment
                try {
                    $assignments = Get-MgDeviceManagementDeviceConfigurationAssignment -DeviceConfigurationId $profile.Id
                    
                    if ($assignments.Count -eq 0) {
                        $issues += "Not assigned to any groups"
                    }
                    else {
                        $strengths += "Assigned to $($assignments.Count) group(s)"
                    }
                }
                catch {
                    $issues += "Unable to check assignments"
                }
                
                # Analyze Windows 10 Device Restriction Profiles
                if ($profile.AdditionalProperties.'@odata.type' -like '*windows10GeneralConfiguration*') {
                    
                    # Password policies
                    if ($profileDetails.passwordRequired -eq $true) {
                        $strengths += "Password enforcement enabled"
                        
                        if ($profileDetails.passwordMinimumLength -ge 8) {
                            $strengths += "Password length: $($profileDetails.passwordMinimumLength) characters (Good)"
                        }
                        
                        if ($profileDetails.passwordExpirationDays) {
                            $strengths += "Password expiration: $($profileDetails.passwordExpirationDays) days"
                        }
                    }
                    
                    # Microsoft Defender settings
                    if ($profileDetails.defenderBlockEndUserAccess -eq $false) {
                        $strengths += "Users can access Defender interface"
                    }
                    
                    if ($profileDetails.defenderRequireRealTimeMonitoring -eq $true) {
                        $strengths += "Real-time monitoring required"
                    }
                    else {
                        $issues += "Real-time monitoring not enforced (Best practice: Enable)"
                    }
                    
                    if ($profileDetails.defenderRequireCloudProtection -eq $true) {
                        $strengths += "Cloud-delivered protection enabled"
                    }
                    else {
                        $recommendations += "Consider enabling cloud-delivered protection"
                    }
                    
                    # SmartScreen settings
                    if ($profileDetails.smartScreenEnableInShell -eq $true) {
                        $strengths += "SmartScreen for file downloads enabled"
                    }
                    else {
                        $issues += "SmartScreen not enabled (Best practice: Enable)"
                    }
                    
                    if ($profileDetails.smartScreenBlockPromptOverride -eq $true) {
                        $strengths += "SmartScreen warnings cannot be bypassed"
                    }
                    
                    # Windows Update settings
                    if ($profileDetails.updateNotificationLevel) {
                        $strengths += "Update notifications configured: $($profileDetails.updateNotificationLevel)"
                    }
                    
                    # Privacy settings
                    if ($profileDetails.privacyBlockInputPersonalization -eq $true) {
                        $strengths += "Input personalization blocked for privacy"
                    }
                    
                    # Cloud and storage
                    if ($profileDetails.storageBlockRemovableStorage -eq $true) {
                        $strengths += "Removable storage blocked (high security)"
                    }
                }
                
                # Analyze Windows Update for Business Profiles
                if ($profile.AdditionalProperties.'@odata.type' -like '*windowsUpdateForBusinessConfiguration*') {
                    
                    if ($profileDetails.automaticUpdateMode) {
                        $strengths += "Automatic updates configured: $($profileDetails.automaticUpdateMode)"
                        
                        if ($profileDetails.automaticUpdateMode -eq 'notifyDownload') {
                            $recommendations += "Consider 'autoInstallAtMaintenanceTime' for better security"
                        }
                    }
                    else {
                        $issues += "Automatic update mode not configured"
                    }
                    
                    if ($profileDetails.qualityUpdatesDeferralPeriodInDays -ne $null) {
                        if ($profileDetails.qualityUpdatesDeferralPeriodInDays -le 7) {
                            $strengths += "Quality updates deferred by $($profileDetails.qualityUpdatesDeferralPeriodInDays) days (Good)"
                        }
                        else {
                            $recommendations += "Quality updates deferred by $($profileDetails.qualityUpdatesDeferralPeriodInDays) days (Consider reducing to 0-7 days)"
                        }
                    }
                    
                    if ($profileDetails.featureUpdatesDeferralPeriodInDays -ne $null) {
                        $strengths += "Feature updates deferred by $($profileDetails.featureUpdatesDeferralPeriodInDays) days"
                    }
                    
                    if ($profileDetails.microsoftUpdateServiceAllowed -eq $true) {
                        $strengths += "Microsoft Update Service enabled (Office updates)"
                    }
                    
                    if ($profileDetails.driversExcluded -eq $true) {
                        $recommendations += "Drivers excluded from updates - ensure you have alternative driver management"
                    }
                }
                
                # Analyze iOS Device Restriction Profiles
                if ($profile.AdditionalProperties.'@odata.type' -like '*iosGeneralDeviceConfiguration*') {
                    
                    # Passcode settings
                    if ($profileDetails.passcodeRequired -eq $true) {
                        $strengths += "Passcode required"
                        
                        if ($profileDetails.passcodeMinimumLength -ge 6) {
                            $strengths += "Passcode length: $($profileDetails.passcodeMinimumLength) (Good)"
                        }
                    }
                    else {
                        $issues += "Passcode not required (Best practice: Enable)"
                    }
                    
                    # Security features
                    if ($profileDetails.appStoreBlockAutomaticDownloads -eq $false) {
                        $recommendations += "Consider blocking automatic app downloads for better control"
                    }
                    
                    if ($profileDetails.safariBlockAutofill -eq $true) {
                        $strengths += "Safari autofill blocked (good for security)"
                    }
                    
                    if ($profileDetails.cameraBlocked -eq $true) {
                        $strengths += "Camera blocked (high security environment)"
                    }
                    
                    if ($profileDetails.iCloudBlockBackup -eq $true) {
                        $strengths += "iCloud backup blocked (data residency control)"
                    }
                }
                
                # Analyze Android Device Restriction Profiles
                if ($profile.AdditionalProperties.'@odata.type' -like '*androidGeneralDeviceConfiguration*' -or
                    $profile.AdditionalProperties.'@odata.type' -like '*androidWorkProfileGeneralDeviceConfiguration*') {
                    
                    # Password settings
                    if ($profileDetails.passwordRequired -eq $true) {
                        $strengths += "Password required"
                    }
                    else {
                        $issues += "Password not required (Best practice: Enable)"
                    }
                    
                    # Security features
                    if ($profileDetails.securityRequireVerifyApps -eq $true) {
                        $strengths += "App verification required (Play Protect)"
                    }
                    else {
                        $issues += "App verification not required (Best practice: Enable Play Protect)"
                    }
                    
                    if ($profileDetails.storageBlockGoogleBackup -eq $true) {
                        $strengths += "Google backup blocked (data control)"
                    }
                    
                    if ($profileDetails.cameraBlocked -eq $true) {
                        $strengths += "Camera blocked (high security)"
                    }
                }
                
                # Analyze Email Profiles
                if ($profile.AdditionalProperties.'@odata.type' -like '*emailProfile*') {
                    $strengths += "Email profile configured for native mail apps"
                    
                    if ($profileDetails.requireSsl -eq $true) {
                        $strengths += "SSL/TLS required for email"
                    }
                    else {
                        $issues += "SSL/TLS not required (Best practice: Enable encryption)"
                    }
                    
                    if ($profileDetails.requireSmime -eq $true) {
                        $strengths += "S/MIME encryption enabled (excellent security)"
                    }
                }
                
                # Analyze WiFi Profiles
                if ($profile.AdditionalProperties.'@odata.type' -like '*wifi*') {
                    $strengths += "WiFi profile configured"
                    
                    if ($profileDetails.wiFiSecurityType -eq 'wpa2Enterprise' -or 
                        $profileDetails.wiFiSecurityType -eq 'wpa3Enterprise') {
                        $strengths += "Enterprise WiFi security: $($profileDetails.wiFiSecurityType) (Excellent)"
                    }
                    elseif ($profileDetails.wiFiSecurityType -eq 'open') {
                        $issues += "Open WiFi network (Security risk - use WPA2/WPA3)"
                    }
                    
                    if ($profileDetails.connectAutomatically -eq $true) {
                        $strengths += "Auto-connect enabled for corporate WiFi"
                    }
                }
                
                # Analyze VPN Profiles
                if ($profile.AdditionalProperties.'@odata.type' -like '*vpn*') {
                    $strengths += "VPN profile configured"
                    
                    if ($profileDetails.connectionType) {
                        $strengths += "VPN type: $($profileDetails.connectionType)"
                    }
                    
                    if ($profileDetails.enableSplitTunneling -eq $false) {
                        $strengths += "Split tunneling disabled (all traffic through VPN)"
                    }
                    else {
                        $recommendations += "Split tunneling enabled - ensure this aligns with security policy"
                    }
                }
                
                # Analyze Endpoint Protection Profiles
                if ($profile.AdditionalProperties.'@odata.type' -like '*windows10EndpointProtectionConfiguration*') {
                    
                    # BitLocker settings
                    if ($profileDetails.bitLockerSystemDrivePolicy) {
                        $strengths += "BitLocker system drive policy configured"
                    }
                    else {
                        $recommendations += "Consider configuring BitLocker for system drive"
                    }
                    
                    # Firewall settings
                    if ($profileDetails.firewallBlockStatefulFTP -eq $true) {
                        $strengths += "Stateful FTP blocked in firewall"
                    }
                    
                    # Application Guard
                    if ($profileDetails.applicationGuardEnabled -eq $true) {
                        $strengths += "Windows Defender Application Guard enabled (Excellent)"
                    }
                    
                    # Credential Guard
                    if ($profileDetails.deviceGuardEnableVirtualizationBasedSecurity -eq $true) {
                        $strengths += "Virtualization-based security enabled (Excellent)"
                    }
                }
                
                # Determine overall status
                $status = "Pass"
                $detailText = ""
                
                if ($issues.Count -gt 0) {
                    if ($issues.Count -ge 3) {
                        $status = "Fail"
                        $detailText = "Critical configuration issues found"
                    }
                    else {
                        $status = "Warning"
                        $detailText = "Configuration improvements recommended"
                    }
                }
                elseif ($recommendations.Count -gt 2) {
                    $status = "Warning"
                    $detailText = "Good configuration with optimization opportunities"
                }
                
                # Build detail output
                if ($strengths.Count -gt 0) {
                    $detailText += "`n✓ Strengths ($($strengths.Count)): " + ($strengths -join "; ")
                }
                if ($issues.Count -gt 0) {
                    $detailText += "`n❌ Issues ($($issues.Count)): " + ($issues -join "; ")
                }
                if ($recommendations.Count -gt 0) {
                    $detailText += "`n💡 Recommendations ($($recommendations.Count)): " + ($recommendations -join "; ")
                }
                
                Add-TestResult -Category "ConfigurationProfiles" `
                    -TestName "Deep Analysis: $($profile.DisplayName)" `
                    -Status $status `
                    -Details $detailText `
                    -Data @{Profile = $profile; Strengths = $strengths; Issues = $issues; Recommendations = $recommendations }
            }
        }
        
        $testResults.ConfigurationProfiles.Summary = @{
            TotalProfiles = $configProfiles.Count
            Types         = ($configProfiles | Group-Object -Property '@odata.type' | Select-Object Name, Count)
        }
        
    }
    catch {
        Add-TestResult -Category "ConfigurationProfiles" -TestName "Configuration Profiles Access" `
            -Status "Fail" -Details "Error accessing configuration profiles: $($_.Exception.Message)"
    }
}

# Test 3: Application Management
function Test-Applications {
    Write-Host "`nTesting Application Management..." -ForegroundColor Cyan
    
    try {
        $apps = Get-MgDeviceAppManagementMobileApp -All
        
        if ($apps.Count -eq 0) {
            Add-TestResult -Category "Applications" -TestName "Applications Exist" `
                -Status "Warning" -Details "No applications found"
        }
        else {
            Add-TestResult -Category "Applications" -TestName "Applications Exist" `
                -Status "Pass" -Details "$($apps.Count) applications found" `
                -Data $apps
            
            # Check app assignments
            $assignedApps = 0
            $unassignedApps = 0
            
            foreach ($app in $apps) {
                try {
                    $assignments = Get-MgDeviceAppManagementMobileAppAssignment -MobileAppId $app.Id
                    
                    if ($assignments.Count -eq 0) {
                        $unassignedApps++
                    }
                    else {
                        $assignedApps++
                    }
                }
                catch {
                    # Some apps might not support assignment queries
                }
            }
            
            if ($unassignedApps -gt 0) {
                Add-TestResult -Category "Applications" -TestName "Application Assignments" `
                    -Status "Warning" `
                    -Details "$unassignedApps out of $($apps.Count) apps are not assigned"
            }
            else {
                Add-TestResult -Category "Applications" -TestName "Application Assignments" `
                    -Status "Pass" `
                    -Details "All applications are assigned"
            }
        }
        
        $testResults.Applications.Summary = @{
            TotalApps = $apps.Count
            AppTypes  = ($apps | Group-Object -Property '@odata.type' | Select-Object Name, Count)
        }
        
    }
    catch {
        Add-TestResult -Category "Applications" -TestName "Applications Access" `
            -Status "Fail" -Details "Error accessing applications: $($_.Exception.Message)"
    }
}

# Test 4: Endpoint Security Policies
function Test-EndpointSecurity {
    Write-Host "`nTesting Endpoint Security Policies..." -ForegroundColor Cyan
    
    try {
        # Get ALL endpoint security intents (not filtered by template)
        try {
            $allIntentsResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/intents"
            $allIntents = $allIntentsResponse.value
            
            if ($allIntents.Count -gt 0) {
                Add-TestResult -Category "EndpointSecurity" -TestName "All Endpoint Security Policies" `
                    -Status "Pass" -Details "$($allIntents.Count) total endpoint security policies found" `
                    -Data $allIntents
                
                # Analyze each policy
                foreach ($intent in $allIntents) {
                    $policyType = "Unknown"
                    $icon = "🔒"
                    
                    # Determine policy type based on template ID
                    switch ($intent.templateId) {
                        '804339ad-1553-4478-a742-138fb5807418' { $policyType = "Antivirus"; $icon = "🦠" }
                        'd02f2162-fcac-48db-9b7b-b0a5f76f6c6e' { $policyType = "Disk Encryption (BitLocker)"; $icon = "🔐" }
                        '4356d05c-a4ab-4a07-9ece-739f7c792910' { $policyType = "Firewall"; $icon = "🔥" }
                        'c7a4c382-b0c7-4d29-9e6b-3e0c1a8e0c1a' { $policyType = "Attack Surface Reduction"; $icon = "🛡️" }
                        '0f2034c6-3cd6-4ee1-bd37-f3c0693e9548' { $policyType = "Endpoint Detection and Response"; $icon = "🎯" }
                        '4cfd164c-5e8c-4c6c-8d9c-352d5b6e7a4c' { $policyType = "Account Protection"; $icon = "👤" }
                        '3f41c2e8-5e3c-4b9e-8d1f-1e5c6f7b8a9c' { $policyType = "Device Control"; $icon = "📱" }
                        default { 
                            # Try to determine from display name
                            if ($intent.displayName -like "*bitlocker*" -or $intent.displayName -like "*encryption*") {
                                $policyType = "Disk Encryption (BitLocker)"
                                $icon = "🔐"
                            }
                            elseif ($intent.displayName -like "*antivirus*" -or $intent.displayName -like "*defender*") {
                                $policyType = "Antivirus/Defender"
                                $icon = "🦠"
                            }
                            elseif ($intent.displayName -like "*firewall*") {
                                $policyType = "Firewall"
                                $icon = "🔥"
                            }
                            else {
                                $policyType = "Security Policy"
                                $icon = "🔒"
                            }
                        }
                    }
                    
                    # Get assignment info
                    $assignmentInfo = "Not assigned"
                    try {
                        $assignments = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/intents/$($intent.id)/assignments"
                        if ($assignments.value.Count -gt 0) {
                            $assignmentInfo = "Assigned to $($assignments.value.Count) group(s)"
                        }
                    }
                    catch {
                        $assignmentInfo = "Unable to check assignments"
                    }
                    
                    $details = "$icon Type: $policyType | $assignmentInfo"
                    if ($intent.roleScopeTagIds) {
                        $details += " | Scope tags: $($intent.roleScopeTagIds.Count)"
                    }
                    
                    Add-TestResult -Category "EndpointSecurity" `
                        -TestName "Policy: $($intent.displayName)" `
                        -Status "Pass" `
                        -Details $details `
                        -Data $intent
                }
            }
            else {
                Add-TestResult -Category "EndpointSecurity" -TestName "Endpoint Security Policies" `
                    -Status "Warning" -Details "No endpoint security policies found"
            }
        }
        catch {
            Add-TestResult -Category "EndpointSecurity" -TestName "Endpoint Security Policies" `
                -Status "Warning" -Details "Unable to access endpoint security policies: $($_.Exception.Message)"
        }
        
        # Also check for Configuration Policies (newer endpoint security policies)
        try {
            $configPoliciesResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
            $configPolicies = $configPoliciesResponse.value
            
            if ($configPolicies.Count -gt 0) {
                Add-TestResult -Category "EndpointSecurity" -TestName "Settings Catalog Policies" `
                    -Status "Pass" -Details "$($configPolicies.Count) Settings Catalog policies found (newer format)" `
                    -Data $configPolicies
                
                foreach ($policy in $configPolicies) {
                    $policyType = "Settings Catalog"
                    
                    # Categorize by name or technology
                    if ($policy.name -like "*bitlocker*" -or $policy.name -like "*encryption*") {
                        $policyType = "Settings Catalog - Encryption"
                    }
                    elseif ($policy.name -like "*defender*" -or $policy.name -like "*antivirus*") {
                        $policyType = "Settings Catalog - Defender"
                    }
                    elseif ($policy.name -like "*firewall*") {
                        $policyType = "Settings Catalog - Firewall"
                    }
                    
                    $platformInfo = if ($policy.platforms) { $policy.platforms } else { "Not specified" }
                    $technologies = if ($policy.technologies) { $policy.technologies -join ", " } else { "Not specified" }
                    
                    Add-TestResult -Category "EndpointSecurity" `
                        -TestName "Policy: $($policy.name)" `
                        -Status "Pass" `
                        -Details "Type: $policyType | Platform: $platformInfo | Technologies: $technologies" `
                        -Data $policy
                }
            }
        }
        catch {
            # Settings catalog may not be accessible or in use
        }
        
        # Summary counts
        $totalIntents = if ($allIntents) { $allIntents.Count } else { 0 }
        $totalConfigPolicies = if ($configPolicies) { $configPolicies.Count } else { 0 }
        $antivirusCount = if ($allIntents) { ($allIntents | Where-Object { $_.templateId -eq '804339ad-1553-4478-a742-138fb5807418' -or $_.displayName -like "*antivirus*" -or $_.displayName -like "*defender*" }).Count } else { 0 }
        $diskEncryptionCount = if ($allIntents) { ($allIntents | Where-Object { $_.templateId -eq 'd02f2162-fcac-48db-9b7b-b0a5f76f6c6e' -or $_.displayName -like "*bitlocker*" -or $_.displayName -like "*encryption*" }).Count } else { 0 }
        $firewallCount = if ($allIntents) { ($allIntents | Where-Object { $_.templateId -eq '4356d05c-a4ab-4a07-9ece-739f7c792910' -or $_.displayName -like "*firewall*" }).Count } else { 0 }
        $asrCount = if ($allIntents) { ($allIntents | Where-Object { $_.templateId -eq 'c7a4c382-b0c7-4d29-9e6b-3e0c1a8e0c1a' }).Count } else { 0 }
        
        $testResults.EndpointSecurity.Summary = @{
            TotalIntents           = $totalIntents
            SettingsCatalogPolicies = $totalConfigPolicies
            AntivirusPolicies      = $antivirusCount
            DiskEncryptionPolicies = $diskEncryptionCount
            FirewallPolicies       = $firewallCount
            ASRPolicies            = $asrCount
        }
        
    }
    catch {
        Add-TestResult -Category "EndpointSecurity" -TestName "Endpoint Security Access" `
            -Status "Fail" -Details "Error accessing endpoint security policies: $($_.Exception.Message)"
    }
}

# Test 5: Enrollment Settings
function Test-EnrollmentSettings {
    Write-Host "`nTesting Enrollment Settings..." -ForegroundColor Cyan
    
    try {
        # Test Enrollment Restrictions
        $enrollmentRestrictions = Get-MgDeviceManagementDeviceEnrollmentConfiguration -All
        
        if ($enrollmentRestrictions.Count -eq 0) {
            Add-TestResult -Category "EnrollmentSettings" -TestName "Enrollment Configurations" `
                -Status "Warning" -Details "No enrollment configurations found"
        }
        else {
            Add-TestResult -Category "EnrollmentSettings" -TestName "Enrollment Configurations" `
                -Status "Pass" -Details "$($enrollmentRestrictions.Count) enrollment configurations found" `
                -Data $enrollmentRestrictions
        }
        
        # Test Autopilot profiles (if accessible)
        try {
            $autopilotProfiles = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles"
            
            Add-TestResult -Category "EnrollmentSettings" -TestName "Autopilot Profiles" `
                -Status $(if ($autopilotProfiles.value.Count -gt 0) { "Pass" } else { "Warning" }) `
                -Details "$($autopilotProfiles.value.Count) Autopilot profiles found" `
                -Data $autopilotProfiles.value
                
            $testResults.EnrollmentSettings.AutopilotProfiles = $autopilotProfiles.value.Count
        }
        catch {
            Add-TestResult -Category "EnrollmentSettings" -TestName "Autopilot Profiles" `
                -Status "Warning" -Details "Unable to access Autopilot profiles"
        }
        
        $testResults.EnrollmentSettings.Summary = @{
            EnrollmentConfigs = $enrollmentRestrictions.Count
        }
        
    }
    catch {
        Add-TestResult -Category "EnrollmentSettings" -TestName "Enrollment Settings Access" `
            -Status "Fail" -Details "Error accessing enrollment settings: $($_.Exception.Message)"
    }
}

# Test 6: Microsoft Best Practices
function Test-BestPractices {
    Write-Host "`nTesting Microsoft Best Practices..." -ForegroundColor Cyan
    
    try {
        # Best Practice 1: Multi-Factor Authentication (Conditional Access)
        try {
            $caPolicies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies"
            
            $mfaPolicies = $caPolicies.value | Where-Object { $_.grantControls.builtInControls -contains "mfa" }
            
            if ($mfaPolicies.Count -gt 0) {
                Add-TestResult -Category "BestPractices" -TestName "MFA Enforcement via Conditional Access" `
                    -Status "Pass" -Details "$($mfaPolicies.Count) Conditional Access policies require MFA" `
                    -Data $mfaPolicies
            }
            else {
                Add-TestResult -Category "BestPractices" -TestName "MFA Enforcement via Conditional Access" `
                    -Status "Warning" -Details "No Conditional Access policies requiring MFA found - Microsoft recommends enforcing MFA"
            }
        }
        catch {
            Add-TestResult -Category "BestPractices" -TestName "MFA Enforcement via Conditional Access" `
                -Status "Warning" -Details "Unable to verify MFA policies - requires additional permissions"
        }
        
        # Best Practice 2: Windows Update Rings
        try {
            $updateRings = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$filter=isof('microsoft.graph.windowsUpdateForBusinessConfiguration')"
            
            if ($updateRings.value.Count -gt 0) {
                Add-TestResult -Category "BestPractices" -TestName "Windows Update Management" `
                    -Status "Pass" -Details "$($updateRings.value.Count) Windows Update rings configured" `
                    -Data $updateRings.value
            }
            else {
                Add-TestResult -Category "BestPractices" -TestName "Windows Update Management" `
                    -Status "Warning" -Details "No Windows Update rings found - Microsoft recommends managing updates via Intune"
            }
        }
        catch {
            Add-TestResult -Category "BestPractices" -TestName "Windows Update Management" `
                -Status "Warning" -Details "Unable to verify Windows Update configuration"
        }
        
        # Best Practice 3: Minimum OS Version Compliance
        try {
            $compliancePolicies = Get-MgDeviceManagementDeviceCompliancePolicy -All
            $osVersionPolicies = $compliancePolicies | Where-Object { 
                $_.AdditionalProperties.ContainsKey('osMinimumVersion') -or 
                $_.AdditionalProperties.ContainsKey('osMinimumBuildVersion')
            }
            
            if ($osVersionPolicies.Count -gt 0) {
                Add-TestResult -Category "BestPractices" -TestName "Minimum OS Version Enforcement" `
                    -Status "Pass" -Details "$($osVersionPolicies.Count) policies enforce minimum OS versions"
            }
            else {
                Add-TestResult -Category "BestPractices" -TestName "Minimum OS Version Enforcement" `
                    -Status "Warning" -Details "No minimum OS version requirements found - Microsoft recommends requiring current OS versions"
            }
        }
        catch {
            Add-TestResult -Category "BestPractices" -TestName "Minimum OS Version Enforcement" `
                -Status "Warning" -Details "Unable to verify OS version policies"
        }
        
        # Best Practice 4: Disk Encryption (BitLocker/FileVault)
        try {
            $encryptionCount = 0
            $encryptionPolicyNames = @()
            
            # Check endpoint security intents (old style)
            try {
                $encryptionIntents = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/intents?`$filter=templateId eq 'd02f2162-fcac-48db-9b7b-b0a5f76f6c6e' or templateId eq 'a239407c-698d-4ef8-b314-e3ae409204b8'"
                $encryptionCount += $encryptionIntents.value.Count
                $encryptionPolicyNames += $encryptionIntents.value | ForEach-Object { $_.displayName }
            }
            catch { }
            
            # Check Settings Catalog policies (new style)
            try {
                $configPolicies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
                $encryptionConfigPolicies = $configPolicies.value | Where-Object { 
                    $_.name -like "*bitlocker*" -or 
                    $_.name -like "*encryption*" -or 
                    $_.name -like "*filevault*" -or
                    ($_.technologies -and $_.technologies -contains "mdm" -and $_.name -match "encrypt|bitlocker|filevault")
                }
                $encryptionCount += $encryptionConfigPolicies.Count
                $encryptionPolicyNames += $encryptionConfigPolicies | ForEach-Object { $_.name }
            }
            catch { }
            
            # Check device configuration profiles
            try {
                $configProfiles = Get-MgDeviceManagementDeviceConfiguration -All
                $encryptionProfiles = $configProfiles | Where-Object {
                    $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.windows10EndpointProtectionConfiguration' -and
                    ($_.AdditionalProperties.bitLockerSystemDrivePolicy -or $_.AdditionalProperties.bitLockerFixedDrivePolicy)
                }
                $encryptionCount += $encryptionProfiles.Count
                $encryptionPolicyNames += $encryptionProfiles | ForEach-Object { $_.DisplayName }
            }
            catch { }
            
            if ($encryptionCount -gt 0) {
                $policyList = if ($encryptionPolicyNames.Count -le 5) { 
                    " | Policies: " + ($encryptionPolicyNames -join ", ") 
                } else { 
                    " | Including: " + (($encryptionPolicyNames | Select-Object -First 3) -join ", ") + "..." 
                }
                Add-TestResult -Category "BestPractices" -TestName "Disk Encryption Enforcement" `
                    -Status "Pass" -Details "$encryptionCount disk encryption policies configured$policyList"
            }
            else {
                Add-TestResult -Category "BestPractices" -TestName "Disk Encryption Enforcement" `
                    -Status "Fail" -Details "No disk encryption policies found - Microsoft requires encryption for sensitive data protection"
            }
        }
        catch {
            Add-TestResult -Category "BestPractices" -TestName "Disk Encryption Enforcement" `
                -Status "Warning" -Details "Unable to verify disk encryption policies: $($_.Exception.Message)"
        }
        
        # Best Practice 5: Microsoft Defender Antivirus
        try {
            $defenderCount = 0
            $defenderPolicyNames = @()
            
            # Check endpoint security intents
            try {
                $defenderIntents = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/intents?`$filter=templateId eq '804339ad-1553-4478-a742-138fb5807418'"
                $defenderCount += $defenderIntents.value.Count
                $defenderPolicyNames += $defenderIntents.value | ForEach-Object { $_.displayName }
            }
            catch { }
            
            # Check Settings Catalog policies
            try {
                $configPolicies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
                $defenderConfigPolicies = $configPolicies.value | Where-Object { 
                    $_.name -like "*defender*" -or 
                    $_.name -like "*antivirus*" -or
                    $_.name -like "*endpoint protection*"
                }
                $defenderCount += $defenderConfigPolicies.Count
                $defenderPolicyNames += $defenderConfigPolicies | ForEach-Object { $_.name }
            }
            catch { }
            
            # Check device configuration profiles
            try {
                $configProfiles = Get-MgDeviceManagementDeviceConfiguration -All
                $defenderProfiles = $configProfiles | Where-Object {
                    $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.windows10EndpointProtectionConfiguration' -and
                    ($_.AdditionalProperties.defenderRequireRealTimeMonitoring -or 
                     $_.AdditionalProperties.defenderRequireCloudProtection)
                }
                $defenderCount += $defenderProfiles.Count
                $defenderPolicyNames += $defenderProfiles | ForEach-Object { $_.DisplayName }
            }
            catch { }
            
            if ($defenderCount -gt 0) {
                $policyList = if ($defenderPolicyNames.Count -le 5) { 
                    " | Policies: " + ($defenderPolicyNames -join ", ") 
                } else { 
                    " | Including: " + (($defenderPolicyNames | Select-Object -First 3) -join ", ") + "..." 
                }
                Add-TestResult -Category "BestPractices" -TestName "Microsoft Defender Antivirus Configuration" `
                    -Status "Pass" -Details "$defenderCount Defender antivirus policies configured$policyList"
            }
            else {
                Add-TestResult -Category "BestPractices" -TestName "Microsoft Defender Antivirus Configuration" `
                    -Status "Fail" -Details "No Defender antivirus policies found - Microsoft requires antivirus protection"
            }
        }
        catch {
            Add-TestResult -Category "BestPractices" -TestName "Microsoft Defender Antivirus Configuration" `
                -Status "Warning" -Details "Unable to verify Defender policies: $($_.Exception.Message)"
        }
        
        # Best Practice 6: Password Complexity Requirements
        try {
            $passwordPolicies = Get-MgDeviceManagementDeviceCompliancePolicy -All | Where-Object {
                $_.AdditionalProperties.ContainsKey('passwordRequired') -and 
                $_.AdditionalProperties['passwordRequired'] -eq $true
            }
            
            if ($passwordPolicies.Count -gt 0) {
                Add-TestResult -Category "BestPractices" -TestName "Password Requirements" `
                    -Status "Pass" -Details "$($passwordPolicies.Count) policies enforce password requirements"
            }
            else {
                Add-TestResult -Category "BestPractices" -TestName "Password Requirements" `
                    -Status "Warning" -Details "No password requirement policies found - Microsoft recommends enforcing strong passwords"
            }
        }
        catch {
            Add-TestResult -Category "BestPractices" -TestName "Password Requirements" `
                -Status "Warning" -Details "Unable to verify password policies"
        }
        
        # Best Practice 7: Application Protection Policies (MAM)
        try {
            $mamPolicies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceAppManagement/managedAppPolicies"
            
            if ($mamPolicies.value.Count -gt 0) {
                Add-TestResult -Category "BestPractices" -TestName "Mobile Application Management (MAM)" `
                    -Status "Pass" -Details "$($mamPolicies.value.Count) app protection policies configured"
            }
            else {
                Add-TestResult -Category "BestPractices" -TestName "Mobile Application Management (MAM)" `
                    -Status "Warning" -Details "No app protection policies found - Microsoft recommends MAM for mobile devices"
            }
        }
        catch {
            Add-TestResult -Category "BestPractices" -TestName "Mobile Application Management (MAM)" `
                -Status "Warning" -Details "Unable to verify MAM policies"
        }
        
        # Best Practice 8: Device Naming Convention
        try {
            $enrollmentProfiles = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles"
            
            $namedProfiles = $enrollmentProfiles.value | Where-Object { 
                $_.deviceNameTemplate -and $_.deviceNameTemplate -ne ""
            }
            
            if ($namedProfiles.Count -gt 0) {
                Add-TestResult -Category "BestPractices" -TestName "Device Naming Convention (Autopilot)" `
                    -Status "Pass" -Details "$($namedProfiles.Count) Autopilot profiles use naming templates"
            }
            else {
                Add-TestResult -Category "BestPractices" -TestName "Device Naming Convention (Autopilot)" `
                    -Status "Warning" -Details "No device naming templates configured - Microsoft recommends standardized naming"
            }
        }
        catch {
            Add-TestResult -Category "BestPractices" -TestName "Device Naming Convention (Autopilot)" `
                -Status "Warning" -Details "Unable to verify device naming configuration"
        }
        
        # Best Practice 9: Security Baseline Profiles
        try {
            $securityBaselines = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/templates?`$filter=isof('microsoft.graph.securityBaselineTemplate')"
            
            if ($securityBaselines.value.Count -gt 0) {
                Add-TestResult -Category "BestPractices" -TestName "Security Baseline Implementation" `
                    -Status "Pass" -Details "Security baseline templates available for deployment"
            }
            else {
                Add-TestResult -Category "BestPractices" -TestName "Security Baseline Implementation" `
                    -Status "Warning" -Details "Consider implementing Microsoft security baselines"
            }
        }
        catch {
            Add-TestResult -Category "BestPractices" -TestName "Security Baseline Implementation" `
                -Status "Warning" -Details "Unable to verify security baselines"
        }
        
        # Best Practice 10: Compliance Grace Period
        try {
            $compliancePolicies = Get-MgDeviceManagementDeviceCompliancePolicy -All
            
            $policiesWithGrace = $compliancePolicies | Where-Object {
                $_.ScheduledActionsForRule -and $_.ScheduledActionsForRule.Count -gt 0
            }
            
            if ($policiesWithGrace.Count -gt 0) {
                Add-TestResult -Category "BestPractices" -TestName "Compliance Grace Period Configuration" `
                    -Status "Pass" -Details "$($policiesWithGrace.Count) policies have scheduled actions configured"
            }
            else {
                Add-TestResult -Category "BestPractices" -TestName "Compliance Grace Period Configuration" `
                    -Status "Warning" -Details "Consider configuring compliance grace periods and actions"
            }
        }
        catch {
            Add-TestResult -Category "BestPractices" -TestName "Compliance Grace Period Configuration" `
                -Status "Warning" -Details "Unable to verify grace period configuration"
        }
        
        $testResults.BestPractices.Summary = @{
            Note = "Tests based on Microsoft Intune Best Practices and Security Recommendations"
        }
        
    }
    catch {
        Add-TestResult -Category "BestPractices" -TestName "Best Practices Assessment" `
            -Status "Fail" -Details "Error during best practices assessment: $($_.Exception.Message)"
    }
}

# Test 7: Reports and Monitoring
function Test-Monitoring {
    Write-Host "`nTesting Reports and Monitoring..." -ForegroundColor Cyan
    
    try {
        # Test managed devices visibility
        $managedDevices = Get-MgDeviceManagementManagedDevice -Top 10
        
        if ($managedDevices.Count -eq 0) {
            Add-TestResult -Category "Monitoring" -TestName "Managed Devices Visibility" `
                -Status "Warning" -Details "No managed devices found or unable to access"
        }
        else {
            Add-TestResult -Category "Monitoring" -TestName "Managed Devices Visibility" `
                -Status "Pass" -Details "Successfully accessed managed devices data" `
                -Data $managedDevices
        }
        
        # Test compliance status
        try {
            $complianceStatus = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=id,deviceName,complianceState&`$top=10"
            
            Add-TestResult -Category "Monitoring" -TestName "Compliance Status Access" `
                -Status "Pass" -Details "Successfully accessed compliance status data"
                
        }
        catch {
            Add-TestResult -Category "Monitoring" -TestName "Compliance Status Access" `
                -Status "Warning" -Details "Limited access to compliance status data"
        }
        
        # Test device health monitoring
        try {
            $deviceHealthScripts = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts"
            
            Add-TestResult -Category "Monitoring" -TestName "Device Health Scripts" `
                -Status $(if ($deviceHealthScripts.value.Count -gt 0) { "Pass" } else { "Warning" }) `
                -Details "$($deviceHealthScripts.value.Count) health monitoring scripts found"
                
            $testResults.Monitoring.HealthScripts = $deviceHealthScripts.value.Count
        }
        catch {
            Add-TestResult -Category "Monitoring" -TestName "Device Health Scripts" `
                -Status "Warning" -Details "Unable to access health monitoring scripts"
        }
        
        $testResults.Monitoring.Summary = @{
            ManagedDevicesAccessible = $managedDevices.Count -gt 0
        }
        
    }
    catch {
        Add-TestResult -Category "Monitoring" -TestName "Monitoring Access" `
            -Status "Fail" -Details "Error accessing monitoring features: $($_.Exception.Message)"
    }
}

# Test 15: Software Update Policies
function Test-SoftwareUpdates {
    Write-Host "`nTesting Software Update Policies..." -ForegroundColor Cyan
    
    try {
        # Windows Update Rings
        try {
            $windowsUpdateRings = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$filter=isof('microsoft.graph.windowsUpdateForBusinessConfiguration')"
            
            if ($windowsUpdateRings.value.Count -gt 0) {
                Add-TestResult -Category "SoftwareUpdates" -TestName "Windows Update Rings" `
                    -Status "Pass" -Details "$($windowsUpdateRings.value.Count) Windows Update ring(s) configured"
                
                foreach ($ring in $windowsUpdateRings.value) {
                    $deferralInfo = ""
                    if ($ring.qualityUpdatesDeferralPeriodInDays) {
                        $deferralInfo += "Quality updates: $($ring.qualityUpdatesDeferralPeriodInDays) days | "
                    }
                    if ($ring.featureUpdatesDeferralPeriodInDays) {
                        $deferralInfo += "Feature updates: $($ring.featureUpdatesDeferralPeriodInDays) days"
                    }
                    
                    Add-TestResult -Category "SoftwareUpdates" `
                        -TestName "Windows Update Ring: $($ring.displayName)" `
                        -Status "Pass" `
                        -Details "Update mode: $($ring.automaticUpdateMode) | $deferralInfo"
                }
            }
            else {
                Add-TestResult -Category "SoftwareUpdates" -TestName "Windows Update Rings" `
                    -Status "Warning" -Details "No Windows Update rings configured - updates not being managed"
            }
        }
        catch {
            Add-TestResult -Category "SoftwareUpdates" -TestName "Windows Update Rings" `
                -Status "Warning" -Details "Unable to access Windows Update rings"
        }
        
        # iOS/iPadOS Update Policies
        try {
            $iosUpdatePolicies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/iosUpdateStatuses"
            
            if ($iosUpdatePolicies.value.Count -gt 0) {
                Add-TestResult -Category "SoftwareUpdates" -TestName "iOS/iPadOS Update Policies" `
                    -Status "Pass" -Details "$($iosUpdatePolicies.value.Count) iOS update configuration(s) found"
            }
        }
        catch {
            # iOS updates may not be configured
        }
        
        # Feature Updates for Windows
        try {
            $featureUpdates = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsFeatureUpdateProfiles"
            
            if ($featureUpdates.value.Count -gt 0) {
                Add-TestResult -Category "SoftwareUpdates" -TestName "Windows Feature Update Profiles" `
                    -Status "Pass" -Details "$($featureUpdates.value.Count) feature update profile(s) configured"
                
                foreach ($profile in $featureUpdates.value) {
                    Add-TestResult -Category "SoftwareUpdates" `
                        -TestName "Feature Update: $($profile.displayName)" `
                        -Status "Pass" `
                        -Details "Target version: $($profile.featureUpdateVersion) | Rollout: $($profile.rolloutSettings.offerStartDateTimeInUTC)"
                }
            }
        }
        catch {
            # Feature updates may not be configured
        }
        
        # Quality Updates for Windows  
        try {
            $qualityUpdates = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsQualityUpdateProfiles"
            
            if ($qualityUpdates.value.Count -gt 0) {
                Add-TestResult -Category "SoftwareUpdates" -TestName "Windows Quality Update Profiles" `
                    -Status "Pass" -Details "$($qualityUpdates.value.Count) quality update profile(s) configured"
            }
        }
        catch {
            # Quality updates may not be configured
        }
        
        $testResults.SoftwareUpdates.Summary = @{
            WindowsUpdateRings = if ($windowsUpdateRings) { $windowsUpdateRings.value.Count } else { 0 }
            FeatureUpdates     = if ($featureUpdates) { $featureUpdates.value.Count } else { 0 }
            QualityUpdates     = if ($qualityUpdates) { $qualityUpdates.value.Count } else { 0 }
        }
        
    }
    catch {
        Add-TestResult -Category "SoftwareUpdates" -TestName "Software Updates Access" `
            -Status "Fail" -Details "Error accessing software update policies: $($_.Exception.Message)"
    }
}

# Test 16: Tenant Configuration & Branding
function Test-TenantConfiguration {
    Write-Host "`nTesting Tenant Configuration & Branding..." -ForegroundColor Cyan
    
    try {
        # Company Portal Branding
        try {
            $branding = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/intuneBrand"
            
            if ($branding) {
                $brandingDetails = @()
                if ($branding.displayName) { $brandingDetails += "Company: $($branding.displayName)" }
                if ($branding.themeColor) { $brandingDetails += "Theme color: $($branding.themeColor)" }
                if ($branding.showLogo) { $brandingDetails += "Logo configured" }
                if ($branding.showDisplayNameNextToLogo) { $brandingDetails += "Display name shown" }
                if ($branding.contactITName) { $brandingDetails += "IT contact: $($branding.contactITName)" }
                
                Add-TestResult -Category "TenantConfiguration" -TestName "Company Portal Branding" `
                    -Status "Pass" -Details ($brandingDetails -join " | ")
            }
        }
        catch {
            Add-TestResult -Category "TenantConfiguration" -TestName "Company Portal Branding" `
                -Status "Warning" -Details "Unable to access branding settings"
        }
        
        # Terms and Conditions
        try {
            $termsAndConditions = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/termsAndConditions"
            
            if ($termsAndConditions.value.Count -gt 0) {
                Add-TestResult -Category "TenantConfiguration" -TestName "Terms and Conditions" `
                    -Status "Pass" -Details "$($termsAndConditions.value.Count) terms and conditions policy/policies configured"
                
                foreach ($terms in $termsAndConditions.value) {
                    Add-TestResult -Category "TenantConfiguration" `
                        -TestName "T&C: $($terms.displayName)" `
                        -Status "Pass" `
                        -Details "Version: $($terms.version) | Modified: $($terms.modifiedDateTime)"
                }
            }
            else {
                Add-TestResult -Category "TenantConfiguration" -TestName "Terms and Conditions" `
                    -Status "Warning" -Details "No terms and conditions configured"
            }
        }
        catch {
            Add-TestResult -Category "TenantConfiguration" -TestName "Terms and Conditions" `
                -Status "Warning" -Details "Unable to access terms and conditions"
        }
        
        # Device Categories
        try {
            $deviceCategories = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCategories"
            
            if ($deviceCategories.value.Count -gt 0) {
                $categoryNames = ($deviceCategories.value | ForEach-Object { $_.displayName }) -join ", "
                Add-TestResult -Category "TenantConfiguration" -TestName "Device Categories" `
                    -Status "Pass" -Details "$($deviceCategories.value.Count) categories: $categoryNames"
            }
            else {
                Add-TestResult -Category "TenantConfiguration" -TestName "Device Categories" `
                    -Status "Warning" -Details "No device categories configured - helpful for organizing devices"
            }
        }
        catch {
            Add-TestResult -Category "TenantConfiguration" -TestName "Device Categories" `
                -Status "Warning" -Details "Unable to access device categories"
        }
        
        # Notification Message Templates
        try {
            $notificationTemplates = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/notificationMessageTemplates"
            
            if ($notificationTemplates.value.Count -gt 0) {
                Add-TestResult -Category "TenantConfiguration" -TestName "Notification Message Templates" `
                    -Status "Pass" -Details "$($notificationTemplates.value.Count) notification template(s) configured"
            }
        }
        catch {
            # Notification templates may not be configured
        }
        
        # Corporate Device Identifiers
        try {
            $corpIdentifiers = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/importedDeviceIdentities?`$top=10"
            
            if ($corpIdentifiers.value.Count -gt 0) {
                Add-TestResult -Category "TenantConfiguration" -TestName "Corporate Device Identifiers" `
                    -Status "Pass" -Details "Corporate-owned device identifiers configured (IMEI/Serial numbers)"
            }
        }
        catch {
            # Corporate identifiers may not be configured
        }
        
        # Device Enrollment Managers
        try {
            $demUsers = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentManagers"
            
            if ($demUsers.value.Count -gt 0) {
                Add-TestResult -Category "TenantConfiguration" -TestName "Device Enrollment Managers" `
                    -Status "Pass" -Details "$($demUsers.value.Count) DEM account(s) configured for bulk enrollment"
            }
            else {
                Add-TestResult -Category "TenantConfiguration" -TestName "Device Enrollment Managers" `
                    -Status "Warning" -Details "No DEM accounts - consider for shared/kiosk devices"
            }
        }
        catch {
            Add-TestResult -Category "TenantConfiguration" -TestName "Device Enrollment Managers" `
                -Status "Warning" -Details "Unable to access DEM accounts"
        }
        
        $testResults.TenantConfiguration.Summary = @{
            DeviceCategories = if ($deviceCategories) { $deviceCategories.value.Count } else { 0 }
            DEMAccounts      = if ($demUsers) { $demUsers.value.Count } else { 0 }
        }
        
    }
    catch {
        Add-TestResult -Category "TenantConfiguration" -TestName "Tenant Configuration Access" `
            -Status "Fail" -Details "Error accessing tenant configuration: $($_.Exception.Message)"
    }
}

# Test 17: Compliance Actions & Notifications
function Test-ComplianceActions {
    Write-Host "`nTesting Compliance Actions & Notifications..." -ForegroundColor Cyan
    
    try {
        $compliancePolicies = Get-MgDeviceManagementDeviceCompliancePolicy -All
        
        if ($compliancePolicies.Count -gt 0) {
            foreach ($policy in $compliancePolicies) {
                try {
                    # Get scheduled actions for the policy
                    $scheduledActions = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.Id)/scheduledActionsForRule"
                    
                    if ($scheduledActions.value.Count -gt 0) {
                        foreach ($action in $scheduledActions.value) {
                            $actionDetails = @()
                            
                            foreach ($config in $action.scheduledActionConfigurations) {
                                $actionType = $config.actionType
                                $gracePeriod = $config.gracePeriodHours
                                
                                $actionDetails += "After $gracePeriod hours: $actionType"
                            }
                            
                            if ($actionDetails.Count -gt 0) {
                                Add-TestResult -Category "ComplianceActions" `
                                    -TestName "Actions for: $($policy.DisplayName)" `
                                    -Status "Pass" `
                                    -Details ($actionDetails -join " | ")
                            }
                        }
                    }
                    else {
                        Add-TestResult -Category "ComplianceActions" `
                            -TestName "Actions for: $($policy.DisplayName)" `
                            -Status "Warning" `
                            -Details "No scheduled actions configured - devices won't be marked non-compliant"
                    }
                }
                catch {
                    # Unable to get actions for this policy
                }
            }
        }
        else {
            Add-TestResult -Category "ComplianceActions" -TestName "Compliance Actions" `
                -Status "Warning" -Details "No compliance policies to check actions for"
        }
        
    }
    catch {
        Add-TestResult -Category "ComplianceActions" -TestName "Compliance Actions Access" `
            -Status "Warning" -Details "Unable to access compliance action details"
    }
}

# Test 18: Windows Hello for Business
function Test-WindowsHello {
    Write-Host "`nTesting Windows Hello for Business..." -ForegroundColor Cyan
    
    try {
        # Windows Hello for Business policies
        try {
            $whfbPolicies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?`$filter=deviceEnrollmentConfigurationType eq 'windowsHelloForBusiness'"
            
            if ($whfbPolicies.value.Count -gt 0) {
                Add-TestResult -Category "WindowsHello" -TestName "Windows Hello for Business Policies" `
                    -Status "Pass" -Details "$($whfbPolicies.value.Count) Windows Hello policy/policies configured"
                
                foreach ($policy in $whfbPolicies.value) {
                    $details = @()
                    if ($policy.pinMinimumLength) { $details += "Min PIN: $($policy.pinMinimumLength)" }
                    if ($policy.pinMaximumLength) { $details += "Max PIN: $($policy.pinMaximumLength)" }
                    if ($policy.pinUppercaseCharactersUsage) { $details += "Uppercase: $($policy.pinUppercaseCharactersUsage)" }
                    if ($policy.pinLowercaseCharactersUsage) { $details += "Lowercase: $($policy.pinLowercaseCharactersUsage)" }
                    if ($policy.pinSpecialCharactersUsage) { $details += "Special chars: $($policy.pinSpecialCharactersUsage)" }
                    
                    Add-TestResult -Category "WindowsHello" `
                        -TestName "WHfB: $($policy.displayName)" `
                        -Status "Pass" `
                        -Details ($details -join " | ")
                }
            }
            else {
                Add-TestResult -Category "WindowsHello" -TestName "Windows Hello for Business" `
                    -Status "Warning" -Details "Not configured - Microsoft recommends passwordless authentication"
            }
        }
        catch {
            Add-TestResult -Category "WindowsHello" -TestName "Windows Hello for Business" `
                -Status "Warning" -Details "Unable to access Windows Hello policies"
        }
        
        $testResults.WindowsHello.Summary = @{
            Policies = if ($whfbPolicies) { $whfbPolicies.value.Count } else { 0 }
        }
        
    }
    catch {
        Add-TestResult -Category "WindowsHello" -TestName "Windows Hello Access" `
            -Status "Warning" -Details "Error accessing Windows Hello configuration"
    }
}

# Test 19: Intune Connectors & Integration
function Test-IntuneConnectors {
    Write-Host "`nTesting Intune Connectors & Integration..." -ForegroundColor Cyan
    
    try {
        # Exchange Connector
        try {
            $exchangeConnector = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/exchangeConnectors"
            
            if ($exchangeConnector.value.Count -gt 0) {
                foreach ($connector in $exchangeConnector.value) {
                    $status = $connector.status
                    $lastSync = $connector.lastSyncDateTime
                    
                    Add-TestResult -Category "IntuneConnectors" `
                        -TestName "Exchange Connector: $($connector.serverName)" `
                        -Status $(if ($status -eq "Connected") { "Pass" } else { "Fail" }) `
                        -Details "Status: $status | Last sync: $lastSync"
                }
            }
        }
        catch {
            # Exchange connector may not be configured
        }
        
        # Partner Device Management (Jamf, VMware Workspace ONE, etc.)
        try {
            $mobileThreatDefense = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors"
            
            if ($mobileThreatDefense.value.Count -gt 0) {
                Add-TestResult -Category "IntuneConnectors" -TestName "Mobile Threat Defense Connectors" `
                    -Status "Pass" -Details "$($mobileThreatDefense.value.Count) MTD connector(s) configured"
                
                foreach ($connector in $mobileThreatDefense.value) {
                    Add-TestResult -Category "IntuneConnectors" `
                        -TestName "MTD: $($connector.displayName)" `
                        -Status "Pass" `
                        -Details "Partner: $($connector.partnerState) | iOS: $($connector.iosEnabled) | Android: $($connector.androidEnabled)"
                }
            }
        }
        catch {
            # MTD may not be configured
        }
        
        # Certificate Connectors
        try {
            $certConnectors = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/ndesConnectors"
            
            if ($certConnectors.value.Count -gt 0) {
                Add-TestResult -Category "IntuneConnectors" -TestName "Certificate Connectors (NDES)" `
                    -Status "Pass" -Details "$($certConnectors.value.Count) NDES connector(s) configured for SCEP"
                
                foreach ($connector in $certConnectors.value) {
                    $lastSync = if ($connector.lastConnectionDateTime) { $connector.lastConnectionDateTime } else { "Never" }
                    Add-TestResult -Category "IntuneConnectors" `
                        -TestName "NDES: $($connector.displayName)" `
                        -Status $(if ($connector.state -eq "active") { "Pass" } else { "Warning" }) `
                        -Details "State: $($connector.state) | Last connection: $lastSync"
                }
            }
        }
        catch {
            # NDES may not be configured
        }
        
        # Telecom Expense Management
        try {
            $temConnectors = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/telecomExpenseManagementPartners"
            
            if ($temConnectors.value.Count -gt 0) {
                Add-TestResult -Category "IntuneConnectors" -TestName "Telecom Expense Management" `
                    -Status "Pass" -Details "$($temConnectors.value.Count) TEM partner(s) configured"
            }
        }
        catch {
            # TEM may not be configured
        }
        
        $testResults.IntuneConnectors.Summary = @{
            TotalConnectors = ($exchangeConnector.value.Count + $mobileThreatDefense.value.Count + $certConnectors.value.Count)
        }
        
    }
    catch {
        Add-TestResult -Category "IntuneConnectors" -TestName "Connectors Access" `
            -Status "Warning" -Details "Unable to access connector information"
    }
}

# Test 20: Device Inventory Summary
function Test-DeviceInventory {
    Write-Host "`nTesting Device Inventory..." -ForegroundColor Cyan
    
    try {
        # Get managed devices summary
        try {
            $allDevices = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=operatingSystem,complianceState,managementAgent&`$top=999"
            
            if ($allDevices.value.Count -gt 0) {
                # Group by OS
                $byOS = $allDevices.value | Group-Object -Property operatingSystem
                $osBreakdown = ($byOS | ForEach-Object { "$($_.Name): $($_.Count)" }) -join " | "
                
                # Group by compliance
                $compliant = ($allDevices.value | Where-Object { $_.complianceState -eq "compliant" }).Count
                $noncompliant = ($allDevices.value | Where-Object { $_.complianceState -eq "noncompliant" }).Count
                $unknown = ($allDevices.value | Where-Object { $_.complianceState -eq "unknown" -or $_.complianceState -eq $null }).Count
                
                Add-TestResult -Category "DeviceInventory" -TestName "Total Managed Devices" `
                    -Status "Pass" -Details "$($allDevices.value.Count) devices | $osBreakdown"
                
                Add-TestResult -Category "DeviceInventory" -TestName "Compliance Status" `
                    -Status $(if ($noncompliant -gt 0) { "Warning" } else { "Pass" }) `
                    -Details "✓ Compliant: $compliant | ❌ Non-compliant: $noncompliant | ⚠ Unknown: $unknown"
                
                # Corporate vs Personal
                $corporate = ($allDevices.value | Where-Object { $_.managementAgent -eq "mdm" -or $_.managementAgent -eq "eas" }).Count
                $byod = ($allDevices.value | Where-Object { $_.managementAgent -eq "mam" }).Count
                
                if ($corporate -gt 0 -or $byod -gt 0) {
                    Add-TestResult -Category "DeviceInventory" -TestName "Device Ownership" `
                        -Status "Pass" -Details "Corporate: $corporate | BYOD: $byod"
                }
            }
            else {
                Add-TestResult -Category "DeviceInventory" -TestName "Managed Devices" `
                    -Status "Warning" -Details "No managed devices found in tenant"
            }
        }
        catch {
            Add-TestResult -Category "DeviceInventory" -TestName "Device Inventory" `
                -Status "Warning" -Details "Unable to access device inventory: $($_.Exception.Message)"
        }
        
        $testResults.DeviceInventory.Summary = @{
            TotalDevices  = if ($allDevices) { $allDevices.value.Count } else { 0 }
            Compliant     = $compliant
            NonCompliant  = $noncompliant
        }
        
    }
    catch {
        Add-TestResult -Category "DeviceInventory" -TestName "Device Inventory Access" `
            -Status "Fail" -Details "Error accessing device inventory"
    }
}

# Generate HTML Report
function Generate-HTMLReport {
    param(
        [object]$Results,
        [string]$OutputPath
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $fileName = "IntuneConfigReport_$timestamp.html"
    $fullPath = Join-Path -Path $OutputPath -ChildPath $fileName
    
    # Define categories first
    $categories = @(
        @{Name = "BestPractices"; Title = "Microsoft Best Practices Assessment" },
        @{Name = "ConditionalAccess"; Title = "Conditional Access Policies (Zero Trust)" },
        @{Name = "CompliancePolicies"; Title = "Device Compliance Policies" },
        @{Name = "ConfigurationProfiles"; Title = "Configuration Profiles" },
        @{Name = "AppProtection"; Title = "App Protection Policies (MAM)" },
        @{Name = "Applications"; Title = "Application Management" },
        @{Name = "EndpointSecurity"; Title = "Endpoint Security Policies" },
        @{Name = "AutopilotProfiles"; Title = "Windows Autopilot Deployment Profiles" },
        @{Name = "EnrollmentSettings"; Title = "Enrollment Settings" },
        @{Name = "DeviceFilters"; Title = "Assignment Filters" },
        @{Name = "Scripts"; Title = "PowerShell Scripts & Proactive Remediations" },
        @{Name = "RBAC"; Title = "Role-Based Access Control" },
        @{Name = "EnrollmentTokens"; Title = "Enrollment Tokens & Certificates" },
        @{Name = "Monitoring"; Title = "Reports and Monitoring" },
        @{Name = "SoftwareUpdates"; Title = "Software Update Policies" },
        @{Name = "TenantConfiguration"; Title = "Tenant Configuration & Branding" },
        @{Name = "ComplianceActions"; Title = "Compliance Actions & Notifications" },
        @{Name = "WindowsHello"; Title = "Windows Hello for Business" },
        @{Name = "IntuneConnectors"; Title = "Intune Connectors & Integration" },
        @{Name = "DeviceInventory"; Title = "Device Inventory Summary" }
    )
    
    # Calculate statistics for charts
    $categoryStats = @{}
    foreach ($category in $categories) {
        $tests = $Results[$category.Name].Tests
        if ($tests) {
            $categoryStats[$category.Name] = @{
                Title = $category.Title
                Total = $tests.Count
                Pass = ($tests | Where-Object { $_.Status -eq "Pass" }).Count
                Fail = ($tests | Where-Object { $_.Status -eq "Fail" }).Count
                Warning = ($tests | Where-Object { $_.Status -eq "Warning" }).Count
            }
        }
    }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Microsoft Intune Configuration Test Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }
        .container { 
            max-width: 1600px; 
            margin: 0 auto; 
            background-color: white; 
            padding: 40px; 
            box-shadow: 0 10px 40px rgba(0,0,0,0.3);
            border-radius: 12px;
        }
        .header {
            background: linear-gradient(135deg, #0078d4 0%, #005a9e 100%);
            color: white;
            padding: 30px;
            border-radius: 8px;
            margin-bottom: 30px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        h1 { 
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
        }
        .header-info {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }
        .header-info-item {
            background: rgba(255,255,255,0.1);
            padding: 10px 15px;
            border-radius: 5px;
            backdrop-filter: blur(10px);
        }
        .header-info-item strong {
            display: block;
            font-size: 0.9em;
            opacity: 0.9;
            margin-bottom: 5px;
        }
        h2 { 
            color: #0078d4; 
            margin: 40px 0 20px 0; 
            border-left: 5px solid #0078d4; 
            padding-left: 15px;
            font-size: 1.8em;
        }
        .summary { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); 
            gap: 20px; 
            margin: 30px 0; 
        }
        .summary-card { 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            color: white; 
            padding: 25px; 
            border-radius: 12px; 
            text-align: center;
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
            cursor: pointer;
        }
        .summary-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 8px 25px rgba(0,0,0,0.3);
        }
        .summary-card h3 { margin: 0; font-size: 3em; text-shadow: 2px 2px 4px rgba(0,0,0,0.2); }
        .summary-card p { margin: 10px 0 0 0; font-size: 1em; opacity: 0.95; }
        .pass { background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%); }
        .fail { background: linear-gradient(135deg, #eb3349 0%, #f45c43 100%); }
        .warning { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); }
        
        .charts-section {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 30px;
            margin: 40px 0;
        }
        .chart-container {
            background: white;
            padding: 25px;
            border-radius: 12px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
            border: 1px solid #e0e0e0;
        }
        .chart-container h3 {
            color: #0078d4;
            margin-bottom: 20px;
            font-size: 1.3em;
            text-align: center;
        }
        
        .test-category { 
            margin: 30px 0; 
            background: #f9f9f9;
            border-radius: 12px;
            overflow: hidden;
            box-shadow: 0 2px 10px rgba(0,0,0,0.05);
            border: 1px solid #e0e0e0;
        }
        .category-header {
            background: linear-gradient(135deg, #0078d4 0%, #005a9e 100%);
            color: white;
            padding: 20px 25px;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
            transition: background 0.3s ease;
        }
        .category-header:hover {
            background: linear-gradient(135deg, #005a9e 0%, #004578 100%);
        }
        .category-header h2 {
            margin: 0;
            color: white;
            border: none;
            padding: 0;
            font-size: 1.5em;
        }
        .toggle-icon {
            font-size: 1.5em;
            transition: transform 0.3s ease;
        }
        .toggle-icon.collapsed {
            transform: rotate(-90deg);
        }
        .category-content {
            max-height: 10000px;
            overflow: hidden;
            transition: max-height 0.5s ease, padding 0.5s ease;
            padding: 25px;
        }
        .category-content.collapsed {
            max-height: 0;
            padding: 0 25px;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }
        .stat-box {
            background: white;
            padding: 15px;
            border-radius: 8px;
            text-align: center;
            border-left: 4px solid #0078d4;
            box-shadow: 0 2px 5px rgba(0,0,0,0.05);
        }
        .stat-box .number {
            font-size: 2em;
            font-weight: bold;
            color: #0078d4;
        }
        .stat-box .label {
            font-size: 0.9em;
            color: #666;
            margin-top: 5px;
        }
        
        table { 
            width: 100%; 
            border-collapse: collapse; 
            margin: 20px 0; 
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            background: white;
            border-radius: 8px;
            overflow: hidden;
        }
        th { 
            background: linear-gradient(135deg, #0078d4 0%, #005a9e 100%);
            color: white; 
            padding: 15px; 
            text-align: left; 
            font-weight: 600;
            font-size: 1em;
        }
        td { 
            padding: 12px 15px; 
            border-bottom: 1px solid #e0e0e0; 
            vertical-align: top;
            line-height: 1.6;
        }
        tr:hover { 
            background-color: #f0f8ff;
            transition: background-color 0.2s ease;
        }
        tr:last-child td {
            border-bottom: none;
        }
        .detail-text { 
            white-space: pre-wrap; 
            font-size: 0.95em; 
            line-height: 1.8;
            color: #333;
        }
        .strength-line { color: #28a745; padding: 2px 0; }
        .issue-line { color: #dc3545; padding: 2px 0; }
        .recommendation-line { color: #007bff; padding: 2px 0; }
        .status-pass { color: #28a745; font-weight: bold; }
        .status-fail { color: #dc3545; font-weight: bold; }
        .status-warning { color: #ffc107; font-weight: bold; }
        
        .badge { 
            display: inline-block; 
            padding: 6px 12px; 
            border-radius: 20px; 
            font-size: 0.85em; 
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .badge-pass { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .badge-fail { background-color: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .badge-warning { background-color: #fff3cd; color: #856404; border: 1px solid #ffeaa7; }
        
        .quick-nav {
            position: sticky;
            top: 20px;
            background: white;
            padding: 20px;
            border-radius: 12px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
            margin-bottom: 30px;
            border: 1px solid #e0e0e0;
            z-index: 100;
        }
        .quick-nav h3 {
            color: #0078d4;
            margin-bottom: 15px;
            font-size: 1.2em;
        }
        .nav-buttons {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
        }
        .nav-button {
            padding: 8px 15px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 0.9em;
            transition: transform 0.2s ease, box-shadow 0.2s ease;
            text-decoration: none;
        }
        .nav-button:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 10px rgba(0,0,0,0.2);
        }
        
        .expand-collapse-all {
            text-align: center;
            margin: 30px 0;
        }
        .expand-collapse-all button {
            padding: 12px 30px;
            margin: 0 10px;
            background: linear-gradient(135deg, #0078d4 0%, #005a9e 100%);
            color: white;
            border: none;
            border-radius: 25px;
            cursor: pointer;
            font-size: 1em;
            font-weight: 600;
            transition: transform 0.2s ease, box-shadow 0.2s ease;
        }
        .expand-collapse-all button:hover {
            transform: scale(1.05);
            box-shadow: 0 5px 15px rgba(0,0,0,0.3);
        }
        
        .footer { 
            margin-top: 60px; 
            padding: 30px;
            border-top: 3px solid #0078d4; 
            color: #666; 
            text-align: center;
            background: #f9f9f9;
            border-radius: 8px;
        }
        .footer p {
            margin: 5px 0;
        }
        
        @media print {
            body { background: white; padding: 0; }
            .container { box-shadow: none; padding: 20px; }
            .quick-nav, .expand-collapse-all { display: none; }
            .category-content { max-height: none !important; padding: 25px !important; }
            .test-category { page-break-inside: avoid; }
        }
        
        @media (max-width: 768px) {
            .summary { grid-template-columns: 1fr 1fr; }
            .charts-section { grid-template-columns: 1fr; }
            .header-info { grid-template-columns: 1fr; }
            h1 { font-size: 1.8em; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛡️ Microsoft Intune Configuration Test Report</h1>
            <div class="header-info">
                <div class="header-info-item">
                    <strong>Generated</strong>
                    <div>$($Results.TestDate.ToString('yyyy-MM-dd HH:mm:ss'))</div>
                </div>
                <div class="header-info-item">
                    <strong>Tenant ID</strong>
                    <div>$((Get-MgContext).TenantId)</div>
                </div>
                <div class="header-info-item">
                    <strong>Account</strong>
                    <div>$((Get-MgContext).Account)</div>
                </div>
                <div class="header-info-item">
                    <strong>Success Rate</strong>
                    <div>$(if ($Results.Summary.TotalTests -gt 0) { [math]::Round(($Results.Summary.PassedTests / $Results.Summary.TotalTests) * 100, 1) } else { 0 })%</div>
                </div>
            </div>
        </div>
        
        <div class="summary">
            <div class="summary-card">
                <h3>$($Results.Summary.TotalTests)</h3>
                <p>Total Tests</p>
            </div>
            <div class="summary-card pass">
                <h3>$($Results.Summary.PassedTests)</h3>
                <p>✓ Passed</p>
            </div>
            <div class="summary-card fail">
                <h3>$($Results.Summary.FailedTests)</h3>
                <p>✗ Failed</p>
            </div>
            <div class="summary-card warning">
                <h3>$($Results.Summary.WarningTests)</h3>
                <p>⚠ Warnings</p>
            </div>
        </div>
        
        <div class="charts-section">
            <div class="chart-container">
                <h3>Overall Test Results</h3>
                <canvas id="overallChart"></canvas>
            </div>
            <div class="chart-container">
                <h3>Results by Category</h3>
                <canvas id="categoryChart"></canvas>
            </div>
        </div>
        
        <div class="expand-collapse-all">
            <button onclick="expandAll()">📂 Expand All Sections</button>
            <button onclick="collapseAll()">📁 Collapse All Sections</button>
            <button onclick="window.print()" style="background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);">🖨️ Print Report</button>
        </div>
        
        <div class="quick-nav">
            <h3>📍 Quick Navigation</h3>
            <div class="nav-buttons" id="quickNavButtons"></div>
        </div>
        
        <div class="test-category">
            <div class="category-header" style="background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);">
                <h2>📊 Configuration Summary</h2>
            </div>
            <div class="category-content">
                <div class="stats-grid">
"@
    
    # Add summary statistics
    if ($Results.CompliancePolicies.Summary.TotalPolicies) {
        $html += @"
                    <div class="stat-box">
                        <div class="number">$($Results.CompliancePolicies.Summary.TotalPolicies)</div>
                        <div class="label">Compliance Policies</div>
                    </div>
"@
    }
    
    if ($Results.ConfigurationProfiles.Summary.TotalProfiles) {
        $html += @"
                    <div class="stat-box">
                        <div class="number">$($Results.ConfigurationProfiles.Summary.TotalProfiles)</div>
                        <div class="label">Configuration Profiles</div>
                    </div>
"@
    }
    
    if ($Results.Applications.Summary.TotalApps) {
        $html += @"
                    <div class="stat-box">
                        <div class="number">$($Results.Applications.Summary.TotalApps)</div>
                        <div class="label">Applications</div>
                    </div>
"@
    }
    
    if ($Results.ConditionalAccess.Summary.TotalPolicies) {
        $html += @"
                    <div class="stat-box">
                        <div class="number">$($Results.ConditionalAccess.Summary.TotalPolicies)</div>
                        <div class="label">Conditional Access Policies</div>
                    </div>
"@
    }
    
    if ($Results.EndpointSecurity.Summary.TotalIntents -or $Results.EndpointSecurity.Summary.SettingsCatalogPolicies) {
        $totalEndpoint = ($Results.EndpointSecurity.Summary.TotalIntents + $Results.EndpointSecurity.Summary.SettingsCatalogPolicies)
        $html += @"
                    <div class="stat-box">
                        <div class="number">$totalEndpoint</div>
                        <div class="label">Endpoint Security Policies</div>
                    </div>
"@
    }
    
    if ($Results.AutopilotProfiles.Summary.TotalProfiles) {
        $html += @"
                    <div class="stat-box">
                        <div class="number">$($Results.AutopilotProfiles.Summary.TotalProfiles)</div>
                        <div class="label">Autopilot Profiles</div>
                    </div>
"@
    }
    
    if ($Results.AppProtection.Summary.TotalPolicies) {
        $html += @"
                    <div class="stat-box">
                        <div class="number">$($Results.AppProtection.Summary.TotalPolicies)</div>
                        <div class="label">App Protection Policies</div>
                    </div>
"@
    }
    
    if ($Results.Scripts.Summary.PowerShellScripts -or $Results.Scripts.Summary.RemediationScripts) {
        $totalScripts = ($Results.Scripts.Summary.PowerShellScripts + $Results.Scripts.Summary.RemediationScripts)
        $html += @"
                    <div class="stat-box">
                        <div class="number">$totalScripts</div>
                        <div class="label">Scripts & Remediations</div>
                    </div>
"@
    }
    
    $html += @"
                </div>
                <p style="text-align: center; margin-top: 20px; color: #666; font-size: 0.95em;">
                    This summary shows the total number of configurations found in your Intune tenant during the assessment.
                </p>
            </div>
        </div>
"@

    # Add each category
    foreach ($category in $categories) {
        $tests = $Results[$category.Name].Tests
        
        if ($tests) {
            $categoryId = $category.Name -replace '\s', ''
            $passCount = ($tests | Where-Object { $_.Status -eq "Pass" }).Count
            $failCount = ($tests | Where-Object { $_.Status -eq "Fail" }).Count
            $warnCount = ($tests | Where-Object { $_.Status -eq "Warning" }).Count
            
            $html += @"
        <div class="test-category" id="category-$categoryId">
            <div class="category-header" onclick="toggleCategory('$categoryId')">
                <h2>$($category.Title)</h2>
                <span class="toggle-icon" id="icon-$categoryId">▼</span>
            </div>
            <div class="category-content" id="content-$categoryId">
                <div class="stats-grid">
                    <div class="stat-box">
                        <div class="number">$($tests.Count)</div>
                        <div class="label">Total Tests</div>
                    </div>
                    <div class="stat-box">
                        <div class="number" style="color: #28a745;">$passCount</div>
                        <div class="label">Passed</div>
                    </div>
                    <div class="stat-box">
                        <div class="number" style="color: #dc3545;">$failCount</div>
                        <div class="label">Failed</div>
                    </div>
                    <div class="stat-box">
                        <div class="number" style="color: #ffc107;">$warnCount</div>
                        <div class="label">Warnings</div>
                    </div>
                </div>
                <table>
                    <thead>
                        <tr>
                            <th style="width: 30%;">Test Name</th>
                            <th style="width: 10%;">Status</th>
                            <th style="width: 60%;">Details</th>
                        </tr>
                    </thead>
                    <tbody>
"@
            
            foreach ($test in $tests) {
                $statusClass = "status-$($test.Status.ToLower())"
                $badgeClass = "badge-$($test.Status.ToLower())"
                
                # Format details with HTML for better readability
                $formattedDetails = $test.Details
                $formattedDetails = $formattedDetails -replace '✓', '<span style="color: #28a745; font-weight: bold;">✓</span>'
                $formattedDetails = $formattedDetails -replace '❌', '<span style="color: #dc3545; font-weight: bold;">❌</span>'
                $formattedDetails = $formattedDetails -replace '💡', '<span style="color: #007bff; font-weight: bold;">💡</span>'
                $formattedDetails = $formattedDetails -replace '⚠', '<span style="color: #ffc107; font-weight: bold;">⚠</span>'
                
                $html += @"
                    <tr>
                        <td style="font-weight: 500;">$($test.TestName)</td>
                        <td><span class="badge $badgeClass">$($test.Status)</span></td>
                        <td class="detail-text">$formattedDetails</td>
                    </tr>
"@
            }
            
            $html += @"
                    </tbody>
                </table>
            </div>
        </div>
"@
        }
    }
    
    # Generate JavaScript for charts
    $categoryLabels = @()
    $categoryPassData = @()
    $categoryFailData = @()
    $categoryWarnData = @()
    
    foreach ($key in $categoryStats.Keys) {
        $categoryLabels += "'$($categoryStats[$key].Title)'"
        $categoryPassData += $categoryStats[$key].Pass
        $categoryFailData += $categoryStats[$key].Fail
        $categoryWarnData += $categoryStats[$key].Warning
    }
    
    $categoryLabelsStr = $categoryLabels -join ','
    $categoryPassDataStr = $categoryPassData -join ','
    $categoryFailDataStr = $categoryFailData -join ','
    $categoryWarnDataStr = $categoryWarnData -join ','
    
    $html += @"
        <div class="footer">
            <p><strong>Report generated by Bareminimum Solutions - Intune Configuration Testing Tool</strong></p>
            <p>© 2025 All rights reserved | Generated on $($Results.TestDate.ToString('MMMM dd, yyyy'))</p>
            <p style="margin-top: 10px; font-size: 0.9em;">This report provides a comprehensive analysis of your Microsoft Intune configuration including compliance policies, configuration profiles, endpoint security, conditional access, and more.</p>
        </div>
    </div>
    
    <script>
        // Overall Results Pie Chart
        const overallCtx = document.getElementById('overallChart').getContext('2d');
        new Chart(overallCtx, {
            type: 'doughnut',
            data: {
                labels: ['Passed', 'Failed', 'Warnings'],
                datasets: [{
                    data: [$($Results.Summary.PassedTests), $($Results.Summary.FailedTests), $($Results.Summary.WarningTests)],
                    backgroundColor: [
                        'rgba(40, 167, 69, 0.8)',
                        'rgba(220, 53, 69, 0.8)',
                        'rgba(255, 193, 7, 0.8)'
                    ],
                    borderColor: [
                        'rgba(40, 167, 69, 1)',
                        'rgba(220, 53, 69, 1)',
                        'rgba(255, 193, 7, 1)'
                    ],
                    borderWidth: 2
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels: {
                            padding: 15,
                            font: {
                                size: 12,
                                family: "'Segoe UI', sans-serif"
                            }
                        }
                    },
                    tooltip: {
                        callbacks: {
                            label: function(context) {
                                let label = context.label || '';
                                if (label) {
                                    label += ': ';
                                }
                                label += context.parsed;
                                const total = context.dataset.data.reduce((a, b) => a + b, 0);
                                const percentage = ((context.parsed / total) * 100).toFixed(1);
                                label += ' (' + percentage + '%)';
                                return label;
                            }
                        }
                    }
                }
            }
        });
        
        // Category Bar Chart
        const categoryCtx = document.getElementById('categoryChart').getContext('2d');
        new Chart(categoryCtx, {
            type: 'bar',
            data: {
                labels: [$categoryLabelsStr],
                datasets: [
                    {
                        label: 'Passed',
                        data: [$categoryPassDataStr],
                        backgroundColor: 'rgba(40, 167, 69, 0.8)',
                        borderColor: 'rgba(40, 167, 69, 1)',
                        borderWidth: 1
                    },
                    {
                        label: 'Failed',
                        data: [$categoryFailDataStr],
                        backgroundColor: 'rgba(220, 53, 69, 0.8)',
                        borderColor: 'rgba(220, 53, 69, 1)',
                        borderWidth: 1
                    },
                    {
                        label: 'Warnings',
                        data: [$categoryWarnDataStr],
                        backgroundColor: 'rgba(255, 193, 7, 0.8)',
                        borderColor: 'rgba(255, 193, 7, 1)',
                        borderWidth: 1
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                scales: {
                    x: {
                        stacked: false,
                        ticks: {
                            font: {
                                size: 10
                            },
                            maxRotation: 45,
                            minRotation: 45
                        }
                    },
                    y: {
                        stacked: false,
                        beginAtZero: true,
                        ticks: {
                            stepSize: 1
                        }
                    }
                },
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels: {
                            padding: 15,
                            font: {
                                size: 12,
                                family: "'Segoe UI', sans-serif"
                            }
                        }
                    },
                    tooltip: {
                        mode: 'index',
                        intersect: false
                    }
                }
            }
        });
        
        // Toggle category visibility
        function toggleCategory(categoryId) {
            const content = document.getElementById('content-' + categoryId);
            const icon = document.getElementById('icon-' + categoryId);
            
            if (content.classList.contains('collapsed')) {
                content.classList.remove('collapsed');
                icon.classList.remove('collapsed');
                icon.textContent = '▼';
            } else {
                content.classList.add('collapsed');
                icon.classList.add('collapsed');
                icon.textContent = '▶';
            }
        }
        
        // Expand all sections
        function expandAll() {
            const contents = document.querySelectorAll('.category-content');
            const icons = document.querySelectorAll('.toggle-icon');
            
            contents.forEach(content => {
                content.classList.remove('collapsed');
            });
            
            icons.forEach(icon => {
                icon.classList.remove('collapsed');
                icon.textContent = '▼';
            });
        }
        
        // Collapse all sections
        function collapseAll() {
            const contents = document.querySelectorAll('.category-content');
            const icons = document.querySelectorAll('.toggle-icon');
            
            contents.forEach(content => {
                content.classList.add('collapsed');
            });
            
            icons.forEach(icon => {
                icon.classList.add('collapsed');
                icon.textContent = '▶';
            });
        }
        
        // Generate quick navigation buttons
        const categories = document.querySelectorAll('.test-category');
        const navContainer = document.getElementById('quickNavButtons');
        
        categories.forEach((category, index) => {
            const button = document.createElement('a');
            button.className = 'nav-button';
            button.textContent = category.querySelector('h2').textContent;
            button.href = '#' + category.id;
            button.onclick = function(e) {
                e.preventDefault();
                category.scrollIntoView({ behavior: 'smooth', block: 'start' });
                // Expand the category if collapsed
                const categoryId = category.id.replace('category-', '');
                const content = document.getElementById('content-' + categoryId);
                if (content && content.classList.contains('collapsed')) {
                    toggleCategory(categoryId);
                }
            };
            navContainer.appendChild(button);
        });
        
        // Smooth scroll behavior
        document.querySelectorAll('a[href^="#"]').forEach(anchor => {
            anchor.addEventListener('click', function (e) {
                const href = this.getAttribute('href');
                if (href !== '#') {
                    e.preventDefault();
                    const target = document.querySelector(href);
                    if (target) {
                        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
                    }
                }
            });
        });
    </script>
</body>
</html>
"@
    
    $html | Out-File -FilePath $fullPath -Encoding UTF8
    Write-Host "`nReport generated: $fullPath" -ForegroundColor Green
    return $fullPath
}

# Test 8: Conditional Access Policies (Detailed)
function Test-ConditionalAccessPolicies {
    Write-Host "`nTesting Conditional Access Policies..." -ForegroundColor Cyan
    
    try {
        $caPolicies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies"
        
        if ($caPolicies.value.Count -eq 0) {
            Add-TestResult -Category "ConditionalAccess" -TestName "Conditional Access Policies" `
                -Status "Warning" -Details "No Conditional Access policies found - Microsoft recommends CA for zero trust"
        }
        else {
            Add-TestResult -Category "ConditionalAccess" -TestName "Conditional Access Policies Exist" `
                -Status "Pass" -Details "$($caPolicies.value.Count) Conditional Access policies found"
            
            # Analyze each policy
            foreach ($policy in $caPolicies.value) {
                $issues = @()
                $strengths = @()
                $recommendations = @()
                
                # Check if enabled
                if ($policy.state -eq "enabled") {
                    $strengths += "Policy is enabled"
                }
                elseif ($policy.state -eq "enabledForReportingButNotEnforced") {
                    $recommendations += "Policy is in report-only mode - consider enabling"
                }
                else {
                    $issues += "Policy is disabled"
                }
                
                # Check MFA requirement
                if ($policy.grantControls.builtInControls -contains "mfa") {
                    $strengths += "Requires MFA"
                }
                else {
                    $recommendations += "Does not require MFA"
                }
                
                # Check device compliance requirement
                if ($policy.grantControls.builtInControls -contains "compliantDevice") {
                    $strengths += "Requires compliant device"
                }
                elseif ($policy.grantControls.builtInControls -contains "domainJoinedDevice") {
                    $strengths += "Requires domain-joined device"
                }
                
                # Check Approved Client App requirement
                if ($policy.grantControls.builtInControls -contains "approvedApplication") {
                    $strengths += "Requires approved client app"
                }
                
                # Check app protection policy requirement
                if ($policy.grantControls.builtInControls -contains "compliantApplication") {
                    $strengths += "Requires app protection policy"
                }
                
                # Check what users are included
                if ($policy.conditions.users.includeUsers -contains "All") {
                    $strengths += "Applies to all users"
                }
                elseif ($policy.conditions.users.includeGroups) {
                    $strengths += "Applies to $($policy.conditions.users.includeGroups.Count) group(s)"
                }
                
                # Check for exclusions
                if ($policy.conditions.users.excludeUsers.Count -gt 0) {
                    $recommendations += "$($policy.conditions.users.excludeUsers.Count) users excluded - review periodically"
                }
                if ($policy.conditions.users.excludeGroups.Count -gt 0) {
                    $recommendations += "$($policy.conditions.users.excludeGroups.Count) groups excluded - review periodically"
                }
                
                # Check platform conditions
                if ($policy.conditions.platforms.includePlatforms) {
                    $platforms = $policy.conditions.platforms.includePlatforms -join ", "
                    $strengths += "Targets platforms: $platforms"
                }
                
                # Check location conditions
                if ($policy.conditions.locations.includeLocations) {
                    $strengths += "Location-based policy configured"
                }
                
                # Check sign-in risk
                if ($policy.conditions.signInRiskLevels) {
                    $riskLevels = $policy.conditions.signInRiskLevels -join ", "
                    $strengths += "Sign-in risk levels: $riskLevels"
                }
                
                # Check session controls
                if ($policy.sessionControls.signInFrequency) {
                    $strengths += "Sign-in frequency: $($policy.sessionControls.signInFrequency.value) $($policy.sessionControls.signInFrequency.type)"
                }
                
                if ($policy.sessionControls.applicationEnforcedRestrictions.isEnabled) {
                    $strengths += "Application enforced restrictions enabled"
                }
                
                if ($policy.sessionControls.cloudAppSecurity.isEnabled) {
                    $strengths += "Cloud App Security session control enabled"
                }
                
                # Determine status
                $status = if ($issues.Count -gt 0) { "Warning" } else { "Pass" }
                
                $detailText = ""
                if ($strengths.Count -gt 0) {
                    $detailText += "`n✓ Configuration ($($strengths.Count)): " + ($strengths -join "; ")
                }
                if ($issues.Count -gt 0) {
                    $detailText += "`n❌ Issues ($($issues.Count)): " + ($issues -join "; ")
                }
                if ($recommendations.Count -gt 0) {
                    $detailText += "`n💡 Recommendations ($($recommendations.Count)): " + ($recommendations -join "; ")
                }
                
                Add-TestResult -Category "ConditionalAccess" `
                    -TestName "CA Policy: $($policy.displayName)" `
                    -Status $status `
                    -Details $detailText
            }
        }
        
        $testResults.ConditionalAccess.Summary = @{
            TotalPolicies   = $caPolicies.value.Count
            EnabledPolicies = ($caPolicies.value | Where-Object { $_.state -eq "enabled" }).Count
        }
        
    }
    catch {
        Add-TestResult -Category "ConditionalAccess" -TestName "Conditional Access Access" `
            -Status "Warning" -Details "Unable to access Conditional Access policies (may need additional permissions)"
    }
}

# Test 9: App Protection Policies (MAM)
function Test-AppProtectionPolicies {
    Write-Host "`nTesting App Protection Policies..." -ForegroundColor Cyan
    
    try {
        $mamPolicies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceAppManagement/managedAppPolicies"
        
        if ($mamPolicies.value.Count -eq 0) {
            Add-TestResult -Category "AppProtection" -TestName "App Protection Policies" `
                -Status "Warning" -Details "No app protection policies found - recommended for BYOD and mobile devices"
        }
        else {
            Add-TestResult -Category "AppProtection" -TestName "App Protection Policies Exist" `
                -Status "Pass" -Details "$($mamPolicies.value.Count) app protection policies found"
            
            # Analyze each policy
            foreach ($policy in $mamPolicies.value) {
                $issues = @()
                $strengths = @()
                $recommendations = @()
                
                # iOS App Protection Policies
                if ($policy.'@odata.type' -eq "#microsoft.graph.iosManagedAppProtection") {
                    
                    if ($policy.dataBackupBlocked -eq $true) {
                        $strengths += "Data backup to iCloud blocked"
                    }
                    else {
                        $recommendations += "Consider blocking data backup for sensitive data"
                    }
                    
                    if ($policy.pinRequired -eq $true) {
                        $strengths += "PIN required for app access"
                        
                        if ($policy.minimumPinLength -ge 4) {
                            $strengths += "PIN length: $($policy.minimumPinLength) digits (Good)"
                        }
                    }
                    else {
                        $issues += "PIN not required (Best practice: Enable)"
                    }
                    
                    if ($policy.managedBrowserToOpenLinksRequired -eq $true) {
                        $strengths += "Managed browser required for links"
                    }
                    
                    if ($policy.saveAsBlocked -eq $true) {
                        $strengths += "Save As blocked (data loss prevention)"
                    }
                    
                    if ($policy.organizationalCredentialsRequired -eq $true) {
                        $strengths += "Organizational credentials required"
                    }
                    
                    if ($policy.printBlocked -eq $true) {
                        $strengths += "Printing blocked (high security)"
                    }
                    
                    if ($policy.appDataEncryptionType -ne "useDeviceLockPin") {
                        $strengths += "App data encryption: $($policy.appDataEncryptionType)"
                    }
                }
                
                # Android App Protection Policies
                if ($policy.'@odata.type' -eq "#microsoft.graph.androidManagedAppProtection") {
                    
                    if ($policy.screenCaptureBlocked -eq $true) {
                        $strengths += "Screen capture blocked"
                    }
                    else {
                        $recommendations += "Consider blocking screen capture"
                    }
                    
                    if ($policy.pinRequired -eq $true) {
                        $strengths += "PIN required for app access"
                        
                        if ($policy.minimumPinLength -ge 4) {
                            $strengths += "PIN length: $($policy.minimumPinLength) digits (Good)"
                        }
                    }
                    else {
                        $issues += "PIN not required (Best practice: Enable)"
                    }
                    
                    if ($policy.disableAppPinIfDevicePinIsSet -eq $false) {
                        $strengths += "App PIN required even with device PIN"
                    }
                    
                    if ($policy.encryptAppData -eq $true) {
                        $strengths += "App data encryption enabled"
                    }
                    else {
                        $issues += "App data encryption not enabled (Best practice: Enable)"
                    }
                }
                
                # Windows App Protection Policies
                if ($policy.'@odata.type' -eq "#microsoft.graph.windowsManagedAppProtection") {
                    
                    if ($policy.printBlocked -eq $true) {
                        $strengths += "Printing blocked"
                    }
                    
                    if ($policy.allowedInboundDataTransferSources) {
                        $strengths += "Inbound data transfer restricted"
                    }
                }
                
                # Determine status
                $status = "Pass"
                if ($issues.Count -gt 0) {
                    $status = if ($issues.Count -ge 2) { "Fail" } else { "Warning" }
                }
                
                $detailText = ""
                if ($strengths.Count -gt 0) {
                    $detailText += "`n✓ Strengths ($($strengths.Count)): " + ($strengths -join "; ")
                }
                if ($issues.Count -gt 0) {
                    $detailText += "`n❌ Issues ($($issues.Count)): " + ($issues -join "; ")
                }
                if ($recommendations.Count -gt 0) {
                    $detailText += "`n💡 Recommendations ($($recommendations.Count)): " + ($recommendations -join "; ")
                }
                
                Add-TestResult -Category "AppProtection" `
                    -TestName "MAM Policy: $($policy.displayName)" `
                    -Status $status `
                    -Details $detailText
            }
        }
        
        $testResults.AppProtection.Summary = @{
            TotalPolicies = $mamPolicies.value.Count
        }
        
    }
    catch {
        Add-TestResult -Category "AppProtection" -TestName "App Protection Access" `
            -Status "Warning" -Details "Unable to access app protection policies: $($_.Exception.Message)"
    }
}

# Test 10: Windows Autopilot Deployment Profiles
function Test-AutopilotProfiles {
    Write-Host "`nTesting Windows Autopilot Profiles..." -ForegroundColor Cyan
    
    try {
        $autopilotProfiles = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles"
        
        if ($autopilotProfiles.value.Count -eq 0) {
            Add-TestResult -Category "AutopilotProfiles" -TestName "Autopilot Profiles" `
                -Status "Warning" -Details "No Autopilot profiles found - recommended for modern provisioning"
        }
        else {
            Add-TestResult -Category "AutopilotProfiles" -TestName "Autopilot Profiles Exist" `
                -Status "Pass" -Details "$($autopilotProfiles.value.Count) Autopilot profiles found"
            
            foreach ($profile in $autopilotProfiles.value) {
                $issues = @()
                $strengths = @()
                $recommendations = @()
                
                # Check device name template
                if ($profile.deviceNameTemplate) {
                    $strengths += "Device naming template: $($profile.deviceNameTemplate)"
                }
                else {
                    $recommendations += "Consider using device naming template for standardization"
                }
                
                # Check OOBE settings
                if ($profile.outOfBoxExperienceSettings) {
                    $oobe = $profile.outOfBoxExperienceSettings
                    
                    if ($oobe.hidePrivacySettings -eq $true) {
                        $strengths += "Privacy settings page hidden (streamlined)"
                    }
                    
                    if ($oobe.hideEULA -eq $true) {
                        $strengths += "EULA page hidden (streamlined)"
                    }
                    
                    if ($oobe.userType -eq "standard") {
                        $strengths += "Users created as standard (security best practice)"
                    }
                    elseif ($oobe.userType -eq "administrator") {
                        $issues += "Users created as administrators (security risk)"
                    }
                    
                    if ($oobe.skipKeyboardSelectionPage -eq $true) {
                        $strengths += "Keyboard selection skipped (streamlined)"
                    }
                    
                    if ($oobe.hideEscapeLink -eq $true) {
                        $strengths += "Escape link hidden (prevents OOBE bypass)"
                    }
                    else {
                        $recommendations += "Consider hiding escape link to prevent setup bypass"
                    }
                }
                
                # Check enrollment status page
                if ($profile.enrollmentStatusScreenSettings.hideInstallationProgress -eq $false) {
                    $strengths += "Installation progress shown to users"
                }
                
                if ($profile.enrollmentStatusScreenSettings.blockDeviceSetupRetryByUser -eq $true) {
                    $strengths += "User cannot retry failed setup (controlled environment)"
                }
                
                # Check hybrid Azure AD join
                if ($profile.'@odata.type' -eq "#microsoft.graph.activeDirectoryWindowsAutopilotDeploymentProfile") {
                    $strengths += "Hybrid Azure AD join profile configured"
                }
                
                # Determine status
                $status = if ($issues.Count -gt 0) { "Warning" } else { "Pass" }
                
                $detailText = ""
                if ($strengths.Count -gt 0) {
                    $detailText += "`n✓ Configuration ($($strengths.Count)): " + ($strengths -join "; ")
                }
                if ($issues.Count -gt 0) {
                    $detailText += "`n❌ Issues ($($issues.Count)): " + ($issues -join "; ")
                }
                if ($recommendations.Count -gt 0) {
                    $detailText += "`n💡 Recommendations ($($recommendations.Count)): " + ($recommendations -join "; ")
                }
                
                Add-TestResult -Category "AutopilotProfiles" `
                    -TestName "Autopilot Profile: $($profile.displayName)" `
                    -Status $status `
                    -Details $detailText
            }
        }
        
        $testResults.AutopilotProfiles.Summary = @{
            TotalProfiles = $autopilotProfiles.value.Count
        }
        
    }
    catch {
        Add-TestResult -Category "AutopilotProfiles" -TestName "Autopilot Access" `
            -Status "Warning" -Details "Unable to access Autopilot profiles"
    }
}

# Test 11: Assignment Filters
function Test-DeviceFilters {
    Write-Host "`nTesting Assignment Filters..." -ForegroundColor Cyan
    
    try {
        $filters = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters"
        
        if ($filters.value.Count -eq 0) {
            Add-TestResult -Category "DeviceFilters" -TestName "Assignment Filters" `
                -Status "Warning" -Details "No assignment filters found - consider using for targeted deployments"
        }
        else {
            Add-TestResult -Category "DeviceFilters" -TestName "Assignment Filters Exist" `
                -Status "Pass" -Details "$($filters.value.Count) assignment filters configured"
            
            foreach ($filter in $filters.value) {
                $details = "Platform: $($filter.platform) | Rule: $($filter.rule)"
                
                Add-TestResult -Category "DeviceFilters" `
                    -TestName "Filter: $($filter.displayName)" `
                    -Status "Pass" `
                    -Details $details
            }
        }
        
        $testResults.DeviceFilters.Summary = @{
            TotalFilters = $filters.value.Count
        }
        
    }
    catch {
        Add-TestResult -Category "DeviceFilters" -TestName "Device Filters Access" `
            -Status "Warning" -Details "Unable to access assignment filters"
    }
}

# Test 12: PowerShell Scripts and Remediation Scripts
function Test-Scripts {
    Write-Host "`nTesting PowerShell and Remediation Scripts..." -ForegroundColor Cyan
    
    $psScriptsCount = 0
    $remediationScriptsCount = 0
    
    try {
        # PowerShell Scripts
        try {
            $psScripts = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts"
            $psScriptsCount = if ($psScripts.value) { $psScripts.value.Count } else { 0 }
            
            if ($psScriptsCount -gt 0) {
                Add-TestResult -Category "Scripts" -TestName "PowerShell Scripts" `
                    -Status "Pass" -Details "$psScriptsCount PowerShell scripts deployed"
                
                foreach ($script in $psScripts.value) {
                    $details = ""
                    if ($script.runAsAccount -eq "system") {
                        $details += "Runs as: System | "
                    }
                    else {
                        $details += "Runs as: User | "
                    }
                    
                    if ($script.enforceSignatureCheck -eq $true) {
                        $details += "Signature check: Enabled (Secure)"
                    }
                    else {
                        $details += "Signature check: Disabled"
                    }
                    
                    Add-TestResult -Category "Scripts" `
                        -TestName "Script: $($script.displayName)" `
                        -Status "Pass" `
                        -Details $details
                }
            }
        }
        catch {
            Add-TestResult -Category "Scripts" -TestName "PowerShell Scripts Access" `
                -Status "Fail" -Details "Error accessing PowerShell scripts: $($_.Exception.Message). Please ensure you have DeviceManagementConfiguration.Read.All permission and consent granted."
            Write-Host "PowerShell Scripts Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        # Proactive Remediation Scripts
        try {
            $remediationScripts = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts"
            $remediationScriptsCount = if ($remediationScripts.value) { $remediationScripts.value.Count } else { 0 }
            
            if ($remediationScriptsCount -gt 0) {
                Add-TestResult -Category "Scripts" -TestName "Proactive Remediations" `
                    -Status "Pass" -Details "$remediationScriptsCount remediation script packages configured"
                
                foreach ($remediation in $remediationScripts.value) {
                    $details = "Detection and remediation script package"
                    if ($remediation.runAsAccount -eq "system") {
                        $details += " | Runs as: System"
                    }
                    
                    Add-TestResult -Category "Scripts" `
                        -TestName "Remediation: $($remediation.displayName)" `
                        -Status "Pass" `
                        -Details $details
                }
            }
        }
        catch {
            Add-TestResult -Category "Scripts" -TestName "Proactive Remediations Access" `
                -Status "Fail" -Details "Error accessing remediation scripts: $($_.Exception.Message). Please ensure you have DeviceManagementConfiguration.Read.All permission and consent granted."
            Write-Host "Remediation Scripts Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        if ($psScriptsCount -eq 0 -and $remediationScriptsCount -eq 0) {
            Add-TestResult -Category "Scripts" -TestName "PowerShell Scripts" `
                -Status "Warning" -Details "No scripts found - consider using for automation and remediation"
        }
        
        $testResults.Scripts.Summary = @{
            PowerShellScripts  = $psScriptsCount
            RemediationScripts = $remediationScriptsCount
        }
        
    }
    catch {
        Add-TestResult -Category "Scripts" -TestName "Scripts Access" `
            -Status "Fail" -Details "Error during scripts assessment: $($_.Exception.Message)"
        Write-Host "General Scripts Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test 13: RBAC and Custom Roles
function Test-RBAC {
    Write-Host "`nTesting Role-Based Access Control..." -ForegroundColor Cyan
    
    try {
        $roleDefinitions = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleDefinitions"
        $roleAssignments = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleAssignments"
        
        Add-TestResult -Category "RBAC" -TestName "Role Definitions" `
            -Status "Pass" -Details "$($roleDefinitions.value.Count) role definitions found"
        
        # Check for custom roles
        $customRoles = $roleDefinitions.value | Where-Object { $_.isBuiltIn -eq $false }
        if ($customRoles.Count -gt 0) {
            Add-TestResult -Category "RBAC" -TestName "Custom Roles" `
                -Status "Pass" -Details "$($customRoles.Count) custom roles defined"
            
            foreach ($role in $customRoles) {
                $permissions = $role.rolePermissions.Count
                Add-TestResult -Category "RBAC" `
                    -TestName "Custom Role: $($role.displayName)" `
                    -Status "Pass" `
                    -Details "$permissions permission(s) defined"
            }
        }
        
        # Check role assignments
        if ($roleAssignments.value.Count -gt 0) {
            Add-TestResult -Category "RBAC" -TestName "Role Assignments" `
                -Status "Pass" -Details "$($roleAssignments.value.Count) role assignments configured"
        }
        else {
            Add-TestResult -Category "RBAC" -TestName "Role Assignments" `
                -Status "Warning" -Details "No role assignments found - ensure proper delegation"
        }
        
        $testResults.RBAC.Summary = @{
            TotalRoles  = $roleDefinitions.value.Count
            CustomRoles = $customRoles.Count
            Assignments = $roleAssignments.value.Count
        }
        
    }
    catch {
        Add-TestResult -Category "RBAC" -TestName "RBAC Access" `
            -Status "Warning" -Details "Unable to access RBAC configuration"
    }
}

# Test 14: Enrollment Tokens and Certificates
function Test-EnrollmentTokens {
    Write-Host "`nTesting Enrollment Tokens and Certificates..." -ForegroundColor Cyan
    
    try {
        # Apple Push Notification Certificate
        try {
            $applePushCert = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/applePushNotificationCertificate"
            
            if ($applePushCert.appleIdentifier) {
                $expirationDate = [DateTime]::Parse($applePushCert.expirationDateTime)
                $daysUntilExpiration = ($expirationDate - (Get-Date)).Days
                
                if ($daysUntilExpiration -lt 30) {
                    Add-TestResult -Category "EnrollmentTokens" -TestName "Apple Push Certificate" `
                        -Status "Fail" -Details "Expires in $daysUntilExpiration days - RENEW IMMEDIATELY"
                }
                elseif ($daysUntilExpiration -lt 60) {
                    Add-TestResult -Category "EnrollmentTokens" -TestName "Apple Push Certificate" `
                        -Status "Warning" -Details "Expires in $daysUntilExpiration days - plan renewal"
                }
                else {
                    Add-TestResult -Category "EnrollmentTokens" -TestName "Apple Push Certificate" `
                        -Status "Pass" -Details "Valid for $daysUntilExpiration days | Apple ID: $($applePushCert.appleIdentifier)"
                }
            }
        }
        catch {
            Add-TestResult -Category "EnrollmentTokens" -TestName "Apple Push Certificate" `
                -Status "Warning" -Details "Not configured or unable to access"
        }
        
        # VPP Tokens
        try {
            $vppTokens = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceAppManagement/vppTokens"
            
            if ($vppTokens.value.Count -gt 0) {
                foreach ($token in $vppTokens.value) {
                    $expirationDate = [DateTime]::Parse($token.expirationDateTime)
                    $daysUntilExpiration = ($expirationDate - (Get-Date)).Days
                    
                    $status = "Pass"
                    $details = "Valid for $daysUntilExpiration days"
                    
                    if ($daysUntilExpiration -lt 30) {
                        $status = "Fail"
                        $details = "Expires in $daysUntilExpiration days - RENEW IMMEDIATELY"
                    }
                    elseif ($daysUntilExpiration -lt 60) {
                        $status = "Warning"
                        $details = "Expires in $daysUntilExpiration days - plan renewal"
                    }
                    
                    Add-TestResult -Category "EnrollmentTokens" `
                        -TestName "VPP Token: $($token.displayName)" `
                        -Status $status `
                        -Details $details
                }
            }
        }
        catch {
            # VPP tokens may not be configured
        }
        
        # DEP Tokens
        try {
            $depTokens = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings"
            
            if ($depTokens.value.Count -gt 0) {
                foreach ($token in $depTokens.value) {
                    $expirationDate = [DateTime]::Parse($token.tokenExpirationDateTime)
                    $daysUntilExpiration = ($expirationDate - (Get-Date)).Days
                    
                    $status = "Pass"
                    $details = "Valid for $daysUntilExpiration days"
                    
                    if ($daysUntilExpiration -lt 30) {
                        $status = "Fail"
                        $details = "Expires in $daysUntilExpiration days - RENEW IMMEDIATELY"
                    }
                    elseif ($daysUntilExpiration -lt 60) {
                        $status = "Warning"
                        $details = "Expires in $daysUntilExpiration days - plan renewal"
                    }
                    
                    Add-TestResult -Category "EnrollmentTokens" `
                        -TestName "Apple DEP Token: $($token.appleIdentifier)" `
                        -Status $status `
                        -Details $details
                }
            }
        }
        catch {
            # DEP tokens may not be configured
        }
        
        # Android Enterprise Binding
        try {
            $androidBinding = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/androidManagedStoreAccountEnterpriseSettings"
            
            if ($androidBinding.bindStatus -eq "bound") {
                Add-TestResult -Category "EnrollmentTokens" -TestName "Android Enterprise Binding" `
                    -Status "Pass" -Details "Bound to managed Google Play | Organization: $($androidBinding.ownerOrganizationName)"
            }
            else {
                Add-TestResult -Category "EnrollmentTokens" -TestName "Android Enterprise Binding" `
                    -Status "Warning" -Details "Not bound to managed Google Play"
            }
        }
        catch {
            Add-TestResult -Category "EnrollmentTokens" -TestName "Android Enterprise Binding" `
                -Status "Warning" -Details "Unable to verify Android Enterprise binding"
        }
        
    }
    catch {
        Add-TestResult -Category "EnrollmentTokens" -TestName "Enrollment Tokens Access" `
            -Status "Warning" -Details "Unable to access enrollment tokens"
    }
}

# Main execution
try {
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "Microsoft Intune Configuration Testing Tool" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    
    # Connect to Graph
    Connect-ToGraph -TenantId $TenantId
    
    # Get tenant info
    $context = Get-MgContext
    $testResults.TenantInfo = @{
        TenantId = $context.TenantId
        Account  = $context.Account
        Scopes   = $context.Scopes
    }
    
    # Run all tests
    Test-BestPractices
    Test-CompliancePolicies
    Test-ConfigurationProfiles
    Test-ConditionalAccessPolicies
    Test-Applications
    Test-AppProtectionPolicies
    Test-EndpointSecurity
    Test-EnrollmentSettings
    Test-AutopilotProfiles
    Test-DeviceFilters
    Test-Scripts
    Test-RBAC
    Test-EnrollmentTokens
    Test-Monitoring
    Test-SoftwareUpdates
    Test-TenantConfiguration
    Test-ComplianceActions
    Test-WindowsHello
    Test-IntuneConnectors
    Test-DeviceInventory
    
    # Generate report
    Write-Host "`nGenerating HTML report..." -ForegroundColor Cyan
    $reportPath = Generate-HTMLReport -Results $testResults -OutputPath $OutputPath
    
    # Display summary
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "Test Summary" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "Total Tests: $($testResults.Summary.TotalTests)" -ForegroundColor White
    Write-Host "Passed: $($testResults.Summary.PassedTests)" -ForegroundColor Green
    Write-Host "Failed: $($testResults.Summary.FailedTests)" -ForegroundColor Red
    Write-Host "Warnings: $($testResults.Summary.WarningTests)" -ForegroundColor Yellow
    Write-Host "`nReport saved to: $reportPath" -ForegroundColor Cyan
    
    # Open report in default browser
    $openReport = Read-Host "`nWould you like to open the report now? (Y/N)"
    if ($openReport -eq 'Y' -or $openReport -eq 'y') {
        Start-Process $reportPath
    }
    
}
catch {
    Write-Host "`nError during execution: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
}
finally {
    # Disconnect from Graph
    Write-Host "`nDisconnecting from Microsoft Graph..." -ForegroundColor Cyan
    Disconnect-MgGraph
}
