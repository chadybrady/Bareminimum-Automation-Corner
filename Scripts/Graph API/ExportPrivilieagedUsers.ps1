# Install necessary modules if not already installed
Install-Module -Name ImportExcel -Scope CurrentUser
Install-Module -Name Microsoft.Graph -Scope CurrentUser

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Directory.Read.All", "RoleManagement.Read.Directory"

# Initialize array to store user and role data
$userRoleArray = @()

# Get all directory roles
$roles = Get-MgDirectoryRole -All

foreach ($role in $roles) {
    Write-Output "Processing role: $($role.DisplayName)"

    # Get the members of the role
    $roleMembers = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All

    foreach ($roleMember in $roleMembers) {
        # Retrieve the full member object
        $memberDetails = Get-MgUser -UserId $roleMember.Id -ErrorAction SilentlyContinue
        if ($memberDetails) {
            # Create a custom object for the user role data
            $userRoleArray += [PSCustomObject]@{
                RoleName = $role.DisplayName
                UserPrincipalName = $memberDetails.UserPrincipalName
                AssignmentType = "Direct"
            }
        } else {
            Write-Output "Member with ID '$($roleMember.Id)' could not be retrieved as a user."
        }
    }
}

# Get all PIM groups (role-assignable groups)
$pimGroups = Get-MgGroup -Filter "securityEnabled eq true and isAssignableToRole eq true" -All

foreach ($pimGroup in $pimGroups) {
    Write-Output "Processing PIM group: $($pimGroup.DisplayName)"

    # Get the members of the PIM group
    $members = Get-MgGroupMember -GroupId $pimGroup.Id -All

    foreach ($member in $members) {
        # Retrieve the full member object
        $memberDetails = Get-MgUser -UserId $member.Id -ErrorAction SilentlyContinue
        if ($memberDetails) {
            # Get the assigned roles for the user
            $assignedRoles = Get-MgDirectoryRole -Filter "members/any(m:m eq '$($memberDetails.Id)')"

            foreach ($role in $assignedRoles) {
                # Create a custom object for the user role data
                $userRoleArray += [PSCustomObject]@{
                    RoleName = $role.DisplayName
                    UserPrincipalName = $memberDetails.UserPrincipalName
                    AssignmentType = "PIM Group"
                    GroupName = $pimGroup.DisplayName
                }
            }
        } else {
            Write-Output "Member with ID '$($member.Id)' could not be retrieved as a user."
        }
    }
}

# XLSX path for exporting
$xlsxPath = ""

# Export to Excel
$userRoleArray | Export-Excel -Path $xlsxPath -WorkSheetname "PIMUsersRoles"

Write-Output "Export complete. File saved at $xlsxPath"