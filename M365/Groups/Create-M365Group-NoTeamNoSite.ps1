#Requires -Version 7.0
<#
.SYNOPSIS
  Creates a Microsoft 365 Unified group with optional Teams and SharePoint site provisioning.

.DESCRIPTION
  Interactively creates an M365 Unified group via the Microsoft Entra module.
  Prompts for visibility, welcome email behaviour, Teams team provisioning, SharePoint site
  provisioning, Outlook visibility, and member subscription behaviour.
  A summary confirmation is shown before anything is created.

.NOTES
  Required module : Microsoft.Entra
  Required scope  : Group.ReadWrite.All
  Author          : Bareminimum Automation, 2026
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── UI Helpers ──────────────────────────────────────────────────────────────

function Write-Step { param([string]$m) Write-Host "  ▶ $m" -ForegroundColor Yellow     }
function Write-Ok   { param([string]$m) Write-Host "  ✓ $m" -ForegroundColor Green      }
function Write-Info { param([string]$m) Write-Host "  · $m" -ForegroundColor Gray       }
function Write-Warn { param([string]$m) Write-Host "  ⚠ $m" -ForegroundColor DarkYellow }
function Write-Fail { param([string]$m) Write-Host "  ✗ $m" -ForegroundColor Red        }

function Show-Banner {
    Write-Host ''
    Write-Host '  ╔══════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
    Write-Host '  ║                                                              ║' -ForegroundColor Cyan
    Write-Host '  ║   Create M365 Group                                          ║' -ForegroundColor Cyan
    Write-Host '  ║   Bareminimum Automation                                     ║' -ForegroundColor DarkCyan
    Write-Host '  ║                                                              ║' -ForegroundColor Cyan
    Write-Host '  ╚══════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
    Write-Host ''
}

# ─── Input Helpers ────────────────────────────────────────────────────────────

function Read-YesNo {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$DefaultYes = $true
    )
    $suffix = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    do {
        $response = (Read-Host "  $Prompt $suffix").Trim()
        if ([string]::IsNullOrWhiteSpace($response)) { return $DefaultYes }
        switch ($response.ToLowerInvariant()) {
            'y'   { return $true  }
            'yes' { return $true  }
            'n'   { return $false }
            'no'  { return $false }
            default { Write-Warn 'Please answer y or n.' }
        }
    } while ($true)
}

function Read-RequiredValue {
    param([Parameter(Mandatory)][string]$Prompt)
    do {
        $value = (Read-Host "  $Prompt").Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
        Write-Warn 'Value cannot be empty.'
    } while ($true)
}

function Read-ValidMailNickname {
    do {
        $nickname = (Read-Host '  Mail nickname (alias, no spaces)').Trim()
        if ([string]::IsNullOrWhiteSpace($nickname)) {
            Write-Warn 'Mail nickname cannot be empty.'
            continue
        }
        # Graph restriction: disallow  @ ( ) \ [ ] " ; : < > , and spaces
        if ($nickname -match '[ @\(\)\\\[\]";:<>\,]') {
            Write-Warn 'Invalid characters. Avoid: spaces  @ ( ) \ [ ] " ; : < > ,'
            continue
        }
        return $nickname
    } while ($true)
}

# ─── Module Management ───────────────────────────────────────────────────────

function Ensure-Module {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue)) {
        Write-Step "Installing module '$Name'..."
        try {
            Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Write-Ok "Module '$Name' installed."
        } catch {
            throw "Failed to install module '$Name': $_"
        }
    }
    if (-not (Get-Module -Name $Name)) {
        Import-Module -Name $Name -ErrorAction Stop
    }
}

# ═════════════════════════════════════════════════════════════════════════════

Show-Banner

# ─── Modules ─────────────────────────────────────────────────────────────────

Write-Step 'Checking required modules...'
Ensure-Module -Name 'Microsoft.Entra'
Write-Ok "Module 'Microsoft.Entra' ready."
Write-Host ''

# ─── Authentication ───────────────────────────────────────────────────────────

Write-Step 'Connecting to Microsoft Entra...'
try {
    Connect-Entra -Scopes @('Group.ReadWrite.All') -ErrorAction Stop
    $mgCtx = Get-MgContext
    Write-Ok "Connected as : $($mgCtx.Account)"
    Write-Ok "Tenant ID    : $($mgCtx.TenantId)"
    # Resolve the tenant display name from the organization endpoint
    try {
        $org = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization?$select=displayName' -ErrorAction Stop
        $tenantName = $org.value[0].displayName
        Write-Ok "Tenant name  : $tenantName"
    } catch {
        Write-Info "Tenant name  : (could not resolve – $($_.Exception.Message))"
    }
} catch {
    Write-Fail "Authentication failed: $_"
    exit 1
}

Write-Host ''

# ─── Group Details ────────────────────────────────────────────────────────────

Write-Host '  ── Group Details ───────────────────────────────────────────────' -ForegroundColor Cyan
Write-Host ''

$displayName  = Read-RequiredValue -Prompt 'Group display name'
$mailNickname = Read-ValidMailNickname
$description  = (Read-Host '  Description (optional)').Trim()

Write-Host ''

# ─── Behaviour Options ────────────────────────────────────────────────────────

Write-Host '  ── Behaviour Options ───────────────────────────────────────────' -ForegroundColor Cyan
Write-Host ''

$isPrivate            = Read-YesNo -Prompt 'Make group Private?'                              -DefaultYes $true
$attachTeam           = Read-YesNo -Prompt 'Provision a Microsoft Teams team?'              -DefaultYes $false
$attachSharePointSite = Read-YesNo -Prompt 'Provision a SharePoint site?'                  -DefaultYes $false
$sendWelcomeEmail     = Read-YesNo -Prompt 'Send welcome email to new members?'           -DefaultYes $false
$hideGroupInOutlook   = Read-YesNo -Prompt 'Hide group in Outlook?'                        -DefaultYes $false
$subscribeNewMembers  = Read-YesNo -Prompt 'Auto-subscribe new members to conversations?'  -DefaultYes $false

# Build ResourceBehaviorOptions list
# ProvisionSiteOnDemand defers SharePoint site creation; omit it to provision immediately.
$resourceBehaviorOptions = [System.Collections.Generic.List[string]]::new()
if (-not $sendWelcomeEmail)  { [void]$resourceBehaviorOptions.Add('WelcomeEmailDisabled') }
if (-not $attachSharePointSite) { [void]$resourceBehaviorOptions.Add('ProvisionSiteOnDemand') }
if ($hideGroupInOutlook)     { [void]$resourceBehaviorOptions.Add('HideGroupInOutlook') }
if ($subscribeNewMembers)    { [void]$resourceBehaviorOptions.Add('SubscribeNewGroupMembers') }

# ─── Confirmation ─────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '  ── Summary ─────────────────────────────────────────────────────' -ForegroundColor Cyan
Write-Host ''
Write-Info "Display name     : $displayName"
Write-Info "Mail nickname    : $mailNickname"
Write-Info "Description      : $(if ($description) { $description } else { '(none)' })"
Write-Info "Visibility       : $(if ($isPrivate) { 'Private' } else { 'Public' })"
Write-Info "Teams team       : $(if ($attachTeam) { 'Yes – will be provisioned after group creation' } else { 'No' })"
Write-Info "SharePoint site  : $(if ($attachSharePointSite) { 'Yes – provisioned automatically' } else { 'Deferred (on-demand only)' })"
Write-Info "Welcome email    : $(if ($sendWelcomeEmail) { 'Enabled' } else { 'Disabled' })"
Write-Info "Hide in Outlook  : $(if ($hideGroupInOutlook) { 'Yes' } else { 'No' })"
Write-Info "Behavior options : $(if ($resourceBehaviorOptions.Count -gt 0) { $resourceBehaviorOptions -join ', ' } else { '(none)' })"
Write-Host ''

if (-not (Read-YesNo -Prompt 'Create this group now?' -DefaultYes $true)) {
    Write-Info 'Cancelled. No group was created.'
    exit 0
}

# ─── Create Group ─────────────────────────────────────────────────────────────

Write-Host ''
Write-Step 'Creating Microsoft 365 group...'

$groupBody = [ordered]@{
    displayName     = $displayName
    mailEnabled     = $true
    mailNickname    = $mailNickname
    securityEnabled = $false
    groupTypes      = @('Unified')
    visibility      = if ($isPrivate) { 'Private' } else { 'Public' }
}

if (-not [string]::IsNullOrWhiteSpace($description)) {
    $groupBody['description'] = $description
}

if ($resourceBehaviorOptions.Count -gt 0) {
    $groupBody['resourceBehaviorOptions'] = $resourceBehaviorOptions.ToArray()
}

try {
    $newGroup = Invoke-MgGraphRequest -Method POST `
        -Uri 'https://graph.microsoft.com/v1.0/groups' `
        -Body ($groupBody | ConvertTo-Json -Depth 5) `
        -ContentType 'application/json'
} catch {
    Write-Fail "Group creation failed: $_"
    exit 1
}

# ─── Teams Provisioning ───────────────────────────────────────────────────────

$teamsProvisioned = $false
if ($attachTeam) {
    Write-Step 'Provisioning Teams team (may take up to a minute)...'
    $teamsBody = @{
        memberSettings    = @{ allowCreateUpdateChannels = $true }
        messagingSettings = @{ allowUserEditMessages = $true; allowUserDeleteMessages = $true }
        funSettings       = @{ allowGiphyContent = $false }
    } | ConvertTo-Json -Depth 5

    $maxAttempts = 6
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Invoke-MgGraphRequest -Method PUT `
                -Uri "https://graph.microsoft.com/v1.0/groups/$($newGroup['id'])/team" `
                -Body $teamsBody -ContentType 'application/json' | Out-Null
            $teamsProvisioned = $true
            Write-Ok 'Teams team provisioned.'
            break
        } catch {
            if ($attempt -lt $maxAttempts) {
                Write-Info "  Group not ready yet – retrying in 15 seconds... ($attempt/$maxAttempts)"
                Start-Sleep -Seconds 15
            } else {
                Write-Warn "Teams provisioning failed after $maxAttempts attempts: $_"
                Write-Info '  You can provision Teams later via the Teams admin centre or Graph API.'
            }
        }
    }
}

# ─── Result ───────────────────────────────────────────────────────────────────

Write-Host ''
Write-Ok 'Group created successfully.'
Write-Host ''
Write-Host '  ── Result ──────────────────────────────────────────────────────' -ForegroundColor Cyan
Write-Host ''
Write-Info "Group ID         : $($newGroup['id'])"
Write-Info "Display name     : $($newGroup['displayName'])"
Write-Info "Mail nickname    : $($newGroup['mailNickname'])"
if ($newGroup['mail']) {
    Write-Info "Email address    : $($newGroup['mail'])"
}
Write-Info "Visibility       : $(if ($isPrivate) { 'Private' } else { 'Public' })"
Write-Info "Teams team       : $(if ($attachTeam) { if ($teamsProvisioned) { 'Provisioned' } else { 'Failed – provision manually' } } else { 'Not provisioned' })"
Write-Info "SharePoint site  : $(if ($attachSharePointSite) { 'Provisioning automatically' } else { 'Deferred (on-demand only)' })"
if ($resourceBehaviorOptions.Count -gt 0) {
    Write-Info "Behavior options : $($resourceBehaviorOptions -join ', ')"
}
Write-Host ''

