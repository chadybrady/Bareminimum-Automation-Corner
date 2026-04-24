#Requires -Version 7.0

<#
.SYNOPSIS
  Checks for new versions of Winget-sourced Win32 apps tracked in a SharePoint list
  and marks them as "Pending Approval" when a newer version is detected.

.DESCRIPTION
  Intended to run as an Azure Automation Runbook (PS7 runtime) on a monthly schedule.
  Authenticates via System-Assigned Managed Identity. Reads all Active Winget-sourced
  items from the Win32-App-Updates SharePoint list, queries the winget-pkgs GitHub repo
  for the latest available version, and PATCHes items where a newer version is found.
  Outputs a JSON summary of updated apps — consumed by the Power Automate approval flow.

.RUNBOOK SETUP
  Azure Automation variables required (Settings → Variables):
    Win32Updates_TenantId         – Entra tenant ID (GUID)
    Win32Updates_SharePointSiteId – SharePoint site ID (GUID)
    Win32Updates_ListId           – SharePoint list ID (GUID)

  Managed Identity Graph app roles required:
    Sites.ReadWrite.All

  Required Automation Account modules:
    Microsoft.Graph.Authentication

.LOCAL USAGE
  ./Check-Win32AppVersions.ps1 `
    -TenantId '00000000-...' `
    -SharePointSiteId '00000000-...' `
    -ListId '00000000-...'

.NOTES
  Author  : Bareminimum Automation Corner
  Version : 1.0
#>

[CmdletBinding()]
param(
    # Entra tenant ID. In runbook context, read from Automation Variable Win32Updates_TenantId.
    [string]$TenantId,

    # SharePoint site ID (GUID). In runbook context, read from Win32Updates_SharePointSiteId.
    [string]$SharePointSiteId,

    # SharePoint list ID (GUID). In runbook context, read from Win32Updates_ListId.
    [string]$ListId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Constants ────────────────────────────────────────────────────────────────

$script:RequiredScopes    = @('Sites.ReadWrite.All')
$script:WingetManifestApi = 'https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests'
$script:GraphBase         = 'https://graph.microsoft.com/v1.0'

# Detect Azure Automation Runbook context
$script:IsRunbook = $false
try { if ($PSPrivateMetadata.JobId.Guid) { $script:IsRunbook = $true } } catch {}

# ─── UI / Output Helpers ──────────────────────────────────────────────────────

function Write-Out  { param([string]$m, [string]$c = 'White') if ($script:IsRunbook) { Write-Output $m } else { Write-Host $m -ForegroundColor $c } }
function Write-Step { param([string]$m) Write-Out "▶ $m" -c Yellow }
function Write-Ok   { param([string]$m) Write-Out "✓ $m" -c Green }
function Write-Info { param([string]$m) Write-Out "· $m" -c Gray }
function Write-Warn { param([string]$m) Write-Out "⚠ $m" -c DarkYellow }
function Write-Fail { param([string]$m) Write-Out "✗ $m" -c Red }

# ─── Helper Functions ─────────────────────────────────────────────────────────

function Get-AutomationVariableOrParam {
    param([string]$VariableName, [string]$ParamValue)
    if (-not [string]::IsNullOrWhiteSpace($ParamValue)) { return $ParamValue }
    if ($script:IsRunbook) { return Get-AutomationVariable -Name $VariableName }
    throw "Required value '$VariableName' not provided. Pass it as a parameter when running locally."
}

function Invoke-GraphRequest {
    param(
        [string]$Uri,
        [string]$Method = 'GET',
        [hashtable]$Body,
        [int]$MaxRetries = 3
    )
    $attempt = 0
    while ($true) {
        try {
            $params = @{ Uri = $Uri; Method = $Method }
            if ($Body) {
                $params.Body        = ($Body | ConvertTo-Json -Depth 10)
                $params.ContentType = 'application/json'
            }
            return Invoke-MgGraphRequest @params
        } catch {
            $attempt++
            $status = $_.Exception.Response?.StatusCode?.value__
            if ($attempt -lt $MaxRetries -and ($status -eq 429 -or $status -ge 500)) {
                $delay = [Math]::Pow(2, $attempt) * 3
                Write-Warn "Graph request failed (HTTP $status). Retrying in ${delay}s…"
                Start-Sleep -Seconds $delay
            } else { throw }
        }
    }
}

function Get-SharePointListItems {
    param([string]$SiteId, [string]$ListId, [string]$Filter)
    $uri   = "$script:GraphBase/sites/$SiteId/lists/$ListId/items?expand=fields&`$filter=$Filter"
    $items = [System.Collections.Generic.List[object]]::new()
    do {
        $response = Invoke-GraphRequest -Uri $uri
        $items.AddRange([object[]]$response.value)
        $uri = $response.'@odata.nextLink'
    } while ($uri)
    return $items
}

function Set-SharePointListItem {
    param([string]$SiteId, [string]$ListId, [string]$ItemId, [hashtable]$Fields)
    $uri = "$script:GraphBase/sites/$SiteId/lists/$ListId/items/$ItemId/fields"
    Invoke-GraphRequest -Uri $uri -Method 'PATCH' -Body $Fields | Out-Null
}

function Get-WingetLatestVersion {
    param([string]$PackageId)
    # PackageId format: Publisher.PackageName  e.g. Mozilla.Firefox
    $parts = $PackageId -split '\.', 2
    if ($parts.Count -ne 2) {
        throw "Invalid WingetPackageId '$PackageId'. Expected format: 'Publisher.PackageName'."
    }
    $publisher   = $parts[0]
    $packageName = $parts[1]
    $firstLetter = $publisher[0].ToString().ToLower()

    $params = @{
        Uri     = "$script:WingetManifestApi/$firstLetter/$publisher/$packageName"
        Headers = @{ 'User-Agent' = 'Win32AppUpdateAutomation/1.0' }
    }
    try {
        $response = Invoke-RestMethod @params -ErrorAction Stop
    } catch {
        throw "Winget manifest lookup failed for '$PackageId': $_"
    }

    $versions = $response |
        Where-Object { $_.type -eq 'dir' } |
        Select-Object -ExpandProperty name

    if (-not $versions) { throw "No version folders found for package '$PackageId'." }

    # Attempt semantic sort; fall back to last entry on parse failure
    $latest = $versions |
        Sort-Object {
            try { [System.Version]($_ -replace '[^0-9.]', '') }
            catch { [System.Version]'0.0' }
        } |
        Select-Object -Last 1

    return $latest
}

function Test-NewerVersion {
    param([string]$Current, [string]$Available)
    if ([string]::IsNullOrWhiteSpace($Current)) { return $true }
    try {
        $c = [System.Version]($Current  -replace '[^0-9.]', '')
        $a = [System.Version]($Available -replace '[^0-9.]', '')
        return $a -gt $c
    } catch {
        # Fall back to string inequality if version parsing fails
        return $Available -ne $Current
    }
}

function Connect-Graph {
    Write-Step 'Authenticating to Microsoft Graph'
    $params = @{ NoWelcome = $true }
    if ($script:IsRunbook) {
        $params.Identity = $true
    } else {
        $params.Scopes   = $script:RequiredScopes
        $params.TenantId = $script:Config.TenantId
    }
    Connect-MgGraph @params
    Write-Ok 'Authenticated'
}

# ─── Main ─────────────────────────────────────────────────────────────────────

Write-Step 'Win32 App Version Check — Starting'

# Resolve configuration from Automation Variables or local parameters
$script:Config = @{
    TenantId         = Get-AutomationVariableOrParam -VariableName 'Win32Updates_TenantId'         -ParamValue $TenantId
    SharePointSiteId = Get-AutomationVariableOrParam -VariableName 'Win32Updates_SharePointSiteId' -ParamValue $SharePointSiteId
    ListId           = Get-AutomationVariableOrParam -VariableName 'Win32Updates_ListId'           -ParamValue $ListId
}

Connect-Graph

# ─── Read SharePoint List ─────────────────────────────────────────────────────

Write-Step 'Reading SharePoint list for Active Winget apps'

try {
    # OData filter — reads items where Source = Winget and Status = Active
    $filter = "fields/Source eq 'Winget' and fields/Status eq 'Active'"
    $items  = Get-SharePointListItems -SiteId $script:Config.SharePointSiteId -ListId $script:Config.ListId -Filter $filter
} catch {
    Write-Fail "Failed to read SharePoint list: $_"
    throw
}

Write-Info "Found $($items.Count) Active Winget app(s) to check"

# ─── Check Versions ───────────────────────────────────────────────────────────

Write-Step 'Querying Winget for latest versions'
$updatedApps = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($item in $items) {
    $fields     = $item.fields
    $appName    = $fields.AppName
    $packageId  = $fields.WingetPackageId
    $currentVer = $fields.CurrentVersion
    $itemId     = $item.id

    if ([string]::IsNullOrWhiteSpace($packageId)) {
        Write-Warn "[$appName] WingetPackageId is empty — skipping"
        continue
    }

    Write-Info "[$appName] Checking '$packageId' (current: $currentVer)"

    try {
        $latestVer = Get-WingetLatestVersion -PackageId $packageId
    } catch {
        Write-Warn "[$appName] Version lookup failed: $_"
        continue
    }

    if (Test-NewerVersion -Current $currentVer -Available $latestVer) {
        Write-Ok "[$appName] New version available: $currentVer → $latestVer"
        try {
            Set-SharePointListItem -SiteId $script:Config.SharePointSiteId -ListId $script:Config.ListId -ItemId $itemId -Fields @{
                AvailableVersion = $latestVer
                Status           = 'Pending Approval'
                LastUpdated      = (Get-Date -Format 'o')
            }
            $updatedApps.Add([PSCustomObject]@{
                AppName          = $appName
                WingetPackageId  = $packageId
                CurrentVersion   = $currentVer
                AvailableVersion = $latestVer
                ListItemId       = $itemId
            })
            Write-Ok "[$appName] SharePoint list updated"
        } catch {
            Write-Fail "[$appName] Failed to update SharePoint list item: $_"
        }
    } else {
        Write-Info "[$appName] Already up to date ($currentVer)"
    }
}

# ─── Output Summary ───────────────────────────────────────────────────────────

Write-Step "Version check complete — $($updatedApps.Count) app(s) marked as Pending Approval"

if ($updatedApps.Count -gt 0) {
    # Emit structured JSON — Power Automate reads this from the runbook job output stream
    $updatedApps | ConvertTo-Json -Depth 5 -Compress | Write-Output
}
