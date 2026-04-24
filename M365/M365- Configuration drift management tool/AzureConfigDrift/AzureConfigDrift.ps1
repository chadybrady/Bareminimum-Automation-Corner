<#
.SYNOPSIS
  Azure Configuration Drift Management Tool – snapshot, baseline, and drift detection
  across Entra ID and Intune endpoints. Supports interactive use, unattended/scheduled
  runs, and Azure Automation Runbooks via Managed Identity.

.COVERAGE
  Entra ID : Conditional Access · Directory roles + PIM · Enterprise apps + OAuth2 grants
             · Named locations + auth methods policy + authorization policy
  Intune   : Device configuration · Compliance · App protection · Scripts + health scripts
             · Enrollment configurations · App assignments

.MODES
  Snapshot      – Collect current state from all selected endpoints and export to JSON
  SetBaseline   – Promote a snapshot run as the approved golden configuration
  CheckDrift    – Compare current state against a baseline and produce a drift report
  ListBaselines – List available baselines (local + Azure Blob if configured)

.RUNBOOK USAGE
  The script auto-detects Azure Automation context ($PSPrivateMetadata.JobId) and:
    · Authenticates via Managed Identity (system-assigned by default)
    · Skips interactive prompts / menus
    · Routes all output through Write-Output for the job stream

  Required Automation Account modules:
    Microsoft.Graph.Authentication, Az.Accounts, Az.Storage

  Required Graph API app roles on the Managed Identity:
    Policy.Read.All, RoleManagement.Read.Directory, Application.Read.All,
    Directory.Read.All, DeviceManagementConfiguration.Read.All,
    DeviceManagementApps.Read.All, DeviceManagementServiceConfig.Read.All,
    DeviceManagementManagedDevices.Read.All

  Required Azure RBAC on the Storage Account:
    Storage Blob Data Contributor

.LOCAL USAGE
  Run interactively – opens a browser for user sign-in:
    ./AzureConfigDrift.ps1

  Run with device code (SSH / headless terminal, no browser available):
    ./AzureConfigDrift.ps1 -AuthMethod DeviceCode

  Target a specific tenant:
    ./AzureConfigDrift.ps1 -TenantId '00000000-0000-0000-0000-000000000000'

.NOTES
  Requires PowerShell 7.0+
  Modules: Microsoft.Graph.Authentication, Az.Accounts (for MI), Az.Storage (for blob)
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
  # Operating mode. Omit for interactive menu.
  [ValidateSet('Snapshot', 'SetBaseline', 'CheckDrift', 'ListBaselines')]
  [string]$Mode,

  # Root folder for all run output and local baselines.
  [string]$OutputPath = '.\AzureConfigDrift',

  # Endpoints to collect. Defaults to all. Valid values:
  # EntraCA, EntraDirectoryRoles, EntraEnterpriseApps, EntraAuthMethods,
  # IntuneDeviceConfig, IntuneCompliance, IntuneAppProtection,
  # IntuneScripts, IntuneEnrollment, IntuneAppAssignments
  [string[]]$Endpoints,

  # Baseline name for SetBaseline (save) or CheckDrift (load).
  [string]$BaselineName,

  # Baseline description saved in baseline-meta.json (SetBaseline mode).
  [string]$BaselineDescription = '',

  # Upload the current run / baseline to Azure Blob Storage.
  [switch]$UploadToBlob,

  # Azure Storage account name (required when -UploadToBlob).
  [string]$StorageAccountName,

  # Blob container name (default: drift-management).
  [string]$ContainerName = 'drift-management',

  # Suppress all interactive prompts; fail on missing required params.
  [switch]$Unattended,

  # Client ID of a user-assigned Managed Identity (optional; omit for system-assigned).
  [string]$ManagedIdentityClientId,

  # Graph / Azure authentication method when running locally.
  # Interactive  – opens a browser pop-up (default).
  # DeviceCode   – prints a code to enter at aka.ms/devicelogin; use this on headless
  #                terminals, SSH sessions, or when a browser is unavailable.
  # Managed Identity is used automatically when the script is running as a Runbook.
  [ValidateSet('Interactive', 'DeviceCode')]
  [string]$AuthMethod = 'Interactive',

  # Entra tenant ID to authenticate against. Useful when the signed-in account
  # has access to multiple tenants. Omit to use the home tenant.
  [string]$TenantId,

  # When specified with CheckDrift, fetches Intune and Entra audit logs to populate
  # the ModifiedBy field in drift rows. Requires AuditLog.Read.All consent.
  [switch]$IncludeAuditData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Constants ───────────────────────────────────────────────────────────────

$script:ToolVersion = '1.0'
$script:ToolName    = 'Azure Config Drift'

$script:AllEndpoints = @(
  'EntraCA', 'EntraDirectoryRoles', 'EntraEnterpriseApps', 'EntraAuthMethods',
  'IntuneDeviceConfig', 'IntuneCompliance', 'IntuneAppProtection',
  'IntuneScripts', 'IntuneEnrollment', 'IntuneAppAssignments', 'IntuneSecurityBaselines'
)

$script:EndpointLabels = @{
  EntraCA              = 'Entra – Conditional Access'
  EntraDirectoryRoles  = 'Entra – Directory Roles + PIM'
  EntraEnterpriseApps  = 'Entra – Enterprise Apps + OAuth2'
  EntraAuthMethods     = 'Entra – Auth Methods + Named Locations'
  IntuneDeviceConfig   = 'Intune – Device Configurations'
  IntuneCompliance     = 'Intune – Compliance Policies'
  IntuneAppProtection  = 'Intune – App Protection Policies'
  IntuneScripts        = 'Intune – Scripts + Health Scripts'
  IntuneEnrollment     = 'Intune – Enrollment Configurations'
  IntuneAppAssignments = 'Intune – App Assignments'
  IntuneSecurityBaselines = 'Intune – Security Baselines'
}

$script:RequiredScopes = @(
  'Policy.Read.All',
  'RoleManagement.Read.Directory',
  'Application.Read.All',
  'Directory.Read.All',
  'DeviceManagementConfiguration.Read.All',
  'DeviceManagementApps.Read.All',
  'DeviceManagementServiceConfig.Read.All',
  'DeviceManagementManagedDevices.Read.All',
  'DeviceManagementScripts.Read.All'
)

# Detect Azure Automation Runbook context
$script:IsRunbook = $false
try {
  if ($PSPrivateMetadata.JobId.Guid) { $script:IsRunbook = $true }
} catch {}

# In runbook context, unattended is always true
if ($script:IsRunbook) { $Unattended = $true }

# ─── UI / Output Helpers ─────────────────────────────────────────────────────

function Write-Out {
  param([string]$Message, [string]$Color = '')
  if ($script:IsRunbook) {
    Write-Output $Message
  } else {
    if ($Color) {
      Write-Host $Message -ForegroundColor $Color
    } else {
      Write-Host $Message
    }
  }
}

function Write-Step  { param([string]$m) Write-Out "  ▶ $m" -Color Yellow     }
function Write-Ok    { param([string]$m) Write-Out "  ✓ $m" -Color Green      }
function Write-Info  { param([string]$m) Write-Out "  · $m" -Color Gray       }
function Write-Warn  { param([string]$m) Write-Out "  ⚠ $m" -Color DarkYellow }
function Write-Fail  { param([string]$m) Write-Out "  ✗ $m" -Color Red        }

function Show-Banner {
  if ($Unattended) { return }
  Write-Host ''
  Write-Host '  ╔══════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
  Write-Host '  ║                                                              ║' -ForegroundColor Cyan
  Write-Host "  ║   Azure Config Drift · v$($script:ToolVersion)                               ║" -ForegroundColor Cyan
  Write-Host '  ║   Bareminimum Automation                                     ║' -ForegroundColor DarkCyan
  Write-Host '  ║                                                              ║' -ForegroundColor Cyan
  Write-Host '  ╚══════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
  Write-Host ''
}

# ─── Filesystem Helpers ──────────────────────────────────────────────────────

function Ensure-Folder {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-JsonFile {
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Path
  )
  $Object | ConvertTo-Json -Depth 20 | Out-File -FilePath $Path -Encoding UTF8
}

function Export-CsvUtf8 {
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Path
  )
  $Object | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $Path
}

# ─── Module Helper ───────────────────────────────────────────────────────────

function Ensure-Module {
  param([Parameter(Mandatory)][string]$Name)
  if ($script:IsRunbook) { return }  # modules pre-loaded in Automation Account
  if (-not (Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue)) {
    Write-Step "Installing module $Name..."
    Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
  }
  Import-Module -Name $Name -ErrorAction Stop
}

# ─── Graph Helpers ───────────────────────────────────────────────────────────

function Normalize-GraphUri {
  param([string]$Uri)
  if ($Uri.StartsWith('/')) {
    if ($Uri.StartsWith('/v1.0/') -or $Uri.StartsWith('/beta/')) { return $Uri }
    return "/v1.0$Uri"
  }
  if ($Uri -match '^https://graph\.microsoft\.com/(v1\.0|beta)/') { return $Uri }
  if ($Uri -match '^https://graph\.microsoft\.com/') {
    return $Uri -replace '^https://graph\.microsoft\.com/', 'https://graph.microsoft.com/v1.0/'
  }
  return $Uri
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
    [int]$MaxRetries = 5
  )
  $all  = [System.Collections.Generic.List[object]]::new()
  $next = Normalize-GraphUri -Uri $Uri

  while ($null -ne $next) {
    $resp    = $null
    $attempt = 0
    while ($attempt -le $MaxRetries) {
      try {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $next
        break
      } catch {
        $statusCode = $null
        try { $statusCode = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($statusCode -eq 429 -and $attempt -lt $MaxRetries) {
          $retryAfter = $null
          try { $retryAfter = [int]$_.Exception.Response.Headers.RetryAfter.Delta.TotalSeconds } catch {}
          $wait = if ($retryAfter -and $retryAfter -gt 0) { $retryAfter } else { [int][math]::Pow(2, $attempt + 1) }
          Write-Warn "Graph throttled (429) – waiting ${wait}s (retry $($attempt+1)/$MaxRetries)..."
          Start-Sleep -Seconds $wait
          $attempt++
        } else { throw }
      }
    }

    $items = Get-GraphPropValue -Obj $resp -Name 'value'
    if ($items) { foreach ($i in $items) { [void]$all.Add($i) } }

    $nl = Get-GraphPropValue -Obj $resp -Name '@odata.nextLink'
    if (-not $nl) { $nl = Get-GraphPropValue -Obj $resp -Name 'odata.nextLink' }
    $next = if ($nl) { Normalize-GraphUri -Uri $nl } else { $null }
  }
  return $all
}

function Invoke-GraphSingle {
  param([Parameter(Mandatory)][string]$Uri)
  Invoke-MgGraphRequest -Method GET -Uri (Normalize-GraphUri $Uri)
}

# ─── Endpoint Collectors ─────────────────────────────────────────────────────

function Get-EntraCASnapshot {
  Write-Info 'Collecting Conditional Access policies...'
  $policies = Get-GraphPaged -Uri '/v1.0/identity/conditionalAccess/policies'
  return $policies | ForEach-Object {
    [pscustomobject]@{
      id          = $_.id
      displayName = $_.displayName
      state       = $_.state
      conditions  = $_.conditions
      grantControls  = $_.grantControls
      sessionControls = $_.sessionControls
      createdDateTime  = $_.createdDateTime
      modifiedDateTime = $_.modifiedDateTime
    }
  }
}

function Get-EntraDirectoryRolesSnapshot {
  Write-Info 'Collecting directory roles, assignments, and PIM eligibility...'

  $roleDefs    = Get-GraphPaged -Uri '/v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName,isBuiltIn,isEnabled'
  $assignments = Get-GraphPaged -Uri '/v1.0/roleManagement/directory/roleAssignments?$expand=principal'

  $pimEligible = @()
  try {
    $pimEligible = Get-GraphPaged -Uri '/v1.0/roleManagement/directory/roleEligibilityScheduleInstances'
  } catch {
    $sc = $null
    try { $sc = $_.Exception.Response.StatusCode.value__ } catch {}
    if ($sc -eq 400) { Write-Warn 'PIM eligible assignments skipped (Entra ID P2 license required).' }
    else { Write-Warn "PIM collection failed: $_" }
  }

  return [pscustomobject]@{
    id          = 'EntraDirectoryRoles'
    roleDefinitions = $roleDefs
    roleAssignments = $assignments
    pimEligible     = $pimEligible
  }
}

function Get-EntraEnterpriseAppsSnapshot {
  Write-Info 'Collecting enterprise apps, app role assignments, and OAuth2 grants...'

  # Service principals that are applications (not managed identities / legacy)
  $sps = Get-GraphPaged -Uri "/v1.0/servicePrincipals?`$filter=servicePrincipalType eq 'Application'&`$select=id,displayName,appId,publisherName,signInAudience"

  $appRoleAssignedTo = [System.Collections.Generic.List[object]]::new()
  foreach ($sp in $sps) {
    try {
      $assigned = Get-GraphPaged -Uri "/v1.0/servicePrincipals/$($sp.id)/appRoleAssignedTo"
      foreach ($a in $assigned) { [void]$appRoleAssignedTo.Add($a) }
    } catch { Write-Warn "  appRoleAssignedTo failed for $($sp.displayName): $_" }
  }

  $oauth2Grants = Get-GraphPaged -Uri '/v1.0/oauth2PermissionGrants'

  return [pscustomobject]@{
    id                 = 'EntraEnterpriseApps'
    servicePrincipals  = $sps
    appRoleAssignedTo  = $appRoleAssignedTo
    oauth2Grants       = $oauth2Grants
  }
}

function Get-EntraAuthMethodsSnapshot {
  Write-Info 'Collecting auth methods, named locations, and authorization policy...'

  $authMethodsPolicy = $null
  try { $authMethodsPolicy = Invoke-GraphSingle '/v1.0/policies/authenticationMethodsPolicy' } catch { Write-Warn "Auth methods policy: $_" }

  $namedLocations = Get-GraphPaged -Uri '/v1.0/identity/conditionalAccess/namedLocations'

  $authzPolicy = $null
  try { $authzPolicy = Invoke-GraphSingle '/v1.0/policies/authorizationPolicy' } catch { Write-Warn "Authorization policy: $_" }

  $mfaRegistration = $null
  try { $mfaRegistration = Invoke-GraphSingle '/v1.0/reports/credentialUserRegistrationDetails' } catch {}

  return [pscustomobject]@{
    id                    = 'EntraAuthMethods'
    authenticationMethodsPolicy = $authMethodsPolicy
    namedLocations              = $namedLocations
    authorizationPolicy         = $authzPolicy
  }
}

function Get-IntuneDeviceConfigSnapshot {
  Write-Info 'Collecting Intune device configurations (legacy profiles + Settings Catalog)...'
  $result = [System.Collections.Generic.List[object]]::new()

  # ── Legacy profiles (/deviceConfigurations) ───────────────────────────────
  try {
    $legacyConfigs = Get-GraphPaged -Uri '/beta/deviceManagement/deviceConfigurations'
    foreach ($cfg in $legacyConfigs) {
      [void]$result.Add([pscustomobject]@{
        id                   = $cfg.id
        displayName          = $cfg.displayName
        policyType           = 'LegacyProfile'
        '@odata.type'        = $cfg.'@odata.type'
        createdDateTime      = $cfg.createdDateTime
        lastModifiedDateTime = $cfg.lastModifiedDateTime
        settings             = $cfg
      })
    }
  } catch { Write-Warn "Legacy device configurations: $_" }

  # ── Settings Catalog (/configurationPolicies) ─────────────────────────────
  try {
    $scPolicies = Get-GraphPaged -Uri '/beta/deviceManagement/configurationPolicies?$select=id,name,description,platforms,technologies,settingCount,createdDateTime,lastModifiedDateTime'
    foreach ($policy in $scPolicies) {
      $settingInstances = @()
      try {
        $settingInstances = Get-GraphPaged -Uri "/beta/deviceManagement/configurationPolicies/$($policy.id)/settings"
      } catch { Write-Warn "  Settings Catalog settings for '$($policy.name)': $_" }

      [void]$result.Add([pscustomobject]@{
        id                   = $policy.id
        displayName          = $policy.name
        policyType           = 'SettingsCatalog'
        '@odata.type'        = '#microsoft.graph.deviceManagementConfigurationPolicy'
        platforms            = (Get-GraphPropValue -Obj $policy -Name 'platforms')
        technologies         = (Get-GraphPropValue -Obj $policy -Name 'technologies')
        settingCount         = (Get-GraphPropValue -Obj $policy -Name 'settingCount')
        createdDateTime      = $policy.createdDateTime
        lastModifiedDateTime = $policy.lastModifiedDateTime
        settings             = $settingInstances
      })
    }
  } catch { Write-Warn "Settings Catalog policies: $_" }

  return $result
}

function Get-IntuneComplianceSnapshot {
  Write-Info 'Collecting Intune compliance policies...'
  $policies = Get-GraphPaged -Uri '/v1.0/deviceManagement/deviceCompliancePolicies'
  return $policies | ForEach-Object {
    [pscustomobject]@{
      id          = $_.id
      displayName = $_.displayName
      '@odata.type' = $_.'@odata.type'
      createdDateTime      = $_.createdDateTime
      lastModifiedDateTime = $_.lastModifiedDateTime
      settings             = $_
    }
  }
}

function Get-IntuneAppProtectionSnapshot {
  Write-Info 'Collecting Intune app protection policies...'
  $policies = Get-GraphPaged -Uri '/beta/deviceAppManagement/managedAppPolicies'
  return $policies | ForEach-Object {
    [pscustomobject]@{
      id          = $_.id
      displayName = $_.displayName
      '@odata.type' = $_.'@odata.type'
      createdDateTime      = $_.createdDateTime
      lastModifiedDateTime = $_.lastModifiedDateTime
      settings             = $_
    }
  }
}

function Get-IntuneScriptsSnapshot {
  Write-Info 'Collecting Intune scripts and health scripts...'
  $scripts = [System.Collections.Generic.List[object]]::new()

  try {
    $deviceScripts = Get-GraphPaged -Uri '/beta/deviceManagement/deviceManagementScripts'
    foreach ($s in $deviceScripts) {
      [void]$scripts.Add([pscustomobject]@{
        id          = $s.id
        displayName = $s.displayName
        scriptType  = 'deviceManagementScript'
        createdDateTime      = $s.createdDateTime
        lastModifiedDateTime = $s.lastModifiedDateTime
        settings             = $s
      })
    }
  } catch { Write-Warn "Device management scripts: $_" }

  try {
    $healthScripts = Get-GraphPaged -Uri '/beta/deviceManagement/deviceHealthScripts'
    foreach ($s in $healthScripts) {
      [void]$scripts.Add([pscustomobject]@{
        id          = $s.id
        displayName = $s.displayName
        scriptType  = 'deviceHealthScript'
        createdDateTime      = $s.createdDateTime
        lastModifiedDateTime = $s.lastModifiedDateTime
        settings             = $s
      })
    }
  } catch { Write-Warn "Device health scripts: $_" }

  return $scripts
}

function Get-IntuneEnrollmentSnapshot {
  Write-Info 'Collecting Intune enrollment configurations...'
  $configs = Get-GraphPaged -Uri '/v1.0/deviceManagement/deviceEnrollmentConfigurations'
  return $configs | ForEach-Object {
    [pscustomobject]@{
      id          = $_.id
      displayName = $_.displayName
      '@odata.type' = (Get-GraphPropValue -Obj $_ -Name '@odata.type')
      priority     = (Get-GraphPropValue -Obj $_ -Name 'priority')
      createdDateTime      = (Get-GraphPropValue -Obj $_ -Name 'createdDateTime')
      lastModifiedDateTime = (Get-GraphPropValue -Obj $_ -Name 'lastModifiedDateTime')
      settings             = $_
    }
  }
}

function Get-IntuneSecurityBaselinesSnapshot {
  Write-Info 'Collecting Intune security baselines...'
  $result = [System.Collections.Generic.List[object]]::new()

  $intents = @()
  try {
    $intents = Get-GraphPaged -Uri '/beta/deviceManagement/intents?$select=id,displayName,description,templateId,isAssigned,roleScopeTagIds,lastModifiedDateTime'
  } catch { Write-Warn "Security baselines list: $_" }

  foreach ($intent in $intents) {
    $settings = @()
    try {
      $settings = Get-GraphPaged -Uri "/beta/deviceManagement/intents/$($intent.id)/settings"
    } catch { Write-Warn "  Settings for baseline '$($intent.displayName)': $_" }

    [void]$result.Add([pscustomobject]@{
      id                   = $intent.id
      displayName          = $intent.displayName
      description          = (Get-GraphPropValue -Obj $intent -Name 'description')
      templateId           = (Get-GraphPropValue -Obj $intent -Name 'templateId')
      isAssigned           = (Get-GraphPropValue -Obj $intent -Name 'isAssigned')
      lastModifiedDateTime = $intent.lastModifiedDateTime
      settings             = $settings
    })
  }
  return $result
}

function Get-IntuneAppAssignmentsSnapshot {
  Write-Info 'Collecting Intune app assignments...'
  # @odata.type is invalid in $select – omit it; the API includes it in the response body regardless
  $apps = Get-GraphPaged -Uri '/v1.0/deviceAppManagement/mobileApps?$select=id,displayName,publisher'
  $result = [System.Collections.Generic.List[object]]::new()

  foreach ($app in $apps) {
    $assignments = @()
    try {
      $assignments = Get-GraphPaged -Uri "/v1.0/deviceAppManagement/mobileApps/$($app.id)/assignments"
    } catch { Write-Warn "  Assignments for app $($app.displayName): $_" }

    [void]$result.Add([pscustomobject]@{
      id          = $app.id
      displayName = $app.displayName
      publisher   = (Get-GraphPropValue -Obj $app -Name 'publisher')
      '@odata.type' = (Get-GraphPropValue -Obj $app -Name '@odata.type')
      assignments = $assignments
    })
  }
  return $result
}

# Endpoint dispatch table
$script:Collectors = [ordered]@{
  EntraCA              = { Get-EntraCASnapshot }
  EntraDirectoryRoles  = { Get-EntraDirectoryRolesSnapshot }
  EntraEnterpriseApps  = { Get-EntraEnterpriseAppsSnapshot }
  EntraAuthMethods     = { Get-EntraAuthMethodsSnapshot }
  IntuneDeviceConfig   = { Get-IntuneDeviceConfigSnapshot }
  IntuneCompliance     = { Get-IntuneComplianceSnapshot }
  IntuneAppProtection  = { Get-IntuneAppProtectionSnapshot }
  IntuneScripts        = { Get-IntuneScriptsSnapshot }
  IntuneEnrollment     = { Get-IntuneEnrollmentSnapshot }
  IntuneAppAssignments     = { Get-IntuneAppAssignmentsSnapshot }
  IntuneSecurityBaselines = { Get-IntuneSecurityBaselinesSnapshot }
}

# ─── Snapshot Orchestrator ───────────────────────────────────────────────────

function Invoke-Snapshot {
  param(
    [Parameter(Mandatory)][string[]]$SelectedEndpoints,
    [Parameter(Mandatory)][string]$RunFolder
  )

  $combined = [ordered]@{}
  $summary  = [System.Collections.Generic.List[pscustomobject]]::new()

  foreach ($ep in $SelectedEndpoints) {
    $label = $script:EndpointLabels[$ep]
    Write-Step "Collecting $label..."
    $status    = 'OK'
    $itemCount = 0
    $data      = $null

    try {
      $data = & $script:Collectors[$ep]
      # PowerShell unrolls empty collections to $null in the pipeline; normalise to empty array
      if ($null -eq $data) { $data = @() }
      $itemCount = if ($data -is [System.Collections.IList]) { $data.Count } elseif ($data -is [array]) { $data.Count } elseif ($null -ne $data) { 1 } else { 0 }
      $fileName  = "$ep.json"
      Write-JsonFile -Object $data -Path (Join-Path $RunFolder $fileName)
      Write-Ok "$label – $itemCount item(s) collected"
    } catch {
      $status = "ERROR: $_"
      Write-Fail "$label – $($_.Exception.Message)"
    }

    [void]$summary.Add([pscustomobject]@{
      Endpoint  = $ep
      Label     = $label
      ItemCount = $itemCount
      Status    = $status
    })

    $combined[$ep] = $data
  }

  # Write combined snapshot
  Write-JsonFile -Object $combined -Path (Join-Path $RunFolder 'Snapshot.json')

  # Print collection summary
  Write-Out ''
  Write-Out '  ── Snapshot Summary ────────────────────────────────────────────' -Color Cyan
  foreach ($row in $summary) {
    $statusIcon = if ($row.Status -eq 'OK') { '✓' } else { '✗' }
    $color      = if ($row.Status -eq 'OK') { 'Green' } else { 'Red' }
    Write-Out ("  {0,-2} {1,-40} {2,5} item(s)  [{3}]" -f $statusIcon, $row.Label, $row.ItemCount, $row.Status) -Color $color
  }
  Write-Out ''

  return $combined
}

# ─── Baseline Manager ────────────────────────────────────────────────────────

function Save-Baseline {
  param(
    [Parameter(Mandatory)][string]$RunFolder,
    [Parameter(Mandatory)][string]$BaselinesRoot,
    [Parameter(Mandatory)][string]$Name,
    [string]$Description = ''
  )

  $dest = Join-Path $BaselinesRoot $Name
  if (Test-Path $dest) {
    Write-Warn "Baseline '$Name' already exists at $dest."
    if (-not $Unattended) {
      $overwrite = Read-Host "  Overwrite? [y/N]"
      if ($overwrite.Trim().ToUpper() -ne 'Y') {
        Write-Info 'Baseline save cancelled.'
        return
      }
      Remove-Item -Recurse -Force $dest
    } else {
      Write-Warn "Overwriting existing baseline '$Name' (unattended mode)."
      Remove-Item -Recurse -Force $dest
    }
  }

  Ensure-Folder -Path $dest
  Copy-Item -Path (Join-Path $RunFolder '*') -Destination $dest -Recurse

  $meta = [pscustomobject]@{
    name        = $Name
    description = $Description
    createdAt   = (Get-Date -Format 'o')
    sourceRun   = (Split-Path $RunFolder -Leaf)
    author      = $env:USERNAME ?? $env:USER ?? 'unknown'
  }
  Write-JsonFile -Object $meta -Path (Join-Path $dest 'baseline-meta.json')
  Write-Ok "Baseline '$Name' saved to $dest"
}

function Get-AvailableBaselines {
  param(
    [Parameter(Mandatory)][string]$BaselinesRoot,
    [string]$StorageCtx,
    [string]$SaContainerName
  )

  $baselines = [System.Collections.Generic.List[pscustomobject]]::new()

  # Local
  if (Test-Path $BaselinesRoot) {
    Get-ChildItem -Path $BaselinesRoot -Directory | ForEach-Object {
      $metaPath = Join-Path $_.FullName 'baseline-meta.json'
      $meta     = if (Test-Path $metaPath) { Get-Content $metaPath -Raw | ConvertFrom-Json } else { $null }
      [void]$baselines.Add([pscustomobject]@{
        Name        = $_.Name
        Source      = 'Local'
        CreatedAt   = ($null -ne $meta) ? $meta.createdAt   : $null
        Description = ($null -ne $meta) ? $meta.description : $null
        Path        = $_.FullName
      })
    }
  }

  # Blob
  if ($StorageCtx) {
    try {
      $blobs = Get-AzStorageBlob -Container $SaContainerName -Context $StorageCtx -Prefix 'baselines/' -ErrorAction SilentlyContinue
      $blobNames = $blobs | ForEach-Object { ($_.Name -split '/')[1] } | Select-Object -Unique
      foreach ($n in $blobNames) {
        if (-not ($baselines | Where-Object { $_.Name -eq $n -and $_.Source -eq 'Local' })) {
          [void]$baselines.Add([pscustomobject]@{
            Name        = $n
            Source      = 'Blob'
            CreatedAt   = $null
            Description = $null
            Path        = "blob:$SaContainerName/baselines/$n"
          })
        }
      }
    } catch { Write-Warn "Could not enumerate blob baselines: $_" }
  }

  return , $baselines
}

function Import-BaselineFromBlob {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$BaselinesRoot,
    [Parameter(Mandatory)]$StorageCtx,
    [Parameter(Mandatory)][string]$SaContainerName
  )

  $dest = Join-Path $BaselinesRoot $Name
  Ensure-Folder -Path $dest

  Write-Step "Downloading baseline '$Name' from blob..."
  $blobs = Get-AzStorageBlob -Container $SaContainerName -Context $StorageCtx -Prefix "baselines/$Name/"
  foreach ($blob in $blobs) {
    $localFile = Join-Path $dest ($blob.Name -replace "^baselines/$Name/", '')
    $blobDir   = Split-Path $localFile -Parent
    Ensure-Folder -Path $blobDir
    Get-AzStorageBlobContent -Container $SaContainerName -Blob $blob.Name -Destination $localFile -Context $StorageCtx -Force | Out-Null
  }
  Write-Ok "Baseline '$Name' downloaded to $dest"
}

# ─── Audit Actor Lookup ──────────────────────────────────────────────────────

function Get-AuditActorLookup {
  # Returns hashtable keyed by resource ID → @{ Actor = '...'; DateTime = '...' }
  # Uses the most recent audit event per resource (results are newest-first).
  $lookup = @{}
  $since  = (Get-Date).AddDays(-30).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

  # ── Intune audit events ──────────────────────────────────────────────────
  try {
    $events = Get-GraphPaged -Uri "/beta/deviceManagement/auditEvents?`$filter=activityDateTime ge $since&`$select=activityDateTime,actor,resources"
    foreach ($evt in $events) {
      $actor    = Get-GraphPropValue -Obj $evt -Name 'actor'
      $actorUpn = ''
      if ($actor) {
        $actorUpn  = Get-GraphPropValue -Obj $actor -Name 'userPrincipalName'
        if (-not $actorUpn) { $actorUpn = Get-GraphPropValue -Obj $actor -Name 'applicationDisplayName' }
        if (-not $actorUpn) { $actorUpn = Get-GraphPropValue -Obj $actor -Name 'userId' }
      }
      $resources = Get-GraphPropValue -Obj $evt -Name 'resources'
      if ($resources) {
        foreach ($res in $resources) {
          $rid = Get-GraphPropValue -Obj $res -Name 'resourceId'
          if ($rid -and -not $lookup.ContainsKey($rid)) {
            $lookup[$rid] = @{ Actor = ($actorUpn ?? ''); DateTime = [string](Get-GraphPropValue -Obj $evt -Name 'activityDateTime') }
          }
        }
      }
    }
    Write-Info "  Indexed $($lookup.Count) resource(s) from Intune audit events."
  } catch { Write-Warn "Intune audit events: $_" }

  # ── Entra audit logs ─────────────────────────────────────────────────────
  $entraCount = 0
  try {
    $events = Get-GraphPaged -Uri "/v1.0/auditLogs/directoryAudits?`$filter=activityDateTime ge $since&`$select=activityDateTime,initiatedBy,targetResources"
    foreach ($evt in $events) {
      $initiatedBy = Get-GraphPropValue -Obj $evt -Name 'initiatedBy'
      $actorUpn    = ''
      if ($initiatedBy) {
        $user = Get-GraphPropValue -Obj $initiatedBy -Name 'user'
        $app  = Get-GraphPropValue -Obj $initiatedBy -Name 'app'
        if ($user) { $actorUpn = Get-GraphPropValue -Obj $user -Name 'userPrincipalName' }
        if (-not $actorUpn -and $app) { $actorUpn = Get-GraphPropValue -Obj $app -Name 'displayName' }
      }
      $targetResources = Get-GraphPropValue -Obj $evt -Name 'targetResources'
      if ($targetResources) {
        foreach ($res in $targetResources) {
          $rid = Get-GraphPropValue -Obj $res -Name 'id'
          if ($rid -and -not $lookup.ContainsKey($rid)) {
            $lookup[$rid] = @{ Actor = ($actorUpn ?? ''); DateTime = [string](Get-GraphPropValue -Obj $evt -Name 'activityDateTime') }
            $entraCount++
          }
        }
      }
    }
    Write-Info "  Indexed $entraCount more resource(s) from Entra audit logs."
  } catch { Write-Warn "Entra audit logs: $_" }

  return $lookup
}

# ─── Drift Engine ────────────────────────────────────────────────────────────

function New-DriftRow {
  param(
    [string]$Endpoint,
    [string]$ChangeType,
    [string]$ResourceId,
    [string]$ResourceName,
    [string]$ChangedProperties,
    [string]$BaselineValue,
    [string]$CurrentValue,
    [string]$LastModified = '',
    [string]$ModifiedBy   = ''
  )
  [pscustomobject]@{
    Endpoint           = $Endpoint
    ChangeType         = $ChangeType
    ResourceId         = $ResourceId
    ResourceName       = $ResourceName
    ChangedProperties  = $ChangedProperties
    BaselineValue      = $BaselineValue
    CurrentValue       = $CurrentValue
    LastModified       = $LastModified
    ModifiedBy         = $ModifiedBy
  }
}

function Compare-Snapshots {
  param(
    [Parameter(Mandatory)][hashtable]$Baseline,
    [Parameter(Mandatory)][hashtable]$Current,
    [Parameter(Mandatory)][string[]]$SelectedEndpoints,
    [hashtable]$AuditLookup = @{}
  )

  $rows = [System.Collections.Generic.List[pscustomobject]]::new()

  foreach ($ep in $SelectedEndpoints) {
    $baseItems    = $Baseline[$ep]
    $currentItems = $Current[$ep]

    # Normalise to arrays
    if ($null -eq $baseItems)    { $baseItems    = @() }
    if ($null -eq $currentItems) { $currentItems = @() }

    # For complex single-object endpoints (e.g. EntraDirectoryRoles), wrap in array
    if ($baseItems -isnot [array] -and $baseItems -isnot [System.Collections.IList]) {
      $baseItems = @($baseItems)
    }
    if ($currentItems -isnot [array] -and $currentItems -isnot [System.Collections.IList]) {
      $currentItems = @($currentItems)
    }

    # Build id-keyed dictionaries
    $baseDict    = @{}
    $currentDict = @{}

    foreach ($item in $baseItems) {
      $itemId = $item.id ?? ($item | ConvertTo-Json -Depth 1 -Compress)
      $baseDict[$itemId] = $item
    }
    foreach ($item in $currentItems) {
      $itemId = $item.id ?? ($item | ConvertTo-Json -Depth 1 -Compress)
      $currentDict[$itemId] = $item
    }

    # Added
    foreach ($key in $currentDict.Keys) {
      if (-not $baseDict.ContainsKey($key)) {
        $item     = $currentDict[$key]
        $lastMod  = [string](Get-GraphPropValue -Obj $item -Name 'lastModifiedDateTime')
        $modBy    = if ($AuditLookup.ContainsKey($key)) { $AuditLookup[$key].Actor } else { '' }
        [void]$rows.Add((New-DriftRow -Endpoint $ep -ChangeType 'Added' -ResourceId $key `
          -ResourceName ($item.displayName ?? $item.id ?? $key) `
          -ChangedProperties '' -BaselineValue '' `
          -CurrentValue ($item | ConvertTo-Json -Depth 5 -Compress | ForEach-Object { if ($_.Length -gt 500) { $_.Substring(0, 500) + '...' } else { $_ } }) `
          -LastModified $lastMod -ModifiedBy $modBy
        ))
      }
    }

    # Removed
    foreach ($key in $baseDict.Keys) {
      if (-not $currentDict.ContainsKey($key)) {
        $item    = $baseDict[$key]
        $lastMod = [string](Get-GraphPropValue -Obj $item -Name 'lastModifiedDateTime')
        $modBy   = if ($AuditLookup.ContainsKey($key)) { $AuditLookup[$key].Actor } else { '' }
        [void]$rows.Add((New-DriftRow -Endpoint $ep -ChangeType 'Removed' -ResourceId $key `
          -ResourceName ($item.displayName ?? $item.id ?? $key) `
          -ChangedProperties '' `
          -BaselineValue ($item | ConvertTo-Json -Depth 5 -Compress | ForEach-Object { if ($_.Length -gt 500) { $_.Substring(0, 500) + '...' } else { $_ } }) `
          -CurrentValue '' -LastModified $lastMod -ModifiedBy $modBy
        ))
      }
    }

    # Modified
    # Timestamp fields are metadata only – exclude from change detection
    $metadataProps = @('lastModifiedDateTime', 'createdDateTime', 'modifiedDateTime', 'version')

    foreach ($key in $baseDict.Keys) {
      if ($currentDict.ContainsKey($key)) {
        $baseJson    = $baseDict[$key]    | ConvertTo-Json -Depth 20 -Compress
        $currentJson = $currentDict[$key] | ConvertTo-Json -Depth 20 -Compress

        if ($baseJson -ne $currentJson) {
          # Determine which top-level properties changed
          $baseObj    = $baseDict[$key]
          $currentObj = $currentDict[$key]

          $changedProps = @()
          $allKeys = @()
          $allKeys += if ($baseObj    -is [System.Collections.IDictionary]) { @($baseObj.Keys)                        } else { @($baseObj.PSObject.Properties.Name)    }
          $allKeys += if ($currentObj -is [System.Collections.IDictionary]) { @($currentObj.Keys)                     } else { @($currentObj.PSObject.Properties.Name) }
          $allKeys  = $allKeys | Select-Object -Unique

          foreach ($prop in $allKeys) {
            if ($prop -in $metadataProps) { continue }  # skip timestamp-only noise
            $bv = if ($baseObj    -is [System.Collections.IDictionary]) { $baseObj[$prop]    } else { $baseObj.$prop    }
            $cv = if ($currentObj -is [System.Collections.IDictionary]) { $currentObj[$prop] } else { $currentObj.$prop }
            $bj = $bv | ConvertTo-Json -Depth 5 -Compress
            $cj = $cv | ConvertTo-Json -Depth 5 -Compress
            if ($bj -ne $cj) { $changedProps += $prop }
          }

          # Skip row if the only differences were metadata timestamps
          if ($changedProps.Count -eq 0) { continue }

          $item    = $currentDict[$key]
          $lastMod = [string](Get-GraphPropValue -Obj $item -Name 'lastModifiedDateTime')
          $modBy   = if ($AuditLookup.ContainsKey($key)) { $AuditLookup[$key].Actor } else { '' }
          [void]$rows.Add((New-DriftRow -Endpoint $ep -ChangeType 'Modified' -ResourceId $key `
            -ResourceName ($item.displayName ?? $item.id ?? $key) `
            -ChangedProperties ($changedProps -join ', ') `
            -BaselineValue ($baseJson | ForEach-Object { if ($_.Length -gt 500) { $_.Substring(0, 500) + '...' } else { $_ } }) `
            -CurrentValue  ($currentJson | ForEach-Object { if ($_.Length -gt 500) { $_.Substring(0, 500) + '...' } else { $_ } }) `
            -LastModified $lastMod -ModifiedBy $modBy
          ))
        }
      }
    }
  }

  return , $rows
}

function Export-DriftReport {
  param(
    [System.Collections.Generic.List[pscustomobject]]$Rows,
    [Parameter(Mandatory)][string]$RunFolder,
    [Parameter(Mandatory)][string[]]$SelectedEndpoints
  )

  if ($null -eq $Rows -or $Rows.Count -eq 0) {
    Write-Ok 'No drift detected – current state matches the baseline.'
    Write-JsonFile -Object @{ driftDetected = $false; generatedAt = (Get-Date -Format 'o') } `
      -Path (Join-Path $RunFolder 'DriftReport.json')
    return
  }

  Write-JsonFile -Object $Rows -Path (Join-Path $RunFolder 'DriftReport.json')
  Export-CsvUtf8 -Object $Rows -Path (Join-Path $RunFolder 'DriftReport.csv')

  # Per-endpoint summary
  Write-Out ''
  Write-Out '  ── Drift Summary ───────────────────────────────────────────────' -Color Cyan
  foreach ($ep in $SelectedEndpoints) {
    $epRows   = $Rows | Where-Object { $_.Endpoint -eq $ep }
    if (-not $epRows) { continue }
    $added    = @($epRows | Where-Object { $_.ChangeType -eq 'Added'    }).Count
    $removed  = @($epRows | Where-Object { $_.ChangeType -eq 'Removed'  }).Count
    $modified = @($epRows | Where-Object { $_.ChangeType -eq 'Modified' }).Count
    $label    = $script:EndpointLabels[$ep]
    Write-Out ("  ⚠ {0,-40}  +{1} Added  -{2} Removed  ~{3} Modified" -f $label, $added, $removed, $modified) -Color DarkYellow
  }
  Write-Out ''
  Write-Warn "Total drift rows: $($Rows.Count) – see DriftReport.csv / DriftReport.json"
}

# ─── Azure Blob Storage ──────────────────────────────────────────────────────

function Get-StorageContext {
  param(
    [Parameter(Mandatory)][string]$SaName,
    [string]$SaContainerName
  )

  if ($script:IsRunbook) {
    # Managed Identity auth – Az.Accounts must be imported
    Write-Info "Using Managed Identity to connect to storage account '$SaName'..."
    $storageCtx = New-AzStorageContext -StorageAccountName $SaName -UseConnectedAccount
    return $storageCtx
  }

  # Interactive: offer SAS token or connection string
  Write-Out ''
  Write-Out '  Storage authentication options:' -Color Yellow
  Write-Out '    1. SAS token'
  Write-Out '    2. Account key'
  Write-Out '    3. Use current Az session (Connect-AzAccount)'
  $authChoice = Read-Host '  Choice [1/2/3]'

  switch ($authChoice.Trim()) {
    '1' {
      $sas = Read-Host '  SAS token (starts with ?sv=...)'
      return New-AzStorageContext -StorageAccountName $SaName -SasToken $sas
    }
    '2' {
      $key = Read-Host '  Storage account key'
      return New-AzStorageContext -StorageAccountName $SaName -StorageAccountKey $key
    }
    default {
      # Sign in as the current user if no Az session exists yet
      if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
        if ($AuthMethod -eq 'DeviceCode') {
          $azParams = @{ UseDeviceAuthentication = $true }
          if ($TenantId) { $azParams['Tenant'] = $TenantId }
          Connect-AzAccount @azParams | Out-Null
        } else {
          $azParams = @{}
          if ($TenantId) { $azParams['Tenant'] = $TenantId }
          Connect-AzAccount @azParams | Out-Null
        }
      }
      return New-AzStorageContext -StorageAccountName $SaName -UseConnectedAccount
    }
  }
}

function Upload-ToBlob {
  param(
    [Parameter(Mandatory)][string]$LocalFolder,
    [Parameter(Mandatory)][string]$BlobPrefix,
    [Parameter(Mandatory)]$StorageCtx,
    [Parameter(Mandatory)][string]$SaContainerName
  )

  Write-Step "Uploading to blob: $SaContainerName/$BlobPrefix"

  # Ensure container exists
  $container = Get-AzStorageContainer -Name $SaContainerName -Context $StorageCtx -ErrorAction SilentlyContinue
  if (-not $container) {
    New-AzStorageContainer -Name $SaContainerName -Context $StorageCtx -Permission Off | Out-Null
    Write-Info "Created container '$SaContainerName'."
  }

  $files = Get-ChildItem -Path $LocalFolder -Recurse -File
  foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($LocalFolder.Length).TrimStart([IO.Path]::DirectorySeparatorChar, '/')
    $blobName     = "$BlobPrefix/$relativePath" -replace '\\', '/'
    $params = @{
      File      = $file.FullName
      Container = $SaContainerName
      Blob      = $blobName
      Context   = $StorageCtx
      Force     = $true
    }
    Set-AzStorageBlobContent @params | Out-Null
  }
  Write-Ok "Uploaded $($files.Count) file(s) to blob prefix '$BlobPrefix'."
}

# ─── Interactive Menus ───────────────────────────────────────────────────────

function Select-Mode {
  Write-Out ''
  Write-Out '  What would you like to do?' -Color Yellow
  Write-Out '    1. Take snapshot & export'
  Write-Out '    2. Set current state as baseline'
  Write-Out '    3. Check drift against a baseline'
  Write-Out '    4. List available baselines'
  Write-Out '    5. Exit'
  Write-Out ''
  $choice = Read-Host '  Choice [1-5]'
  switch ($choice.Trim()) {
    '1' { return @{ Mode = 'Snapshot';      IncludeAudit = $false } }
    '2' { return @{ Mode = 'SetBaseline';   IncludeAudit = $false } }
    '3' {
      Write-Out ''
      $auditChoice = Read-Host '  Include who made each change? Requires AuditLog.Read.All consent. [y/N]'
      return @{ Mode = 'CheckDrift'; IncludeAudit = ($auditChoice.Trim().ToUpper() -eq 'Y') }
    }
    '4' { return @{ Mode = 'ListBaselines'; IncludeAudit = $false } }
    '5' { return @{ Mode = 'Exit';          IncludeAudit = $false } }
    default {
      Write-Warn "Invalid choice '$choice'. Please enter 1-5."
      return Select-Mode
    }
  }
}

function Select-Endpoints {
  Write-Out ''
  Write-Out '  Select endpoints to include (comma-separated numbers, or Enter for all):' -Color Yellow
  $i = 1
  foreach ($ep in $script:AllEndpoints) {
    Write-Out ("    {0,2}. {1}" -f $i, $script:EndpointLabels[$ep])
    $i++
  }
  Write-Out ''
  $input = Read-Host '  Endpoints [default: all]'
  if ([string]::IsNullOrWhiteSpace($input)) { return $script:AllEndpoints }

  $selected = [System.Collections.Generic.List[string]]::new()
  foreach ($part in ($input -split ',')) {
    $idx = [int]($part.Trim()) - 1
    if ($idx -ge 0 -and $idx -lt $script:AllEndpoints.Count) {
      [void]$selected.Add($script:AllEndpoints[$idx])
    } else {
      Write-Warn "  Invalid endpoint number: $($part.Trim())"
    }
  }
  if ($selected.Count -eq 0) { return $script:AllEndpoints }
  return $selected
}

# ─── Main Flow ───────────────────────────────────────────────────────────────

Show-Banner

# Resolve output paths
Ensure-Folder -Path $OutputPath
$baselinesRoot = Join-Path $OutputPath 'Baselines'
Ensure-Folder -Path $baselinesRoot

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runFolder  = Join-Path $OutputPath "Run-$timestamp"
Ensure-Folder -Path $runFolder
$runFolder = (Resolve-Path $runFolder).Path

# Start transcript
$transcriptStarted = $false
try {
  Start-Transcript -Path (Join-Path $runFolder 'audit.log') | Out-Null
  $transcriptStarted = $true
} catch { Write-Warn "Could not start transcript: $_" }

Write-Info "Run folder: $runFolder"

# Resolve mode
if (-not $Mode) {
  if ($Unattended) {
    throw '-Mode is required in unattended/runbook mode. Valid: Snapshot, SetBaseline, CheckDrift, ListBaselines'
  }
  $menuResult     = Select-Mode
  $Mode           = $menuResult.Mode
  if (-not $IncludeAuditData) { $IncludeAuditData = $menuResult.IncludeAudit }
}
if ($Mode -eq 'Exit') {
  Write-Info 'Exiting.'
  if ($transcriptStarted) { Stop-Transcript | Out-Null }
  return
}

# Resolve endpoints
if (-not $Endpoints -or $Endpoints.Count -eq 0) {
  if ($Unattended) {
    $Endpoints = $script:AllEndpoints
    Write-Info "No -Endpoints specified – defaulting to all $($Endpoints.Count) endpoints."
  } else {
    $Endpoints = Select-Endpoints
  }
}
# Validate
$invalid = $Endpoints | Where-Object { $_ -notin $script:AllEndpoints }
if ($invalid) {
  throw "Invalid endpoint name(s): $($invalid -join ', '). Valid: $($script:AllEndpoints -join ', ')"
}

# ── Module loading ────────────────────────────────────────────────────────────

Ensure-Module -Name 'Microsoft.Graph.Authentication'

$storageCtx = $null
if ($UploadToBlob -or ($Mode -eq 'CheckDrift' -and -not (Test-Path (Join-Path $baselinesRoot ($BaselineName ?? 'x'))))) {
  Ensure-Module -Name 'Az.Accounts'
  Ensure-Module -Name 'Az.Storage'
}

# ── Authentication ────────────────────────────────────────────────────────────

Write-Step 'Authenticating to Microsoft Graph...'
try {
  $effectiveScopes = if ($IncludeAuditData) { $script:RequiredScopes + 'AuditLog.Read.All' } else { $script:RequiredScopes }
  if ($script:IsRunbook) {
    # ── Managed Identity (Azure Automation Runbook) ───────────────────────────
    $mgParams = @{ Identity = $true; NoWelcome = $true }
    if ($ManagedIdentityClientId) { $mgParams['ClientId'] = $ManagedIdentityClientId }
    if ($TenantId)                { $mgParams['TenantId'] = $TenantId }
    Connect-MgGraph @mgParams
  } elseif ($AuthMethod -eq 'DeviceCode') {
    # ── Device code – user auth, no browser required ──────────────────────────
    Write-Info 'Device code authentication: open https://aka.ms/devicelogin and enter the code shown below.'
    $mgParams = @{ Scopes = $effectiveScopes; UseDeviceAuthentication = $true; NoWelcome = $true }
    if ($TenantId) { $mgParams['TenantId'] = $TenantId }
    Connect-MgGraph @mgParams
  } else {
    # ── Interactive browser – user auth (default for local runs) ──────────────
    $mgParams = @{ Scopes = $effectiveScopes; NoWelcome = $true }
    if ($TenantId) { $mgParams['TenantId'] = $TenantId }
    Connect-MgGraph @mgParams
  }
  $ctx = Get-MgContext
  Write-Ok "Connected to Microsoft Graph as: $($ctx.Account ?? 'Managed Identity') (tenant: $($ctx.TenantId))"
} catch {
  throw "Graph authentication failed: $_"
}

# ── Storage authentication ────────────────────────────────────────────────────

if ($UploadToBlob -or ($Mode -eq 'ListBaselines') -or ($Mode -eq 'CheckDrift')) {
  if ($StorageAccountName) {
    Write-Step "Connecting to storage account '$StorageAccountName'..."
    try {
      if ($script:IsRunbook) {
        $storageCtx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
      } else {
        $storageCtx = Get-StorageContext -SaName $StorageAccountName -SaContainerName $ContainerName
      }
      Write-Ok "Connected to storage account '$StorageAccountName'."
    } catch {
      Write-Warn "Storage connection failed: $_"
      $storageCtx = $null
    }
  } else {
    if ($UploadToBlob) {
      if ($Unattended) {
        throw '-StorageAccountName is required when -UploadToBlob is specified.'
      }
      $StorageAccountName = Read-Host '  Storage account name'
      $storageCtx = Get-StorageContext -SaName $StorageAccountName -SaContainerName $ContainerName
    }
  }
}

# ────────────────────────────────────────────────────────────────────────────
# Mode: ListBaselines
# ────────────────────────────────────────────────────────────────────────────

if ($Mode -eq 'ListBaselines') {
  Write-Step 'Listing available baselines...'
  $blobCtxArg  = if ($storageCtx) { $storageCtx } else { $null }
  $blobSaArg   = if ($storageCtx) { $ContainerName } else { '' }
  $baselines   = Get-AvailableBaselines -BaselinesRoot $baselinesRoot -StorageCtx $blobCtxArg -SaContainerName $blobSaArg

  if ($baselines.Count -eq 0) {
    Write-Info 'No baselines found.'
  } else {
    Write-Out ''
    Write-Out ('  {0,-30} {1,-8} {2,-26} {3}' -f 'Name', 'Source', 'Created At', 'Description') -Color Cyan
    Write-Out ('  {0,-30} {1,-8} {2,-26} {3}' -f '----', '------', '----------', '-----------') -Color DarkGray
    foreach ($b in $baselines) {
      Write-Out ('  {0,-30} {1,-8} {2,-26} {3}' -f $b.Name, $b.Source, ($b.CreatedAt ?? ''), ($b.Description ?? ''))
    }
  }
  Write-Out ''

  if ($transcriptStarted) { Stop-Transcript | Out-Null }
  try { Disconnect-MgGraph | Out-Null } catch {}
  return
}

# ────────────────────────────────────────────────────────────────────────────
# Mode: Snapshot / SetBaseline / CheckDrift  – all need a fresh snapshot
# ────────────────────────────────────────────────────────────────────────────

Write-Step "Taking snapshot of $($Endpoints.Count) endpoint(s)..."
$currentSnapshot = Invoke-Snapshot -SelectedEndpoints $Endpoints -RunFolder $runFolder
Write-Ok "Snapshot written to $runFolder"

# ── SetBaseline ───────────────────────────────────────────────────────────────

if ($Mode -eq 'SetBaseline') {
  if (-not $BaselineName) {
    if ($Unattended) { throw '-BaselineName is required for SetBaseline mode.' }
    $BaselineName       = Read-Host '  Baseline name'
    $BaselineDescription = Read-Host '  Description (optional)'
  }
  Save-Baseline -RunFolder $runFolder -BaselinesRoot $baselinesRoot `
    -Name $BaselineName -Description $BaselineDescription

  if ($UploadToBlob -and $storageCtx) {
    $blobDest = Join-Path $baselinesRoot $BaselineName
    Upload-ToBlob -LocalFolder $blobDest -BlobPrefix "baselines/$BaselineName" `
      -StorageCtx $storageCtx -SaContainerName $ContainerName
  }
}

# ── CheckDrift ────────────────────────────────────────────────────────────────

if ($Mode -eq 'CheckDrift') {
  if (-not $BaselineName) {
    if ($Unattended) { throw '-BaselineName is required for CheckDrift mode.' }

    # Show available baselines and prompt
    $available = Get-AvailableBaselines -BaselinesRoot $baselinesRoot `
      -StorageCtx $storageCtx -SaContainerName $ContainerName
    if ($available.Count -eq 0) {
      throw 'No baselines available. Run with -Mode SetBaseline first.'
    }
    Write-Out ''
    Write-Out '  Available baselines:' -Color Yellow
    $idx = 1
    foreach ($b in $available) {
      Write-Out ("    {0}. {1} [{2}]" -f $idx, $b.Name, $b.Source)
      $idx++
    }
    $sel = Read-Host '  Select baseline number'
    $BaselineName = $available[[int]$sel - 1].Name
  }

  # Resolve baseline path – download from blob if needed
  $baselinePath = Join-Path $baselinesRoot $BaselineName
  if (-not (Test-Path $baselinePath)) {
    if ($storageCtx) {
      Import-BaselineFromBlob -Name $BaselineName -BaselinesRoot $baselinesRoot `
        -StorageCtx $storageCtx -SaContainerName $ContainerName
    } else {
      throw "Baseline '$BaselineName' not found locally and no storage context available."
    }
  }

  # Load baseline snapshot
  $baselineSnapshotPath = Join-Path $baselinePath 'Snapshot.json'
  if (-not (Test-Path $baselineSnapshotPath)) {
    throw "Baseline '$BaselineName' is missing Snapshot.json. It may be corrupt."
  }
  $baselineSnapshot = Get-Content $baselineSnapshotPath -Raw | ConvertFrom-Json -AsHashtable

  Write-Step "Comparing current state against baseline '$BaselineName'..."
  $auditLookup = @{}
  if ($IncludeAuditData) {
    Write-Step 'Fetching audit data for change attribution...'
    try { $auditLookup = Get-AuditActorLookup } catch { Write-Warn "Audit lookup failed – ModifiedBy will be empty: $_" }
  }
  $driftRows = Compare-Snapshots -Baseline $baselineSnapshot -Current $currentSnapshot -SelectedEndpoints $Endpoints -AuditLookup $auditLookup
  Export-DriftReport -Rows $driftRows -RunFolder $runFolder -SelectedEndpoints $Endpoints
}

# ── Upload run to Blob ─────────────────────────────────────────────────────────

if ($UploadToBlob -and $storageCtx) {
  Upload-ToBlob -LocalFolder $runFolder -BlobPrefix "runs/$timestamp" `
    -StorageCtx $storageCtx -SaContainerName $ContainerName
}

# ── Final summary ─────────────────────────────────────────────────────────────

Write-Out ''
Write-Ok "Done. Mode: $Mode"
Write-Info "Run folder : $runFolder"
if ($UploadToBlob -and $storageCtx) {
  Write-Info "Blob prefix: $ContainerName/runs/$timestamp"
}
Write-Out ''

if ($transcriptStarted) { Stop-Transcript | Out-Null }
try { Disconnect-MgGraph | Out-Null } catch {}
