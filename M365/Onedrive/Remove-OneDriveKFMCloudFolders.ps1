# ============================================================
# Admin Tool - OneDrive KFM Cloud Folder Cleanup
# ============================================================
# Run locally by a Microsoft 365 administrator.
#
# Purpose:
#   After the Intune Proactive Remediation scripts have moved
#   KFM data back to local user folders, this script removes
#   the Known Folder Move directories (Desktop, Documents,
#   Pictures and localized equivalents) from the targeted
#   user's OneDrive in the cloud via Microsoft Graph.
#
# Prerequisites:
#   - PowerShell 5.1 or later
#   - Microsoft.Graph modules (installed automatically if missing)
#
# Authentication options (prompted at runtime):
#
#   [1] Delegated / browser sign-in
#       The signed-in account must be a SharePoint Administrator
#       or Global Administrator. Works for your own tenant where
#       you have admin consent for the required scopes.
#
#   [2] App-only / client credentials (recommended for bulk ops)
#       Requires an Entra ID App Registration with APPLICATION
#       (not delegated) permissions:
#           Files.ReadWrite.All
#           User.Read.All
#           GroupMember.Read.All
#           Group.Read.All
#           Sites.ReadWrite.All
#       Steps:
#         1. Entra admin center -> App registrations -> New registration
#         2. API permissions -> Add -> Microsoft Graph -> Application
#            permissions -> add the five scopes above -> Grant admin consent
#         3. Certificates & secrets -> New client secret -> copy the value
#         4. Copy the Application (client) ID and Directory (tenant) ID
#         5. Enter those values when prompted by this script
#
# Notes:
#   Deleted folders land in the user's OneDrive Recycle Bin
#   (30-day recovery window) before permanent removal.
# ============================================================

#Requires -Version 5.1

# KFM subfolder names across locales (English + Swedish)
$kfmFolderNames = @(
    "Desktop",   "Skrivbord",
    "Documents", "Dokument", "My Documents",
    "Pictures",  "Bilder",   "My Pictures"
)


function Write-Status {
    param(
        [string]$Message,
        [string]$Color  = "Cyan",
        [string]$Prefix = "INFO"
    )
    Write-Host "[$Prefix] $(Get-Date -Format 'HH:mm:ss') - $Message" -ForegroundColor $Color
}


# ============================================================
# Banner
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  OneDrive KFM Cloud Folder Cleanup - Admin Tool" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Run mode options:" -ForegroundColor DarkGray
Write-Host "    Test Mode  - scans and reports without deleting anything" -ForegroundColor DarkGray
Write-Host "    Live Mode  - deletes KFM folders (moved to Recycle Bin)" -ForegroundColor DarkGray
Write-Host ""


# ============================================================
# Ensure required Graph modules are installed and imported
# ============================================================
Write-Status "Checking required PowerShell modules..." "Yellow" "MODULE"

$requiredModules = @("Microsoft.Graph.Users", "Microsoft.Graph.Files", "Microsoft.Graph.Groups")
foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Status "'$mod' not found. Installing from PSGallery..." "Yellow" "MODULE"
        try {
            Install-Module -Name $mod -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Write-Status "'$mod' installed successfully." "Green" "MODULE"
        } catch {
            Write-Status "Failed to install '$mod': $_" "Red" "MODULE"
            exit 1
        }
    } else {
        Write-Status "'$mod' is available." "DarkGray" "MODULE"
    }
    Import-Module -Name $mod -Force -ErrorAction SilentlyContinue
}

Write-Host ""


# ============================================================
# Connect to Microsoft Graph
# ============================================================
Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
Write-Host "  Authentication Mode" -ForegroundColor DarkCyan
Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "    [1] Delegated  - browser sign-in (account must be SharePoint/Global Admin)"
Write-Host "    [2] App-only   - client credentials via App Registration (recommended)" -ForegroundColor Green
Write-Host ""

$authMode = (Read-Host "  Choice (1/2)").Trim()
if ($authMode -notin @("1","2")) {
    Write-Status "Invalid choice '$authMode'. Exiting." "Red" "INPUT"
    exit 1
}

# Disconnect any existing cached session before connecting
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

if ($authMode -eq "1") {
    Write-Status "Connecting via delegated auth (browser sign-in will open)..." "Yellow" "AUTH"
    try {
        Connect-MgGraph -Scopes "Files.ReadWrite.All","User.Read.All","GroupMember.Read.All","Group.Read.All","Sites.ReadWrite.All" -NoWelcome -ErrorAction Stop
        $mgContext = Get-MgContext
        Write-Status "Connected as: $($mgContext.Account)" "Green" "AUTH"
    } catch {
        Write-Status "Failed to connect: $_" "Red" "AUTH"
        exit 1
    }
} else {
    Write-Host ""
    $tenantId     = (Read-Host "  Tenant ID (Directory ID)").Trim()
    $clientId     = (Read-Host "  Application (Client) ID").Trim()
    $clientSecret = Read-Host "  Client Secret" -AsSecureString

    if ([string]::IsNullOrWhiteSpace($tenantId) -or [string]::IsNullOrWhiteSpace($clientId)) {
        Write-Status "Tenant ID and Client ID are required. Exiting." "Red" "AUTH"
        exit 1
    }

    Write-Status "Connecting via app-only (client credentials)..." "Yellow" "AUTH"
    try {
        $credential = New-Object System.Management.Automation.PSCredential($clientId, $clientSecret)
        Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $credential -NoWelcome -ErrorAction Stop
        $mgContext = Get-MgContext
        Write-Status "Connected as app: $($mgContext.AppName) (Tenant: $($mgContext.TenantId))" "Green" "AUTH"
    } catch {
        Write-Status "Failed to connect: $_" "Red" "AUTH"
        exit 1
    }
}

Write-Host ""


# ============================================================
# Main loop - repeats until admin chooses to exit
# ============================================================
$runAgain = $true
while ($runAgain) {

# ============================================================
# Input: Target user(s)
# ============================================================
Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
Write-Host "  User Selection" -ForegroundColor DarkCyan
Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Select targeting mode:"
Write-Host "    [1] Single user   - enter a UPN (e.g. user@contoso.com)"
Write-Host "    [2] Group         - enter a group name or Object ID"
Write-Host "    [3] All users     - every user in the tenant" -ForegroundColor Yellow
Write-Host ""

$mode = (Read-Host "  Choice (1/2/3)").Trim()

if ($mode -notin @("1","2","3")) {
    Write-Status "Invalid choice '$mode'. Exiting." "Red" "INPUT"
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    exit 1
}

$targetUsers = @()

switch ($mode) {

    "1" {
        $upnInput = (Read-Host "  User UPN").Trim()
        if ([string]::IsNullOrWhiteSpace($upnInput)) {
            Write-Status "No UPN provided. Exiting." "Red" "INPUT"
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            exit 1
        }
        Write-Status "Looking up user '$upnInput'..." "Yellow" "USERS"
        try {
            $user = Get-MgUser -UserId $upnInput -Property "Id,DisplayName,UserPrincipalName" -ErrorAction Stop
            $targetUsers = @($user)
            Write-Status "Found: $($user.DisplayName) ($($user.UserPrincipalName))" "Green" "USERS"
        } catch {
            Write-Status "User '$upnInput' not found: $_" "Red" "USERS"
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            exit 1
        }
    }

    "2" {
        $groupInput = (Read-Host "  Group name or Object ID").Trim()
        if ([string]::IsNullOrWhiteSpace($groupInput)) {
            Write-Status "No group provided. Exiting." "Red" "INPUT"
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            exit 1
        }

        # Try by Object ID first, then fall back to display name search
        Write-Status "Looking up group '$groupInput'..." "Yellow" "GROUP"
        $group = $null
        try {
            $group = Get-MgGroup -GroupId $groupInput -ErrorAction Stop
        } catch {
            # Not a valid GUID or not found by ID - search by display name
            try {
                $group = Get-MgGroup -Filter "displayName eq '$groupInput'" -ErrorAction Stop |
                    Select-Object -First 1
            } catch {}
        }

        if (-not $group) {
            Write-Status "Group '$groupInput' not found. Exiting." "Red" "GROUP"
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            exit 1
        }

        Write-Status "Found group: $($group.DisplayName) (ID: $($group.Id))" "Green" "GROUP"
        Write-Status "Fetching group members..." "Yellow" "GROUP"

        try {
            $members = Get-MgGroupMember -GroupId $group.Id -All -ErrorAction Stop
        } catch {
            Write-Status "Failed to retrieve group members: $_" "Red" "GROUP"
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            exit 1
        }

        # Resolve each member to a full user object (skip non-user members such as devices/groups)
        foreach ($member in $members) {
            try {
                $u = Get-MgUser -UserId $member.Id -Property "Id,DisplayName,UserPrincipalName" -ErrorAction Stop
                $targetUsers += $u
            } catch {
                Write-Status "Skipping member '$($member.Id)' (not a user or access denied)" "DarkGray" "GROUP"
            }
        }

        Write-Status "Resolved $($targetUsers.Count) user(s) from group '$($group.DisplayName)'." "Cyan" "GROUP"
    }

    "3" {
        Write-Status "Fetching all users from the tenant..." "Yellow" "USERS"
        try {
            $targetUsers = Get-MgUser -All -Property "Id,DisplayName,UserPrincipalName" -ErrorAction Stop
            Write-Status "Found $($targetUsers.Count) user(s)." "Cyan" "USERS"
        } catch {
            Write-Status "Failed to retrieve users: $_" "Red" "USERS"
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            exit 1
        }
    }
}

Write-Host ""

# ============================================================
# Test mode / Live mode selection
# ============================================================
Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
Write-Host "  Run Mode" -ForegroundColor DarkCyan
Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "    [T] Test Mode  - scan only, no changes made" -ForegroundColor Green
Write-Host "    [L] Live Mode  - delete KFM folders (moved to Recycle Bin)" -ForegroundColor Yellow
Write-Host ""

$runModeInput = (Read-Host "  Choice (T/L)").Trim().ToUpper()

if ($runModeInput -notin @("T","L")) {
    Write-Status "Invalid choice '$runModeInput'. Exiting." "Red" "INPUT"
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    exit 1
}

$testMode = ($runModeInput -eq "T")

if ($testMode) {
    Write-Host ""
    Write-Host "  *** TEST MODE - no folders will be deleted ***" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "  *** LIVE MODE - folders WILL be deleted ***" -ForegroundColor Yellow
}

Write-Host ""


# ============================================================
# Confirm before proceeding
# ============================================================
if ($testMode) {
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
    Write-Host "  TEST MODE - the following folders will be SCANNED (not deleted):" -ForegroundColor Green
    Write-Host ""
    $kfmFolderNames | ForEach-Object { Write-Host "    - $_" -ForegroundColor Green }
    Write-Host ""
    Write-Host "  Target(s) : $($targetUsers.Count) user(s)" -ForegroundColor Green
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
} else {
    Write-Host "------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "  The following cloud folders will be DELETED from the" -ForegroundColor Yellow
    Write-Host "  OneDrive root of the targeted user(s):" -ForegroundColor Yellow
    Write-Host ""
    $kfmFolderNames | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "  Target(s)    : $($targetUsers.Count) user(s)" -ForegroundColor Yellow
    Write-Host "  Recovery     : Deleted folders land in the Recycle Bin (30-day window)." -ForegroundColor DarkGray
    Write-Host "------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host ""

    $confirm = (Read-Host "  Type 'YES' to proceed").Trim()
    if ($confirm -ne "YES") {
        Write-Status "Operation cancelled by admin." "DarkGray" "CANCEL"
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        exit 0
    }
}

Write-Host ""


# ============================================================
# Process each user
# ============================================================
$totalDeleted  = 0
$totalSkipped  = 0
$totalFailed   = 0
$totalDetected = 0

foreach ($user in $targetUsers) {

    $userId = $user.Id
    $upn    = $user.UserPrincipalName
    $name   = $user.DisplayName

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor DarkCyan
    Write-Status "Processing: $name ($upn)" "Cyan" "USER"
    Write-Host "==================================================" -ForegroundColor DarkCyan

    # -- Get the user's OneDrive --
    Write-Status "Fetching OneDrive..." "Yellow" "DRIVE"
    $drive = $null
    try {
        $drive = Get-MgUserDrive -UserId $userId -ErrorAction Stop | Select-Object -First 1
    } catch {
        Write-Status "Could not fetch OneDrive for '$name': $_" "Red" "DRIVE"
        Write-Status "Skipping '$name' (no license, no OneDrive, or insufficient permissions)." "DarkGray" "SKIP"
        $totalSkipped++
        continue
    }

    if (-not $drive -or [string]::IsNullOrWhiteSpace($drive.Id)) {
        Write-Status "No OneDrive found for '$name' - skipping." "DarkGray" "SKIP"
        $totalSkipped++
        continue
    }

    $driveId = [string]$drive.Id
    Write-Status "OneDrive found." "DarkGray" "DRIVE"

    # -- List root items --
    Write-Status "Scanning OneDrive root for KFM folders..." "Yellow" "SCAN"
    try {
        $rootItems = Get-MgDriveRootChild -DriveId $driveId -All -ErrorAction Stop
    } catch {
        Write-Status "Could not read OneDrive root for '$name': $_" "Red" "SCAN"
        $totalFailed++
        continue
    }

    $kfmFolders = @($rootItems | Where-Object {
        $_.Name -in $kfmFolderNames -and $null -ne $_.Folder
    })

    if ($kfmFolders.Count -eq 0) {
        Write-Status "No KFM folders found in OneDrive root for '$name' - skipping." "DarkGray" "SKIP"
        $totalSkipped++
        continue
    }

    $actionLabel = if ($testMode) { "would be removed" } else { "to remove" }
    Write-Status "Found $($kfmFolders.Count) KFM folder(s) ${actionLabel}:" "Cyan" "SCAN"
    $kfmFolders | ForEach-Object {
        $sizeKB = [math]::Round($_.Size / 1KB, 1)
        $itemCount = if ($_.Folder.ChildCount) { "$($_.Folder.ChildCount) item(s)" } else { "0 items" }
        Write-Status "  $($_.Name)  ($sizeKB KB, $itemCount)" "DarkGray" "SCAN"
        $totalDetected++
    }

    if ($testMode) {
        # Test mode: report only, no deletion
        Write-Status "[TEST MODE] Skipping deletion for '$name'." "Green" "TESTMODE"
    } else {
        # -- Delete each KFM folder --
        foreach ($folder in $kfmFolders) {
            Write-Status "Deleting '$($folder.Name)'..." "Yellow" "DELETE"
            try {
                Remove-MgDriveItem -DriveId $driveId -DriveItemId $folder.Id -ErrorAction Stop
                Write-Status "Deleted '$($folder.Name)' from $name's OneDrive (moved to Recycle Bin)." "Green" "DELETE"
                $totalDeleted++
            } catch {
                Write-Status "Failed to delete '$($folder.Name)' for '$name': $_" "Red" "DELETE"
                $totalFailed++
            }
        }
    }
}


# ============================================================
# Summary
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
$modeLabel = if ($testMode) { "Summary  [TEST MODE - no changes made]" } else { "Summary" }
Write-Host "  $modeLabel" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Status "Users targeted    : $($targetUsers.Count)" "Cyan"     "RESULT"
Write-Status "Users skipped     : $totalSkipped"         "DarkGray" "RESULT"

if ($testMode) {
    Write-Status "Folders detected  : $totalDetected (no changes made)" "Green" "RESULT"
} else {
    Write-Status "Folders detected  : $totalDetected"  "Cyan"  "RESULT"
    Write-Status "Folders deleted   : $totalDeleted"   "Green" "RESULT"
    $failColor = if ($totalFailed -gt 0) { "Red" } else { "DarkGray" }
    Write-Status "Failures          : $totalFailed" $failColor "RESULT"
}

Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
$again = (Read-Host "  Run again with different settings? (Y/N)").Trim().ToUpper()
if ($again -ne "Y") {
    $runAgain = $false
}
Write-Host ""

} # end while ($runAgain)


# ============================================================
# Disconnect
# ============================================================
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
Write-Status "Disconnected from Microsoft Graph." "DarkGray" "AUTH"
Write-Host ""

if ($totalFailed -gt 0) { exit 1 } else { exit 0 }
