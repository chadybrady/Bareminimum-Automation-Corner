# ============================================================
# Intune Proactive Remediation - REMEDIATION
# OneDrive .old Folder Cleanup
# ============================================================
# Runs as SYSTEM (Intune context)
#
# Steps:
#   1. Find all OneDrive .old / .old_<timestamp> remnant folders
#      under every user profile in C:\Users.
#   2. Delete each folder permanently (no Recycle Bin).
#   3. Exit 0 on success, 1 if any folder could not be removed.
# ============================================================


$skipProfiles = @("Default", "Default User", "Public", "All Users", "defaultuser0")


function Write-Status {
    param([string]$Message, [string]$Color = "Cyan", [string]$Prefix = "INFO")
    Write-Host "[$Prefix] $(Get-Date -Format 'HH:mm:ss') - $Message" -ForegroundColor $Color
}


# -- Enumerate all user profiles under C:\Users --
Write-Status "Enumerating user profiles under C:\Users..." "Yellow" "SCAN"

try {
    $profiles = Get-ChildItem "C:\Users" -Directory -ErrorAction Stop |
        Where-Object { $_.Name -notin $skipProfiles -and $_.Name -notlike ".*" }
} catch {
    Write-Status "ERROR: Could not enumerate C:\Users - $_" "Red" "SCAN"
    exit 1
}

Write-Status "Found $($profiles.Count) user profile(s) to process." "Cyan" "SCAN"

$failureCount = 0

foreach ($profile in $profiles) {

    $oldFolders = Get-Item "$($profile.FullName)\OneDrive*" -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.PSIsContainer } |
        Where-Object { $_.Name -like '*.old' -or $_.Name -like '*.old_*' }

    if (-not $oldFolders) {
        Write-Status "No .old folders found for '$($profile.Name)' - skipping." "DarkGray" "SKIP"
        continue
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor DarkCyan
    Write-Status "Processing user: $($profile.Name)" "Cyan" "USER"
    Write-Host "==================================================" -ForegroundColor DarkCyan

    foreach ($folder in $oldFolders) {
        Write-Status "Removing: $($folder.FullName)" "Yellow" "DELETE"
        try {
            Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction Stop
            Write-Status "Deleted: $($folder.FullName)" "Green" "DELETE"
        } catch {
            Write-Status "Failed to delete '$($folder.FullName)': $_" "Red" "DELETE"
            $failureCount++
        }
    }
}

Write-Host ""
if ($failureCount -gt 0) {
    Write-Status "$failureCount folder(s) could not be deleted - see above for details." "Red" "RESULT"
    exit 1
}

Write-Status "All OneDrive .old folders removed successfully." "Green" "RESULT"
exit 0
