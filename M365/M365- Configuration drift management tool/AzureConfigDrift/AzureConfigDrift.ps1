<#
.SYNOPSIS
  Azure Configuration Drift Management Tool – snapshot, baseline, and drift detection
  across Entra ID, Intune, SharePoint, OneDrive, Microsoft 365 Groups, Teams, and
  Microsoft security posture. It captures tenant governance settings instead of
  enumerating every group, Team, SharePoint site, or OneDrive personal site.

.COVERAGE
  Entra ID : Conditional Access · Directory roles + PIM · Enterprise apps + OAuth2 grants
             · Named locations + auth methods policy + authorization policy
  Intune   : Device configuration · Compliance · App protection · Scripts + health scripts
             · Enrollment configurations · App assignments · Security baselines
             · Feature update profiles · Quality update profiles
  M365     : SharePoint / OneDrive tenant settings · Microsoft 365 Group governance
             · Teams tenant policies · Microsoft Secure Score controls
  Exchange : Organization · Mail flow · Client access · Defender for Office 365 policies

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
    DeviceManagementManagedDevices.Read.All, DeviceManagementScripts.Read.All,
    SharePointTenantSettings.Read.All, SecurityEvents.Read.All

  Teams tenant policies use the MicrosoftTeams module and delegated interactive or
  device-code authentication. They are not collected by an Automation Account or
  Graph client-secret authentication.

  Exchange tenant policies use the ExchangeOnlineManagement module and delegated
  interactive or device-code authentication. They are not collected by an Automation
  Account or Graph client-secret authentication.

  Required Azure RBAC on the Storage Account:
    Storage Blob Data Contributor

.LOCAL USAGE
  Run interactively – opens a browser for user sign-in:
    ./AzureConfigDrift.ps1

  Run with device code (SSH / headless terminal, no browser available):
    ./AzureConfigDrift.ps1 -AuthMethod DeviceCode

  Run as an Enterprise Application (app-only, client secret):
    ./AzureConfigDrift.ps1 -AuthMethod ClientCredentials \
        -TenantId '00000000-0000-0000-0000-000000000000' \
        -ClientId  '11111111-0000-0000-0000-000000000000' \
        -ClientSecret $env:APP_SECRET -Mode Snapshot -Unattended

  Target a specific tenant:
    ./AzureConfigDrift.ps1 -TenantId '00000000-0000-0000-0000-000000000000'

.NOTES
  Requires PowerShell 7.0+
  Modules: Microsoft.Graph.Authentication, Az.Accounts (for MI/SP), Az.Storage (for blob)
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
  # IntuneScripts, IntuneEnrollment, IntuneAppAssignments,
  # IntuneSecurityBaselines, IntuneFeatureUpdateProfiles, IntuneQualityUpdateProfiles,
  # SharePointOneDriveTenantSettings, M365GroupGovernance, TeamsTenantPolicies,
  # DefenderSecurityPosture, ExchangeOrganization, ExchangeMailFlow,
  # ExchangeClientAccess, ExchangeDefenderForOffice
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
  # Interactive        – opens a browser pop-up (default).
  # DeviceCode         – prints a code to enter at aka.ms/devicelogin; use this on headless
  #                      terminals, SSH sessions, or when a browser is unavailable.
  # ClientCredentials  – app-only sign-in via an Entra App Registration client secret.
  #                      Requires -TenantId, -ClientId, and -ClientSecret.
  # Managed Identity is used automatically when the script is running as a Runbook.
  [ValidateSet('Interactive', 'DeviceCode', 'ClientCredentials')]
  [string]$AuthMethod = 'Interactive',

  # Entra tenant ID to authenticate against. Required for ClientCredentials auth.
  [string]$TenantId,

  # App Registration Application (client) ID. Required when -AuthMethod ClientCredentials.
  [string]$ClientId,

  # App Registration client secret. Required when -AuthMethod ClientCredentials.
  # Pass as a SecureString, e.g.: -ClientSecret (ConvertTo-SecureString $env:APP_SECRET -AsPlainText -Force)
  [SecureString]$ClientSecret,

  # When specified with CheckDrift, fetches Intune and Entra audit logs to populate
  # the ModifiedBy field in drift rows. Requires AuditLog.Read.All consent.
  [switch]$IncludeAuditData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Constants ───────────────────────────────────────────────────────────────

$script:ToolVersion = '1.6'
$script:ToolName    = 'Azure Config Drift'

$script:AllEndpoints = @(
  'EntraCA', 'EntraDirectoryRoles', 'EntraEnterpriseApps', 'EntraAuthMethods',
  'IntuneDeviceConfig', 'IntuneCompliance', 'IntuneAppProtection',
  'IntuneScripts', 'IntuneEnrollment', 'IntuneAppAssignments', 'IntuneSecurityBaselines',
  'IntuneFeatureUpdateProfiles', 'IntuneQualityUpdateProfiles',
  'SharePointOneDriveTenantSettings', 'M365GroupGovernance', 'TeamsTenantPolicies',
  'DefenderSecurityPosture', 'ExchangeOrganization', 'ExchangeMailFlow',
  'ExchangeClientAccess', 'ExchangeDefenderForOffice'
)

$script:DelegatedOnlyEndpoints = @(
  'TeamsTenantPolicies',
  'ExchangeOrganization', 'ExchangeMailFlow', 'ExchangeClientAccess', 'ExchangeDefenderForOffice'
)
$script:ExchangeEndpoints = @(
  'ExchangeOrganization', 'ExchangeMailFlow', 'ExchangeClientAccess', 'ExchangeDefenderForOffice'
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
  IntuneSecurityBaselines      = 'Intune – Security Baselines'
  IntuneFeatureUpdateProfiles  = 'Intune – Feature Update Profiles'
  IntuneQualityUpdateProfiles  = 'Intune – Quality Update Profiles'
  SharePointOneDriveTenantSettings = 'SharePoint / OneDrive – Tenant Settings'
  M365GroupGovernance         = 'Microsoft 365 – Group Governance'
  TeamsTenantPolicies         = 'Microsoft Teams – Tenant Policies'
  DefenderSecurityPosture     = 'Microsoft Defender – Secure Score Controls'
  ExchangeOrganization         = 'Exchange Online – Organization'
  ExchangeMailFlow             = 'Exchange Online – Mail Flow'
  ExchangeClientAccess         = 'Exchange Online – Client Access'
  ExchangeDefenderForOffice    = 'Defender for Office 365 – Policies'
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
  'DeviceManagementScripts.Read.All',
  'SharePointTenantSettings.Read.All',
  'SecurityEvents.Read.All'
)

$script:TeamsConnected = $false
$script:ExchangeConnected = $false
$script:ExchangeConnectionId = $null
$script:GraphConnected = $false
$script:GraphTenantId = $null
$script:LastSnapshotEndpointStatus = @{}

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

function Ensure-ExchangeOnlineManagementModule {
  [CmdletBinding()]
  param()

  $minimumSupportedVersion = [version]'7.4.0'
  if ($PSVersionTable.PSVersion -lt $minimumSupportedVersion) {
    throw "Exchange endpoints require PowerShell 7.4 or later. Current version: $($PSVersionTable.PSVersion)."
  }

  $minimumCurrentVersion = [version]'7.6.0'
  if ($PSVersionTable.PSVersion -ge $minimumCurrentVersion) {
    Ensure-Module -Name 'ExchangeOnlineManagement'
    return
  }

  $compatibleVersion = [version]'3.9.2'
  $module = Get-Module -ListAvailable -Name 'ExchangeOnlineManagement' |
    Where-Object { $_.Version -eq $compatibleVersion } |
    Select-Object -First 1
  if (-not $module) {
    Write-Step "Installing ExchangeOnlineManagement $compatibleVersion for PowerShell $($PSVersionTable.PSVersion)..."
    Install-Module -Name 'ExchangeOnlineManagement' -RequiredVersion $compatibleVersion -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    $module = Get-Module -ListAvailable -Name 'ExchangeOnlineManagement' |
      Where-Object { $_.Version -eq $compatibleVersion } |
      Select-Object -First 1
  }
  if (-not $module) {
    throw "ExchangeOnlineManagement $compatibleVersion could not be installed for PowerShell $($PSVersionTable.PSVersion). Upgrade to PowerShell 7.6 or install the compatible module version manually."
  }
  Import-Module -Name $module.Path -Force -ErrorAction Stop
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

function Connect-TeamsForSnapshot {
  <#
  .SYNOPSIS
    Connects to Microsoft Teams PowerShell for tenant-policy collection.

  .DESCRIPTION
    Establishes a separate delegated Teams session because tenant policy cmdlets
    aren't exposed through the Microsoft Graph connection used by this tool.

  .NOTES
    Read-only. Requires the MicrosoftTeams module and an account permitted to
    read Teams tenant policies.
  #>
  [CmdletBinding()]
  param()

  if ($script:TeamsConnected) { return }
  if ($script:IsRunbook -or $AuthMethod -eq 'ClientCredentials') {
    throw 'TeamsTenantPolicies requires delegated Interactive or DeviceCode authentication. MicrosoftTeams certificate authentication is not configured by this tool.'
  }

  Write-Step 'Authenticating to Microsoft Teams PowerShell...'
  $teamsParams = @{ ErrorAction = 'Stop' }
  if ($TenantId) { $teamsParams['TenantId'] = $TenantId }
  if ($AuthMethod -eq 'DeviceCode') { $teamsParams['UseDeviceAuthentication'] = $true }
  Connect-MicrosoftTeams @teamsParams | Out-Null
  $script:TeamsConnected = $true
  Write-Ok 'Connected to Microsoft Teams PowerShell.'
}

function Test-IsTeamsFeatureNotEnabled {
  <#
  .SYNOPSIS
    Identifies a Teams cmdlet unavailable because its feature isn't enabled.

  .DESCRIPTION
    Some MicrosoftTeams module commands are exposed before their backing service
    type is enabled for a tenant. The service reports this as error 40003.
  #>
  [CmdletBinding()]
  param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

  $message = $ErrorRecord.Exception.Message
  return $message -match '(?i)not currently enabled in flighting' -or
    $message -match '"errorCode"\s*:\s*"?40003"?'
}

function Connect-ExchangeForSnapshot {
  <#
  .SYNOPSIS
    Connects to Exchange Online PowerShell for tenant-policy collection.

  .DESCRIPTION
    Establishes a separate delegated Exchange Online session because Exchange
    policy cmdlets aren't exposed through the Microsoft Graph connection.

  .NOTES
    Read-only. Requires ExchangeOnlineManagement and Exchange RBAC access to
    the selected tenant policy surfaces.
  #>
  [CmdletBinding()]
  param()

  if ($script:ExchangeConnected) { return }
  if ($script:IsRunbook -or $AuthMethod -eq 'ClientCredentials') {
    throw 'Exchange endpoints require delegated Interactive or DeviceCode authentication. Exchange certificate or managed-identity authentication is not configured by this tool.'
  }

  Write-Step 'Authenticating to Exchange Online PowerShell...'
  $existingConnectionIds = @(
    Get-ConnectionInformation -ErrorAction Stop |
      ForEach-Object { [string]$_.ConnectionId }
  )
  $exchangeParams = @{
    ShowBanner = $false
    ErrorAction = 'Stop'
  }
  if ($AuthMethod -eq 'DeviceCode') { $exchangeParams['Device'] = $true }
  Connect-ExchangeOnline @exchangeParams | Out-Null

  $newConnections = @(
    Get-ConnectionInformation -ErrorAction Stop |
      Where-Object { $_.State -eq 'Connected' -and $_.ConnectionId -notin $existingConnectionIds }
  )
  if ($newConnections.Count -ne 1) {
    foreach ($connection in $newConnections) {
      try {
        Disconnect-ExchangeOnline -ConnectionId $connection.ConnectionId -Confirm:$false | Out-Null
      } catch {
        Write-Warn "Could not disconnect an untracked Exchange Online session: $_"
      }
    }
    throw "Exchange Online connection tracking failed: expected one new connection but found $($newConnections.Count)."
  }

  $script:ExchangeConnectionId = [string]$newConnections[0].ConnectionId
  if (-not $script:GraphTenantId -or [string]$newConnections[0].TenantID -ne $script:GraphTenantId) {
    try {
      Disconnect-ExchangeOnline -ConnectionId $script:ExchangeConnectionId -Confirm:$false | Out-Null
    } catch {
      Write-Warn "Could not disconnect the Exchange Online tenant-mismatch session: $_"
    }
    $script:ExchangeConnectionId = $null
    throw "Exchange Online connected to tenant '$($newConnections[0].TenantID)', but Microsoft Graph is connected to tenant '$($script:GraphTenantId ?? 'unknown')'. Sign in to the same tenant and try again."
  }

  $script:ExchangeConnected = $true
  Write-Ok 'Connected to Exchange Online PowerShell.'
}

function Test-IsExchangeCapabilityUnavailable {
  <#
  .SYNOPSIS
    Identifies confirmed license or feature availability failures.

  .DESCRIPTION
    Defender for Office 365 cmdlets can be present in the module while their
    service feature isn't available in a tenant. Permission and transport errors
    aren't classified as capability failures.
  #>
  [CmdletBinding()]
  param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

  $message = $ErrorRecord.Exception.Message
  return $message -match '(?i)(feature|capability).{0,80}(not|isn''t).{0,40}(enabled|available)' -or
    $message -match '(?i)(requires|does not have).{0,80}(license|licence)' -or
    $message -match '(?i)(not licensed|license is required)'
}

function Invoke-ExchangeSnapshotCommand {
  <#
  .SYNOPSIS
    Invokes one reviewed Exchange policy cmdlet and records its collection state.

  .DESCRIPTION
    Ensures every collection is complete when the cmdlet supports ResultSize.
    Only explicitly optional Defender capability failures become visible skipped
    records; other failures propagate to the containing Exchange endpoint.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Name,
    [hashtable]$AdditionalParameters = @{},
    [switch]$CapabilityOptional
  )

  $command = Get-Command -Name $Name -ErrorAction SilentlyContinue
  if (-not $command) {
    throw "Exchange command '$Name' isn't available in the connected session. Verify the ExchangeOnlineManagement module version and the account's Exchange RBAC permissions."
  }

  $parameters = @{ ErrorAction = 'Stop' }
  if ($command.Parameters.ContainsKey('ResultSize')) {
    $parameters['ResultSize'] = 'Unlimited'
  }
  foreach ($key in $AdditionalParameters.Keys) {
    $parameters[$key] = $AdditionalParameters[$key]
  }

  try {
    return [pscustomobject]@{
      status = 'Collected'
      reason = ''
      data   = @(& $command @parameters | ForEach-Object { ConvertTo-ExchangeSnapshotValue -Value $_ })
    }
  } catch {
    if ($CapabilityOptional -and (Test-IsExchangeCapabilityUnavailable -ErrorRecord $_)) {
      Write-Warn "  Skipping ${Name}: Exchange reports that the required Defender feature or license is unavailable."
      return [pscustomobject]@{
        status = 'Skipped'
        reason = 'The required Defender for Office 365 feature or license is unavailable in this tenant.'
        data   = @()
      }
    }
    throw
  }
}

function ConvertTo-ExchangeSnapshotValue {
  <#
  .SYNOPSIS
    Removes volatile Exchange remoting metadata from a policy result.

  .DESCRIPTION
    Exchange cmdlets return server and remoting metadata that can change without
    a configuration change. Recursively removing those fields prevents false
    positives while retaining the returned policy configuration.
  #>
  [CmdletBinding()]
  param([AllowNull()]$Value)

  if ($null -eq $Value -or
      $Value -is [string] -or
      $Value -is [char] -or
      $Value -is [bool] -or
      $Value -is [byte] -or
      $Value -is [sbyte] -or
      $Value -is [int16] -or
      $Value -is [uint16] -or
      $Value -is [int32] -or
      $Value -is [uint32] -or
      $Value -is [int64] -or
      $Value -is [uint64] -or
      $Value -is [single] -or
      $Value -is [double] -or
      $Value -is [decimal] -or
      $Value -is [datetime] -or
      $Value -is [datetimeoffset] -or
      $Value -is [timespan] -or
      $Value -is [guid] -or
      $Value -is [System.Enum]) {
    return $Value
  }

  $volatileProperties = @(
    'WhenChanged', 'WhenChangedUTC', 'WhenCreated', 'WhenCreatedUTC',
    'ExchangeVersion', 'AdminDisplayVersion', 'ObjectState',
    'RunspaceId', 'PSComputerName', 'PSShowComputerName', 'PSSourceJobInstanceId'
  )

  if ($Value -is [System.Collections.IDictionary]) {
    $snapshot = [ordered]@{}
    foreach ($key in $Value.Keys) {
      if ($key -notin $volatileProperties) {
        $snapshot[$key] = ConvertTo-ExchangeSnapshotValue -Value $Value[$key]
      }
    }
    return [pscustomobject]$snapshot
  }

  if ($Value -is [System.Collections.IEnumerable]) {
    return @($Value | ForEach-Object { ConvertTo-ExchangeSnapshotValue -Value $_ })
  }

  $properties = @($Value.PSObject.Properties | Where-Object { $_.Name -notin $volatileProperties })
  if ($properties.Count -eq 0) { return $Value }

  $snapshot = [ordered]@{}
  foreach ($property in $properties) {
    $snapshot[$property.Name] = ConvertTo-ExchangeSnapshotValue -Value $property.Value
  }
  return [pscustomobject]$snapshot
}

function Get-ExchangeSnapshotItemIdentity {
  <#
  .SYNOPSIS
    Returns a stable identifier for an Exchange policy object.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Value,
    [Parameter(Mandatory)][int]$Index
  )

  foreach ($property in @('ExternalDirectoryObjectId', 'Guid', 'Identity', 'Id', 'Name', 'DomainName', 'PrimarySmtpAddress')) {
    $candidate = Get-GraphPropValue -Obj $Value -Name $property
    if ($null -ne $candidate -and -not [string]::IsNullOrWhiteSpace([string]$candidate)) {
      return [string]$candidate
    }
  }
  return "index-$Index"
}

function Get-ExchangeEndpointSnapshot {
  <#
  .SYNOPSIS
    Collects a reviewed set of Exchange Online tenant policy commands.

  .DESCRIPTION
    Emits one snapshot record per command, enabling drift reports to identify
    the Exchange configuration surface that changed without collecting mailbox
    or recipient data.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Endpoint,
    [Parameter(Mandatory)][object[]]$Definitions
  )

  Connect-ExchangeForSnapshot
  $records = [System.Collections.Generic.List[object]]::new()

  foreach ($definition in $Definitions) {
    $name = [string]$definition.Name
    Write-Info "  Reading $name..."
    $invokeParams = @{
      Name = $name
      CapabilityOptional = ($definition.ContainsKey('CapabilityOptional') -and [bool]$definition.CapabilityOptional)
    }
    if ($definition.ContainsKey('AdditionalParameters')) {
      $invokeParams['AdditionalParameters'] = $definition.AdditionalParameters
    }
    $result = Invoke-ExchangeSnapshotCommand @invokeParams
    $recordKey = if ($definition.ContainsKey('Key')) { [string]$definition.Key } else { $name }

    if ($result.status -eq 'Collected') {
      if ($result.data.Count -eq 0) { continue }

      $index = 0
      foreach ($item in $result.data) {
        $index++
        $itemId = Get-ExchangeSnapshotItemIdentity -Value $item -Index $index
        $itemName = Get-GraphPropValue -Obj $item -Name 'DisplayName'
        if (-not $itemName) { $itemName = Get-GraphPropValue -Obj $item -Name 'Name' }
        if (-not $itemName) { $itemName = $itemId }

        [void]$records.Add([pscustomobject]@{
          id               = "$Endpoint/$recordKey/$itemId"
          displayName      = "$($definition.DisplayName) – $itemName"
          command          = $name
          collectionStatus = $result.status
          collectionReason = $result.reason
          settings         = $item
        })
      }
      continue
    }

    [void]$records.Add([pscustomobject]@{
      id               = "$Endpoint/$recordKey"
      displayName      = [string]$definition.DisplayName
      command          = $name
      collectionStatus = $result.status
      collectionReason = $result.reason
      settings         = $result.data
    })
  }

  return $records
}

function Get-IntuneAssignments {
  param(
    [Parameter(Mandatory)][string]$Uri,
    [Parameter(Mandatory)][string]$ResourceName
  )

  try {
    return @(Get-GraphPaged -Uri $Uri)
  } catch {
    Write-Warn "  Assignments for '$ResourceName': $_"
    return @()
  }
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
        assignments          = Get-IntuneAssignments -Uri "/beta/deviceManagement/deviceConfigurations/$($cfg.id)/assignments" -ResourceName $cfg.displayName
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
        assignments          = Get-IntuneAssignments -Uri "/beta/deviceManagement/configurationPolicies/$($policy.id)/assignments" -ResourceName $policy.name
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
      assignments          = Get-IntuneAssignments -Uri "/v1.0/deviceManagement/deviceCompliancePolicies/$($_.id)/assignments" -ResourceName $_.displayName
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
      assignments          = Get-IntuneAssignments -Uri "/beta/deviceAppManagement/managedAppPolicies/$($_.id)/assignments" -ResourceName $_.displayName
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
        assignments          = Get-IntuneAssignments -Uri "/beta/deviceManagement/deviceManagementScripts/$($s.id)/assignments" -ResourceName $s.displayName
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
        assignments          = Get-IntuneAssignments -Uri "/beta/deviceManagement/deviceHealthScripts/$($s.id)/assignments" -ResourceName $s.displayName
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
      assignments          = Get-IntuneAssignments -Uri "/v1.0/deviceManagement/deviceEnrollmentConfigurations/$($_.id)/assignments" -ResourceName $_.displayName
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
      assignments          = Get-IntuneAssignments -Uri "/beta/deviceManagement/intents/$($intent.id)/assignments" -ResourceName $intent.displayName
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

function Get-IntuneFeatureUpdateProfilesSnapshot {
  Write-Info 'Collecting Intune Windows Feature Update profiles...'
  $result = [System.Collections.Generic.List[object]]::new()

  $profiles = @()
  try {
    $profiles = Get-GraphPaged -Uri '/beta/deviceManagement/windowsFeatureUpdateProfiles'
  } catch { Write-Warn "Feature update profiles: $_" }

  foreach ($profile in $profiles) {
    $assignments = @()
    try {
      $assignments = Get-GraphPaged -Uri "/beta/deviceManagement/windowsFeatureUpdateProfiles/$($profile.id)/assignments"
    } catch { Write-Warn "  Assignments for feature update profile '$($profile.displayName)': $_" }

    [void]$result.Add([pscustomobject]@{
      id                         = $profile.id
      displayName                = $profile.displayName
      description                = (Get-GraphPropValue -Obj $profile -Name 'description')
      featureUpdateVersion       = (Get-GraphPropValue -Obj $profile -Name 'featureUpdateVersion')
      installLatestWindows10OnWindows11IneligibleDevice = (Get-GraphPropValue -Obj $profile -Name 'installLatestWindows10OnWindows11IneligibleDevice')
      rolloutSettings            = (Get-GraphPropValue -Obj $profile -Name 'rolloutSettings')
      deployableContentDisplayName = (Get-GraphPropValue -Obj $profile -Name 'deployableContentDisplayName')
      endOfSupportDate           = (Get-GraphPropValue -Obj $profile -Name 'endOfSupportDate')
      createdDateTime            = $profile.createdDateTime
      lastModifiedDateTime       = $profile.lastModifiedDateTime
      assignments                = $assignments
    })
  }
  return $result
}

function Get-IntuneQualityUpdateProfilesSnapshot {
  Write-Info 'Collecting Intune Windows Quality Update profiles...'
  $result = [System.Collections.Generic.List[object]]::new()

  $profiles = @()
  try {
    $profiles = Get-GraphPaged -Uri '/beta/deviceManagement/windowsQualityUpdateProfiles'
  } catch { Write-Warn "Quality update profiles: $_" }

  foreach ($profile in $profiles) {
    $assignments = @()
    try {
      $assignments = Get-GraphPaged -Uri "/beta/deviceManagement/windowsQualityUpdateProfiles/$($profile.id)/assignments"
    } catch { Write-Warn "  Assignments for quality update profile '$($profile.displayName)': $_" }

    [void]$result.Add([pscustomobject]@{
      id                   = $profile.id
      displayName          = $profile.displayName
      description          = (Get-GraphPropValue -Obj $profile -Name 'description')
      expeditedUpdateSettings = (Get-GraphPropValue -Obj $profile -Name 'expeditedUpdateSettings')
      releaseDateDisplayName  = (Get-GraphPropValue -Obj $profile -Name 'releaseDateDisplayName')
      deployableContentDisplayName = (Get-GraphPropValue -Obj $profile -Name 'deployableContentDisplayName')
      createdDateTime      = $profile.createdDateTime
      lastModifiedDateTime = $profile.lastModifiedDateTime
      assignments          = $assignments
    })
  }
  return $result
}

function Get-SharePointOneDriveTenantSettingsSnapshot {
  Write-Info 'Collecting SharePoint and OneDrive tenant settings...'
  return [pscustomobject]@{
    id       = 'SharePointOneDriveTenantSettings'
    settings = Invoke-GraphSingle -Uri '/v1.0/admin/sharepoint/settings'
  }
}

function Get-M365GroupGovernanceSnapshot {
  <#
  .SYNOPSIS
    Captures tenant-wide Microsoft 365 Group governance settings.

  .DESCRIPTION
    Captures only Group.Unified directory settings and group lifecycle policies.
    It intentionally doesn't enumerate individual Microsoft 365 Groups.

  .NOTES
    Read-only. Requires Directory.Read.All.
  #>
  [CmdletBinding()]
  param()

  Write-Info 'Collecting Microsoft 365 Group governance settings...'
  # Group.Unified tenant settings are currently available only in Microsoft Graph beta.
  $directorySettings = Get-GraphPaged -Uri '/beta/settings'
  $groupSettings = @($directorySettings | Where-Object {
    [string](Get-GraphPropValue -Obj $_ -Name 'displayName') -like 'Group.Unified*'
  })
  $lifecyclePolicies = Get-GraphPaged -Uri '/v1.0/groupLifecyclePolicies'

  return [pscustomobject]@{
    id                = 'M365GroupGovernance'
    directorySettings = $groupSettings
    lifecyclePolicies = $lifecyclePolicies
  }
}

function Get-TeamsTenantPoliciesSnapshot {
  <#
  .SYNOPSIS
    Captures Microsoft Teams tenant configuration and policy objects.

  .DESCRIPTION
    Invokes Teams PowerShell cmdlets that expose tenant configuration and policy
    objects. It doesn't enumerate individual Teams, channels, users, or members.

  .NOTES
    Read-only. Requires the MicrosoftTeams module and delegated Teams administration.
  #>
  [CmdletBinding()]
  param()

  Connect-TeamsForSnapshot
  Write-Info 'Collecting Microsoft Teams tenant policies...'

  $coreCommands = @(
    'Get-CsTenant',
    'Get-CsExternalAccessPolicy',
    'Get-CsTeamsCustomBannerText',
    'Get-CsTeamsSettingsCustomApp',
    'Get-CsTeamsTranslationRule',
    'Get-CsTeamsUnassignedNumberTreatment'
  )
  $policyCommands = @(
    Get-Command -Module MicrosoftTeams -CommandType Cmdlet,Function -ErrorAction Stop |
      Where-Object {
        $_.Name -match '^Get-CsTeams.+(Policy|Configuration)$' -or
        $_.Name -match '^Get-Cs(Online|Tenant).+(Policy|Configuration)$' -or
        $_.Name -in $coreCommands
      } |
      Sort-Object -Property Name
  )
  if ($policyCommands.Count -eq 0) {
    throw 'No supported Teams tenant policy cmdlets were found in the MicrosoftTeams module.'
  }

  $policies = [ordered]@{}
  foreach ($command in $policyCommands) {
    Write-Info "  Reading $($command.Name)..."
    try {
      $policies[$command.Name] = @(& $command -ErrorAction Stop)
    } catch {
      if (Test-IsTeamsFeatureNotEnabled -ErrorRecord $_) {
        Write-Warn "  Skipping $($command.Name): its Teams feature isn't enabled for this tenant."
        continue
      }
      throw "Teams tenant policy collection failed for $($command.Name): $($_.Exception.Message)"
    }
  }

  return [pscustomobject]@{
    id       = 'TeamsTenantPolicies'
    policies = $policies
  }
}

function Get-DefenderSecurityPostureSnapshot {
  Write-Info 'Collecting Microsoft Secure Score control profiles...'
  $profiles = Get-GraphPaged -Uri '/v1.0/security/secureScoreControlProfiles'
  return $profiles | ForEach-Object {
    [pscustomobject]@{
      id                   = $_.id
      displayName          = $_.title
      lastModifiedDateTime = $_.lastModifiedDateTime
      control              = $_
    }
  }
}

function Get-ExchangeOrganizationSnapshot {
  Write-Info 'Collecting Exchange Online organization configuration...'
  $definitions = @(
    @{ Name = 'Get-OrganizationConfig'; DisplayName = 'Organization configuration' },
    @{ Name = 'Get-AcceptedDomain'; DisplayName = 'Accepted domains' },
    @{ Name = 'Get-RemoteDomain'; DisplayName = 'Remote domains' },
    @{ Name = 'Get-EmailAddressPolicy'; DisplayName = 'Email address policies' },
    @{ Name = 'Get-FederatedOrganizationIdentifier'; DisplayName = 'Federated organization identifier' },
    @{ Name = 'Get-FederationTrust'; DisplayName = 'Federation trusts' },
    @{ Name = 'Get-IntraOrganizationConnector'; DisplayName = 'Intra-organization connectors' },
    @{ Name = 'Get-OrganizationRelationship'; DisplayName = 'Organization relationships' },
    @{ Name = 'Get-SharingPolicy'; DisplayName = 'Sharing policies' },
    @{ Name = 'Get-RoleAssignmentPolicy'; DisplayName = 'Role assignment policies' },
    @{ Name = 'Get-ManagementScope'; DisplayName = 'Management scopes' }
  )
  return Get-ExchangeEndpointSnapshot -Endpoint 'ExchangeOrganization' -Definitions $definitions
}

function Get-ExchangeMailFlowSnapshot {
  Write-Info 'Collecting Exchange Online mail flow configuration...'
  $definitions = @(
    @{ Name = 'Get-TransportConfig'; DisplayName = 'Global transport configuration' },
    @{ Name = 'Get-TransportRule'; DisplayName = 'Mail flow rules' },
    @{ Name = 'Get-InboundConnector'; DisplayName = 'Inbound connectors' },
    @{ Name = 'Get-OutboundConnector'; DisplayName = 'Outbound connectors' },
    @{ Name = 'Get-JournalRule'; DisplayName = 'Journaling rules' }
  )
  return Get-ExchangeEndpointSnapshot -Endpoint 'ExchangeMailFlow' -Definitions $definitions
}

function Get-ExchangeClientAccessSnapshot {
  Write-Info 'Collecting Exchange Online client access configuration...'
  $definitions = @(
    @{ Name = 'Get-OwaMailboxPolicy'; DisplayName = 'Outlook on the web mailbox policies' },
    @{ Name = 'Get-MobileDeviceMailboxPolicy'; DisplayName = 'Mobile device mailbox policies' },
    @{ Name = 'Get-ActiveSyncOrganizationSettings'; DisplayName = 'ActiveSync organization settings' },
    @{ Name = 'Get-ActiveSyncDeviceAccessRule'; DisplayName = 'ActiveSync device access rules' },
    @{ Name = 'Get-AuthenticationPolicy'; DisplayName = 'Authentication policies' }
  )
  return Get-ExchangeEndpointSnapshot -Endpoint 'ExchangeClientAccess' -Definitions $definitions
}

function Get-ExchangeDefenderForOfficeSnapshot {
  Write-Info 'Collecting Defender for Office 365 policy configuration...'
  $definitions = @(
    @{ Name = 'Get-HostedContentFilterPolicy'; DisplayName = 'Anti-spam policies'; CapabilityOptional = $true },
    @{ Name = 'Get-HostedContentFilterRule'; DisplayName = 'Anti-spam policy rules'; CapabilityOptional = $true },
    @{ Name = 'Get-HostedConnectionFilterPolicy'; DisplayName = 'Connection filter policies'; CapabilityOptional = $true },
    @{ Name = 'Get-HostedOutboundSpamFilterPolicy'; DisplayName = 'Outbound spam policies'; CapabilityOptional = $true },
    @{ Name = 'Get-HostedOutboundSpamFilterRule'; DisplayName = 'Outbound spam policy rules'; CapabilityOptional = $true },
    @{ Name = 'Get-MalwareFilterPolicy'; DisplayName = 'Anti-malware policies'; CapabilityOptional = $true },
    @{ Name = 'Get-MalwareFilterRule'; DisplayName = 'Anti-malware policy rules'; CapabilityOptional = $true },
    @{ Name = 'Get-AntiPhishPolicy'; DisplayName = 'Anti-phishing policies'; CapabilityOptional = $true },
    @{ Name = 'Get-AntiPhishRule'; DisplayName = 'Anti-phishing policy rules'; CapabilityOptional = $true },
    @{ Name = 'Get-SafeAttachmentPolicy'; DisplayName = 'Safe Attachments policies'; CapabilityOptional = $true },
    @{ Name = 'Get-SafeAttachmentRule'; DisplayName = 'Safe Attachments policy rules'; CapabilityOptional = $true },
    @{ Name = 'Get-SafeLinksPolicy'; DisplayName = 'Safe Links policies'; CapabilityOptional = $true },
    @{ Name = 'Get-SafeLinksRule'; DisplayName = 'Safe Links policy rules'; CapabilityOptional = $true },
    @{ Name = 'Get-AtpPolicyForO365'; DisplayName = 'Microsoft 365 app protection policies'; CapabilityOptional = $true },
    @{ Name = 'Get-DkimSigningConfig'; DisplayName = 'DKIM signing configuration'; CapabilityOptional = $true },
    @{ Name = 'Get-QuarantinePolicy'; DisplayName = 'Quarantine policies'; CapabilityOptional = $true },
    @{ Name = 'Get-EOPProtectionPolicyRule'; DisplayName = 'Preset security policy EOP protection rules'; CapabilityOptional = $true },
    @{ Name = 'Get-ATPProtectionPolicyRule'; DisplayName = 'Preset security policy Defender protection rules'; CapabilityOptional = $true },
    @{ Name = 'Get-ATPBuiltInProtectionRule'; DisplayName = 'Built-in protection rule'; CapabilityOptional = $true },
    @{ Name = 'Get-ReportSubmissionPolicy'; DisplayName = 'User report submission policy'; CapabilityOptional = $true },
    @{ Name = 'Get-ReportSubmissionRule'; DisplayName = 'User report submission rule'; CapabilityOptional = $true },
    @{ Name = 'Get-TenantAllowBlockListSpoofItems'; DisplayName = 'Tenant Allow/Block List spoof entries'; CapabilityOptional = $true },
    @{ Name = 'Get-TenantAllowBlockListItems'; Key = 'Get-TenantAllowBlockListItems-Sender'; DisplayName = 'Tenant Allow/Block List sender entries with expiration'; AdditionalParameters = @{ ListType = 'Sender' }; CapabilityOptional = $true },
    @{ Name = 'Get-TenantAllowBlockListItems'; Key = 'Get-TenantAllowBlockListItems-Sender-NoExpiration'; DisplayName = 'Tenant Allow/Block List permanent sender entries'; AdditionalParameters = @{ ListType = 'Sender'; NoExpiration = $true }; CapabilityOptional = $true },
    @{ Name = 'Get-TenantAllowBlockListItems'; Key = 'Get-TenantAllowBlockListItems-Url'; DisplayName = 'Tenant Allow/Block List URL entries with expiration'; AdditionalParameters = @{ ListType = 'Url' }; CapabilityOptional = $true },
    @{ Name = 'Get-TenantAllowBlockListItems'; Key = 'Get-TenantAllowBlockListItems-Url-NoExpiration'; DisplayName = 'Tenant Allow/Block List permanent URL entries'; AdditionalParameters = @{ ListType = 'Url'; NoExpiration = $true }; CapabilityOptional = $true },
    @{ Name = 'Get-TenantAllowBlockListItems'; Key = 'Get-TenantAllowBlockListItems-FileHash'; DisplayName = 'Tenant Allow/Block List file hash entries with expiration'; AdditionalParameters = @{ ListType = 'FileHash' }; CapabilityOptional = $true },
    @{ Name = 'Get-TenantAllowBlockListItems'; Key = 'Get-TenantAllowBlockListItems-FileHash-NoExpiration'; DisplayName = 'Tenant Allow/Block List permanent file hash entries'; AdditionalParameters = @{ ListType = 'FileHash'; NoExpiration = $true }; CapabilityOptional = $true },
    @{ Name = 'Get-TenantAllowBlockListItems'; Key = 'Get-TenantAllowBlockListItems-IP'; DisplayName = 'Tenant Allow/Block List IP entries with expiration'; AdditionalParameters = @{ ListType = 'IP' }; CapabilityOptional = $true },
    @{ Name = 'Get-TenantAllowBlockListItems'; Key = 'Get-TenantAllowBlockListItems-IP-NoExpiration'; DisplayName = 'Tenant Allow/Block List permanent IP entries'; AdditionalParameters = @{ ListType = 'IP'; NoExpiration = $true }; CapabilityOptional = $true },
    @{ Name = 'Get-SecOpsOverridePolicy'; DisplayName = 'Advanced Delivery SecOps override policy'; CapabilityOptional = $true },
    @{ Name = 'Get-ExoSecOpsOverrideRule'; DisplayName = 'Advanced Delivery SecOps override rules'; CapabilityOptional = $true },
    @{ Name = 'Get-PhishSimOverridePolicy'; DisplayName = 'Advanced Delivery phishing simulation override policy'; CapabilityOptional = $true },
    @{ Name = 'Get-ExoPhishSimOverrideRule'; DisplayName = 'Advanced Delivery phishing simulation override rules'; CapabilityOptional = $true },
    @{ Name = 'Get-TenantAllowBlockListItems'; Key = 'Get-TenantAllowBlockListItems-AdvancedDelivery-Url'; DisplayName = 'Advanced Delivery phishing simulation URL entries with expiration'; AdditionalParameters = @{ ListType = 'Url'; ListSubType = 'AdvancedDelivery' }; CapabilityOptional = $true },
    @{ Name = 'Get-TenantAllowBlockListItems'; Key = 'Get-TenantAllowBlockListItems-AdvancedDelivery-Url-NoExpiration'; DisplayName = 'Advanced Delivery permanent phishing simulation URL entries'; AdditionalParameters = @{ ListType = 'Url'; ListSubType = 'AdvancedDelivery'; NoExpiration = $true }; CapabilityOptional = $true }
  )
  return Get-ExchangeEndpointSnapshot -Endpoint 'ExchangeDefenderForOffice' -Definitions $definitions
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
  IntuneAppAssignments        = { Get-IntuneAppAssignmentsSnapshot }
  IntuneSecurityBaselines     = { Get-IntuneSecurityBaselinesSnapshot }
  IntuneFeatureUpdateProfiles = { Get-IntuneFeatureUpdateProfilesSnapshot }
  IntuneQualityUpdateProfiles = { Get-IntuneQualityUpdateProfilesSnapshot }
  SharePointOneDriveTenantSettings = { Get-SharePointOneDriveTenantSettingsSnapshot }
  M365GroupGovernance         = { Get-M365GroupGovernanceSnapshot }
  TeamsTenantPolicies         = { Get-TeamsTenantPoliciesSnapshot }
  DefenderSecurityPosture     = { Get-DefenderSecurityPostureSnapshot }
  ExchangeOrganization         = { Get-ExchangeOrganizationSnapshot }
  ExchangeMailFlow             = { Get-ExchangeMailFlowSnapshot }
  ExchangeClientAccess         = { Get-ExchangeClientAccessSnapshot }
  ExchangeDefenderForOffice    = { Get-ExchangeDefenderForOfficeSnapshot }
}

# ─── Snapshot Orchestrator ───────────────────────────────────────────────────

function Invoke-Snapshot {
  param(
    [Parameter(Mandatory)][string[]]$SelectedEndpoints,
    [Parameter(Mandatory)][string]$RunFolder
  )

  $combined = [ordered]@{}
  $summary  = [System.Collections.Generic.List[pscustomobject]]::new()
  $script:LastSnapshotEndpointStatus = @{}

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
      $skippedComponents = @(
        $data | Where-Object {
          (Get-GraphPropValue -Obj $_ -Name 'collectionStatus') -eq 'Skipped'
        }
      )
      if ($skippedComponents.Count -gt 0) {
        $status = "INCOMPLETE: $($skippedComponents.Count) component(s) unavailable"
        Write-Warn "$label – $itemCount item(s) collected, but $($skippedComponents.Count) component(s) were unavailable."
      } else {
        Write-Ok "$label – $itemCount item(s) collected"
      }
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

    $script:LastSnapshotEndpointStatus[$ep] = $status
    $combined[$ep] = $data
  }

  # Write combined snapshot
  Write-JsonFile -Object $combined -Path (Join-Path $RunFolder 'Snapshot.json')

  # Print collection summary
  Write-Out ''
  Write-Out '  ── Snapshot Summary ────────────────────────────────────────────' -Color Cyan
  foreach ($row in $summary) {
    $statusIcon = if ($row.Status -eq 'OK') { '✓' } elseif ($row.Status -like 'INCOMPLETE:*') { '⚠' } else { '✗' }
    $color      = if ($row.Status -eq 'OK') { 'Green' } elseif ($row.Status -like 'INCOMPLETE:*') { 'DarkYellow' } else { 'Red' }
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

function Test-IsExchangeComparableSnapshotItem {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Item,
    [string[]]$SkippedCommandIds = @()
  )

  $id = [string](Get-GraphPropValue -Obj $Item -Name 'id')
  if ((Get-GraphPropValue -Obj $Item -Name 'collectionStatus') -eq 'Skipped') {
    return $false
  }
  foreach ($skippedCommandId in $SkippedCommandIds) {
    if ($id -eq $skippedCommandId -or $id.StartsWith("$skippedCommandId/")) {
      return $false
    }
  }

  # Version 1.4 emitted a command-level record only when its result was empty.
  # Ignore that legacy placeholder so it does not appear as drift after v1.5.
  $status = Get-GraphPropValue -Obj $Item -Name 'collectionStatus'
  $settings = Get-GraphPropValue -Obj $Item -Name 'settings'
  $isEmpty = $null -eq $settings -or (
    $settings -is [System.Collections.ICollection] -and $settings.Count -eq 0
  )
  return -not ($status -eq 'Collected' -and $id -match '^Exchange[^/]+/[^/]+$' -and $isEmpty)
}

function Compare-Snapshots {
  param(
    [Parameter(Mandatory)][hashtable]$Baseline,
    [Parameter(Mandatory)][hashtable]$Current,
    [Parameter(Mandatory)][string[]]$SelectedEndpoints,
    [hashtable]$AuditLookup = @{},
    [hashtable]$CurrentCollectionStatus = @{},
    [string[]]$MissingBaselineEndpoints = @()
  )

  $rows = [System.Collections.Generic.List[pscustomobject]]::new()

  foreach ($ep in $SelectedEndpoints) {
    if ($ep -in $MissingBaselineEndpoints) {
      Write-Warn "Skipping drift comparison for $($script:EndpointLabels[$ep]): the baseline does not contain this endpoint."
      continue
    }
    if ($CurrentCollectionStatus.ContainsKey($ep) -and $CurrentCollectionStatus[$ep] -ne 'OK') {
      Write-Warn "Skipping drift comparison for $($script:EndpointLabels[$ep]): current collection is incomplete or failed."
      continue
    }

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
    if ($ep -in $script:ExchangeEndpoints) {
      $skippedCommandIds = @(
        @($baseItems + $currentItems) |
          Where-Object { (Get-GraphPropValue -Obj $_ -Name 'collectionStatus') -eq 'Skipped' } |
          ForEach-Object { [string](Get-GraphPropValue -Obj $_ -Name 'id') }
      )
      $baseItems = @($baseItems | Where-Object {
        Test-IsExchangeComparableSnapshotItem -Item $_ -SkippedCommandIds $skippedCommandIds
      })
      $currentItems = @($currentItems | Where-Object {
        Test-IsExchangeComparableSnapshotItem -Item $_ -SkippedCommandIds $skippedCommandIds
      })
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
    [Parameter(Mandatory)][string[]]$SelectedEndpoints,
    [hashtable]$CurrentCollectionStatus = @{},
    [string[]]$MissingBaselineEndpoints = @()
  )

  $failedEndpoints = @(
    $CurrentCollectionStatus.GetEnumerator() |
      Where-Object { $_.Value -ne 'OK' }
  )
  if ($failedEndpoints.Count -gt 0 -or $MissingBaselineEndpoints.Count -gt 0) {
    $reportRows = [System.Collections.Generic.List[pscustomobject]]::new()
    if ($Rows) {
      foreach ($row in $Rows) { [void]$reportRows.Add($row) }
    }
    foreach ($failure in $failedEndpoints) {
      $changeType = if ($failure.Value -like 'INCOMPLETE:*') { 'CollectionIncomplete' } else { 'CollectionFailed' }
      [void]$reportRows.Add((New-DriftRow -Endpoint $failure.Key -ChangeType $changeType `
        -ResourceId "$($failure.Key)/Collection" `
        -ResourceName $script:EndpointLabels[$failure.Key] `
        -ChangedProperties 'Collection incomplete or failed' -BaselineValue '' -CurrentValue ([string]$failure.Value)
      ))
    }
    foreach ($endpoint in $MissingBaselineEndpoints) {
      [void]$reportRows.Add((New-DriftRow -Endpoint $endpoint -ChangeType 'BaselineMissing' `
        -ResourceId "$endpoint/Baseline" `
        -ResourceName $script:EndpointLabels[$endpoint] `
        -ChangedProperties 'Baseline endpoint missing' -BaselineValue '' `
        -CurrentValue 'Create a new baseline that includes this endpoint.'
      ))
    }
    Write-JsonFile -Object $reportRows -Path (Join-Path $RunFolder 'DriftReport.json')
    Export-CsvUtf8 -Object $reportRows -Path (Join-Path $RunFolder 'DriftReport.csv')
    $inconclusiveReasons = @()
    if ($failedEndpoints.Count -gt 0) { $inconclusiveReasons += "collection incomplete or failed for $($failedEndpoints.Key -join ', ')" }
    if ($MissingBaselineEndpoints.Count -gt 0) { $inconclusiveReasons += "baseline missing $($MissingBaselineEndpoints -join ', ')" }
    Write-Warn "Drift check is inconclusive: $($inconclusiveReasons -join '; '). See DriftReport.csv / DriftReport.json."
    return
  }

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

  if ($AuthMethod -eq 'ClientCredentials') {
    # ── Service principal (client secret) ─────────────────────────────────────
    Write-Info "Connecting to storage account '$SaName' as service principal..."
    $spCred = New-Object System.Management.Automation.PSCredential($ClientId, $ClientSecret)
    Connect-AzAccount -ServicePrincipal -TenantId $TenantId -Credential $spCred | Out-Null
    return New-AzStorageContext -StorageAccountName $SaName -UseConnectedAccount
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
      $sasSecure = Read-Host '  SAS token (starts with ?sv=...)' -AsSecureString
      $sas = [System.Net.NetworkCredential]::new('', $sasSecure).Password
      return New-AzStorageContext -StorageAccountName $SaName -SasToken $sas
    }
    '2' {
      $keySecure = Read-Host '  Storage account key' -AsSecureString
      $key = [System.Net.NetworkCredential]::new('', $keySecure).Password
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
  do {
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
      }
    }
  } while ($true)
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
  $userSelection = Read-Host '  Endpoints [default: all supported by the selected authentication method]'
  if ([string]::IsNullOrWhiteSpace($userSelection)) {
    if ($script:IsRunbook -or $AuthMethod -eq 'ClientCredentials') {
      return @($script:AllEndpoints | Where-Object { $_ -notin $script:DelegatedOnlyEndpoints })
    }
    return $script:AllEndpoints
  }

  $selected = [System.Collections.Generic.List[string]]::new()
  foreach ($part in ($userSelection -split ',')) {
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

function Close-DriftConnections {
  if ($transcriptStarted) {
    try { Stop-Transcript | Out-Null } catch { Write-Warn "Could not stop transcript: $_" }
  }
  if ($script:GraphConnected) {
    try { Disconnect-MgGraph | Out-Null } catch { Write-Warn "Could not disconnect Microsoft Graph: $_" }
  }
  if ($script:TeamsConnected) {
    try { Disconnect-MicrosoftTeams | Out-Null } catch { Write-Warn "Could not disconnect Microsoft Teams: $_" }
  }
  if ($script:ExchangeConnected) {
    try { Disconnect-ExchangeOnline -ConnectionId $script:ExchangeConnectionId -Confirm:$false | Out-Null } catch { Write-Warn "Could not disconnect Exchange Online: $_" }
  }
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

try {
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
  return
}

# Resolve endpoints
if (-not $Endpoints -or $Endpoints.Count -eq 0) {
  if ($Unattended) {
    $Endpoints = @($script:AllEndpoints | Where-Object {
      -not (($script:IsRunbook -or $AuthMethod -eq 'ClientCredentials') -and $_ -in $script:DelegatedOnlyEndpoints)
    })
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
$delegatedOnlySelection = @($Endpoints | Where-Object { $_ -in $script:DelegatedOnlyEndpoints })
if ($delegatedOnlySelection.Count -gt 0 -and ($script:IsRunbook -or $AuthMethod -eq 'ClientCredentials')) {
  throw "Endpoint(s) $($delegatedOnlySelection -join ', ') require delegated Interactive or DeviceCode authentication. Remove these endpoints or change -AuthMethod."
}

# ── Module loading ────────────────────────────────────────────────────────────

Ensure-Module -Name 'Microsoft.Graph.Authentication'
if ($Endpoints -contains 'TeamsTenantPolicies') {
  Ensure-Module -Name 'MicrosoftTeams'
}
if (@($Endpoints | Where-Object { $_ -in $script:ExchangeEndpoints }).Count -gt 0) {
  Ensure-ExchangeOnlineManagementModule
}

$storageCtx = $null
if ($UploadToBlob -or ($AuthMethod -eq 'ClientCredentials' -and $StorageAccountName) -or ($Mode -eq 'CheckDrift' -and -not (Test-Path (Join-Path $baselinesRoot ($BaselineName ?? 'x'))))) {
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
  } elseif ($AuthMethod -eq 'ClientCredentials') {
    # ── Enterprise Application – app-only, client secret ─────────────────────
    if (-not $TenantId)     { throw '-TenantId is required when -AuthMethod ClientCredentials is used.' }
    if (-not $ClientId)     { throw '-ClientId is required when -AuthMethod ClientCredentials is used.' }
    if (-not $ClientSecret) { throw '-ClientSecret is required when -AuthMethod ClientCredentials is used.' }
    $appCred = New-Object System.Management.Automation.PSCredential($ClientId, $ClientSecret)
    Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -ClientSecretCredential $appCred -NoWelcome
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
  $script:GraphConnected = $true
  $script:GraphTenantId = [string]$ctx.TenantId
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
  $failedEndpoints = @($script:LastSnapshotEndpointStatus.GetEnumerator() | Where-Object { $_.Value -ne 'OK' })
  if ($failedEndpoints.Count -gt 0) {
    throw "Cannot save a baseline because collection failed for: $($failedEndpoints.Key -join ', '). Resolve the errors and run SetBaseline again."
  }
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
  $missingBaselineEndpoints = @($Endpoints | Where-Object { -not $baselineSnapshot.ContainsKey($_) })
  $driftRows = Compare-Snapshots -Baseline $baselineSnapshot -Current $currentSnapshot -SelectedEndpoints $Endpoints -AuditLookup $auditLookup -CurrentCollectionStatus $script:LastSnapshotEndpointStatus -MissingBaselineEndpoints $missingBaselineEndpoints
  Export-DriftReport -Rows $driftRows -RunFolder $runFolder -SelectedEndpoints $Endpoints -CurrentCollectionStatus $script:LastSnapshotEndpointStatus -MissingBaselineEndpoints $missingBaselineEndpoints
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

} finally {
  Close-DriftConnections
}
