##Create a Conditional Access Baseline Policy
##Created by: Tim Hjort, 2025

$requiredModules = @(
    'Microsoft.Entra',
    'Microsoft.Graph',
    'Microsoft.Graph.Identity.SignIns'
)

foreach ($module in $requiredModules) {
    try {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            Write-Host "Installing module: $module"
            Install-Module -Name $module -Force -Scope CurrentUser -ErrorAction Stop -AllowClobber
        } else {
            Write-Host "Module $module is already installed."
        }

        # Check if the module is already imported
        if (-not (Get-Module -Name $module)) {
            # Import the module
            Import-Module $module -ErrorAction Stop
            Write-Host "Module $module has been imported."
        } else {
            Write-Host "Module $module is already imported."
        }
    } catch {
        Write-Error "Failed to install or import module $module : $_"
    }
}

try {
    # Connect to Microsoft Entra ID
    Connect-Entra -Scopes @(
        'Policy.ReadWrite.ConditionalAccess',
        'Policy.Read.All',
        'Group.ReadWrite.All'
    ) -ErrorAction Stop
} catch {
    Write-Error "Failed to connect to Microsoft Entra ID: $_"
}

$LicensResponse = Read-Host "Do you have Entra ID P2 Licenses? (Y/N)"
if ($LicensResponse -eq "Y") {
    Write-Host "Entra ID P2 licenses are available."
} else {
    Write-Host "Entra ID P2 licenses are not available. Some policies may not be created." -ForegroundColor Yellow
}

#Create Group to exclude users from Conditional Access policies
$excludeGroupsResponse = Read-Host "Group creation options:
1. Create a group to exclude the accounts from Conditional Access policies
2. Use an existing group to assign the accounts to
3. Do not create a group and do not assign the accounts to a group"
if ($excludeGroupsResponse -eq '1') {
    $GroupParameters1 = @{
        DisplayName = 'AZ-CA-User Exclude'
        MailNickname = 'AZ-CA-UserExclude'
        Description = 'This group is used to exclude all accounts from Conditional Access policies.'
        MailEnabled = $false
        SecurityEnabled = $true
        GroupTypes = @()
    }
    $CreateExcludeGroup = New-EntraGroup @GroupParameters1
    $excludeGroupId = $CreateExcludeGroup.Id
}
elseif ($excludeGroupsResponse -eq '2') {
    $GroupID = Read-Host "Please enter the group ID to assign the accounts to:"
    $excludeGroupId = $GroupID

}
elseif ($excludeGroupsResponse -eq '3') {
    Write-Host "No group created and no group assigned to the accounts." -ForegroundColor Yellow
}

##Creates CA001-Require MFA for administrators##
$adminRoles = @(
    "62e90394-69f5-4237-9190-012177145e10", # Global Administrator
    "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3", # Application Administrator
    "c4e39bd9-1100-46d3-8c65-fb160da0071f", # Authentication Administrator
    "b0f54661-2d74-4c50-afa3-1ec803f12efe", # Billing Administrator
    "158c047a-c907-4556-b7ef-446551a6b5f7", # Cloud Application Administrator
    "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9", # Conditional Access Administrator
    "29232cdf-9323-42fd-ade2-1d097af3e4de", # Exchange Administrator
    "729827e3-9c14-49f7-bb1b-9608f156bbb8", # Helpdesk Administrator
    "966707d0-3269-4727-9be2-8c3a10f19b9d", # Password Administrator
    "7be44c8a-adaf-4e2a-84d6-ab2649e08a13", # Privileged Authentication Administrator
    "e8611ab8-c189-46e8-94e1-60213ab1f814", # Privileged Role Administrator
    "194ae4cb-b126-40b2-bd5b-6091b380977d", # Security Administrator
    "f28a1f50-f6e7-4571-818b-6a12f2af6b6c", # SharePoint Administrator
    "fe930be7-5e62-47db-91af-98c3a49a38b1"  # User Administrator
)
##Ask if the rules should be report only or enabled
$reportOnly = Read-Host "Do you want to create the rules in report-only mode? (Y/N)"
if ($reportOnly -eq "Y") {
    $reportOnly = "enabledForReportingButNotEnforced"
} else {
    $reportOnly = "enabled"
}
$CA001 = @{
    DisplayName = "CA001-Require MFA for administrators"
    State = $reportOnly
    Conditions = @{
        Applications = @{
            IncludeApplications = "All"
        }
        Users = @{
            IncludeRoles = $adminRoles
            ExcludeGroups = @($excludeGroupId)
        }
        ClientAppTypes = @(
            "browser",
            "mobileAppsAndDesktopClients"
        )
    }
    GrantControls = @{
        _Operator = "OR"
        BuiltInControls = @("mfa")
    }
}

New-EntraConditionalAccessPolicy @CA001

###CA002-Require phishing-resistant multifactor authentication for administrators##
$CA002 = @{
    DisplayName = "CA002-Require phishing-resistant MFA for administrators"
    State = $reportOnly
    Conditions = @{
        Applications = @{
            IncludeApplications = "All"
        }
        Users = @{
            IncludeRoles = $adminRoles
            ExcludeGroups = @($excludeGroupId)
        }
        ClientAppTypes = @(
            "browser",
            "mobileAppsAndDesktopClients"
        )
    }
    GrantControls = @{
        _Operator = "AND"
        BuiltInControls = @(
            "mfa",
            "compliantDevice"
        )
    }
}

New-EntraConditionalAccessPolicy @CA002

##CA005-Block legacy authentication

$CA005 = @{
    DisplayName = "CA005-Block legacy authentication"
    State = $reportOnly
    Conditions = @{
        ClientAppTypes = @(
            "exchangeActiveSync",
            "other"
        )
        Applications = @{
            IncludeApplications = "All"
        }
        Users = @{
            IncludeUsers = "All"
            ExcludeGroups = @($excludeGroupId)
        }
    }
    GrantControls = @{
        _Operator = "OR"
        BuiltInControls = @("block")
    }
}

New-EntraConditionalAccessPolicy @CA005

##CA007-Require MFA for all users##
$excludedApps = @(
    "45a330b1-b1ec-4cc1-9161-9f03992aa49f", # Windows Store for Business
    "0000000a-0000-0000-c000-000000000000" 
)

$CA007 = @{
    DisplayName = "CA007-Require MFA for all users"
    State = $reportOnly
    Conditions = @{
        Applications = @{
            IncludeApplications = "All"
            ExcludeApplications = $excludedApps
        }
        Users = @{
            IncludeUsers = "All"
            ExcludeGroups = @($excludeGroupId)
        }
        ClientAppTypes = @(
            "browser",
            "mobileAppsAndDesktopClients"
        )
    }
    SessionControls = @{
        SignInFrequency = @{
            IsEnabled = $true
            Value = 1
            Type = "days"
        }
    }
    GrantControls = @{
        _Operator = "OR"
        BuiltInControls = @("mfa")
    }
}

New-EntraConditionalAccessPolicy @CA007

##CA008-Require MFA for Azure management##

$azureMgmtApps = @(
    "797f4846-ba00-4fd7-ba43-dac1f8f63013"  
)

$CA008 = @{
    DisplayName = "CA008-Require MFA for Azure management"
    State = $reportOnly
    Conditions = @{
        Applications = @{
            IncludeApplications = $azureMgmtApps
        }
        Users = @{
            IncludeUsers = "All"
            ExcludeGroups = @($excludeGroupId)
        }
        ClientAppTypes = @(
            "browser",
            "mobileAppsAndDesktopClients",
            "other"
        )
    }
    GrantControls = @{
        _Operator = "OR"
        BuiltInControls = @("mfa")
    }
}
New-EntraConditionalAccessPolicy @CA008


##CA012-Requires Compliant Device##
$excludedAppsCompliance = @(    "45a330b1-b1ec-4cc1-9161-9f03992aa49f"
)

$CA012 = @{
    DisplayName = "CA012-Requires Compliant Device"
    State = $reportOnly
    Conditions = @{
        Applications = @{
            IncludeApplications = @("All")
            ExcludeApplications = $excludedAppsCompliance
        }
        Users = @{
            IncludeUsers = @("All")
            ExcludeGroups = @($excludeGroupId)
        }
        ClientAppTypes = @(
            "browser",
            "mobileAppsAndDesktopClients"
        )
        Platforms = @{
            IncludePlatforms = @(
                "android",
                "iOS",
                "windows",
                "macOS"
            )
        }
    }
    GrantControls = @{
        Operator = "AND"
        BuiltInControls = @("compliantDevice")
    }
}
New-MgIdentityConditionalAccessPolicy -BodyParameter ($CA012 | ConvertTo-Json -Depth 10)

##CA017-Require reauthentication and disable browser persistence on Unmanaged Device##
$CA017 = @{
    DisplayName = "CA017-Require reauthentication on unmanaged devices"
    State = $reportOnly
    Conditions = @{
        Applications = @{
            IncludeApplications = "All"
        }
        Users = @{
            IncludeUsers = "All"
            ExcludeGroups = @($excludeGroupId)
        }
        ClientAppTypes = @(
            "browser"
        )
        Platforms = @{
            IncludePlatforms = @("all")
        }
    }
    SessionControls = @{
        SignInFrequency = @{
            IsEnabled = $true
            Value = 1
            Type = "hours"
        }
        PersistentBrowser = @{
            IsEnabled = $true
            Mode = "never"
        }
    }
}
New-EntraConditionalAccessPolicy @CA017    

if ($LicensResponse -eq "Y") {
    ##CA009-Sign-in risk-based multifactor authentication##
    $CA009 = @{
        DisplayName = "CA009-Sign-in risk-based MFA"
        State = $reportOnly
        Conditions = @{
            "@odata.type" = "#microsoft.graph.conditionalAccessConditionSet"
            Applications = @{
                IncludeApplications = "All"
            }
            Users = @{
                IncludeUsers = "All"
                ExcludeGroups = @($excludeGroupId)
            }
            ClientAppTypes = @(
                "browser",
                "mobileAppsAndDesktopClients"
            )
            SignInRiskLevels = @(
                "medium",
                "high"
            )
        }
        GrantControls = @{
            "@odata.type" = "#microsoft.graph.conditionalAccessGrantControls"
            Operator = "AND"
            BuiltInControls = @("mfa")
        }
    }
New-MgIdentityConditionalAccessPolicy -BodyParameter $CA009


##CA010-User risk-based password change##
$CA010 = @{
    DisplayName = "CA010-User risk-based password change"
    State = $reportOnly
    Conditions = @{
        "@odata.type" = "#microsoft.graph.conditionalAccessConditionSet"
        Applications = @{
            IncludeApplications = "All"
        }
        Users = @{
            IncludeUsers = "All"
            ExcludeGroups = @($excludeGroupId)
        }
        ClientAppTypes = @(
            "all"
        )
        UserRiskLevels = @(
            "medium",
            "high"
        )
    }
    GrantControls = @{
        "@odata.type" = "#microsoft.graph.conditionalAccessGrantControls"
        Operator = "AND"
        BuiltInControls = @("mfa", "passwordChange")
    }
}
New-MgIdentityConditionalAccessPolicy -BodyParameter $CA010
}
    try {
        Disconnect-Entra -ErrorAction Stop
        Write-Host "Disconnected from Microsoft Entra ID."
    } catch {
        Write-Error "Failed to disconnect from Microsoft Entra ID: $_"
    }

    # Cleanup: Uninstall modules
foreach ($module in $requiredModules) {
    try {
        # First remove the module from the current session
        if (Get-Module -Name "$module*") {
            Write-Host "Removing module from current session: $module"
            Remove-Module -Name "$module*" -Force -ErrorAction Stop
        }

        # Then uninstall all versions of the module and its submodules
        $moduleVersions = Get-Module -Name "$module*" -ListAvailable
        foreach ($version in $moduleVersions) {
            Write-Host "Uninstalling module: $($version.Name) version $($version.Version)"
            Uninstall-Module -Name $version.Name -RequiredVersion $version.Version -Force -ErrorAction Stop
        }
        
        Write-Host "Module $module and its components have been completely removed" -ForegroundColor Green
    } catch {
        Write-Error "Failed to remove/uninstall module $module : $_"
    }
}