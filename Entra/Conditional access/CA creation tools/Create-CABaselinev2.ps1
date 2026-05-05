#Requires -Version 7.0
<#
.SYNOPSIS
    Interactive Conditional Access baseline creation tool

.DESCRIPTION
    Creates CA policies, exclusion groups, and named locations following the
    HLD Conditional Access naming standard ([Persona]-[SeqNum]-[Action]-[TargetApp]-[Condition]).
    Keeps the operator in the loop for every decision: group creation, named locations,
    policy selection, and policy state (Report-Only / Enabled / Disabled).

.NOTES
    Required Graph permissions:
        Policy.ReadWrite.ConditionalAccess
        Policy.Read.All
        Group.ReadWrite.All
        Directory.Read.All
        Application.Read.All
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Constants ────────────────────────────────────────────────────────────────

$script:AdminRoleIds = [string[]]@(
    '62e90394-69f5-4237-9190-012177145e10' # Global Administrator
    '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3' # Application Administrator
    'c4e39bd9-1100-46d3-8c65-fb160da0071f' # Authentication Administrator
    'b0f54661-2d74-4c50-afa3-1ec803f12efe' # Billing Administrator
    '158c047a-c907-4556-b7ef-446551a6b5f7' # Cloud Application Administrator
    'b1be1c3e-b65d-4f19-8427-f6fa0d97feb9' # Conditional Access Administrator
    '29232cdf-9323-42fd-ade2-1d097af3e4de' # Exchange Administrator
    '729827e3-9c14-49f7-bb1b-9608f156bbb8' # Helpdesk Administrator
    '966707d0-3269-4727-9be2-8c3a10f19b9d' # Password Administrator
    '7be44c8a-adaf-4e2a-84d6-ab2649e08a13' # Privileged Authentication Administrator
    'e8611ab8-c189-46e8-94e1-60213ab1f814' # Privileged Role Administrator
    '194ae4cb-b126-40b2-bd5b-6091b380977d' # Security Administrator
    'f28a1f50-f6e7-4571-818b-6a12f2af6b6c' # SharePoint Administrator
    'fe930be7-5e62-47db-91af-98c3a49a38b1' # User Administrator
)

$script:AzureManagementAppId        = '797f4846-ba00-4fd7-ba43-dac1f8f63013'
$script:PhishingResistantStrengthId = '00000000-0000-0000-0000-000000000004'

# ─── UI helpers ───────────────────────────────────────────────────────────────

function Write-Header {
    param([string]$Text)
    $bar = '═' * 68
    Write-Host "`n$bar" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "$bar`n" -ForegroundColor Cyan
}

function Write-Step { param([string]$T) Write-Host "`n▶ $T" -ForegroundColor Yellow }
function Write-Ok   { param([string]$T) Write-Host "  ✓ $T" -ForegroundColor Green }
function Write-Info { param([string]$T) Write-Host "  · $T" -ForegroundColor Gray }
function Write-Warn { param([string]$T) Write-Host "  ⚠ $T" -ForegroundColor DarkYellow }
function Write-Fail { param([string]$T) Write-Host "  ✗ $T" -ForegroundColor Red }

function Confirm-Prompt {
    param([string]$Prompt, [string]$Default = 'Y')
    $hint = if ($Default -eq 'Y') { '[Y/n]' } else { '[y/N]' }
    $in   = (Read-Host "$Prompt $hint").Trim().ToUpper()
    if (-not $in) { $in = $Default.ToUpper() }
    return $in -eq 'Y'
}

function Read-PolicyState {
    param([string]$Label)
    Write-Host "  State for $Label" -ForegroundColor White
    Write-Host '    1. Report-Only  (recommended for new deployments)'
    Write-Host '    2. Enabled      (enforce immediately)'
    Write-Host '    3. Disabled     (create policy but do not evaluate)'
    do { $c = (Read-Host '    Choice [1/2/3]').Trim() } until ($c -in '1', '2', '3')
    if ($c -eq '1') { return 'enabledForReportingButNotEnforced' }
    if ($c -eq '2') { return 'enabled' }
    return 'disabled'
}

# ─── Policy catalogue ─────────────────────────────────────────────────────────

$script:PolicyCatalog = @(
    [PSCustomObject]@{
        Id           = 'ADM-100'; Category = 'Foundation'; RequiresP2 = $false; Optional = $false
        Name         = 'ADM-100-REQUIRE-AllApps-MFA-Always'
        Description  = 'MFA for all users with admin directory roles'
        DefaultState = 'enabledForReportingButNotEnforced'
    }
    [PSCustomObject]@{
        Id           = 'GLB-006'; Category = 'Foundation'; RequiresP2 = $false; Optional = $false
        Name         = 'GLB-006-BLOCK-SecurityInfoReg-UntrustedLocation'
        Description  = 'Block MFA method registration from outside trusted locations'
        DefaultState = 'enabledForReportingButNotEnforced'
    }
    [PSCustomObject]@{
        Id           = 'GLB-001'; Category = 'Foundation'; RequiresP2 = $false; Optional = $false
        Name         = 'GLB-001-BLOCK-AllApps-LegacyAuth'
        Description  = 'Block Basic Auth, POP, IMAP, SMTP (exchangeActiveSync + other)'
        DefaultState = 'enabledForReportingButNotEnforced'
    }
    [PSCustomObject]@{
        Id           = 'GLB-002'; Category = 'Foundation'; RequiresP2 = $false; Optional = $false
        Name         = 'GLB-002-REQUIRE-AllApps-MFA'
        Description  = 'Enforce MFA for all users on all cloud apps'
        DefaultState = 'enabledForReportingButNotEnforced'
    }
    [PSCustomObject]@{
        Id           = 'GST-400'; Category = 'Foundation'; RequiresP2 = $false; Optional = $false
        Name         = 'GST-400-REQUIRE-AllApps-MFA-Always'
        Description  = 'Enforce MFA for all guest and external users'
        DefaultState = 'enabledForReportingButNotEnforced'
    }
    [PSCustomObject]@{
        Id           = 'GLB-007'; Category = 'Foundation'; RequiresP2 = $false; Optional = $false
        Name         = 'GLB-007-REQUIRE-AzureMgmt-MFA'
        Description  = 'MFA for Azure Portal, PowerShell, CLI, ARM API'
        DefaultState = 'enabledForReportingButNotEnforced'
    }
    [PSCustomObject]@{
        Id           = 'ADM-101'; Category = 'Foundation'; RequiresP2 = $false; Optional = $false
        Name         = 'ADM-101-SESSION-AllApps-NoPersistentSession'
        Description  = '9-hour sign-in frequency, no persistent browser session for admins'
        DefaultState = 'enabledForReportingButNotEnforced'
    }
    [PSCustomObject]@{
        Id           = 'GLB-008'; Category = 'Foundation'; RequiresP2 = $false; Optional = $false
        Name         = 'GLB-008-REQUIRE-AdminPortals-MFA'
        Description  = 'MFA for all Microsoft admin portal access regardless of role'
        DefaultState = 'enabledForReportingButNotEnforced'
    }
    [PSCustomObject]@{
        Id           = 'GLB-003'; Category = 'Foundation'; RequiresP2 = $false; Optional = $false
        Name         = 'GLB-003-BLOCK-AllApps-DeviceCodeFlow'
        Description  = 'Block device code flow auth (HLD: activate directly, not Report-Only)'
        DefaultState = 'enabled'
    }
    [PSCustomObject]@{
        Id           = 'GLB-004'; Category = 'Advanced'; RequiresP2 = $false; Optional = $false
        Name         = 'GLB-004-BLOCK-AllApps-UnknownPlatform'
        Description  = 'Block access from Linux, ChromeOS, and unknown OS platforms'
        DefaultState = 'enabledForReportingButNotEnforced'
    }
    [PSCustomObject]@{
        Id           = 'SVC-500'; Category = 'Advanced'; RequiresP2 = $false; Optional = $false
        Name         = 'SVC-500-BLOCK-AllApps-UntrustedNetwork'
        Description  = 'Service accounts may only authenticate from trusted IPs (needs SG-ServiceAccounts)'
        DefaultState = 'enabledForReportingButNotEnforced'
    }
    [PSCustomObject]@{
        Id           = 'GLB-005'; Category = 'Advanced'; RequiresP2 = $false; Optional = $false
        Name         = 'GLB-005-BLOCK-AllApps-BlockedCountry'
        Description  = 'Block sign-ins from countries outside Allowed Countries named location'
        DefaultState = 'enabledForReportingButNotEnforced'
    }
    [PSCustomObject]@{
        Id           = 'GLB-009'; Category = 'Risk-based (P2)'; RequiresP2 = $true; Optional = $false
        Name         = 'GLB-009-REQUIRE-AllApps-MFA-MediumHighRiskSignIn'
        Description  = 'MFA required on medium and high risk sign-ins'
        DefaultState = 'enabledForReportingButNotEnforced'
    }
    [PSCustomObject]@{
        Id           = 'GLB-010'; Category = 'Risk-based (P2)'; RequiresP2 = $true; Optional = $false
        Name         = 'GLB-010-REQUIRE-AllApps-MFA-PwChange-HighRiskUser'
        Description  = 'MFA + forced password reset on high user risk'
        DefaultState = 'enabledForReportingButNotEnforced'
    }
    [PSCustomObject]@{
        Id           = 'GST-401'; Category = 'Risk-based (P2)'; RequiresP2 = $true; Optional = $false
        Name         = 'GST-401-BLOCK-AllApps-MediumHighRisk'
        Description  = 'Block guest sign-ins with medium or high risk level'
        DefaultState = 'enabledForReportingButNotEnforced'
    }
    [PSCustomObject]@{
        Id           = 'ADM-102'; Category = 'Optional'; RequiresP2 = $false; Optional = $true
        Name         = 'ADM-102-REQUIRE-AllApps-CompliantDevice'
        Description  = 'Require Intune-compliant or hybrid-joined device for admin access'
        DefaultState = 'disabled'
    }
    [PSCustomObject]@{
        Id           = 'ADM-103'; Category = 'Optional'; RequiresP2 = $false; Optional = $true
        Name         = 'ADM-103-REQUIRE-AllApps-PhishingResistantMFA'
        Description  = 'Require FIDO2/WHfB authentication strength for admin accounts'
        DefaultState = 'disabled'
    }
)

# ─── Interactive policy selection menu ───────────────────────────────────────

function Show-PolicyMenu {
    param([bool]$HasP2)

    $selected = @{}
    foreach ($p in $script:PolicyCatalog) {
        $sel = -not $p.Optional
        if ($p.RequiresP2 -and -not $HasP2) { $sel = $false }
        $selected[$p.Id] = $sel
    }

    $categories = $script:PolicyCatalog | Select-Object -ExpandProperty Category -Unique

    while ($true) {
        Clear-Host
        Write-Header 'Policy Selection  –  Toggle by number | A = all | N = none | done = proceed'

        $idx    = 1
        $idxMap = @{}

        foreach ($cat in $categories) {
            Write-Host ("  ── {0} {1}" -f $cat, ('─' * (50 - $cat.Length))) -ForegroundColor DarkCyan
            foreach ($p in ($script:PolicyCatalog | Where-Object Category -eq $cat)) {
                $check   = if ($selected[$p.Id]) { '[X]' } else { '[ ]' }
                $p2tag   = if ($p.RequiresP2)    { ' (P2)     ' } else { '           ' }
                $opttag  = if ($p.Optional)      { ' [Optional]' } else { '' }
                $noLic   = $p.RequiresP2 -and -not $HasP2
                $fgColor = if ($noLic) { 'DarkGray' } else { 'Gray' }

                Write-Host ("  {0,2}. {1} {2}{3}{4}" -f $idx, $check, $p.Id, $p2tag, $opttag) -ForegroundColor $fgColor
                Write-Host ("        {0}" -f $p.Name) -ForegroundColor DarkGray
                $idxMap[$idx] = $p.Id
                $idx++
            }
        }

        Write-Host ''
        $menuInput = (Read-Host "  Command [1-$($idx - 1) | A | N | done]").Trim()

        if ($menuInput -eq '')                  { continue }
        if ($menuInput.ToLower() -eq 'done')    { break }
        if ($menuInput.ToUpper() -eq 'A') {
            foreach ($k in @($selected.Keys)) { $selected[$k] = $true }
            continue
        }
        if ($menuInput.ToUpper() -eq 'N') {
            foreach ($k in @($selected.Keys)) { $selected[$k] = $false }
            continue
        }

        if ($menuInput -match '^\d+$') {
            $n = [int]$menuInput
            if ($idxMap.ContainsKey($n)) {
                $policyId = $idxMap[$n]
                $pol = $script:PolicyCatalog | Where-Object Id -eq $policyId
                if ($pol.RequiresP2 -and -not $HasP2 -and -not $selected[$policyId]) {
                    Write-Warn "$policyId requires Entra ID P2. Enable anyway?"
                    if (-not (Confirm-Prompt "Enable $policyId without confirmed P2 license?" 'N')) { continue }
                }
                $selected[$policyId] = -not $selected[$policyId]
            }
        }
    }

    return @($script:PolicyCatalog | Where-Object { $selected[$_.Id] })
}

# ─── Graph helpers ────────────────────────────────────────────────────────────

function Get-OrCreateGroup {
    param([string]$DisplayName, [string]$Description)

    $escapedName = $DisplayName.Replace("'", "''")
    $existing    = (Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$escapedName'&`$select=id,displayName").value

    if ($existing) {
        Write-Info "Already exists: $DisplayName  ($($existing[0].id))"
        return [string]$existing[0].id
    }

    $nick  = ($DisplayName -replace '[^a-zA-Z0-9]', '').ToLower()
    $body  = @{
        displayName     = $DisplayName
        description     = $Description
        mailEnabled     = $false
        securityEnabled = $true
        mailNickname    = $nick
        groupTypes      = @()
    }
    $g = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/groups' -Body $body
    Write-Ok "Created group: $DisplayName  ($($g.id))"
    return [string]$g.id
}

function Get-ExcludeGroups {
    param([string]$PolicyKey)
    [string[]]$ids = @()
    if ($script:GroupIds['Emergency']) { $ids += [string]$script:GroupIds['Emergency'] }
    if ($script:GroupIds.ContainsKey($PolicyKey) -and
        $script:GroupIds[$PolicyKey] -and
        $script:GroupIds[$PolicyKey] -ne $script:GroupIds['Emergency']) {
        $ids += [string]$script:GroupIds[$PolicyKey]
    }
    return [string[]]($ids | Select-Object -Unique)
}

function New-IpNamedLocation {
    param([string]$Name, [string[]]$Ranges, [bool]$IsTrusted = $true)

    $body = @{
        '@odata.type' = '#microsoft.graph.ipNamedLocation'
        displayName   = $Name
        isTrusted     = $IsTrusted
        ipRanges      = @($Ranges | ForEach-Object {
            @{ '@odata.type' = '#microsoft.graph.iPv4CidrRange'; cidrAddress = $_ }
        })
    }
    $r = Invoke-MgGraphRequest -Method POST `
        -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations' -Body $body
    Write-Ok "Named location created: $Name  ($($r.id))"
    return [string]$r.id
}

function New-CountryNamedLocation {
    param([string]$Name, [string[]]$CountryCodes)

    $body = @{
        '@odata.type'                     = '#microsoft.graph.countryNamedLocation'
        displayName                       = $Name
        countriesAndRegions               = $CountryCodes
        includeUnknownCountriesAndRegions = $false
    }
    $r = Invoke-MgGraphRequest -Method POST `
        -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations' -Body $body
    Write-Ok "Named location created: $Name  ($($r.id))"
    return [string]$r.id
}

function Invoke-RemoveCAPolicies {
    Write-Header 'Remove CA Policies – HLD Standard'

    try {
        $allPolicies = @(
            (Invoke-MgGraphRequest -Method GET `
                -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?$select=id,displayName,state').value
        )
    } catch {
        Write-Fail "Could not retrieve CA policies: $_"
        return
    }

$hldPolicies = @($allPolicies | Where-Object { $_.displayName -match '^(GLB|ADM|INT|EXT|GST|SVC|WLD)-\d{3}-' } | Sort-Object displayName)

    if ($hldPolicies.Count -eq 0) {
        Write-Warn 'No CA policies matching the naming standard (PERSONA-NNN-ACTION) were found.'
        return
    }

    Write-Info "Found $($hldPolicies.Count) matching policies:"
    Write-Host ''

    for ($i = 0; $i -lt $hldPolicies.Count; $i++) {
        $pol        = $hldPolicies[$i]
        $stateColor = switch ($pol.state) {
            'enabled'                           { 'Red' }
            'enabledForReportingButNotEnforced' { 'Yellow' }
            default                             { 'DarkGray' }
        }
        Write-Host ("  {0,2}. {1}" -f ($i + 1), $pol.displayName) -NoNewline
        Write-Host ("  [{0}]" -f $pol.state) -ForegroundColor $stateColor
    }

    Write-Host ''
    Write-Host '  Options:'
    Write-Host '    A. Remove ALL listed policies'
    Write-Host '    S. Select individual policies to remove'
    Write-Host '    C. Cancel'
    $removeMode = (Read-Host '  Choice [A/S/C]').Trim().ToUpper()

    if ($removeMode -eq 'C' -or $removeMode -eq '') {
        Write-Info 'Cancelled – no policies removed.'
        return
    }

    $toRemove = @()

    if ($removeMode -eq 'A') {
        if (-not (Confirm-Prompt "  Remove ALL $($hldPolicies.Count) policies? This cannot be undone." 'N')) {
            Write-Info 'Cancelled.'
            return
        }
        $toRemove = $hldPolicies
    } elseif ($removeMode -eq 'S') {
        Write-Host '  Enter policy numbers to remove, comma-separated (e.g. 1,3,5):'
        $selInput = (Read-Host '  Numbers').Trim()
        $indices  = $selInput -split ',' |
            Where-Object { $_ -match '^\d+$' } |
            ForEach-Object { [int]$_ - 1 }
        $toRemove = @($indices |
            Where-Object { $_ -ge 0 -and $_ -lt $hldPolicies.Count } |
            ForEach-Object { $hldPolicies[$_] })

        if ($toRemove.Count -eq 0) {
            Write-Warn 'No valid selections – nothing removed.'
            return
        }

        Write-Host ''
        Write-Warn "About to remove $($toRemove.Count) policy/policies:"
        $toRemove | ForEach-Object { Write-Info "  · $($_.displayName)" }
        if (-not (Confirm-Prompt '  Confirm removal?' 'N')) {
            Write-Info 'Cancelled.'
            return
        }
    } else {
        Write-Warn "Unknown option '$removeMode' – nothing removed."
        return
    }

    $removed  = 0
    $rmFailed = 0
    foreach ($pol in $toRemove) {
        try {
            Invoke-MgGraphRequest -Method DELETE `
                -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$([string]$pol.id)" | Out-Null
            Write-Ok "Removed: $($pol.displayName)"
            $removed++
        } catch {
            Write-Fail "Failed to remove $($pol.displayName): $_"
            $rmFailed++
        }
    }

    Write-Host ''
    Write-Host ("  Removed : {0}" -f $removed)  -ForegroundColor Green
    Write-Host ("  Failed  : {0}" -f $rmFailed) -ForegroundColor Red
}

# ─── Policy body builders ─────────────────────────────────────────────────────

function Build-PolicyBody {
    param([string]$Id, [string]$State)

    switch ($Id) {
        'ADM-100' {
            return @{
                displayName   = 'ADM-100-REQUIRE-AllApps-MFA-Always'
                state         = $State
                conditions    = @{
                    clientAppTypes = @('browser', 'mobileAppsAndDesktopClients')
                    applications   = @{ includeApplications = @('All') }
                    users          = @{
                        includeRoles  = $script:AdminRoleIds
                        excludeGroups = @(Get-ExcludeGroups 'ADM-100')
                    }
                }
                grantControls = @{ operator = 'OR'; builtInControls = @('mfa') }
            }
        }

        'GLB-006' {
            return @{
                displayName   = 'GLB-006-BLOCK-SecurityInfoReg-UntrustedLocation'
                state         = $State
                conditions    = @{
                    applications = @{ includeUserActions = @('urn:user:registersecurityinfo') }
                    users        = @{
                        includeUsers  = @('All')
                        excludeGroups = @(Get-ExcludeGroups 'GLB-006')
                    }
                    locations    = @{
                        includeLocations = @('All')
                        excludeLocations = @('AllTrusted')
                    }
                }
                grantControls = @{ operator = 'OR'; builtInControls = @('block') }
            }
        }

        'GLB-001' {
            return @{
                displayName   = 'GLB-001-BLOCK-AllApps-LegacyAuth'
                state         = $State
                conditions    = @{
                    clientAppTypes = @('exchangeActiveSync', 'other')
                    applications   = @{ includeApplications = @('All') }
                    users          = @{
                        includeUsers  = @('All')
                        excludeGroups = @(Get-ExcludeGroups 'GLB-001')
                    }
                }
                grantControls = @{ operator = 'OR'; builtInControls = @('block') }
            }
        }

        'GLB-002' {
            return @{
                displayName   = 'GLB-002-REQUIRE-AllApps-MFA'
                state         = $State
                conditions    = @{
                    clientAppTypes = @('browser', 'mobileAppsAndDesktopClients')
                    applications   = @{ includeApplications = @('All') }
                    users          = @{
                        includeUsers  = @('All')
                        excludeGroups = @(Get-ExcludeGroups 'GLB-002')
                    }
                }
                grantControls = @{ operator = 'OR'; builtInControls = @('mfa') }
            }
        }

        'GST-400' {
            return @{
                displayName   = 'GST-400-REQUIRE-AllApps-MFA-Always'
                state         = $State
                conditions    = @{
                    clientAppTypes = @('browser', 'mobileAppsAndDesktopClients')
                    applications   = @{ includeApplications = @('All') }
                    users          = @{
                        includeGuestsOrExternalUsers = @{
                            guestOrExternalUserTypes = 'internalGuest,b2bCollaborationGuest,b2bCollaborationMember,b2bDirectConnectUser,otherExternalUser,serviceProvider'
                            externalTenants = @{ membershipKind = 'all' }
                        }
                        excludeGroups = @(Get-ExcludeGroups 'GST-400')
                    }
                }
                grantControls = @{ operator = 'OR'; builtInControls = @('mfa') }
            }
        }

        'GLB-007' {
            return @{
                displayName   = 'GLB-007-REQUIRE-AzureMgmt-MFA'
                state         = $State
                conditions    = @{
                    clientAppTypes = @('browser', 'mobileAppsAndDesktopClients')
                    applications   = @{ includeApplications = @($script:AzureManagementAppId) }
                    users          = @{
                        includeUsers  = @('All')
                        excludeGroups = @(Get-ExcludeGroups 'GLB-007')
                    }
                }
                grantControls = @{ operator = 'OR'; builtInControls = @('mfa') }
            }
        }

        'GLB-009' {
            return @{
                displayName      = 'GLB-009-REQUIRE-AllApps-MFA-MediumHighRiskSignIn'
                state            = $State
                conditions       = @{
                    clientAppTypes   = @('browser', 'mobileAppsAndDesktopClients')
                    applications     = @{ includeApplications = @('All') }
                    signInRiskLevels = @('medium', 'high')
                    users            = @{
                        includeUsers  = @('All')
                        excludeGroups = @(Get-ExcludeGroups 'GLB-009')
                    }
                }
                grantControls = @{ operator = 'OR'; builtInControls = @('mfa') }
            }
        }

        'GLB-010' {
            # passwordChange control requires clientAppTypes = 'all' (Graph API requirement)
            return @{
                displayName   = 'GLB-010-REQUIRE-AllApps-MFA-PwChange-HighRiskUser'
                state         = $State
                conditions    = @{
                    clientAppTypes = @('all')
                    applications   = @{ includeApplications = @('All') }
                    userRiskLevels = @('high')
                    users          = @{
                        includeUsers  = @('All')
                        excludeGroups = @(Get-ExcludeGroups 'GLB-010')
                    }
                }
                grantControls = @{ operator = 'AND'; builtInControls = @('mfa', 'passwordChange') }
            }
        }

        'ADM-102' {
            return @{
                displayName   = 'ADM-102-REQUIRE-AllApps-CompliantDevice'
                state         = $State
                conditions    = @{
                    clientAppTypes = @('browser', 'mobileAppsAndDesktopClients')
                    applications   = @{ includeApplications = @('All') }
                    users          = @{
                        includeRoles  = $script:AdminRoleIds
                        excludeGroups = @(Get-ExcludeGroups 'ADM-102')
                    }
                }
                grantControls = @{ operator = 'OR'; builtInControls = @('compliantDevice', 'domainJoinedDevice') }
            }
        }

        'GLB-004' {
            return @{
                displayName   = 'GLB-004-BLOCK-AllApps-UnknownPlatform'
                state         = $State
                conditions    = @{
                    clientAppTypes = @('browser', 'mobileAppsAndDesktopClients')
                    applications   = @{ includeApplications = @('All') }
                    platforms      = @{
                        includePlatforms = @('all')
                        excludePlatforms = @('android', 'iOS', 'windows', 'macOS')
                    }
                    users          = @{
                        includeUsers  = @('All')
                        excludeGroups = @(Get-ExcludeGroups 'GLB-004')
                    }
                }
                grantControls = @{ operator = 'OR'; builtInControls = @('block') }
            }
        }

        'ADM-101' {
            return @{
                displayName     = 'ADM-101-SESSION-AllApps-NoPersistentSession'
                state           = $State
                conditions      = @{
                    clientAppTypes = @('browser')
                    applications   = @{ includeApplications = @('All') }
                    users          = @{
                        includeRoles  = $script:AdminRoleIds
                        excludeGroups = @(Get-ExcludeGroups 'ADM-101')
                    }
                }
                sessionControls = @{
                    persistentBrowser = @{
                        mode      = 'never'
                        isEnabled = $true
                    }
                    signInFrequency = @{
                        value                 = 9
                        type                  = 'hours'
                        isEnabled             = $true
                        authenticationType    = 'primaryAndSecondaryAuthentication'
                        frequencyInterval     = 'timeBased'
                    }
                }
            }
        }

        'ADM-103' {
            return @{
                displayName   = 'ADM-103-REQUIRE-AllApps-PhishingResistantMFA'
                state         = $State
                conditions    = @{
                    clientAppTypes = @('browser', 'mobileAppsAndDesktopClients')
                    applications   = @{ includeApplications = @('All') }
                    users          = @{
                        includeRoles  = $script:AdminRoleIds
                        excludeGroups = @(Get-ExcludeGroups 'ADM-103')
                    }
                }
                grantControls = @{
                    operator               = 'OR'
                    authenticationStrength = @{ id = $script:PhishingResistantStrengthId }
                }
            }
        }

        'GLB-008' {
            return @{
                displayName   = 'GLB-008-REQUIRE-AdminPortals-MFA'
                state         = $State
                conditions    = @{
                    clientAppTypes = @('browser', 'mobileAppsAndDesktopClients')
                    applications   = @{ includeApplications = @('MicrosoftAdminPortals') }
                    users          = @{
                        includeUsers  = @('All')
                        excludeGroups = @(Get-ExcludeGroups 'GLB-008')
                    }
                }
                grantControls = @{ operator = 'OR'; builtInControls = @('mfa') }
            }
        }

        'SVC-500' {
            if (-not $script:GroupIds['SG']) {
                Write-Warn 'SVC-500 requires the SG-ServiceAccounts group – policy will be skipped.'
                return $null
            }
            return @{
                displayName   = 'SVC-500-BLOCK-AllApps-UntrustedNetwork'
                state         = $State
                conditions    = @{
                    clientAppTypes = @('browser', 'mobileAppsAndDesktopClients', 'exchangeActiveSync', 'other')
                    applications   = @{ includeApplications = @('All') }
                    users          = @{
                        includeGroups = [string[]]@([string]$script:GroupIds['SG'])
                        excludeGroups = [string[]]@(Get-ExcludeGroups 'SVC-500')
                    }
                    locations      = @{
                        includeLocations = @('All')
                        excludeLocations = @('AllTrusted')
                    }
                }
                grantControls = @{ operator = 'OR'; builtInControls = @('block') }
            }
        }

        'GLB-005' {
            if (-not $script:LocationIds.AllowedCountries) {
                Write-Warn 'GLB-005 requires the Allowed Countries named location – policy will be skipped.'
                return $null
            }
            return @{
                displayName   = 'GLB-005-BLOCK-AllApps-BlockedCountry'
                state         = $State
                conditions    = @{
                    clientAppTypes = @('browser', 'mobileAppsAndDesktopClients', 'exchangeActiveSync', 'other')
                    applications   = @{ includeApplications = @('All') }
                    users          = @{
                        includeUsers  = @('All')
                        excludeGroups = @(Get-ExcludeGroups 'GLB-005')
                    }
                    locations      = @{
                        includeLocations = @('All')
                        excludeLocations = @($script:LocationIds.AllowedCountries)
                    }
                }
                grantControls = @{ operator = 'OR'; builtInControls = @('block') }
            }
        }

        'GST-401' {
            return @{
                displayName      = 'GST-401-BLOCK-AllApps-MediumHighRisk'
                state            = $State
                conditions       = @{
                    clientAppTypes   = @('browser', 'mobileAppsAndDesktopClients')
                    applications     = @{ includeApplications = @('All') }
                    signInRiskLevels = @('medium', 'high')
                    users            = @{
                        includeGuestsOrExternalUsers = @{
                            guestOrExternalUserTypes = 'internalGuest,b2bCollaborationGuest,b2bCollaborationMember,b2bDirectConnectUser,otherExternalUser,serviceProvider'
                            externalTenants = @{ membershipKind = 'all' }
                        }
                        excludeGroups = @(Get-ExcludeGroups 'GST-401')
                    }
                }
                grantControls = @{ operator = 'OR'; builtInControls = @('block') }
            }
        }

        'GLB-003' {
            # authenticationFlows condition is available in Graph v1.0
            return @{
                displayName   = 'GLB-003-BLOCK-AllApps-DeviceCodeFlow'
                state         = $State
                conditions    = @{
                    applications        = @{ includeApplications = @('All') }
                    authenticationFlows = @{ transferMethods = 'deviceCodeFlow' }
                    users               = @{
                        includeUsers  = @('All')
                        excludeGroups = @(Get-ExcludeGroups 'GLB-003')
                    }
                }
                grantControls = @{ operator = 'OR'; builtInControls = @('block') }
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

Write-Header 'CA Baseline Tool  –  HLD Standard  (PERSONA-NNN-ACTION-TargetApp)'

# ─── Module bootstrap ────────────────────────────────────────────────────────

Write-Step 'Checking required modules'
$requiredModules = @(
    'Microsoft.Graph.Authentication'
    'Microsoft.Graph.Identity.SignIns'
    'Microsoft.Graph.Groups'
)
foreach ($mod in $requiredModules) {
    if (-not (Get-Module -Name $mod -ListAvailable)) {
        Write-Info "Installing $mod..."
        Install-Module $mod -Scope CurrentUser -Force -AllowClobber
    }
    if (-not (Get-Module -Name $mod)) {
        Import-Module $mod -ErrorAction Stop
    }
}
Write-Ok 'Modules ready'

# ─── Authentication ──────────────────────────────────────────────────────────

Write-Step 'Authenticating to Microsoft Graph'
$graphScopes = @(
    'Policy.ReadWrite.ConditionalAccess'
    'Policy.Read.All'
    'Group.ReadWrite.All'
    'Directory.Read.All'
    'Application.Read.All'
)

Write-Info 'Required scopes:'
$graphScopes | ForEach-Object { Write-Info "  · $_" }

Write-Host ''
$authMode = ''
while ($authMode -notin '1', '2', '3') {
    Write-Host '  Authentication method:'
    Write-Host '    1. Interactive (browser sign-in)   – recommended'
    Write-Host '    2. Device code (for headless/SSH sessions)'
    Write-Host '    3. Use existing connection (if already authenticated)'
    $authMode = (Read-Host '  Choice [1/2/3]').Trim()
}

try {
    switch ($authMode) {
        '1' { Connect-MgGraph -Scopes $graphScopes -NoWelcome }
        '2' { Connect-MgGraph -Scopes $graphScopes -UseDeviceCode -NoWelcome }
        '3' {
            $ctx = Get-MgContext
            if (-not $ctx) {
                Write-Warn 'No existing connection found – falling back to interactive.'
                Connect-MgGraph -Scopes $graphScopes -NoWelcome
            }
        }
    }
    $ctx = Get-MgContext
    Write-Ok "Connected as $($ctx.Account)"
    Write-Info "Tenant: $($ctx.TenantId)"
} catch {
    Write-Fail "Authentication failed: $_"
    exit 1
}

# ─── Main menu ───────────────────────────────────────────────────────────────

$script:MenuChoice = ''
while ($script:MenuChoice -notin '1', '2', '3') {
    Write-Header 'Main Menu'
    Write-Host '    1. Create CA Baseline     – create policies, exclusion groups, named locations'
    Write-Host '    2. Remove CA Policies     – delete existing policies matching the naming standard (PERSONA-NNN-...)'
    Write-Host '    3. Exit'
    $script:MenuChoice = (Read-Host '  Choice [1/2/3]').Trim()
}

if ($script:MenuChoice -eq '3') { Write-Info 'Exiting.'; exit 0 }

if ($script:MenuChoice -eq '2') {
    Invoke-RemoveCAPolicies
    exit 0
}

# ─── P2 licence check ────────────────────────────────────────────────────────

Write-Header 'Step 1 – Entra ID P2 Licence Check'
$script:hasP2 = $false
try {
    $skus  = (Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/subscribedSkus').value
    $p2Sku = $skus | Where-Object { $_.skuPartNumber -match 'AAD_PREMIUM_P2|EMSPREMIUM|M365EDU_A5|SPE_E5' }
    if ($p2Sku) {
        $script:hasP2 = $true
        Write-Ok "P2 licence detected: $($p2Sku[0].skuPartNumber)"
    } else {
        Write-Warn 'No Entra ID P2 licence detected. P2 policies will be deselected by default.'
        if (Confirm-Prompt 'Treat as P2 available anyway (e.g. trial or undetected SKU)?' 'N') {
            $script:hasP2 = $true
            Write-Info 'P2 availability overridden.'
        }
    }
} catch {
    Write-Warn "Licence check failed: $_"
    $script:hasP2 = Confirm-Prompt 'Does this tenant have Entra ID P2?' 'N'
}

# ─── Exclusion groups ────────────────────────────────────────────────────────

Write-Header 'Step 2 – Exclusion Groups'
Write-Info 'HLD standard: CA-EXC-Emergency-BreakGlass (global, all policies) + CA-EXC-[Persona]-[SeqNum]-[Action]-[TargetApp]-[Condition] per policy + SG-ServiceAccounts'
Write-Info 'CA-EXC-Emergency-BreakGlass must contain Break-The-Glass accounts.'
Write-Host ''

$script:GroupIds = @{}

$groupDefs = [ordered]@{
    'Emergency' = @{ Name = 'CA-EXC-Emergency-BreakGlass';                                        Desc = 'Break-Glass emergency exclusion – added to ALL CA policies' }
    'SG'        = @{ Name = 'SG-ServiceAccounts';                                                  Desc = 'Service accounts – used as include group in SVC-500 policy' }
    'ADM-100'   = @{ Name = 'CA-EXC-ADM-100-REQUIRE-AllApps-MFA-Always';                          Desc = 'Per-policy exclusion for ADM-100' }
    'GLB-006'   = @{ Name = 'CA-EXC-GLB-006-BLOCK-SecurityInfoReg-UntrustedLocation';              Desc = 'Per-policy exclusion for GLB-006' }
    'GLB-001'   = @{ Name = 'CA-EXC-GLB-001-BLOCK-AllApps-LegacyAuth';                            Desc = 'Per-policy exclusion for GLB-001' }
    'GLB-002'   = @{ Name = 'CA-EXC-GLB-002-REQUIRE-AllApps-MFA';                                 Desc = 'Per-policy exclusion for GLB-002' }
    'GST-400'   = @{ Name = 'CA-EXC-GST-400-REQUIRE-AllApps-MFA-Always';                          Desc = 'Per-policy exclusion for GST-400' }
    'GLB-007'   = @{ Name = 'CA-EXC-GLB-007-REQUIRE-AzureMgmt-MFA';                               Desc = 'Per-policy exclusion for GLB-007' }
    'GLB-009'   = @{ Name = 'CA-EXC-GLB-009-REQUIRE-AllApps-MFA-MediumHighRiskSignIn';             Desc = 'Per-policy exclusion for GLB-009 (P2)' }
    'GLB-010'   = @{ Name = 'CA-EXC-GLB-010-REQUIRE-AllApps-MFA-PwChange-HighRiskUser';            Desc = 'Per-policy exclusion for GLB-010 (P2)' }
    'ADM-102'   = @{ Name = 'CA-EXC-ADM-102-REQUIRE-AllApps-CompliantDevice';                     Desc = 'Per-policy exclusion for ADM-102 (Optional)' }
    'GLB-004'   = @{ Name = 'CA-EXC-GLB-004-BLOCK-AllApps-UnknownPlatform';                       Desc = 'Per-policy exclusion for GLB-004' }
    'ADM-101'   = @{ Name = 'CA-EXC-ADM-101-SESSION-AllApps-NoPersistentSession';                 Desc = 'Per-policy exclusion for ADM-101' }
    'ADM-103'   = @{ Name = 'CA-EXC-ADM-103-REQUIRE-AllApps-PhishingResistantMFA';                Desc = 'Per-policy exclusion for ADM-103 (Optional)' }
    'GLB-008'   = @{ Name = 'CA-EXC-GLB-008-REQUIRE-AdminPortals-MFA';                            Desc = 'Per-policy exclusion for GLB-008' }
    'SVC-500'   = @{ Name = 'CA-EXC-SVC-500-BLOCK-AllApps-UntrustedNetwork';                      Desc = 'Per-policy exclusion for SVC-500' }
    'GLB-005'   = @{ Name = 'CA-EXC-GLB-005-BLOCK-AllApps-BlockedCountry';                        Desc = 'Per-policy exclusion for GLB-005' }
    'GST-401'   = @{ Name = 'CA-EXC-GST-401-BLOCK-AllApps-MediumHighRisk';                        Desc = 'Per-policy exclusion for GST-401 (P2)' }
    'GLB-003'   = @{ Name = 'CA-EXC-GLB-003-BLOCK-AllApps-DeviceCodeFlow';                        Desc = 'Per-policy exclusion for GLB-003' }
}

$groupMode = ''
while ($groupMode -notin '1', '2', '3') {
    Write-Host '  How should exclusion groups be handled?'
    Write-Host '    1. Create all groups automatically             (recommended)'
    Write-Host '    2. Enter existing group object IDs manually'
    Write-Host '    3. Create CA-EXC-Emergency-BreakGlass + SG-ServiceAccounts only  (all per-policy exclusions mapped to Emergency)'
    $groupMode = (Read-Host '  Choice [1/2/3]').Trim()
}

switch ($groupMode) {
    '1' {
        Write-Step 'Creating all exclusion groups...'
        foreach ($key in $groupDefs.Keys) {
            try {
                $script:GroupIds[$key] = Get-OrCreateGroup `
                    -DisplayName $groupDefs[$key].Name `
                    -Description $groupDefs[$key].Desc
            } catch {
                Write-Fail "Failed to create $($groupDefs[$key].Name): $_"
            }
        }
    }
    '2' {
        Write-Step 'Enter existing group object IDs (leave blank to skip)'
        foreach ($key in $groupDefs.Keys) {
            $id = (Read-Host "  $($groupDefs[$key].Name)").Trim()
            if ($id) { $script:GroupIds[$key] = $id }
        }
    }
    '3' {
        Write-Step 'Creating CA-EXC-Emergency-BreakGlass and SG-ServiceAccounts...'
        try {
            $script:GroupIds['Emergency'] = Get-OrCreateGroup `
                -DisplayName 'CA-EXC-Emergency-BreakGlass' `
                -Description 'Break-Glass emergency exclusion – added to ALL CA policies'
            $script:GroupIds['SG'] = Get-OrCreateGroup `
                -DisplayName 'SG-ServiceAccounts' `
                -Description 'Service accounts – used as include group in SVC-500 policy'
        } catch {
            Write-Fail "Group creation failed: $_"
        }
        foreach ($key in $groupDefs.Keys | Where-Object { $_ -notin 'Emergency', 'SG' }) {
            $script:GroupIds[$key] = $script:GroupIds['Emergency']
        }
        Write-Info 'All per-policy exclusions mapped to CA-EXC-Emergency-BreakGlass.'
    }
}

# ─── Named locations ─────────────────────────────────────────────────────────

Write-Header 'Step 3 – Named Locations'
Write-Info 'GLB-006 uses AllTrusted (automatic). SVC-500 uses AllTrusted. GLB-005 needs Allowed Countries.'
Write-Info 'IP-based locations are optional – skip if you already have trusted locations configured.'

$script:LocationIds = @{
    OfficeNetwork    = $null
    TrustedNetwork   = $null
    AllowedCountries = $null
}

$existingLocs = @()
try {
    $existingLocs = @(
        (Invoke-MgGraphRequest -Method GET `
            -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations?$select=id,displayName').value
    )
    if ($existingLocs.Count -gt 0) {
        Write-Info "Found $($existingLocs.Count) existing named location(s):"
        $existingLocs | ForEach-Object { Write-Info "  · $($_.displayName)  ($($_.id))" }
    }
} catch {
    Write-Warn "Could not retrieve named locations: $_"
}

# IP-based locations
if (Confirm-Prompt 'Create or map IP-based named locations (Office Network / Trusted Network)?' 'Y') {
    foreach ($locName in @('Office Network', 'Trusted Network')) {
        Write-Host "`n  ── $locName ───────────────────────────────"

        $match = $existingLocs | Where-Object { $_.displayName -eq $locName }
        if ($match -and (Confirm-Prompt "  Use existing '$locName' ($($match.id))?" 'Y')) {
            $key = $locName -replace ' ', ''
            $script:LocationIds[$key] = $match.id
            continue
        }

        $ranges = @()
        Write-Host "  Enter IP ranges in CIDR notation – empty line to finish:"
        do {
            $r = (Read-Host "    CIDR (e.g. 10.0.0.0/8 or 203.0.113.0/24)").Trim()
            if ($r) { $ranges += $r }
        } until (-not $r)

        if ($ranges.Count -gt 0) {
            try {
                $key = $locName -replace ' ', ''
                $script:LocationIds[$key] = New-IpNamedLocation -Name $locName -Ranges $ranges
            } catch {
                Write-Fail "Failed to create '$locName': $_"
            }
        } else {
            Write-Warn "No ranges entered – '$locName' not created."
        }
    }
}

# Allowed Countries
Write-Host "`n  ── Allowed Countries (required for GLB-005) ──────────────"

$matchAC = $existingLocs | Where-Object { $_.displayName -eq 'Allowed Countries' }
if ($matchAC -and (Confirm-Prompt "  Use existing 'Allowed Countries' ($($matchAC.id))?" 'Y')) {
    $script:LocationIds.AllowedCountries = $matchAC.id
}

if (-not $script:LocationIds.AllowedCountries) {
    $commonCountries = [ordered]@{
        'SE' = 'Sweden';         'NO' = 'Norway';          'DK' = 'Denmark'
        'FI' = 'Finland';        'DE' = 'Germany';          'GB' = 'United Kingdom'
        'NL' = 'Netherlands';    'US' = 'United States';    'FR' = 'France'
        'CH' = 'Switzerland';    'AT' = 'Austria';          'BE' = 'Belgium'
        'ES' = 'Spain';          'IT' = 'Italy';            'PL' = 'Poland'
        'IE' = 'Ireland';        'LU' = 'Luxembourg';       'EE' = 'Estonia'
        'LV' = 'Latvia';         'LT' = 'Lithuania';        'IS' = 'Iceland'
    }
    $cList = @($commonCountries.Keys)

    Write-Host ''
    Write-Host '  Select allowed countries (comma-separated numbers, or type custom for manual ISO codes):'
    for ($i = 0; $i -lt $cList.Count; $i++) {
        Write-Host ("    {0,2}. {1}  –  {2}" -f ($i + 1), $cList[$i], $commonCountries[$cList[$i]])
    }

    $countryInput = (Read-Host "`n  Selection (e.g. 1,2,3 or 'custom' or blank to skip)").Trim()
    $codes = @()

    if ($countryInput.ToLower() -eq 'custom') {
        $raw   = Read-Host '  ISO 3166-1 alpha-2 codes, comma-separated (e.g. SE,NO,DK)'
        $codes = $raw -split ',' | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ }
    } elseif ($countryInput) {
        $indices = $countryInput -split ',' |
            Where-Object { $_ -match '^\d+$' } |
            ForEach-Object { [int]$_ - 1 }
        $codes = @($indices |
            Where-Object { $_ -ge 0 -and $_ -lt $cList.Count } |
            ForEach-Object { $cList[$_] })
    }

    if ($codes.Count -gt 0) {
        Write-Info "Selected: $($codes -join ', ')"
        try {
            $script:LocationIds.AllowedCountries = New-CountryNamedLocation -Name 'Allowed Countries' -CountryCodes $codes
        } catch {
            Write-Fail "Failed to create Allowed Countries: $_"
        }
    } else {
        Write-Warn "No countries selected – GLB-005 will be skipped if chosen."
    }
}

# ─── Policy selection ────────────────────────────────────────────────────────

$selectedPolicies = Show-PolicyMenu -HasP2 $script:hasP2

if (-not $selectedPolicies -or $selectedPolicies.Count -eq 0) {
    Write-Warn 'No policies selected. Exiting.'
    exit 0
}

# ─── Policy state ────────────────────────────────────────────────────────────

Write-Header "Step 4 – Policy State  ($($selectedPolicies.Count) policies selected)"
Write-Host '  Set a global default state, then optionally override per policy.'
Write-Host ''

$globalState    = Read-PolicyState 'all selected policies'
$perPolicyState = @{}

if (Confirm-Prompt "`n  Override state individually for specific policies?" 'N') {
    foreach ($p in $selectedPolicies) {
        Write-Host "`n  $($p.Id)  –  $($p.Name)" -ForegroundColor White
        Write-Info "  HLD default: $($p.DefaultState)"
        if (Confirm-Prompt "  Override state for $($p.Id)?" 'N') {
            $perPolicyState[$p.Id] = Read-PolicyState $p.Id
        } else {
            $perPolicyState[$p.Id] = $globalState
        }
    }
} else {
    foreach ($p in $selectedPolicies) {
        $perPolicyState[$p.Id] = $globalState
    }
}

# ─── Create policies ─────────────────────────────────────────────────────────

Write-Header "Step 5 – Creating $($selectedPolicies.Count) Policies"
$results = [System.Collections.Generic.List[hashtable]]::new()

foreach ($p in $selectedPolicies) {
    Write-Step "$($p.Id)  –  $($p.Name)"

    try {
        $state = $perPolicyState[$p.Id]
        $body  = Build-PolicyBody -Id $p.Id -State $state

        if ($null -eq $body) {
            $results.Add(@{ Id = $p.Id; Name = $p.Name; Status = 'Skipped'; Reason = 'Missing prerequisite (group or named location)' })
            continue
        }

        $escapedName     = $body.displayName.Replace("'", "''")
        $existingPolicies = @(
            (Invoke-MgGraphRequest -Method GET `
                -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?`$filter=displayName eq '$escapedName'&`$select=id,displayName").value
        )

        if ($existingPolicies.Count -gt 0) {
            $existId = $existingPolicies[0].id
            Write-Warn "Policy already exists: $($body.displayName)  ($existId)"

            if (Confirm-Prompt '  Update (PATCH) existing policy?' 'N') {
                Invoke-MgGraphRequest -Method PATCH `
                    -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$existId" `
                    -Body $body | Out-Null
                Write-Ok "Updated: $($body.displayName)"
                $results.Add(@{ Id = $p.Id; Name = $p.Name; Status = 'Updated'; State = $state; PolicyId = $existId })
            } else {
                $results.Add(@{ Id = $p.Id; Name = $p.Name; Status = 'Skipped'; Reason = 'Already exists – update declined' })
            }
        } else {
            $created = Invoke-MgGraphRequest -Method POST `
                -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' `
                -Body $body
            Write-Ok "Created [$state]: $($body.displayName)  ($($created.id))"
            $results.Add(@{ Id = $p.Id; Name = $p.Name; Status = 'Created'; State = $state; PolicyId = $created.id })
        }
    } catch {
        Write-Fail "Failed: $_"
        $results.Add(@{ Id = $p.Id; Name = $p.Name; Status = 'Failed'; Reason = $_.Exception.Message })
    }
}

# ─── Summary ─────────────────────────────────────────────────────────────────

Write-Header 'Summary'

$colorMap = @{
    'Created' = 'Green'
    'Updated' = 'Cyan'
    'Skipped' = 'Yellow'
    'Failed'  = 'Red'
}

foreach ($r in $results) {
    $color  = if ($colorMap.ContainsKey($r.Status)) { $colorMap[$r.Status] } else { 'Gray' }
    $state  = if ($r['State'])  { "  [$($r['State'])]" } else { '' }
    $reason = if ($r['Reason']) { "  – $($r['Reason'])" } else { '' }
    Write-Host ("  [{0,-7}]  {1}  –  {2}{3}{4}" -f $r.Status, $r.Id, $r.Name, $state, $reason) -ForegroundColor $color
}

Write-Host ''
Write-Host ("  Created : {0}" -f @($results | Where-Object Status -eq 'Created').Count) -ForegroundColor Green
Write-Host ("  Updated : {0}" -f @($results | Where-Object Status -eq 'Updated').Count) -ForegroundColor Cyan
Write-Host ("  Skipped : {0}" -f @($results | Where-Object Status -eq 'Skipped').Count) -ForegroundColor Yellow
Write-Host ("  Failed  : {0}" -f @($results | Where-Object Status -eq 'Failed').Count)  -ForegroundColor Red

Write-Host ''

if ($script:GroupIds['Emergency']) {
    Write-Host '  ⚠ ACTION REQUIRED: Add your Break-The-Glass accounts to CA-EXC-Emergency-BreakGlass!' -ForegroundColor DarkYellow
    Write-Info "    Group ID: $($script:GroupIds['Emergency'])"
}
if ($script:GroupIds['SG'] -and ($results | Where-Object Id -eq 'SVC-500' | Where-Object Status -in 'Created', 'Updated')) {
    Write-Host '  ⚠ ACTION REQUIRED: Populate SG-ServiceAccounts with all service account objects.' -ForegroundColor DarkYellow
    Write-Info "    Group ID: $($script:GroupIds['SG'])"
}

Write-Host "`n  Portal: https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade`n" -ForegroundColor DarkCyan
