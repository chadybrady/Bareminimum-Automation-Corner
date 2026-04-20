# ============================================================
# Intune Proactive Remediation - DETECTION
# OneDrive .old Folder Cleanup
# ============================================================
# Checks whether any OneDrive .old or .old_<timestamp> remnant
# folders exist under C:\Users (left behind by the KFM cleanup
# remediation). If found, signals non-compliance so the
# companion remediation script can delete them.
# ============================================================

$skipProfiles = @("Default", "Default User", "Public", "All Users", "defaultuser0")

$nonCompliantEntries = @()

try {
    $profiles = Get-ChildItem "C:\Users" -Directory -ErrorAction Stop |
        Where-Object { $_.Name -notin $skipProfiles -and $_.Name -notlike ".*" }
} catch {
    Write-Output "ERROR: Could not enumerate C:\Users - $_"
    exit 1
}

foreach ($profile in $profiles) {
    $oldFolders = Get-Item "$($profile.FullName)\OneDrive*" -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.PSIsContainer } |
        Where-Object { $_.Name -like '*.old' -or $_.Name -like '*.old_*' }

    foreach ($folder in $oldFolders) {
        $nonCompliantEntries += "$($profile.Name): $($folder.FullName)"
    }
}

if ($nonCompliantEntries.Count -gt 0) {
    Write-Output "Non-compliant: OneDrive .old folder(s) found:"
    $nonCompliantEntries | ForEach-Object { Write-Output "  $_" }
    exit 1
}

Write-Output "Compliant: no OneDrive .old folders found."
exit 0
