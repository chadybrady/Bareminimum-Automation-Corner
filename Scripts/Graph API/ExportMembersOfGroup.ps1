# Install necessary modules if not already installed
Install-Module -Name ImportExcel -Scope CurrentUser
Install-Module -Name Microsoft.Graph -Scope CurrentUser    

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All", "AuditLog.Read.All"

# Define the group IDs you want to retrieve
$groupIds = @("") # Replace with your group IDs

# Initialize array to store group and member data
$groupMemberArray = @()

foreach ($groupId in $groupIds) {
    try {
        # Get the group
        $group = Get-MgGroup -GroupId $groupId
        Write-Output "Processing group: $($group.DisplayName)"

        if ($group) {
            # Get the members of the group
            $members = Get-MgGroupMember -GroupId $group.Id -All
            Write-Output "Found $($members.Count) members in group: $($group.DisplayName)"

            foreach ($member in $members) {
                # Retrieve the full member object
                $memberDetails = Get-MgUser -UserId $member.Id -Property "userPrincipalName,createdDateTime" -ErrorAction SilentlyContinue
                if ($memberDetails) {
                    # Retrieve the latest sign-in record for the user
                    $lastSignIn = Get-MgAuditLogSignIn -Filter "userPrincipalName eq '$($memberDetails.UserPrincipalName)'" -Top 1 | Sort-Object -Property CreatedDateTime -Descending | Select-Object -First 1

                    # Debugging output
                    Write-Output "Member: $($memberDetails.UserPrincipalName), Created: $($memberDetails.CreatedDateTime), Last Sign-In: $($lastSignIn.CreatedDateTime)"

                    # Create a custom object for the group member data
                    $groupMemberArray += [PSCustomObject]@{
                        GroupName = $group.DisplayName
                        UserPrincipalName = $memberDetails.UserPrincipalName
                        CreatedDateTime = $memberDetails.CreatedDateTime
                        LastInteractiveSignInDateTime = if ($lastSignIn) { $lastSignIn.CreatedDateTime } else { "N/A" }
                    }
                } else {
                    Write-Output "Member with ID '$($member.Id)' could not be retrieved as a user."
                }
            }
        } else {
            Write-Output "Group with ID '$groupId' not found."
        }
    } catch {
        Write-Output "An error occurred while processing group with ID '$groupId': $_"
    }
}

# XLSX path for exporting
$xlsxPath = ""

# Export to Excel
$groupMemberArray | Export-Excel -Path $xlsxPath -WorkSheetname "GroupMembers"

Write-Output "Export complete. File saved at $xlsxPath"


