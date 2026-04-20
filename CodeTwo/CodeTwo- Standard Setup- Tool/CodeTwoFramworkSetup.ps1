#Used to Deploy standard groups, and deployment creation of the codetwo apps in M365 apps.

# Install the required PowerShell modules if not already installed
$InstallModule = Read-Host "Do you want to install the required PowerShell modules? (Y/N)"
if ($InstallModule -eq "Y") {
    # List of required modules
    $RequiredModules = @("Microsoft.Entra", "MicrosoftTeams")

    foreach ($Module in $RequiredModules) {
        if (-not (Get-Module -ListAvailable -Name $Module)) {
            Write-Host "Installing $Module..."
            Install-Module -Name $Module -Scope CurrentUser -Force -AllowClobber
        } else {
            Write-Host "$Module is already installed."
        }
    }
}


#Connect to Microsoft Entra
Write-Host "Connecting to Microsoft Entra..." -ForegroundColor Green
try {
    Connect-Entra -Scopes 'Group.ReadWrite.All','Group.Create'
    Write-Host "Successfully connected to Microsoft Entra" -ForegroundColor Green
} catch {
    Write-Error "Failed to connect to Microsoft Entra. Please ensure you have the necessary permissions."
    exit 1
}

#Groups creation stage
$CreateGroups = Read-Host "Do you want to create the standard groups? (Y/N)"

if ($CreateGroups -eq "Y") {
    $SignatureAdminsGroup = @{
        DisplayName = "AZ-MDM-User-CodeTwoSignatureAdmins"
        MailNickname = "CodeTwoSignatureAdmins"
        Description = "Group for CodeTwo Signature Admins"
        SecurityEnabled = $true
        MailEnabled = $false
        GroupTypes = @()
    }
    $CodeTwoAdminsGroup = @{
        DisplayName = "AZ-MDM-User-CodeTwoAdmins"
        MailNickname = "CodeTwoAdmins"
        Description = "Group for CodeTwo Admins"
        SecurityEnabled = $true
        MailEnabled = $false
        GroupTypes = @()
    }
    $CodeTwoAddInDeployGroup = @{
        DisplayName = "AZ-MDM-User-CodeTwoAddInDeploy"
        MailNickname = "CodeTwoAddInDeploy"
        Description = "Group for CodeTwo Add-In Deployment"
        SecurityEnabled = $true
        MailEnabled = $false
        GroupTypes = @()
    }
    $GroupsToCreate = @($SignatureAdminsGroup, $CodeTwoAdminsGroup, $CodeTwoAddInDeployGroup)
    New-EntraGroup @GroupsToCreate
}
elseif ($CreateGroups -eq "N") {
    Write-Host "Skipping group creation." -ForegroundColor Yellow
    exit 0
  }

#Add the CodeTwo AddIn to the tenant
#Connecting to Teams Module
Write-Host "Connecting to Microsoft Teams..." -ForegroundColor Green
try {
    Connect-MicrosoftTeams
    Write-Host "Successfully connected to Microsoft Teams" -ForegroundColor Green
} catch {
    Write-Error "Failed to connect to Microsoft Teams. Please ensure you have the necessary permissions."
    exit 1
}
$AddIn = Read-Host "Do you want to add the CodeTwo Add-In to the tenant? (Y/N)"
    if ($AddIn -eq "Y") {
        # Define the CodeTwo Signatures Add-in App ID (from Microsoft AppSource)
        $codeTwoAppId = "WA200003022" # This is the Office Store ID for CodeTwo Signatures Add-in for Outlook
    
        # Determine target group
        if ($CreateGroups -eq "Y") {
            # Use the newly created Add-In group
            $targetGroup = $CodeTwoAddInDeployGroup
            $targetGroupId = (Get-EntraGroup -Filter "displayName eq '$($targetGroup.DisplayName)'").Id
        } else {
            # Ask user for group ID
            $targetGroupId = Read-Host "Enter the Group ID to deploy the Add-In to"
        }
    
        Write-Host "Deploying CodeTwo Signatures Add-in for Outlook to group: $targetGroupId" -ForegroundColor Cyan
    
        # Deploy the app using Microsoft Graph (requires admin consent for Integrated Apps)
        try {
            # Assign the add-in to the group
            New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $codeTwoAppId -PrincipalId $targetGroupId -ResourceId $codeTwoAppId -AppRoleId "00000000-0000-0000-0000-000000000000"
            Write-Host "Successfully deployed CodeTwo Signatures Add-in for Outlook to the group." -ForegroundColor Green
        } catch {
            Write-Error "Failed to deploy the Add-In: $($_.Exception.Message)"
        }
    }

