Write-Host "# Created By: Tim Hjort, 2025"
Write-Host "# This script creates a Break the Glass account in Entra ID and assigns it to the Global Admin role."
Write-Host "# It creates two different accounts"

#Specify the required modules
$requiredModules = @(
    'Microsoft.Entra'
)
#Checks if the module is already installed, or not.
foreach ($module in $requiredModules) {
    if (-not (Get-Module -Name $module -ListAvailable)) {
        Write-Host "Installing module: $module"
        Install-Module -Name $module -Force -Scope CurrentUser
    } else {
        Write-Host "Module $module is already installed."
    }
}
# Import the module
Import-Module $module
# Connect to Microsoft Entra ID with required permissions
Connect-Entra -Scopes @(
    'User.ReadWrite.All',
    'Group.ReadWrite.All',
    'GroupMember.Read.All',
    'RoleManagement.ReadWrite.Directory',
    'Directory.ReadWrite.All',
    'RoleManagementPolicy.ReadWrite.Directory'
)
Write-Host "Connected to Microsoft Entra ID"

$domain = Read-Host "Please enter the domain to be used: (e.g. contoso.com)"

# Function to generate a secure password
function New-SecurePassword {
    $length = 24
    $nonAlphanumeric = 3
    $characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;:,.<>?'
    $special = '!@#$%^&*()_+-=[]{}|;:,.<>?'
    
    # Start with required special characters
    $password = 1..$nonAlphanumeric | ForEach-Object { $special[(Get-Random -Maximum $special.Length)] }
    
    # Add remaining random characters
    $password += 1..($length - $nonAlphanumeric) | ForEach-Object { $characters[(Get-Random -Maximum $characters.Length)] }
    
    # Shuffle the password characters
    $password = ($password | Get-Random -Count $password.Count)
    
    return -join $password
}

# Create and store passwords
$password1 = New-SecurePassword
$password2 = New-SecurePassword

$userParams1 = @{
    DisplayName = 'Break the Glass Account 1'
    UserPrincipalName = 'breaktheglass1@' + $domain
    MailNickName = 'breaktheglass1'
    AccountEnabled = $true
    PasswordProfile = @{
        Password = $password1
        ForceChangePasswordNextLogin = $false
        EnforceChangePasswordPolicy = $false
    }
    PasswordPolicies = 'DisablePasswordExpiration'
}
Write-Host "Creating 1st Break the Glass account..."
$user1 = New-EntraUser @userParams1


$userParams2 = @{
    DisplayName = 'Break the Glass Account 2'
    UserPrincipalName = 'breaktheglass2@' + $domain
    MailNickName = 'breaktheglass2'
    AccountEnabled = $true
    PasswordProfile = @{
        Password = $password2
        ForceChangePasswordNextLogin = $false
        EnforceChangePasswordPolicy = $false
    }
    PasswordPolicies = 'DisablePasswordExpiration'
}
##Creates the second Break the Glass account
Write-Host "Creating 2nd Break the Glass account..."
$user2 = New-EntraUser @userParams2

##Assign the Global Administrator role to both accounts
$roleId = '62e90394-69f5-4237-9190-012177145e10' # Global Administrator role ID
$roleAssignmentParams1 = @{
    RoleDefinitionId = $roleId
    PrincipalId = $user1.Id
    DirectoryScopeId = '/' # Root scope for full tenant access
}
$roleAssignmentParams2 = @{
    RoleDefinitionId = $roleId
    PrincipalId = $user2.Id
    DirectoryScopeId = '/' # Root scope for full tenant access
}
New-EntraDirectoryRoleAssignment @roleAssignmentParams1
New-EntraDirectoryRoleAssignment @roleAssignmentParams2

# Display the account information
Write-Host "`nBreak Glass Account Details:" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host "Account 1:" -ForegroundColor Yellow
Write-Host "UPN: breaktheglass1@$domain"
Write-Host "Password: $password1"
Write-Host "Roles assigned: Global Administrator" -ForegroundColor Yellow
Write-Host "`nAccount 2:" -ForegroundColor Yellow
Write-Host "UPN: breaktheglass2@$domain"
Write-Host "Password: $password2"
Write-Host "Roles assigned: Global Administrator" -ForegroundColor Yellow
Write-Host "`nPLEASE STORE THESE CREDENTIALS SECURELY!" -ForegroundColor Red


$excludeGroupsResponse = Read-Host "Group creation options:
1. Create a group to exclude the accounts from Conditional Access policies
2. Assign the accounts to a already existing group
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
    
    # Add members one at a time
    Write-Host "Adding members to exclude group..." -ForegroundColor Yellow
    foreach ($userId in @($user1.Id, $user2.Id)) {
        Add-EntraGroupMember -GroupId $CreateExcludeGroup.Id -MemberId $userId
    }
    Write-Host "Break glass accounts added to exclude group successfully" -ForegroundColor Green
}
elseif ($excludeGroupsResponse -eq '2') {
    $GroupID = Read-Host "Please enter the group ID to assign the accounts to:"
    forEach ($userId in @($user1.Id, $user2.Id)) {
        Add-EntraGroupMember -GroupId $GroupID -MemberId $userId
    }
}
elseif ($excludeGroupsResponse -eq '3') {
    Write-Host "No group created and no group assigned to the accounts." -ForegroundColor Yellow
}

