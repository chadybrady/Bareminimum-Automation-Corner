# Install necessary modules if not already installed
Install-Module -Name ImportExcel -Scope CurrentUser
Install-Module -Name Microsoft.Graph -Scope CurrentUser    

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All", "AuditLog.Read.All"

# Define the properties to retrieve for users
$userProperties = @('id', 'userPrincipalName', 'createdDateTime', 'onPremisesSyncEnabled', 'accountEnabled')

# Get all users
$users = Get-MgUser -All -Property $userProperties

# Initialize array to store user data
$userArray = @()

# Define the date filter for the last 30 days
$startDate = (Get-Date).AddDays(-90).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Get sign-in logs for all users (last 30 days to limit data)
$signInLogs = Get-MgAuditLogSignIn -All -Filter "createdDateTime ge $startDate"

# Convert sign-in logs to a hashtable for faster lookup
$signInHashTable = @{}
foreach ($log in $signInLogs) {
    $signInHashTable[$log.UserPrincipalName] = $log
}

# Loop through each user and get their last sign-in data
foreach ($user in $users) {
    # Get the last sign-in record for the user from the hashtable
    $lastSignIn = $signInHashTable[$user.UserPrincipalName]

    # Create a custom object for the user data
    $userArray += [PSCustomObject]@{
        UserPrincipalName = $user.UserPrincipalName
        CreatedDateTime = $user.CreatedDateTime
        LastInteractiveSignInDateTime = if ($lastSignIn) { $lastSignIn.CreatedDateTime } else { "N/A" }
        OnPremisesSyncEnabled = $user.OnPremisesSyncEnabled
        AccountEnabled = $user.AccountEnabled
    }
}

# XLSX path for exporting
$xlsxPath = ""

# Export to Excel
$userArray | Export-Excel -Path $xlsxPath -WorkSheetname "Users"

Write-Output "Export complete. File saved at $xlsxPath"