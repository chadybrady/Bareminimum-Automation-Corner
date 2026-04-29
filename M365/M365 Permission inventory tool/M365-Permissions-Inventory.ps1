<#
.SYNOPSIS
  Tenant-wide permissions inventory (read-only) -> CSV
  Each row = unique assignment of a principal (user/group/SP) to a
  service/resource with a role/permission.

.COVERAGE
  - Entra directory role assignments
  - Enterprise app appRoleAssignedTo (users/groups assigned to enterprise apps)
  - OAuth2 permission grants (delegated/admin consent)
  - Teams membership/owners
  - SharePoint site permissions (incl. OneDrive when selected)
  - Exchange mailbox permissions (FullAccess, SendAs, SendOnBehalf)
  - Distribution groups & mail-enabled security groups (members, sync status)
  - Conditional Access policy assignments (included/excluded users/groups)
  - PIM role assignments (eligible/not-yet-activated and active/permanent/activated)

.NOTES
  - SharePoint item-level permissions (files/folders) NOT enumerated.
  - Exchange folder permissions (calendar etc.) not included.
  - Requires PowerShell 7.0+

.REQUIREMENTS
  - Microsoft.Graph PowerShell SDK
  - Optional: ExchangeOnlineManagement (prompted if Exchange selected)
  - Optional: ActiveDirectory RSAT module on Windows (prompted for AD crosscheck)
  - Optional: ldapsearch on macOS/Linux (prompted for AD crosscheck)
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
  [string]$OutputPath = ".\M365-Permissions-Inventory"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ==============================================================
# SECTION 1/3 - INTERACTIVE PROMPTS
# ==============================================================

function Prompt-YesNo {
  param(
    [string]$Question,
    [string]$Default = "Y"
  )
  $hint   = if ($Default -eq "Y") { "[Y/n]" } else { "[y/N]" }
  $answer = Read-Host "$Question $hint"
  if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
  return $answer.Trim().ToUpper() -eq "Y"
}

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║                                                              ║" -ForegroundColor Cyan
Write-Host "  ║        M365 Permissions Inventory  ·  v2.0                  ║" -ForegroundColor Cyan
Write-Host "  ║        Bareminimum Automation                                ║" -ForegroundColor DarkCyan
Write-Host "  ║                                                              ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This tool produces a read-only permissions inventory across"    -ForegroundColor White
Write-Host "  your Microsoft 365 tenant and exports results to CSV/Excel."    -ForegroundColor White
Write-Host ""
Write-Host "  Coverage:"                                                       -ForegroundColor Gray
Write-Host "    · Entra directory roles & PIM assignments (eligible + active)"            -ForegroundColor Gray
Write-Host "    · Enterprise apps, OAuth2 consent grants"                      -ForegroundColor Gray
Write-Host "    · Teams, SharePoint & OneDrive site permissions"               -ForegroundColor Gray
Write-Host "    · Exchange mailboxes, distribution groups"                     -ForegroundColor Gray
Write-Host "    · Conditional Access policy assignments"                       -ForegroundColor Gray
Write-Host ""
Write-Host "  Requirements: Microsoft.Graph SDK  |  PowerShell 7+"            -ForegroundColor DarkGray
Write-Host "  Optional    : ExchangeOnlineManagement, ImportExcel"             -ForegroundColor DarkGray
Write-Host ""
Write-Host "  ──────────────────────────────────────────────────────────────" -ForegroundColor DarkCyan
Write-Host "  Select which sections to include below."                         -ForegroundColor Yellow
Write-Host "  Press Enter to accept the default [Y] for each section."        -ForegroundColor DarkGray
Write-Host ""

$IncludeDirectoryRoles  = Prompt-YesNo "  [1] Entra Directory Role Assignments?"
$IncludeEnterpriseApps  = Prompt-YesNo "  [2] Enterprise App Role Assignments?"
$IncludeOAuth2Grants    = Prompt-YesNo "  [3] OAuth2 Permission Grants (Consent)?"
$IncludeTeams           = Prompt-YesNo "  [4] Teams Memberships (Owners/Members)?"
$IncludeSharePointSites = Prompt-YesNo "  [5] SharePoint Site Permissions?"   

$IncludeOneDriveSites = $false
if ($IncludeSharePointSites) {
  $IncludeOneDriveSites = Prompt-YesNo "       Include OneDrive sites as well?"
} else {
  $IncludeOneDriveSites = Prompt-YesNo "  [5b] OneDrive Site Permissions (without SharePoint)?"
}

$IncludeExchange     = Prompt-YesNo "  [6] Exchange Mailbox Permissions (FullAccess, SendAs, SendOnBehalf)?"
$IncludeDistGroups   = Prompt-YesNo "  [7] Distribution Groups & Mail-enabled Security Groups (members, sync status)?"
$IncludeCondAccess   = Prompt-YesNo "  [8] Conditional Access Policy Assignments (users/groups in policies)?"
$IncludePIMEligible  = Prompt-YesNo "  [9] PIM Role Assignments (eligible + active/permanent/activated)?"
Write-Host ""

# Detect platform and available AD tools
$ADMethod = "none"
if ($IsWindows -and (Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue)) {
  $ADMethod = "rsat"
} elseif (Get-Command ldapsearch -ErrorAction SilentlyContinue) {
  $ADMethod = "ldapsearch"
}

if ($ADMethod -eq "rsat") {
  $IncludeADCrosscheck = Prompt-YesNo "  [AD] Enrich AD-synced accounts with OU from on-prem AD? (via RSAT ActiveDirectory module)" -Default "N"
} elseif ($ADMethod -eq "ldapsearch") {
  $IncludeADCrosscheck = Prompt-YesNo "  [AD] Enrich AD-synced accounts with OU from on-prem AD? (via ldapsearch)" -Default "N"
} else {
  Write-Host "  [AD] AD enrichment not available (requires RSAT on Windows or ldapsearch on macOS/Linux)" -ForegroundColor DarkGray
  $IncludeADCrosscheck = $false
}

# App-only / client credentials auth
$UseAppOnlyAuth      = $false
$AppOnlyTenantId     = ""
$AppOnlyClientId     = ""
$AppOnlyClientSecret = $null

$needsSharePoint = $IncludeSharePointSites -or $IncludeOneDriveSites
Write-Host ""
if ($needsSharePoint) {
  Write-Host "  NOTE: SharePoint/OneDrive enumeration requires app-only authentication."    -ForegroundColor Yellow
  Write-Host "        Delegated auth (even Global Admin) returns 403 on /beta/sites/getAllSites." -ForegroundColor DarkGray
  Write-Host ""
}
$UseAppOnlyAuth = Prompt-YesNo "  [Auth] Use app-only authentication (client credentials)?" `
  -Default $(if ($needsSharePoint) { "Y" } else { "N" })

if ($UseAppOnlyAuth) {
  Write-Host ""
  Write-Host "  App-only requires an Entra App Registration with Application permissions"  -ForegroundColor DarkGray
  Write-Host "  (not Delegated) and admin consent granted for:"                            -ForegroundColor DarkGray
  Write-Host "    Directory.Read.All, RoleManagement.Read.Directory"                       -ForegroundColor DarkGray
  Write-Host "    Application.Read.All, TeamMember.Read.All, Sites.Manage.All, Mail.Read"    -ForegroundColor DarkGray
  if ($IncludeCondAccess)  { Write-Host "    Policy.Read.All                          (Conditional Access selected)" -ForegroundColor DarkGray }
  if ($IncludePIMEligible) { Write-Host "    RoleEligibilitySchedule.Read.Directory   (PIM selected)"               -ForegroundColor DarkGray }
  Write-Host ""
  $AppOnlyTenantId     = Read-Host "  Tenant ID  (e.g. xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
  $AppOnlyClientId     = Read-Host "  Client ID  (App Registration Application ID)"
  Write-Host "  ⚠ Enter the secret VALUE (the long string), NOT the secret ID (the GUID)" -ForegroundColor DarkYellow
  $secretPlain         = Read-Host "  Client Secret value (paste supported, shown briefly)"
  $AppOnlyClientSecret = ConvertTo-SecureString $secretPlain -AsPlainText -Force
  $secretPlain         = $null
}

Write-Host ""
Write-Host "Selected sections:" -ForegroundColor Cyan
Write-Host "  Directory Roles  : $IncludeDirectoryRoles"
Write-Host "  Enterprise Apps  : $IncludeEnterpriseApps"
Write-Host "  OAuth2 Grants    : $IncludeOAuth2Grants"
Write-Host "  Teams            : $IncludeTeams"
Write-Host "  SharePoint Sites : $IncludeSharePointSites"
Write-Host "  OneDrive Sites   : $IncludeOneDriveSites"
Write-Host "  Exchange         : $IncludeExchange"
Write-Host "  Dist Groups      : $IncludeDistGroups"
Write-Host "  Cond. Access     : $IncludeCondAccess"
Write-Host "  PIM Eligible     : $IncludePIMEligible"
Write-Host "  AD Crosscheck    : $IncludeADCrosscheck"
Write-Host "  Auth Mode        : $(if ($UseAppOnlyAuth) { 'App-only (client credentials)' } else { 'Delegated (interactive)' })"
Write-Host ""

$confirm = Prompt-YesNo "Start inventory with these settings?" -Default "Y"
if (-not $confirm) {
  Write-Host "Cancelled by user." -ForegroundColor Red
  exit
}

# ==============================================================
# SECTION 1/3 - HELPERS
# ==============================================================

function Ensure-Folder {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Get-OuFromDn {
  param([string]$DistinguishedName)
  if (-not $DistinguishedName) { return "" }
  $idx = $DistinguishedName.IndexOf("OU=", [System.StringComparison]::OrdinalIgnoreCase)
  if ($idx -ge 0) { return $DistinguishedName.Substring($idx) }
  $idx2 = $DistinguishedName.IndexOf("CN=", [System.StringComparison]::OrdinalIgnoreCase)
  if ($idx2 -ge 0) {
    $comma = $DistinguishedName.IndexOf(",", $idx2)
    if ($comma -ge 0) { return $DistinguishedName.Substring($comma + 1).Trim() }
  }
  return $DistinguishedName
}

function Export-CsvUtf8 {
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Path
  )
  $columns = @(
    "Service","ResourceType","ResourceId","ResourceName",
    "AssignmentType","RoleOrPermission",
    "PrincipalType","PrincipalId","PrincipalDisplayName","PrincipalUPN",
    "Origin","AssignedViaOnPremGroup","OnPremisesDN","OnPremisesOU","Details"
  )
  $Object | Select-Object $columns |
    Export-Csv -NoTypeInformation -Encoding UTF8 -Path $Path
}

function Write-JsonFile {
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Path
  )
  $Object | ConvertTo-Json -Depth 25 | Out-File -FilePath $Path -Encoding UTF8
}

function Normalize-GraphUri {
  param([string]$Uri)
  if ($Uri.StartsWith("/")) {
    if ($Uri.StartsWith("/v1.0/") -or $Uri.StartsWith("/beta/")) { return $Uri }
    return "/v1.0$Uri"
  }
  if ($Uri -match '^https://graph\.microsoft\.com/(v1\.0|beta)/') { return $Uri }
  if ($Uri -match '^https://graph\.microsoft\.com/') {
    return $Uri -replace '^https://graph\.microsoft\.com/',
                          'https://graph.microsoft.com/v1.0/'
  }
  return $Uri
}

# New: simple null-coalescing helper for compatibility across PS versions
function Coalesce {
  param(
    $Value,
    $Fallback
  )
  if ($null -ne $Value) { return $Value }
  return $Fallback
}

function Get-GraphPropValue {
  param(
    [Parameter(Mandatory)][object]$Obj,
    [Parameter(Mandatory)][string]$Name
  )
  if ($null -eq $Obj) { return $null }
  if ($Obj -is [System.Collections.IDictionary]) {
    if ($Obj.Contains($Name)) { return $Obj[$Name] }
    return $null
  }
  $p = $Obj.PSObject.Properties[$Name]
  if ($p) { return $p.Value }
  return $null
}

function Get-GraphPaged {
  param(
    [Parameter(Mandatory)][string]$Uri,
    [hashtable]$Headers  = @{},
    [int]$MaxRetries     = 5
  )

  $all  = New-Object System.Collections.Generic.List[object]
  $next = Normalize-GraphUri -Uri $Uri

  while ($null -ne $next) {
    $resp    = $null
    $attempt = 0

    while ($attempt -le $MaxRetries) {
      try {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $next -Headers $Headers
        break
      }
      catch {
        $statusCode = $null
        try { $statusCode = $_.Exception.Response.StatusCode.value__ } catch {}

        if ($statusCode -eq 429 -and $attempt -lt $MaxRetries) {
          $retryAfter = $null
          try {
            $retryAfter = [int]$_.Exception.Response.Headers.RetryAfter.Delta.TotalSeconds
          } catch {}
          $wait = if ($retryAfter -and $retryAfter -gt 0) {
            $retryAfter
          } else {
            [int][math]::Pow(2, $attempt + 1)
          }
          Write-Warning "Graph throttled (429). Waiting ${wait}s before retry $($attempt+1)/$MaxRetries..."
          Start-Sleep -Seconds $wait
          $attempt++
        }
        else { throw }
      }
    }

    $items = Get-GraphPropValue -Obj $resp -Name "value"
    if ($items) {
      foreach ($i in $items) { [void]$all.Add($i) }
    }

    $nl = Get-GraphPropValue -Obj $resp -Name "@odata.nextLink"
    if (-not $nl) { $nl = Get-GraphPropValue -Obj $resp -Name "odata.nextLink" }
    $next = if ($nl) { Normalize-GraphUri -Uri $nl } else { $null }
  }

  return $all
}

function New-AssignmentRow {
  param(
    [string]$Service,
    [string]$ResourceType,
    [string]$ResourceId,
    [string]$ResourceName,
    [string]$AssignmentType,
    [string]$RoleOrPermission,
    [hashtable]$PrincipalInfo,
    [string]$Details
  )
  # Flag if assignment is via an on-prem synced security group
  $viaOnPremGroup = ""
  if ($PrincipalInfo.PrincipalType -eq "Group" -and $PrincipalInfo.Origin -eq "ADSync") {
    $viaOnPremGroup = "Yes"
  }

  [pscustomobject]@{
    Service              = $Service
    ResourceType         = $ResourceType
    ResourceId           = $ResourceId
    ResourceName         = $ResourceName
    AssignmentType       = $AssignmentType
    RoleOrPermission     = $RoleOrPermission
    PrincipalType        = $PrincipalInfo.PrincipalType
    PrincipalId          = $PrincipalInfo.PrincipalId
    PrincipalDisplayName = $PrincipalInfo.DisplayName
    PrincipalUPN         = $PrincipalInfo.UPN
    Origin               = $PrincipalInfo.Origin
    AssignedViaOnPremGroup = $viaOnPremGroup
    OnPremisesDN         = $PrincipalInfo.OnPremisesDN
    OnPremisesOU         = $PrincipalInfo.OnPremisesOU
    Details              = $Details
  }
}

# ==============================================================
# SECTION 1/3 - OUTPUT PREP + TRANSCRIPT
# ==============================================================

Ensure-Folder -Path $OutputPath
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runFolder  = Join-Path $OutputPath "Run-$timestamp"
Ensure-Folder -Path $runFolder
$runFolder = (Resolve-Path $runFolder).Path

$transcriptStarted = $false
try {
  Start-Transcript -Path (Join-Path $runFolder "audit.log") | Out-Null
  $transcriptStarted = $true
}
catch {
  Write-Warning "Could not start transcript: $_"
}

Write-Host "Output folder: $runFolder" -ForegroundColor Cyan

# ==============================================================
# SECTION 1/3 - GRAPH CONNECT
# ==============================================================

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
  throw ("Microsoft.Graph module not found. " +
         "Run: Install-Module Microsoft.Graph -Scope CurrentUser")
}
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

if ($UseAppOnlyAuth) {
  if (-not $AppOnlyTenantId -or -not $AppOnlyClientId -or -not $AppOnlyClientSecret) {
    throw "App-only auth selected but TenantId, ClientId or ClientSecret is missing."
  }
  $credential = New-Object System.Management.Automation.PSCredential(
    $AppOnlyClientId, $AppOnlyClientSecret
  )
  try {
    Connect-MgGraph -TenantId $AppOnlyTenantId -ClientSecretCredential $credential -NoWelcome
  }
  catch {
    $inner = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
    Write-Host ""
    Write-Host "✗ App-only authentication failed." -ForegroundColor Red
    Write-Host "  Reason : $inner" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "  Common causes:" -ForegroundColor DarkYellow
    Write-Host "    · Secret VALUE entered instead of secret ID (AADSTS7000215)" -ForegroundColor DarkYellow
    Write-Host "    · Wrong TenantId, ClientId, or ClientSecret" -ForegroundColor DarkYellow
    Write-Host "    · Client secret has expired" -ForegroundColor DarkYellow
    Write-Host "    · Application permissions not granted admin consent" -ForegroundColor DarkYellow
    Write-Host "    · App registration does not exist in this tenant" -ForegroundColor DarkYellow
    throw
  }
} else {
  $graphScopes = @(
    "Directory.Read.All",
    "RoleManagement.Read.Directory",
    "Application.Read.All",
    "Team.ReadBasic.All",
    "TeamMember.Read.All",
    "Sites.Manage.All",
    "Mail.Read"
  )
  if ($IncludeCondAccess)  { $graphScopes += "Policy.Read.All" }
  if ($IncludePIMEligible) { $graphScopes += "RoleEligibilitySchedule.Read.Directory" }
  Connect-MgGraph -Scopes $graphScopes -NoWelcome
}
Write-Host "Connected to Microsoft Graph." -ForegroundColor Green

$headers = @{ "ConsistencyLevel" = "eventual" }

# ==============================================================
# SECTION 1/3 - EXO CONNECT (only if Exchange selected)
# ==============================================================

if ($IncludeExchange) {
  if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    throw ("ExchangeOnlineManagement module not found. " +
           "Run: Install-Module ExchangeOnlineManagement -Scope CurrentUser")
  }

  # Disable MSAL WAM/broker BEFORE import — MSAL reads this at class-init time.
  # On Windows Server the RuntimeBroker constructor crashes with NullReferenceException
  # on a background thread (uncatchable) when there is no interactive window handle.
  $env:MSAL_DISABLE_WAM    = "1"
  $env:MSAL_DISABLE_BROKER = "1"

  Import-Module ExchangeOnlineManagement -ErrorAction Stop

  # Cross-platform temp directory for EXO module
  $exoTmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "M365PermInv"
  New-Item -ItemType Directory -Path $exoTmpDir -Force | Out-Null
  $env:TEMP = $exoTmpDir
  $env:TMP  = $exoTmpDir

  # On Windows, skip the pre-disconnect: Disconnect-ExchangeOnline calls ClearAllTokensAsync()
  # which initialises the WAM broker on a background thread — the resulting NullReferenceException
  # is unhandled and kills the process. Only disconnect when not on Windows.
  if (-not $IsWindows) {
    try {
      Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    } catch {}
  }

  $exoCmds = @(
    'Get-EXOMailbox',
    'Get-EXOMailboxPermission',
    'Get-EXORecipientPermission',
    'Get-Mailbox'
  )

  Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan

  # Auth flow selection:
  #   On Windows: skip Flow 1 (-UseWebLogin) — it uses the WAM broker which crashes
  #               on Windows Server with no window handle (NullReferenceException on
  #               background thread, uncatchable). Go straight to device code.
  #   On macOS/Linux: try web login first, then device code, then plain interactive.

  $ceoCmd    = Get-Command Connect-ExchangeOnline -ErrorAction SilentlyContinue
  $paramKeys = if ($ceoCmd -and $ceoCmd.Parameters) { $ceoCmd.Parameters.Keys } else { @() }

  $baseParams = @{
    ShowBanner            = $false
    CommandName           = $exoCmds
    SkipLoadingFormatData = $true
    SkipLoadingCmdletHelp = $true
  }

  $connected = $false
  $lastErr   = $null

  # --- Flow 1: explicit web-browser login — skipped on Windows (WAM broker crash risk) ---
  if (-not $connected -and -not $IsWindows -and $paramKeys -contains 'UseWebLogin') {
    try {
      Connect-ExchangeOnline @baseParams -UseWebLogin | Out-Null
      $connected = $true
      Write-Host "  (web browser login succeeded)" -ForegroundColor Gray
    }
    catch {
      # Check whether it's the known broker DLL error; if so, suppress and try next flow
      if ($_.Exception.Message -match 'BrokerExtension' -or $_.Exception.Message -match 'WithBroker') {
        Write-Warning "Flow 1 (-UseWebLogin) triggered broker error, trying next flow..."
      } else {
        Write-Warning "Flow 1 (-UseWebLogin) failed: $_"
      }
      $lastErr = $_
    }
  }

  # --- Flow 2: device-code flow (works headlessly / avoids WAM popup) ---
  if (-not $connected) {
    $deviceParam = $null
    if     ($paramKeys -contains 'Device')                 { $deviceParam = 'Device' }
    elseif ($paramKeys -contains 'UseDeviceAuthentication') { $deviceParam = 'UseDeviceAuthentication' }

    if ($deviceParam) {
      try {
        $deviceParams = $baseParams.Clone()
        $deviceParams[$deviceParam] = $true
        Connect-ExchangeOnline @deviceParams | Out-Null
        $connected = $true
        Write-Host "  (device code login succeeded)" -ForegroundColor Gray
      }
      catch {
        if ($_.Exception.Message -match 'BrokerExtension' -or $_.Exception.Message -match 'WithBroker') {
          Write-Warning "Flow 2 (device code) triggered broker error, trying next flow..."
        } else {
          Write-Warning "Flow 2 (device code) failed: $_"
        }
        $lastErr = $_
      }
    }
  }

  # --- Flow 3: plain interactive (no extra switches, module chooses auth UI) ---
  if (-not $connected) {
    try {
      Connect-ExchangeOnline @baseParams | Out-Null
      $connected = $true
      Write-Host "  (interactive login succeeded)" -ForegroundColor Gray
    }
    catch {
      Write-Warning "Flow 3 (plain interactive) failed: $_"
      $lastErr = $_
    }
  }

  if (-not $connected) {
    throw ("Connect-ExchangeOnline failed after all flows. Last error: $lastErr`n" +
           "Tip: run 'Update-Module ExchangeOnlineManagement' and start a new PS session.")
  }

  Get-EXOMailbox -ResultSize 1 | Out-Null
  Write-Host "Connected to Exchange Online." -ForegroundColor Green
}

# ==============================================================
# SECTION 1/3 - PRINCIPAL CACHE
# ==============================================================

$PrincipalCache = @{}

function Get-PrincipalInfo {
  param(
    [Parameter(Mandatory)][string]$Id,
    [string]$HintType = ""
  )

  if ($PrincipalCache.ContainsKey($Id)) { return $PrincipalCache[$Id] }

  $info = @{
    PrincipalType                = "Unknown"
    PrincipalId                  = $Id
    DisplayName                  = ""
    UPN                          = ""
    Origin                       = "CloudOnly"
    OnPremisesDN                 = ""
    OnPremisesOU                 = ""
    OnPremisesSamAccountName     = ""
    OnPremisesSecurityIdentifier = ""
  }

  $tryOrder = switch ($HintType) {
    "user"  { @("user",  "group", "sp") }
    "group" { @("group", "user",  "sp") }
    "sp"    { @("sp",    "user",  "group") }
    default { @("user",  "group", "sp") }
  }

  foreach ($t in $tryOrder) {
    try {
      switch ($t) {

        "user" {
          $u = Invoke-MgGraphRequest -Method GET -Uri (
            ("/v1.0/users/{0}?`$select=id,displayName,userPrincipalName," +
            "onPremisesSyncEnabled,onPremisesDistinguishedName," +
            "onPremisesSamAccountName,onPremisesSecurityIdentifier") -f $Id
          )
          if ($u) {
            $info.PrincipalType = "User"
            $info.DisplayName   = Coalesce -Value (Get-GraphPropValue $u "displayName") -Fallback ""
            $info.UPN           = Coalesce -Value (Get-GraphPropValue $u "userPrincipalName") -Fallback ""
            $dn   = Get-GraphPropValue $u "onPremisesDistinguishedName"
            $sync = Get-GraphPropValue $u "onPremisesSyncEnabled"
            if ($dn -or $sync -eq $true) {
              $info.Origin                       = "ADSync"
              $info.OnPremisesDN                 = Coalesce -Value $dn -Fallback ""
              $info.OnPremisesOU                 = Get-OuFromDn -DistinguishedName (Coalesce -Value $dn -Fallback "")
              $info.OnPremisesSamAccountName     = Coalesce -Value (Get-GraphPropValue $u "onPremisesSamAccountName") -Fallback ""
              $info.OnPremisesSecurityIdentifier = Coalesce -Value (Get-GraphPropValue $u "onPremisesSecurityIdentifier") -Fallback ""
            }
            $PrincipalCache[$Id] = $info
            return $info
          }
        }

        "group" {
          $g = Invoke-MgGraphRequest -Method GET -Uri (
            ("/v1.0/groups/{0}?`$select=id,displayName,onPremisesSyncEnabled," +
            "onPremisesDistinguishedName,onPremisesSamAccountName,onPremisesSecurityIdentifier") -f $Id
          )
          if ($g) {
            $info.PrincipalType = "Group"
            $info.DisplayName   = Coalesce -Value (Get-GraphPropValue $g "displayName") -Fallback ""
            $dn   = Get-GraphPropValue $g "onPremisesDistinguishedName"
            $sync = Get-GraphPropValue $g "onPremisesSyncEnabled"
            if ($dn -or $sync -eq $true) {
              $info.Origin                       = "ADSync"
              $info.OnPremisesDN                 = Coalesce -Value $dn -Fallback ""
              $info.OnPremisesOU                 = Get-OuFromDn -DistinguishedName (Coalesce -Value $dn -Fallback "")
              $info.OnPremisesSamAccountName     = Coalesce -Value (Get-GraphPropValue $g "onPremisesSamAccountName") -Fallback ""
              $info.OnPremisesSecurityIdentifier = Coalesce -Value (Get-GraphPropValue $g "onPremisesSecurityIdentifier") -Fallback ""
            }
            $PrincipalCache[$Id] = $info
            return $info
          }
        }

        "sp" {
          $sp = Invoke-MgGraphRequest -Method GET -Uri (
            "/v1.0/servicePrincipals/{0}?`$select=id,displayName,appId" -f $Id
          )
          if ($sp) {
            $info.PrincipalType = "ServicePrincipal"
            $info.DisplayName   = Coalesce -Value (Get-GraphPropValue $sp "displayName") -Fallback ""
            $PrincipalCache[$Id] = $info
            return $info
          }
        }
      }
    }
    catch {
      # 404 / ResourceNotFound means the object is deleted — no point trying other types
      if ($_ -match 'ResourceNotFound|does not exist|404') {
        $info.PrincipalType  = "DeletedObject"
        $info.DisplayName    = "(deleted)"
        $PrincipalCache[$Id] = $info
        return $info
      }
      Write-Verbose "Principal lookup ($t) failed for $Id : $_"
    }
  }

  $info.PrincipalType  = "Unknown"
  $PrincipalCache[$Id] = $info
  return $info
}

# ==============================================================
# SECTION 2/3 - AD ENRICHMENT FUNCTIONS
# ==============================================================

# LDAP connection details — only prompted if ldapsearch method is used
$script:LdapServer   = ""
$script:LdapBaseDN   = ""
$script:LdapBindUser = ""

function Prompt-LdapConfig {
  Write-Host ""
  Write-Host "Configure LDAP connection for AD enrichment:" -ForegroundColor Cyan
  $script:LdapServer   = Read-Host "  LDAP server (e.g. dc01.contoso.local)"
  $script:LdapBaseDN   = Read-Host "  Base DN (e.g. DC=contoso,DC=local)"
  $script:LdapBindUser = Read-Host "  Bind user (e.g. user@contoso.local, leave blank for anonymous)"
  Write-Host ""
}

function Get-ADInfoViaLdap {
  param(
    [string]$Filter,
    [string]$ObjectClass
  )

  $ldapArgs = @(
    "-LLL"
    "-x"
    "-H", "ldap://$($script:LdapServer)"
    "-b", $script:LdapBaseDN
  )

  if ($script:LdapBindUser) {
    $ldapArgs += @("-D", $script:LdapBindUser, "-W")
  }

  $ldapArgs += @($Filter, "dn")

  try {
    $result = & ldapsearch @ldapArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }

    foreach ($line in $result) {
      if ($line -match '^dn:\s*(.+)$') {
        return $Matches[1].Trim()
      }
    }
  }
  catch {
    Write-Verbose "ldapsearch failed: $_"
  }
  return $null
}

function Enrich-PrincipalCacheFromAD {
  param([string]$Method = "rsat")

  if ($Method -eq "rsat") {
    Import-Module ActiveDirectory -ErrorAction Stop
  }
  elseif ($Method -eq "ldapsearch") {
    Prompt-LdapConfig
    if (-not $script:LdapServer -or -not $script:LdapBaseDN) {
      Write-Warning "LDAP server or Base DN missing. Skipping AD enrichment."
      return
    }
  }

  $adAttemptCount       = 0
  $adFailCount          = 0
  $consecutiveFailCount = 0
  $throttleWarningShown = $false

  foreach ($id in @($PrincipalCache.Keys)) {
    $p = $PrincipalCache[$id]

    if ($p.PrincipalType -notin @("User","Group")) { continue }
    if ($p.Origin -ne "ADSync")                    { continue }
    if ($p.OnPremisesDN -and $p.OnPremisesOU)      { continue }

    $adAttemptCount++
    try {
      $dn = $null

      if ($Method -eq "rsat") {
        $ad = $null
        if ($p.PrincipalType -eq "User") {
          if ($p.OnPremisesSecurityIdentifier) {
            $ad = Get-ADUser -Identity $p.OnPremisesSecurityIdentifier `
                             -Properties DistinguishedName
          }
          elseif ($p.OnPremisesSamAccountName) {
            $ad = Get-ADUser -Identity $p.OnPremisesSamAccountName `
                             -Properties DistinguishedName
          }
          elseif ($p.UPN) {
            $escapedUpn = $p.UPN -replace "'", "''"
            $ad = Get-ADUser -Filter "UserPrincipalName -eq '$escapedUpn'" `
                             -Properties DistinguishedName
          }
        }
        elseif ($p.PrincipalType -eq "Group") {
          if ($p.OnPremisesSecurityIdentifier) {
            $ad = Get-ADGroup -Identity $p.OnPremisesSecurityIdentifier `
                              -Properties DistinguishedName
          }
          elseif ($p.OnPremisesSamAccountName) {
            $ad = Get-ADGroup -Identity $p.OnPremisesSamAccountName `
                              -Properties DistinguishedName
          }
        }
        if ($ad -and $ad.DistinguishedName) {
          $dn = $ad.DistinguishedName
        }
      }
      elseif ($Method -eq "ldapsearch") {
        $objClass = if ($p.PrincipalType -eq "User") { "user" } else { "group" }
        if ($p.OnPremisesSamAccountName) {
          $dn = Get-ADInfoViaLdap `
            -Filter "(&(objectClass=$objClass)(sAMAccountName=$($p.OnPremisesSamAccountName)))" `
            -ObjectClass $objClass
        }
        elseif ($p.UPN -and $p.PrincipalType -eq "User") {
          $dn = Get-ADInfoViaLdap `
            -Filter "(&(objectClass=user)(userPrincipalName=$($p.UPN)))" `
            -ObjectClass "user"
        }
      }

      if ($dn) {
        $p.OnPremisesDN  = $dn
        $p.OnPremisesOU  = Get-OuFromDn -DistinguishedName $dn
        $PrincipalCache[$id] = $p
      }
      $consecutiveFailCount = 0
    }
    catch {
      $adFailCount++
      $consecutiveFailCount++
      Write-Warning ("AD lookup failed for '{0}' ({1}): {2}" -f
        $p.DisplayName, $p.PrincipalType, $_.Exception.Message)
      if ($consecutiveFailCount -ge 3 -and -not $throttleWarningShown) {
        $throttleWarningShown = $true
        Write-Warning ("AD enrichment: $consecutiveFailCount consecutive lookup failures detected — " +
          "the domain controller may be throttling or rate-limiting requests. " +
          "Remaining principals may not be enriched. " +
          "Consider re-running with only AD enrichment enabled.")
      }
    }
  }

  if ($adFailCount -gt 0) {
    Write-Warning ("AD enrichment summary: $adFailCount of $adAttemptCount principal lookups failed.")
  }
}

function Apply-EnrichedADToRows {
  param(
    [Parameter(Mandatory)]
    [System.Collections.Generic.List[object]]$Rows
  )
  foreach ($r in $Rows) {
    if ($r.Origin -ne "ADSync")           { continue }
    if ($r.OnPremisesDN -and $r.OnPremisesOU) { continue }

    if ($r.PrincipalId -and $PrincipalCache.ContainsKey($r.PrincipalId)) {
      $p = $PrincipalCache[$r.PrincipalId]
      if ($p.OnPremisesDN) { $r.OnPremisesDN = $p.OnPremisesDN }
      if ($p.OnPremisesOU) { $r.OnPremisesOU = $p.OnPremisesOU }
    }
  }
}

# ==============================================================
# SECTION 2/3 - ROW COLLECTION
# ==============================================================

$rows = New-Object System.Collections.Generic.List[object]
$roleDefMap = @{}

# --------------------------------------------------------------
# 1) Directory Role Assignments
# --------------------------------------------------------------
if ($IncludeDirectoryRoles) {
  Write-Host "Retrieving directory role assignments..." -ForegroundColor Cyan

  $roleDefs = Get-GraphPaged `
    -Uri "/v1.0/roleManagement/directory/roleDefinitions?`$select=id,displayName" `
    -Headers $headers

  $roleDefMap = @{}
  foreach ($rd in $roleDefs) {
    $roleDefMap[$rd.id] = $rd.displayName
  }

  $roleAssignments = Get-GraphPaged `
    -Uri "/v1.0/roleManagement/directory/roleAssignments?`$select=id,principalId,roleDefinitionId,directoryScopeId" `
    -Headers $headers

  foreach ($ra in $roleAssignments) {
    $p        = Get-PrincipalInfo -Id $ra.principalId
    $roleName = Coalesce -Value $roleDefMap[$ra.roleDefinitionId] -Fallback $ra.roleDefinitionId
    [void]$rows.Add((New-AssignmentRow `
      -Service          "Entra" `
      -ResourceType     "DirectoryRole" `
      -ResourceId       $ra.roleDefinitionId `
      -ResourceName     $roleName `
      -AssignmentType   "RoleAssignment" `
      -RoleOrPermission $roleName `
      -PrincipalInfo    $p `
      -Details          ("ScopeId={0}" -f $ra.directoryScopeId)
    ))
  }
  Write-Host "  -> $($rows.Count) rows so far." -ForegroundColor Gray
}

# --------------------------------------------------------------
# 2) Enterprise App Role Assignments
# --------------------------------------------------------------
if ($IncludeEnterpriseApps) {
  Write-Host "Retrieving enterprise app role assignments..." -ForegroundColor Cyan
  $countBefore = $rows.Count

  $sps = Get-GraphPaged `
    -Uri "/v1.0/servicePrincipals?`$select=id,displayName" `
    -Headers $headers

  foreach ($sp in $sps) {
    $appRoleMap = @{}
    try {
      $spFull   = Invoke-MgGraphRequest -Method GET -Uri (
        "/v1.0/servicePrincipals/{0}?`$select=id,displayName,appRoles" -f $sp.id
      )
      $appRoles = Get-GraphPropValue -Obj $spFull -Name "appRoles"
      if ($appRoles) {
        foreach ($ar in $appRoles) {
          if ($ar.id -and $ar.value) {
            $appRoleMap[[string]$ar.id] = $ar.value
          }
        }
      }
    } catch {
      Write-Verbose "Failed to read appRoles for SP $($sp.id): $_"
    }

    try {
      $assignedTo = Get-GraphPaged `
        -Uri (("/v1.0/servicePrincipals/{0}/appRoleAssignedTo" +
              "?`$select=id,principalId,principalType,principalDisplayName,appRoleId") -f $sp.id) `
        -Headers $headers

      foreach ($a in $assignedTo) {
        $hint = ""
        if     ($a.principalType -match "User")  { $hint = "user"  }
        elseif ($a.principalType -match "Group") { $hint = "group" }

        $p       = Get-PrincipalInfo -Id $a.principalId -HintType $hint
        $roleVal = if ($a.appRoleId -and $appRoleMap.ContainsKey([string]$a.appRoleId)) {
                     $appRoleMap[[string]$a.appRoleId]
                   } else {
                     [string]$a.appRoleId
                   }

        [void]$rows.Add((New-AssignmentRow `
          -Service          "EnterpriseApp" `
          -ResourceType     "ServicePrincipal" `
          -ResourceId       $sp.id `
          -ResourceName     $sp.displayName `
          -AssignmentType   "AppRoleAssignment" `
          -RoleOrPermission $roleVal `
          -PrincipalInfo    $p `
          -Details          ""
        ))
      }
    } catch {
      Write-Verbose "Failed to read appRoleAssignedTo for SP $($sp.id) ($($sp.displayName)): $_"
    }
  }
  Write-Host "  -> $(($rows.Count - $countBefore)) new rows." -ForegroundColor Gray
}

# --------------------------------------------------------------
# 3) OAuth2 Permission Grants
# --------------------------------------------------------------
if ($IncludeOAuth2Grants) {
  Write-Host "Retrieving OAuth2 permission grants..." -ForegroundColor Cyan
  $countBefore = $rows.Count

  $grants = Get-GraphPaged `
    -Uri "/v1.0/oauth2PermissionGrants?`$select=id,clientId,resourceId,principalId,scope,consentType" `
    -Headers $headers

  foreach ($g in $grants) {
    $client   = Get-PrincipalInfo -Id $g.clientId   -HintType "sp"
    $resource = Get-PrincipalInfo -Id $g.resourceId -HintType "sp"

    if ($g.consentType -eq "AllPrincipals") {
      $tenantPrincipal = @{
        PrincipalType                = "Tenant"
        PrincipalId                  = ""
        DisplayName                  = "AllPrincipals"
        UPN                          = ""
        Origin                       = "N/A"
        OnPremisesDN                 = ""
        OnPremisesOU                 = ""
        OnPremisesSamAccountName     = ""
        OnPremisesSecurityIdentifier = ""
      }
      [void]$rows.Add((New-AssignmentRow `
        -Service          "OAuth2Consent" `
        -ResourceType     "API" `
        -ResourceId       $resource.PrincipalId `
        -ResourceName     $resource.DisplayName `
        -AssignmentType   "AdminConsent" `
        -RoleOrPermission $g.scope `
        -PrincipalInfo    $tenantPrincipal `
        -Details          ("ClientApp={0}" -f $client.DisplayName)
      ))
    }
    else {
      if ($g.principalId) {
        $p = Get-PrincipalInfo -Id $g.principalId -HintType "user"
        [void]$rows.Add((New-AssignmentRow `
          -Service          "OAuth2Consent" `
          -ResourceType     "API" `
          -ResourceId       $resource.PrincipalId `
          -ResourceName     $resource.DisplayName `
          -AssignmentType   "UserConsent" `
          -RoleOrPermission $g.scope `
          -PrincipalInfo    $p `
          -Details          ("ClientApp={0}" -f $client.DisplayName)
        ))
      }
    }
  }
  Write-Host "  -> $(($rows.Count - $countBefore)) new rows." -ForegroundColor Gray
}

# --------------------------------------------------------------
# 4) Teams Memberships
# --------------------------------------------------------------
if ($IncludeTeams) {
  Write-Host "Retrieving Teams memberships..." -ForegroundColor Cyan
  $countBefore = $rows.Count

  $groups = Get-GraphPaged `
    -Uri "/v1.0/groups?`$select=id,displayName,resourceProvisioningOptions&`$top=999" `
    -Headers $headers

  $teams = $groups | Where-Object {
    $_.resourceProvisioningOptions -and
    ($_.resourceProvisioningOptions -contains "Team")
  }

  foreach ($t in $teams) {
    try {
      $members = Get-GraphPaged `
        -Uri ("/v1.0/teams/{0}/members" -f $t.id) `
        -Headers $headers

      foreach ($m in $members) {
        $uid = Get-GraphPropValue -Obj $m -Name "userId"
        if ($uid) {
          $p    = Get-PrincipalInfo -Id $uid -HintType "user"
          $role = "Member"
          $roles = Get-GraphPropValue -Obj $m -Name "roles"
          if ($roles -and ($roles -contains "owner")) { $role = "Owner" }

          [void]$rows.Add((New-AssignmentRow `
            -Service          "Teams" `
            -ResourceType     "Team" `
            -ResourceId       $t.id `
            -ResourceName     $t.displayName `
            -AssignmentType   "TeamMembership" `
            -RoleOrPermission $role `
            -PrincipalInfo    $p `
            -Details          ""
          ))
        }
      }
    }
    catch {
      Write-Warning "Could not retrieve members for team '$($t.displayName)': $_"
    }
  }
  Write-Host "  -> $(($rows.Count - $countBefore)) new rows." -ForegroundColor Gray
}

# --------------------------------------------------------------
# 5) SharePoint + OneDrive Site Permissions
# --------------------------------------------------------------
if ($IncludeSharePointSites -or $IncludeOneDriveSites) {
  Write-Host "Retrieving SharePoint/OneDrive site permissions (may take a while)..." -ForegroundColor Cyan
  $countBefore = $rows.Count

  $sites = $null
  try {
    $sites = Get-GraphPaged `
      -Uri "/beta/sites/getAllSites?`$select=id,displayName,webUrl,siteCollection" `
      -Headers $headers
  }
  catch {
    $statusCode = $null
    try { $statusCode = $_.Exception.Response.StatusCode.value__ } catch {}
    if ($statusCode -eq 403) {
      Write-Warning ("SharePoint: access denied to /beta/sites/getAllSites (HTTP 403). " +
        "The signed-in user must have the SharePoint Administrator or Global Administrator role. " +
        "Skipping SharePoint section.")
      $sites = @()
    } else {
      throw
    }
  }

  $siteCount        = 0
  $sp403Count       = 0   # per-site 403 on SharePoint sites
  $od403Count       = 0   # per-site 403 on OneDrive sites
  $lockedSiteCount  = 0   # per-site 423 (admin-blocked) skips
  foreach ($s in $sites) {
    $webUrl     = Get-GraphPropValue -Obj $s -Name "webUrl"
    $siteName   = Get-GraphPropValue -Obj $s -Name "displayName"
    $isOneDrive = $false

    if ($webUrl -and $webUrl -match "-my\.sharepoint\.com/personal/") {
      $isOneDrive = $true
    }

    if ($isOneDrive -and -not $IncludeOneDriveSites)     { continue }
    if (-not $isOneDrive -and -not $IncludeSharePointSites) { continue }

    $siteCount++
    if ($siteCount % 50 -eq 0) {
      Write-Host "  ... processing site $siteCount / $($sites.Count)" -ForegroundColor Gray
    }

    try {
      $perms = Get-GraphPaged `
        -Uri ("/v1.0/sites/{0}/permissions" -f $s.id) `
        -Headers $headers

      foreach ($p0 in $perms) {
        $roles = Get-GraphPropValue -Obj $p0 -Name "roles"
        if (-not $roles) { $roles = @("") }

        # Try grantedToIdentitiesV2 first (modern), fall back to grantedToV2,
        # then fall back to legacy non-V2 fields for older permission entries
        $identities = Get-GraphPropValue -Obj $p0 -Name "grantedToIdentitiesV2"
        if (-not $identities) {
          # grantedToV2 is a single object, not an array - wrap it
          $grantedToV2 = Get-GraphPropValue -Obj $p0 -Name "grantedToV2"
          if ($grantedToV2) { $identities = @($grantedToV2) }
        }
        # Legacy fallback: some entries (e.g. unlicensed/SharePoint-only users) use old format
        if (-not $identities) {
          $legacyIdentities = Get-GraphPropValue -Obj $p0 -Name "grantedToIdentities"
          if ($legacyIdentities) { $identities = $legacyIdentities }
        }
        if (-not $identities) {
          $legacyGrantedTo = Get-GraphPropValue -Obj $p0 -Name "grantedTo"
          if ($legacyGrantedTo) { $identities = @($legacyGrantedTo) }
        }

        if ($identities) {
          foreach ($g0 in $identities) {
            $u  = Get-GraphPropValue -Obj $g0 -Name "user"
            $gr = Get-GraphPropValue -Obj $g0 -Name "group"
            # siteUser/siteGroup are SharePoint-specific identities used for unlicensed
            # accounts and external/guest users that aren't full Entra ID members
            $su = Get-GraphPropValue -Obj $g0 -Name "siteUser"
            $sg = Get-GraphPropValue -Obj $g0 -Name "siteGroup"
            $ap = Get-GraphPropValue -Obj $g0 -Name "application"

            if ($u -and (Get-GraphPropValue $u "id")) {
              $pi = Get-PrincipalInfo -Id (Get-GraphPropValue $u "id") -HintType "user"
              foreach ($r in $roles) {
                [void]$rows.Add((New-AssignmentRow `
                  -Service          "SharePoint" `
                  -ResourceType     $(if ($isOneDrive) { "OneDrive" } else { "Site" }) `
                  -ResourceId       $s.id `
                  -ResourceName     $siteName `
                  -AssignmentType   "SitePermission" `
                  -RoleOrPermission $r `
                  -PrincipalInfo    $pi `
                  -Details          $webUrl
                ))
              }
            }
            elseif ($gr -and (Get-GraphPropValue $gr "id")) {
              $pi = Get-PrincipalInfo -Id (Get-GraphPropValue $gr "id") -HintType "group"
              foreach ($r in $roles) {
                [void]$rows.Add((New-AssignmentRow `
                  -Service          "SharePoint" `
                  -ResourceType     $(if ($isOneDrive) { "OneDrive" } else { "Site" }) `
                  -ResourceId       $s.id `
                  -ResourceName     $siteName `
                  -AssignmentType   "SitePermission" `
                  -RoleOrPermission $r `
                  -PrincipalInfo    $pi `
                  -Details          $webUrl
                ))
              }
            }
            else {
              # No Entra ID user/group with a GUID — check SharePoint-specific fields
              # (siteUser/siteGroup = unlicensed/external/SharePoint-only accounts)
              $specialName = ""
              $specialUpn  = ""
              $specialType = "Special"

              if ($su) {
                $specialType = "SPUser"
                $specialName = Coalesce -Value (Get-GraphPropValue $su "displayName") -Fallback ""
                # loginName format: "i:0#.f|membership|user@domain.com" — extract UPN
                $ln = Get-GraphPropValue $su "loginName"
                if ($ln -and $ln -match '\|(.+@.+)$') { $specialUpn = $Matches[1] }
                if (-not $specialName) { $specialName = $specialUpn }
                if (-not $specialName) { $specialName = $ln }
              }
              elseif ($sg) {
                $specialType = "SPGroup"
                $specialName = Coalesce -Value (Get-GraphPropValue $sg "displayName") -Fallback ""
              }
              elseif ($ap) {
                $specialType = "Application"
                $specialName = Coalesce -Value (Get-GraphPropValue $ap "displayName") -Fallback ""
              }
              # Legacy fields (non-V2 format)
              if (-not $specialName -and $u)  { $specialName = Coalesce -Value (Get-GraphPropValue $u  "displayName") -Fallback "" }
              if (-not $specialName -and $gr) { $specialName = Coalesce -Value (Get-GraphPropValue $gr "displayName") -Fallback "" }
              if (-not $specialName) { $specialName = "UnresolvedPrincipal" }

              $pi = @{
                PrincipalType                = $specialType
                PrincipalId                  = ""
                DisplayName                  = $specialName
                UPN                          = $specialUpn
                Origin                       = "N/A"
                OnPremisesDN                 = ""
                OnPremisesOU                 = ""
                OnPremisesSamAccountName     = ""
                OnPremisesSecurityIdentifier = ""
              }
              foreach ($r in $roles) {
                [void]$rows.Add((New-AssignmentRow `
                  -Service          "SharePoint" `
                  -ResourceType     $(if ($isOneDrive) { "OneDrive" } else { "Site" }) `
                  -ResourceId       $s.id `
                  -ResourceName     $siteName `
                  -AssignmentType   "SitePermission" `
                  -RoleOrPermission $r `
                  -PrincipalInfo    $pi `
                  -Details          $webUrl
                ))
              }
            }
          }
        }
      }
      # For personal OneDrive sites, /sites/{id}/permissions only returns explicit sharing
      # grants — not the implicit site owner. Fetch the drive owner and add a SiteOwner row.
      if ($isOneDrive) {
        try {
          $driveResp  = Invoke-MgGraphRequest -Method GET `
            -Uri ("/v1.0/sites/{0}/drive?`$select=owner" -f $s.id)
          $driveOwner = Get-GraphPropValue $driveResp "owner"
          $ownerUser  = if ($driveOwner) { Get-GraphPropValue $driveOwner "user" } else { $null }
          $ownerId    = if ($ownerUser)  { Get-GraphPropValue $ownerUser  "id"   } else { $null }
          if ($ownerId) {
            $pi = Get-PrincipalInfo -Id $ownerId -HintType "user"
            [void]$rows.Add((New-AssignmentRow `
              -Service          "SharePoint" `
              -ResourceType     "OneDrive" `
              -ResourceId       $s.id `
              -ResourceName     $siteName `
              -AssignmentType   "SiteOwner" `
              -RoleOrPermission "owner" `
              -PrincipalInfo    $pi `
              -Details          $webUrl
            ))
          }
        }
        catch {
          Write-Verbose "Could not retrieve drive owner for '$siteName' ($webUrl): $_"
        }
      }
    }
    catch {
      $sc = $null
      try { $sc = $_.Exception.Response.StatusCode.value__ } catch {}
      if ($sc -eq 403) {
        if ($isOneDrive) { $od403Count++ } else { $sp403Count++ }
      } elseif ($sc -eq 423 -or $_ -match 'resourceLocked') {
        $lockedSiteCount++   # site is admin-locked — skip silently, summarise after loop
      } else {
        Write-Warning "Could not retrieve permissions for site '$siteName' ($webUrl): $_"
      }
    }
  }
  # Post-loop 403 summary — distinguish between "a few classic/archived sites" (normal)
  # and "everything failed" which indicates a missing permission
  $permMissingMsg = @"

  The app registration may be missing 'Sites.Manage.All' (Application permission).
  Steps to fix in the Azure portal:
    1. App registrations -> your app -> API permissions
    2. Add: Microsoft Graph -> Application permissions -> Sites.Manage.All
    3. Click 'Grant admin consent'
"@
  if ($sp403Count -gt 0) {
    $spTotal = @($sites | Where-Object { (Get-GraphPropValue $_ 'webUrl') -notmatch '-my\.sharepoint\.com/personal/' }).Count
    if ($sp403Count -ge [Math]::Max(5, [int]($spTotal * 0.5))) {
      Write-Warning ("SharePoint: $sp403Count of $spTotal sites returned 403 (access denied)." + $permMissingMsg)
    } else {
      Write-Host "  · $sp403Count SharePoint site(s) skipped (HTTP 403 — classic/archived sites, expected)." -ForegroundColor DarkYellow
    }
  }
  if ($od403Count -gt 0) {
    $odTotal = @($sites | Where-Object { (Get-GraphPropValue $_ 'webUrl') -match '-my\.sharepoint\.com/personal/' }).Count
    if ($od403Count -ge [Math]::Max(5, [int]($odTotal * 0.5))) {
      Write-Warning ("OneDrive: $od403Count of $odTotal sites returned 403 (access denied)." + $permMissingMsg)
    } else {
      Write-Host "  · $od403Count OneDrive site(s) skipped (HTTP 403 — unlicensed/archived sites, expected)." -ForegroundColor DarkYellow
    }
  }
  if ($lockedSiteCount -gt 0) {
    Write-Host "  · Skipped $lockedSiteCount site(s) locked by admin (HTTP 423 - access blocked by SharePoint admin)." -ForegroundColor DarkYellow
  }
  Write-Host "  -> $(($rows.Count - $countBefore)) new rows from $siteCount sites." -ForegroundColor Gray
}

# --------------------------------------------------------------
# 6) Exchange Mailbox Permissions
# --------------------------------------------------------------
if ($IncludeExchange) {
  Write-Host "Retrieving Exchange mailbox permissions (may take a while)..." -ForegroundColor Cyan
  $countBefore = $rows.Count

  # Helper: try to resolve an EXO identity string to a Graph principal
  function Resolve-ExoIdentity {
    param([string]$RawIdentity)
    $pi = @{
      PrincipalType                = "ExchangeIdentity"
      PrincipalId                  = ""
      DisplayName                  = $RawIdentity
      UPN                          = if ($RawIdentity -match "@") { $RawIdentity } else { "" }
      Origin                       = "Unknown"
      OnPremisesDN                 = ""
      OnPremisesOU                 = ""
      OnPremisesSamAccountName     = ""
      OnPremisesSecurityIdentifier = ""
    }
    if ($pi.UPN) {
      try {
        $escapedUpn = $pi.UPN -replace "'", "''"
        $found = Get-GraphPaged `
          -Uri (("/v1.0/users?`$select=id,displayName,userPrincipalName," +
                "onPremisesSyncEnabled,onPremisesDistinguishedName" +
                "&`$filter=userPrincipalName eq '{0}'") -f $escapedUpn) `
          -Headers $headers
        if ($found.Count -gt 0) {
          return Get-PrincipalInfo -Id $found[0].id -HintType "user"
        }
      } catch {
        Write-Verbose "Resolve-ExoIdentity lookup failed for '$RawIdentity': $_"
      }
    }
    return $pi
  }

  $mailboxes = @(Get-EXOMailbox `
    -ResultSize Unlimited `
    -RecipientTypeDetails UserMailbox,SharedMailbox `
    -PropertySets Minimum,AddressList)

  $mbCount = 0
  foreach ($mb in $mailboxes) {
    $mbCount++
    if ($mbCount % 100 -eq 0) {
      Write-Host "  ... processing mailbox $mbCount / $($mailboxes.Count)" -ForegroundColor Gray
    }

    # --- FullAccess ---
    try {
      $faPerms = Get-EXOMailboxPermission -Identity $mb.Identity -ErrorAction SilentlyContinue |
        Where-Object {
          $_.User -ne "NT AUTHORITY\SELF" -and
          (([string]$_.AccessRights) -match "FullAccess")
        }

      foreach ($e in $faPerms) {
        $pi = Resolve-ExoIdentity -RawIdentity ([string]$e.User)
        [void]$rows.Add((New-AssignmentRow `
          -Service          "Exchange" `
          -ResourceType     "Mailbox" `
          -ResourceId       $mb.ExternalDirectoryObjectId `
          -ResourceName     $mb.PrimarySmtpAddress `
          -AssignmentType   "MailboxPermission" `
          -RoleOrPermission "FullAccess" `
          -PrincipalInfo    $pi `
          -Details          ""
        ))
      }
    } catch {
      Write-Warning "FullAccess error for $($mb.PrimarySmtpAddress): $_"
    }

    # --- SendAs ---
    try {
      $saPerms = Get-EXORecipientPermission -Identity $mb.Identity -ErrorAction SilentlyContinue |
        Where-Object {
          $_.Trustee -and
          (([string]$_.AccessRights) -match "SendAs") -and
          $_.Trustee -ne "NT AUTHORITY\SELF"
        }

      foreach ($e in $saPerms) {
        $pi = Resolve-ExoIdentity -RawIdentity ([string]$e.Trustee)
        [void]$rows.Add((New-AssignmentRow `
          -Service          "Exchange" `
          -ResourceType     "Mailbox" `
          -ResourceId       $mb.ExternalDirectoryObjectId `
          -ResourceName     $mb.PrimarySmtpAddress `
          -AssignmentType   "RecipientPermission" `
          -RoleOrPermission "SendAs" `
          -PrincipalInfo    $pi `
          -Details          ""
        ))
      }
    } catch {
      Write-Warning "SendAs error for $($mb.PrimarySmtpAddress): $_"
    }

    # --- SendOnBehalf ---
    try {
      $sobMailbox = Get-Mailbox -Identity $mb.Identity -ErrorAction SilentlyContinue
      if ($sobMailbox -and $sobMailbox.GrantSendOnBehalfTo) {
        foreach ($delegate in $sobMailbox.GrantSendOnBehalfTo) {
          $raw = [string]$delegate
          $pi  = Resolve-ExoIdentity -RawIdentity $raw
          [void]$rows.Add((New-AssignmentRow `
            -Service          "Exchange" `
            -ResourceType     "Mailbox" `
            -ResourceId       $mb.ExternalDirectoryObjectId `
            -ResourceName     $mb.PrimarySmtpAddress `
            -AssignmentType   "SendOnBehalf" `
            -RoleOrPermission "SendOnBehalf" `
            -PrincipalInfo    $pi `
            -Details          ""
          ))
        }
      }
    } catch {
      Write-Warning "SendOnBehalf error for $($mb.PrimarySmtpAddress): $_"
    }
  }
  Write-Host "  -> $(($rows.Count - $countBefore)) new rows from $mbCount mailboxes." -ForegroundColor Gray
}

# --------------------------------------------------------------
# 7) Distribution Groups & Mail-enabled Security Groups
# --------------------------------------------------------------
if ($IncludeDistGroups) {
  Write-Host "Retrieving distribution groups and mail-enabled security groups..." -ForegroundColor Cyan
  $countBefore = $rows.Count

  # Get all mail-enabled groups (distribution lists + mail-enabled security groups)
  # Exclude Unified (M365) groups — those are covered by Teams/SharePoint
  $mailGroups = $null
  try {
    $mailGroups = Get-GraphPaged `
      -Uri "/v1.0/groups?`$filter=mailEnabled eq true and NOT groupTypes/any(c:c eq 'Unified')&`$select=id,displayName,mail,mailEnabled,securityEnabled,onPremisesSyncEnabled,onPremisesDistinguishedName,onPremisesSamAccountName,onPremisesSecurityIdentifier,groupTypes&`$top=999" `
      -Headers $headers
  } catch {
    Write-Warning "Complex group filter not supported, retrieving all mail-enabled groups and filtering locally..."
    $allMailGroups = Get-GraphPaged `
      -Uri "/v1.0/groups?`$filter=mailEnabled eq true&`$select=id,displayName,mail,mailEnabled,securityEnabled,onPremisesSyncEnabled,onPremisesDistinguishedName,onPremisesSamAccountName,onPremisesSecurityIdentifier,groupTypes&`$top=999" `
      -Headers $headers
    $mailGroups = @($allMailGroups | Where-Object {
      $gt = Get-GraphPropValue -Obj $_ -Name "groupTypes"
      -not ($gt -and ($gt -contains "Unified"))
    })
  }

  if ($null -eq $mailGroups) {
    $mailGroups = @()
  }

  $dgCount = 0
  foreach ($dg in $mailGroups) {
    $dgCount++
    if ($dgCount % 50 -eq 0) {
      Write-Host "  ... processing group $dgCount / $($mailGroups.Count)" -ForegroundColor Gray
    }

    $groupTypes = Get-GraphPropValue -Obj $dg -Name "groupTypes"
    # Skip Unified (M365) groups if they slipped through
    if ($groupTypes -and ($groupTypes -contains "Unified")) { continue }

    $secEnabled  = Get-GraphPropValue -Obj $dg -Name "securityEnabled"
    $resourceType = if ($secEnabled -eq $true) { "MailSecurityGroup" } else { "DistributionGroup" }

    # Ensure this group is in the principal cache
    $groupPrincipal = Get-PrincipalInfo -Id $dg.id -HintType "group"

    # Get group members
    try {
      $members = Get-GraphPaged `
        -Uri ("/v1.0/groups/{0}/members?`$select=id,displayName,userPrincipalName,mail" -f $dg.id) `
        -Headers $headers

      foreach ($m in $members) {
        $memberId = Get-GraphPropValue -Obj $m -Name "id"
        if (-not $memberId) { continue }

        $odataType = Get-GraphPropValue -Obj $m -Name "@odata.type"
        $hint = if ($odataType -match "user") { "user" }
                elseif ($odataType -match "group") { "group" }
                else { "" }

        $pi = Get-PrincipalInfo -Id $memberId -HintType $hint

        [void]$rows.Add((New-AssignmentRow `
          -Service          "Exchange" `
          -ResourceType     $resourceType `
          -ResourceId       $dg.id `
          -ResourceName     (Coalesce -Value (Get-GraphPropValue $dg "mail") -Fallback (Get-GraphPropValue $dg "displayName")) `
          -AssignmentType   "GroupMembership" `
          -RoleOrPermission "Member" `
          -PrincipalInfo    $pi `
          -Details          ("GroupSyncStatus={0}" -f $groupPrincipal.Origin)
        ))
      }
    }
    catch {
      Write-Warning "Could not retrieve members for group '$($dg.displayName)': $_"
    }

    # Get group owners
    try {
      $owners = Get-GraphPaged `
        -Uri ("/v1.0/groups/{0}/owners?`$select=id,displayName,userPrincipalName" -f $dg.id) `
        -Headers $headers

      foreach ($o in $owners) {
        $ownerId = Get-GraphPropValue -Obj $o -Name "id"
        if (-not $ownerId) { continue }

        $pi = Get-PrincipalInfo -Id $ownerId -HintType "user"

        [void]$rows.Add((New-AssignmentRow `
          -Service          "Exchange" `
          -ResourceType     $resourceType `
          -ResourceId       $dg.id `
          -ResourceName     (Coalesce -Value (Get-GraphPropValue $dg "mail") -Fallback (Get-GraphPropValue $dg "displayName")) `
          -AssignmentType   "GroupOwnership" `
          -RoleOrPermission "Owner" `
          -PrincipalInfo    $pi `
          -Details          ("GroupSyncStatus={0}" -f $groupPrincipal.Origin)
        ))
      }
    }
    catch {
      Write-Verbose "No owners for group '$($dg.displayName)': $_"
    }
  }
  Write-Host "  -> $(($rows.Count - $countBefore)) new rows from $dgCount groups." -ForegroundColor Gray
}

# --------------------------------------------------------------
# 8) Conditional Access Policy Assignments
# --------------------------------------------------------------
if ($IncludeCondAccess) {
  Write-Host "Retrieving Conditional Access policies..." -ForegroundColor Cyan
  $countBefore = $rows.Count

  try {
    $caPolicies = Get-GraphPaged `
      -Uri "/v1.0/identity/conditionalAccess/policies?`$select=id,displayName,state,conditions" `
      -Headers $headers

    foreach ($ca in $caPolicies) {
      $policyName  = Coalesce -Value (Get-GraphPropValue $ca "displayName") -Fallback $ca.id
      $policyState = Coalesce -Value (Get-GraphPropValue $ca "state") -Fallback "unknown"
      $conditions  = Get-GraphPropValue -Obj $ca -Name "conditions"
      if (-not $conditions) { continue }

      $users = Get-GraphPropValue -Obj $conditions -Name "users"
      if (-not $users) { continue }

      # Process included users
      $includeUsers = Get-GraphPropValue -Obj $users -Name "includeUsers"
      if ($includeUsers) {
        foreach ($uid in $includeUsers) {
          if ($uid -eq "All" -or $uid -eq "GuestsOrExternalUsers" -or $uid -eq "None") {
            $pi = @{
              PrincipalType = "Special"; PrincipalId = ""; DisplayName = $uid; UPN = ""
              Origin = "N/A"; OnPremisesDN = ""; OnPremisesOU = ""
              OnPremisesSamAccountName = ""; OnPremisesSecurityIdentifier = ""
            }
          } else {
            $pi = Get-PrincipalInfo -Id $uid -HintType "user"
          }
          [void]$rows.Add((New-AssignmentRow `
            -Service          "ConditionalAccess" `
            -ResourceType     "Policy" `
            -ResourceId       $ca.id `
            -ResourceName     $policyName `
            -AssignmentType   "IncludeUser" `
            -RoleOrPermission "Include" `
            -PrincipalInfo    $pi `
            -Details          ("PolicyState={0}" -f $policyState)
          ))
        }
      }

      # Process excluded users
      $excludeUsers = Get-GraphPropValue -Obj $users -Name "excludeUsers"
      if ($excludeUsers) {
        foreach ($uid in $excludeUsers) {
          if ($uid -eq "GuestsOrExternalUsers") {
            $pi = @{
              PrincipalType = "Special"; PrincipalId = ""; DisplayName = $uid; UPN = ""
              Origin = "N/A"; OnPremisesDN = ""; OnPremisesOU = ""
              OnPremisesSamAccountName = ""; OnPremisesSecurityIdentifier = ""
            }
          } else {
            $pi = Get-PrincipalInfo -Id $uid -HintType "user"
          }
          [void]$rows.Add((New-AssignmentRow `
            -Service          "ConditionalAccess" `
            -ResourceType     "Policy" `
            -ResourceId       $ca.id `
            -ResourceName     $policyName `
            -AssignmentType   "ExcludeUser" `
            -RoleOrPermission "Exclude" `
            -PrincipalInfo    $pi `
            -Details          ("PolicyState={0}" -f $policyState)
          ))
        }
      }

      # Process included groups
      $includeGroups = Get-GraphPropValue -Obj $users -Name "includeGroups"
      if ($includeGroups) {
        foreach ($gid in $includeGroups) {
          if ($gid -eq "All") {
            $pi = @{
              PrincipalType = "Special"; PrincipalId = ""; DisplayName = "AllGroups"; UPN = ""
              Origin = "N/A"; OnPremisesDN = ""; OnPremisesOU = ""
              OnPremisesSamAccountName = ""; OnPremisesSecurityIdentifier = ""
            }
          } else {
            $pi = Get-PrincipalInfo -Id $gid -HintType "group"
          }
          [void]$rows.Add((New-AssignmentRow `
            -Service          "ConditionalAccess" `
            -ResourceType     "Policy" `
            -ResourceId       $ca.id `
            -ResourceName     $policyName `
            -AssignmentType   "IncludeGroup" `
            -RoleOrPermission "Include" `
            -PrincipalInfo    $pi `
            -Details          ("PolicyState={0}" -f $policyState)
          ))
        }
      }

      # Process excluded groups
      $excludeGroups = Get-GraphPropValue -Obj $users -Name "excludeGroups"
      if ($excludeGroups) {
        foreach ($gid in $excludeGroups) {
          $pi = Get-PrincipalInfo -Id $gid -HintType "group"
          [void]$rows.Add((New-AssignmentRow `
            -Service          "ConditionalAccess" `
            -ResourceType     "Policy" `
            -ResourceId       $ca.id `
            -ResourceName     $policyName `
            -AssignmentType   "ExcludeGroup" `
            -RoleOrPermission "Exclude" `
            -PrincipalInfo    $pi `
            -Details          ("PolicyState={0}" -f $policyState)
          ))
        }
      }
    }
  }
  catch {
    $statusCode = $null
    try { $statusCode = $_.Exception.Response.StatusCode.value__ } catch {}
    if ($statusCode -eq 403) {
      Write-Warning ("Conditional Access: access denied (HTTP 403). " +
        "Requires Policy.Read.All permission. Skipping section.")
    } else {
      Write-Warning "Conditional Access retrieval failed: $_"
    }
  }
  Write-Host "  -> $(($rows.Count - $countBefore)) new rows from CA policies." -ForegroundColor Gray
}

# --------------------------------------------------------------
# 9) PIM Role Assignments (Eligible + Active)
# --------------------------------------------------------------
$pimDetailRows = New-Object System.Collections.Generic.List[object]

if ($IncludePIMEligible) {
  Write-Host "Retrieving PIM role assignments (eligible + active)..." -ForegroundColor Cyan
  $countBefore = $rows.Count

  # Reuse role definitions from section 1, or fetch if not already loaded
  if (-not $roleDefMap -or $roleDefMap.Count -eq 0) {
    $roleDefMap = @{}
    try {
      $roleDefs = Get-GraphPaged `
        -Uri "/v1.0/roleManagement/directory/roleDefinitions?`$select=id,displayName" `
        -Headers $headers
      foreach ($rd in $roleDefs) {
        $roleDefMap[$rd.id] = $rd.displayName
      }
    } catch {
      Write-Warning "Could not retrieve role definitions for PIM: $_"
    }
  }

  # --- Eligible assignments ---
  try {
    $eligibleAssignments = Get-GraphPaged `
      -Uri "/v1.0/roleManagement/directory/roleEligibilityScheduleInstances?`$select=id,principalId,roleDefinitionId,directoryScopeId,startDateTime,endDateTime,memberType" `
      -Headers $headers

    foreach ($ea in $eligibleAssignments) {
      $p          = Get-PrincipalInfo -Id $ea.principalId
      $roleName   = Coalesce -Value $roleDefMap[$ea.roleDefinitionId] -Fallback $ea.roleDefinitionId
      $startDt    = Coalesce -Value (Get-GraphPropValue $ea "startDateTime") -Fallback ""
      $endDt      = Coalesce -Value (Get-GraphPropValue $ea "endDateTime") -Fallback ""
      $endDtDisp  = if ($endDt) { $endDt } else { "permanent" }
      $scopeId    = Coalesce -Value (Get-GraphPropValue $ea "directoryScopeId") -Fallback ""
      $memberType = Coalesce -Value (Get-GraphPropValue $ea "memberType") -Fallback ""
      $status     = Coalesce -Value (Get-GraphPropValue $ea "status") -Fallback ""

      # Keep main row (backward compat)
      [void]$rows.Add((New-AssignmentRow `
        -Service          "Entra" `
        -ResourceType     "DirectoryRole" `
        -ResourceId       $ea.roleDefinitionId `
        -ResourceName     $roleName `
        -AssignmentType   "EligibleRoleAssignment" `
        -RoleOrPermission $roleName `
        -PrincipalInfo    $p `
        -Details          ("ScopeId={0}; Eligible={1} to {2}" -f $scopeId, $startDt, $endDtDisp)
      ))

      # Rich PIM detail row
      [void]$pimDetailRows.Add([pscustomobject]@{
        AssignmentCategory = "Eligible"
        AssignmentType     = "Eligible"
        IsPermanent        = if (-not $endDt) { "Yes" } else { "No" }
        StartDateTime      = $startDt
        EndDateTime        = $endDtDisp
        Status             = $status
        MemberType         = $memberType
        ScopeId            = $scopeId
        ScopeType          = if ($scopeId -eq "/") { "Tenant" } else { "AdministrativeUnit" }
        RoleDefinitionId   = $ea.roleDefinitionId
        RoleName           = $roleName
        PrincipalId        = $p.PrincipalId
        PrincipalType      = $p.PrincipalType
        DisplayName        = $p.DisplayName
        UPN                = $p.UPN
        Origin             = $p.Origin
        OnPremisesDN       = $p.OnPremisesDN
        OnPremisesOU       = $p.OnPremisesOU
      })
    }
  }
  catch {
    $statusCode = $null
    try { $statusCode = $_.Exception.Response.StatusCode.value__ } catch {}
    if ($statusCode -eq 403) {
      Write-Warning ("PIM Eligible: access denied (HTTP 403). " +
        "Requires RoleEligibilitySchedule.Read.Directory permission. Skipping eligible assignments.")
    } elseif ($statusCode -eq 400) {
      $errMsg = $_.Exception.Message
      if ($errMsg -match 'OData|property named|Parsing') {
        Write-Warning ("PIM Eligible: Graph rejected the query (OData field error): $errMsg")
      } else {
        Write-Warning ("PIM Eligible: API returned 400. " +
          "Entra ID P2 license may be required for PIM. Skipping eligible assignments.")
      }
    } else {
      Write-Warning "PIM eligible assignment retrieval failed: $_"
    }
  }

  # --- Active (assigned / activated) assignments ---
  try {
    $activeAssignments = Get-GraphPaged `
      -Uri "/v1.0/roleManagement/directory/roleAssignmentScheduleInstances?`$select=id,principalId,roleDefinitionId,directoryScopeId,startDateTime,endDateTime,assignmentType,memberType" `
      -Headers $headers

    foreach ($aa in $activeAssignments) {
      $p          = Get-PrincipalInfo -Id $aa.principalId
      $roleName   = Coalesce -Value $roleDefMap[$aa.roleDefinitionId] -Fallback $aa.roleDefinitionId
      $startDt    = Coalesce -Value (Get-GraphPropValue $aa "startDateTime") -Fallback ""
      $endDt      = Coalesce -Value (Get-GraphPropValue $aa "endDateTime") -Fallback ""
      $endDtDisp  = if ($endDt) { $endDt } else { "permanent" }
      $scopeId    = Coalesce -Value (Get-GraphPropValue $aa "directoryScopeId") -Fallback ""
      $assignType = Coalesce -Value (Get-GraphPropValue $aa "assignmentType") -Fallback ""
      $memberType = Coalesce -Value (Get-GraphPropValue $aa "memberType") -Fallback ""
      $status     = Coalesce -Value (Get-GraphPropValue $aa "status") -Fallback ""

      [void]$pimDetailRows.Add([pscustomobject]@{
        AssignmentCategory = "Active"
        AssignmentType     = $assignType
        IsPermanent        = if (-not $endDt) { "Yes" } else { "No" }
        StartDateTime      = $startDt
        EndDateTime        = $endDtDisp
        Status             = $status
        MemberType         = $memberType
        ScopeId            = $scopeId
        ScopeType          = if ($scopeId -eq "/") { "Tenant" } else { "AdministrativeUnit" }
        RoleDefinitionId   = $aa.roleDefinitionId
        RoleName           = $roleName
        PrincipalId        = $p.PrincipalId
        PrincipalType      = $p.PrincipalType
        DisplayName        = $p.DisplayName
        UPN                = $p.UPN
        Origin             = $p.Origin
        OnPremisesDN       = $p.OnPremisesDN
        OnPremisesOU       = $p.OnPremisesOU
      })
    }
  }
  catch {
    $statusCode = $null
    try { $statusCode = $_.Exception.Response.StatusCode.value__ } catch {}
    if ($statusCode -eq 403) {
      Write-Warning ("PIM Active: access denied (HTTP 403). " +
        "Requires RoleManagement.Read.Directory permission. Skipping active assignments.")
    } elseif ($statusCode -eq 400) {
      $errMsg = $_.Exception.Message
      if ($errMsg -match 'OData|property named|Parsing') {
        Write-Warning ("PIM Active: Graph rejected the query (OData field error): $errMsg")
      } else {
        Write-Warning ("PIM Active: API returned 400. " +
          "Entra ID P2 license may be required for PIM. Skipping active assignments.")
      }
    } else {
      Write-Warning "PIM active assignment retrieval failed: $_"
    }
  }

  Write-Host "  -> $(($rows.Count - $countBefore)) new rows from PIM eligible." -ForegroundColor Gray
  Write-Host "  -> $($pimDetailRows.Count) total PIM detail rows (eligible + active)." -ForegroundColor Gray
}

# ==============================================================
# SECTION 3/3 - AD CROSSCHECK (OPTIONAL)
# ==============================================================

if ($IncludeADCrosscheck) {
  Write-Host "Enriching ADSync accounts with OU from on-prem AD ($ADMethod)..." -ForegroundColor Cyan
  try {
    Enrich-PrincipalCacheFromAD -Method $ADMethod
    Apply-EnrichedADToRows -Rows $rows
    Write-Host "  -> AD enrichment complete." -ForegroundColor Gray
  }
  catch {
    Write-Warning "AD enrichment failed: $_. Continuing with export."
  }
}

# ==============================================================
# SECTION 3/3 - SYNC ANALYSIS
# ==============================================================

Write-Host "Building sync analysis from Entra data..." -ForegroundColor Cyan

# Pre-compute per-principal permission stats from $rows
$permsByPrincipal = @{}
$privilegedPrincipals = [System.Collections.Generic.HashSet[string]]::new()

foreach ($r in $rows) {
  $princId = $r.PrincipalId
  if (-not $princId) { continue }

  if (-not $permsByPrincipal.ContainsKey($princId)) {
    $permsByPrincipal[$princId] = @{ Count = 0; Services = [System.Collections.Generic.HashSet[string]]::new(); ServiceCounts = @{} }
  }
  $permsByPrincipal[$princId].Count++
  [void]$permsByPrincipal[$princId].Services.Add($r.Service)
  if (-not $permsByPrincipal[$princId].ServiceCounts.ContainsKey($r.Service)) {
    $permsByPrincipal[$princId].ServiceCounts[$r.Service] = 0
  }
  $permsByPrincipal[$princId].ServiceCounts[$r.Service]++

  # Track principals with privileged directory roles (active or PIM eligible)
  if ($r.Service -eq "Entra" -and $r.ResourceType -eq "DirectoryRole") {
    [void]$privilegedPrincipals.Add($princId)
  }
  # Track principals referenced in Conditional Access policies
  if ($r.Service -eq "ConditionalAccess") {
    [void]$privilegedPrincipals.Add($princId)
  }
}

$syncAnalysisRows = New-Object System.Collections.Generic.List[object]

# Pre-compute CA and PIM flags per principal
$caPrincipals  = [System.Collections.Generic.HashSet[string]]::new()
$pimPrincipals = [System.Collections.Generic.HashSet[string]]::new()
foreach ($r in $rows) {
  if (-not $r.PrincipalId) { continue }
  if ($r.Service -eq "ConditionalAccess") { [void]$caPrincipals.Add($r.PrincipalId) }
  if ($r.Service -eq "Entra" -and $r.AssignmentType -eq "EligibleRoleAssignment") { [void]$pimPrincipals.Add($r.PrincipalId) }
}

foreach ($id in @($PrincipalCache.Keys)) {
  $p = $PrincipalCache[$id]

  # Only analyze users and groups
  if ($p.PrincipalType -notin @("User", "Group")) { continue }

  $hasPerms      = $permsByPrincipal.ContainsKey($id)
  $hasPrivileged = $privilegedPrincipals.Contains($id)
  $inCA          = $caPrincipals.Contains($id)
  $hasPIM        = $pimPrincipals.Contains($id)

  $recommendation = if ($p.Origin -eq "ADSync" -and $hasPerms) {
    "Already synced"
  } elseif ($p.Origin -eq "CloudOnly" -and $hasPrivileged) {
    "Consider syncing"
  } elseif ($p.Origin -eq "ADSync" -and -not $hasPerms) {
    "Review sync need"
  } else {
    "Cloud-only (OK)"
  }

  # Override: if synced with no direct permissions but IS in a CA policy, keep syncing
  if ($recommendation -eq "Review sync need" -and $inCA) {
    $recommendation = "Keep synced (CA policy)"
  }

  $baseProps = @{
    PrincipalType      = $p.PrincipalType
    PrincipalId        = $p.PrincipalId
    DisplayName        = $p.DisplayName
    UPN                = $p.UPN
    Origin             = $p.Origin
    OnPremisesDN       = $p.OnPremisesDN
    OnPremisesOU       = $p.OnPremisesOU
    HasM365Permissions = if ($hasPerms) { "Yes" } else { "No" }
    HasPrivilegedRole  = if ($hasPrivileged) { "Yes" } else { "No" }
    InCAPolicy         = if ($inCA) { "Yes" } else { "No" }
    HasPIMEligible     = if ($hasPIM) { "Yes" } else { "No" }
    SyncRecommendation = $recommendation
  }

  if ($hasPerms) {
    # One row per service so each service lands on its own line
    foreach ($svc in ($permsByPrincipal[$id].ServiceCounts.Keys | Sort-Object)) {
      [void]$syncAnalysisRows.Add([pscustomobject]($baseProps + @{
        Service         = $svc
        PermissionCount = $permsByPrincipal[$id].ServiceCounts[$svc]
      }))
    }
  } else {
    [void]$syncAnalysisRows.Add([pscustomobject]($baseProps + @{
      Service         = ""
      PermissionCount = 0
    }))
  }
}

# Sort: actionable items first, then by principal name and service
$syncAnalysisRows = [System.Collections.Generic.List[object]]@(
  $syncAnalysisRows | Sort-Object @{Expression={
    switch ($_.SyncRecommendation) {
      "Consider syncing"      { 1 }
      "Review sync need"      { 2 }
      "Keep synced (CA policy)" { 3 }
      "Already synced"        { 4 }
      "Cloud-only (OK)"       { 5 }
      default                 { 6 }
    }
  }}, DisplayName, Service
)

# Count unique principals per category (each principal may appear once per service)
$syncedCount          = @($syncAnalysisRows | Group-Object PrincipalId | Where-Object { $_.Group[0].Origin -eq "ADSync" }).Count
$cloudOnlyCount       = @($syncAnalysisRows | Group-Object PrincipalId | Where-Object { $_.Group[0].Origin -eq "CloudOnly" }).Count
$considerSyncingCount = @($syncAnalysisRows | Group-Object PrincipalId | Where-Object { $_.Group[0].SyncRecommendation -eq "Consider syncing" }).Count
$reviewSyncCount      = @($syncAnalysisRows | Group-Object PrincipalId | Where-Object { $_.Group[0].SyncRecommendation -eq "Review sync need" }).Count
$keepSyncedCACount    = @($syncAnalysisRows | Group-Object PrincipalId | Where-Object { $_.Group[0].SyncRecommendation -eq "Keep synced (CA policy)" }).Count

$uniquePrincipalsAnalyzed = @($syncAnalysisRows | Select-Object PrincipalId -Unique).Count
Write-Host "  -> $uniquePrincipalsAnalyzed principals analyzed ($($syncAnalysisRows.Count) service-rows)." -ForegroundColor Gray
Write-Host "     Synced: $syncedCount | Cloud-only: $cloudOnlyCount" -ForegroundColor Gray
if ($considerSyncingCount -gt 0) {
  Write-Host "     Consider syncing: $considerSyncingCount (cloud-only with privileged roles/CA)" -ForegroundColor Yellow
}
if ($reviewSyncCount -gt 0) {
  Write-Host "     Review sync need: $reviewSyncCount (synced without M365 permissions)" -ForegroundColor Yellow
}
if ($keepSyncedCACount -gt 0) {
  Write-Host "     Keep synced (CA policy): $keepSyncedCACount (synced without direct M365 permission but referenced in CA policy)" -ForegroundColor Cyan
}

$csvPath  = Join-Path $runFolder "PermissionsInventory.csv"
$jsonPath = Join-Path $runFolder "Summary.json"
$xlsxPath = Join-Path $runFolder "PermissionsInventory.xlsx"

# Resolve to absolute paths — ImportExcel/EPPlus requires absolute paths
$csvPath  = [System.IO.Path]::GetFullPath($csvPath)
$jsonPath = [System.IO.Path]::GetFullPath($jsonPath)
$xlsxPath = [System.IO.Path]::GetFullPath($xlsxPath)

$hasImportExcel = [bool](Get-Module -ListAvailable -Name ImportExcel -ErrorAction SilentlyContinue)

try {
  # Always export CSV as fallback
  Export-CsvUtf8 -Object $rows -Path $csvPath

  # Excel export with separate worksheets per service
  if ($hasImportExcel) {
   try {
    Import-Module ImportExcel -ErrorAction Stop

    $columns = @(
      "Service","ResourceType","ResourceId","ResourceName",
      "AssignmentType","RoleOrPermission",
      "PrincipalType","PrincipalId","PrincipalDisplayName","PrincipalUPN",
      "Origin","AssignedViaOnPremGroup","OnPremisesDN","OnPremisesOU","Details"
    )

    # All data on one sheet
    $rows | Select-Object $columns |
      Export-Excel -Path $xlsxPath -WorksheetName "All Permissions" `
                   -AutoSize -AutoFilter -FreezeTopRow

    # Per-service worksheets
    $serviceGroups = $rows | Group-Object -Property Service
    foreach ($sg in $serviceGroups) {
      $sheetName = $sg.Name
      # Excel sheet names max 31 chars, no special chars
      if ($sheetName.Length -gt 31) { $sheetName = $sheetName.Substring(0, 31) }

      $sg.Group | Select-Object $columns |
        Export-Excel -Path $xlsxPath -WorksheetName $sheetName `
                     -AutoSize -AutoFilter -FreezeTopRow -Append
    }

    # Summary sheet
    $summaryData = $serviceGroups | ForEach-Object {
      [pscustomobject]@{
        Service    = $_.Name
        TotalRows  = $_.Count
        UniqueUsers = @($_.Group | Where-Object { $_.PrincipalType -eq "User" } |
                       Select-Object -ExpandProperty PrincipalId -Unique).Count
        OnPremGroupAssignments = @($_.Group | Where-Object { $_.AssignedViaOnPremGroup -eq "Yes" }).Count
      }
    }

    # Add sync stats row to summary
    $summaryData = @($summaryData) + @([pscustomobject]@{
      Service    = "--- SYNC STATS ---"
      TotalRows  = ""
      UniqueUsers = ""
      OnPremGroupAssignments = ""
    }, [pscustomobject]@{
      Service    = "Synced principals"
      TotalRows  = $syncedCount
      UniqueUsers = ""
      OnPremGroupAssignments = ""
    }, [pscustomobject]@{
      Service    = "Cloud-only principals"
      TotalRows  = $cloudOnlyCount
      UniqueUsers = ""
      OnPremGroupAssignments = ""
    }, [pscustomobject]@{
      Service    = "Cloud-only with privileged roles"
      TotalRows  = $considerSyncingCount
      UniqueUsers = ""
      OnPremGroupAssignments = ""
    }, [pscustomobject]@{
      Service    = "Synced with no M365 permissions"
      TotalRows  = $reviewSyncCount
      UniqueUsers = ""
      OnPremGroupAssignments = ""
    }, [pscustomobject]@{
      Service    = "Keep synced (CA policy ref)"
      TotalRows  = $keepSyncedCACount
      UniqueUsers = ""
      OnPremGroupAssignments = ""
    })

    $summaryData | Export-Excel -Path $xlsxPath -WorksheetName "Summary" `
                                -AutoSize -AutoFilter -FreezeTopRow -Append

    # Sync Analysis worksheet
    if ($syncAnalysisRows.Count -gt 0) {
      $syncColumns = @(
        "PrincipalType","PrincipalId","DisplayName","UPN",
        "Origin","OnPremisesDN","OnPremisesOU",
        "HasM365Permissions","Service","PermissionCount",
        "HasPrivilegedRole","InCAPolicy","HasPIMEligible","SyncRecommendation"
      )
      $syncAnalysisRows | Select-Object $syncColumns |
        Export-Excel -Path $xlsxPath -WorksheetName "Sync Analysis" `
                     -AutoSize -AutoFilter -FreezeTopRow -Append
    }

    # PIM Details worksheet
    if ($IncludePIMEligible -and $pimDetailRows.Count -gt 0) {
      $pimColumns = @(
        "AssignmentCategory","AssignmentType","IsPermanent",
        "StartDateTime","EndDateTime","Status","MemberType",
        "ScopeId","ScopeType","RoleDefinitionId","RoleName",
        "PrincipalId","PrincipalType","DisplayName","UPN",
        "Origin","OnPremisesDN","OnPremisesOU"
      )
      $pimDetailRows | Select-Object $pimColumns |
        Export-Excel -Path $xlsxPath -WorksheetName "PIM Details" `
                     -AutoSize -AutoFilter -FreezeTopRow -Append
      Write-Host "  PIM Details sheet    : $($pimDetailRows.Count) rows" -ForegroundColor Green
    }

    Write-Host "  Excel            : $xlsxPath" -ForegroundColor Green
   } catch {
    Write-Warning "Excel export failed: $_. CSV was created instead."
   }
  } else {
    Write-Host "  (ImportExcel module not found - install with: Install-Module ImportExcel -Scope CurrentUser)" -ForegroundColor DarkGray
    Write-Host "  (Skipping Excel export, CSV was created instead)" -ForegroundColor DarkGray
  }

  # Always export sync analysis as CSV too
  if ($syncAnalysisRows.Count -gt 0) {
    $syncCsvPath = Join-Path $runFolder "SyncAnalysis.csv"
    $syncAnalysisRows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $syncCsvPath
    Write-Host "  Sync analysis (CSV) : $syncCsvPath" -ForegroundColor Green
  }

  # Always export PIM details as CSV too
  if ($IncludePIMEligible -and $pimDetailRows.Count -gt 0) {
    $pimCsvPath = Join-Path $runFolder "PIMDetails.csv"
    $pimDetailRows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $pimCsvPath
    Write-Host "  PIM details (CSV)   : $pimCsvPath" -ForegroundColor Green
  }

  Write-JsonFile -Object @{
    Timestamp  = (Get-Date).ToString("s")
    RunFolder  = $runFolder
    TotalRows  = $rows.Count
    Included   = @{
      DirectoryRoles  = [bool]$IncludeDirectoryRoles
      EnterpriseApps  = [bool]$IncludeEnterpriseApps
      OAuth2Grants    = [bool]$IncludeOAuth2Grants
      Teams           = [bool]$IncludeTeams
      SharePointSites = [bool]$IncludeSharePointSites
      OneDriveSites   = [bool]$IncludeOneDriveSites
      Exchange        = [bool]$IncludeExchange
      DistGroups      = [bool]$IncludeDistGroups
      CondAccess      = [bool]$IncludeCondAccess
      PIMEligible     = [bool]$IncludePIMEligible
      ADCrosscheck    = [bool]$IncludeADCrosscheck
    }
  } -Path $jsonPath

  Write-Host ""
  Write-Host "===============================================" -ForegroundColor Green
  Write-Host "   Inventory complete!" -ForegroundColor Green
  Write-Host "===============================================" -ForegroundColor Green
  Write-Host "  Total rows          : $($rows.Count)" -ForegroundColor Green
  Write-Host "  CSV                 : $csvPath"        -ForegroundColor Green
  Write-Host "  Summary (JSON)      : $jsonPath"       -ForegroundColor Green
  Write-Host "  Logg               : $(Join-Path $runFolder 'audit.log')" -ForegroundColor Green
  Write-Host ""
}
catch {
  Write-Error "Export failed: $_"
}
finally {
  # Always disconnect from remote services
  try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}
  if ($IncludeExchange) {
    try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
  }
  if ($transcriptStarted) {
    try { Stop-Transcript | Out-Null } catch {}
  }
}
