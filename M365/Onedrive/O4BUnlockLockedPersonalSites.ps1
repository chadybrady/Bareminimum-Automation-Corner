#Requires -Modules Microsoft.Online.SharePoint.PowerShell

<#
.SYNOPSIS
    Unlocks all OneDrive personal sites with LockState "NoAccess".

.DESCRIPTION
    Connects to SharePoint Online, retrieves all personal (OneDrive) sites
    with a LockState of "NoAccess", and sets them to "Unlock".

.PARAMETER TenantAdminUrl
    The SharePoint admin center URL, e.g. https://contoso-admin.sharepoint.com

.NOTES
    Requires the Microsoft.Online.SharePoint.PowerShell module.
    Must be run as a SharePoint Administrator.
    Supports -WhatIf to preview changes without applying them.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$TenantAdminUrl
)

# ── Connect ────────────────────────────────────────────────────────────────────
Write-Host "Connecting to SharePoint Online..." -ForegroundColor Cyan
Connect-SPOService -Url $TenantAdminUrl

# ── Retrieve locked personal sites ────────────────────────────────────────────
Write-Host "Retrieving personal sites with LockState 'NoAccess'..." -ForegroundColor Cyan

$lockedSites = Get-SPOSite -IncludePersonalSite $true -Limit All `
    -Filter "Url -like '-my.sharepoint.com/personal/'" |
    Where-Object { $_.LockState -eq "NoAccess" }

if ($lockedSites.Count -eq 0) {
    Write-Host "No personal sites with LockState 'NoAccess' found." -ForegroundColor Green
    exit 0
}

Write-Host "Found $($lockedSites.Count) site(s) with LockState 'NoAccess'." -ForegroundColor Yellow
Write-Host ""

# ── Unlock each site ──────────────────────────────────────────────────────────
$success = 0
$failed  = 0

foreach ($site in $lockedSites) {
    if ($PSCmdlet.ShouldProcess($site.Url, "Set LockState to Unlock")) {
        try {
            Set-SPOSite -Identity $site.Url -LockState Unlock
            Write-Host "  [OK] Unlocked: $($site.Url)" -ForegroundColor Green
            $success++
        }
        catch {
            Write-Warning "  [FAIL] $($site.Url) - $_"
            $failed++
        }
    }
}

Write-Host ""
Write-Host "Completed. Unlocked: $success  |  Failed: $failed" -ForegroundColor Cyan
