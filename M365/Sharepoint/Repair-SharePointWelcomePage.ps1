# Repair-SharePointWelcomePage.ps1
# Requires: PnP.PowerShell
# Install if needed:
# Install-Module PnP.PowerShell -Scope CurrentUser

param(
    [string]$SiteUrl  = "",
    [string]$ClientId = "",
    [string]$HomePageName = ""
)

$ErrorActionPreference = "Stop"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

function Write-WarnMsg {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

try {
    Write-Info "Connecting to $SiteUrl"
    Connect-PnPOnline -Url $SiteUrl -Interactive -ClientId $ClientId
    Write-Ok "Connected successfully"
}
catch {
    Write-Fail "Failed to connect: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "Fallback option:" -ForegroundColor Yellow
    Write-Host "Connect-PnPOnline -Url `"$SiteUrl`" -DeviceLogin -ClientId `"$ClientId`""
    exit 1
}

try {
    Write-Info "Reading current site welcome page"
    $web = Get-PnPWeb -Includes WelcomePage, ServerRelativeUrl, Title
    Write-Ok "Site title: $($web.Title)"
    Write-Ok "ServerRelativeUrl: $($web.ServerRelativeUrl)"
    Write-Ok "Current WelcomePage: $($web.WelcomePage)"
}
catch {
    Write-Fail "Failed to read web properties: $($_.Exception.Message)"
    exit 1
}

$pageRelativeUrl = "SitePages/$HomePageName"
$pageExists = $false
$pageRestored = $false

try {
    Write-Info "Checking whether $HomePageName exists in Site Pages"
    $page = Get-PnPPage -Identity $HomePageName -ErrorAction SilentlyContinue

    if ($null -ne $page) {
        $pageExists = $true
        Write-Ok "$HomePageName already exists"
    }
    else {
        Write-WarnMsg "$HomePageName was not found in Site Pages"
    }

    Write-Info "Listing available pages in Site Pages"
    $allPages = Get-PnPPage
    if ($allPages) {
        $allPages | Select-Object Name, Title | Format-Table -AutoSize
    }
}
catch {
    Write-Fail "Failed while checking Site Pages: $($_.Exception.Message)"
}

if (-not $pageExists) {
    try {
        Write-Info "Checking Recycle Bin for deleted homepage or Site Pages content"
        $recycleItems = Get-PnPRecycleBinItem

        $deletedHome = $recycleItems | Where-Object {
            $_.LeafName -eq $HomePageName -or $_.DirName -match "SitePages|Site Pages"
        } | Select-Object -First 1

        if ($deletedHome) {
            Write-WarnMsg "Found matching deleted item in Recycle Bin: $($deletedHome.LeafName)"
            Restore-PnPRecycleBinItem -Identity $deletedHome -Force
            Write-Ok "Recycle Bin item restored"
            Start-Sleep -Seconds 5

            $page = Get-PnPPage -Identity $HomePageName -ErrorAction SilentlyContinue
            if ($null -ne $page) {
                $pageExists = $true
                $pageRestored = $true
                Write-Ok "$HomePageName is now available after restore"
            }
            else {
                Write-WarnMsg "Restore completed, but $HomePageName is still not visible as a page"
            }
        }
        else {
            Write-WarnMsg "No deleted homepage or matching Site Pages item found in Recycle Bin"
        }
    }
    catch {
        Write-Fail "Failed while checking or restoring from Recycle Bin: $($_.Exception.Message)"
    }
}

if (-not $pageExists) {
    try {
        Write-Info "Creating a new modern homepage: $HomePageName"
        Add-PnPPage -Name $HomePageName -LayoutType Home -Publish | Out-Null
        Start-Sleep -Seconds 3

        $page = Get-PnPPage -Identity $HomePageName -ErrorAction SilentlyContinue
        if ($null -ne $page) {
            $pageExists = $true
            Write-Ok "$HomePageName created successfully"
        }
        else {
            throw "Page creation completed, but page could not be retrieved afterwards."
        }
    }
    catch {
        Write-Fail "Failed to create $HomePageName : $($_.Exception.Message)"
        exit 1
    }
}

try {
    Write-Info "Setting $HomePageName as the site home page"
    Set-PnPHomePage -RootFolderRelativeUrl $pageRelativeUrl
    Write-Ok "Homepage updated to $pageRelativeUrl"
}
catch {
    Write-Fail "Failed to set homepage: $($_.Exception.Message)"
    exit 1
}

try {
    Write-Info "Verifying updated welcome page"
    $updatedWeb = Get-PnPWeb -Includes WelcomePage
    Write-Ok "Updated WelcomePage: $($updatedWeb.WelcomePage)"
}
catch {
    Write-Fail "Failed to verify updated welcome page: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Repair completed." -ForegroundColor Green
Write-Host "Site URL: $SiteUrl"
Write-Host "Expected homepage path: $pageRelativeUrl"
if ($pageRestored) {
    Write-Host "Result: Existing homepage was restored from Recycle Bin and reassigned."
}
else {
    Write-Host "Result: Homepage was verified or recreated and then reassigned."
}