#Requires -Version 7.0
# ─────────────────────────────────────────────────────────────────────────────
#  Create-AdminUsers.ps1
#  Bulk-creates Entra ID admin accounts from an Excel input file.
#  UPN format: cadm-<first3_firstname><first3_lastname>-<3digits>@domain
#
#  Usage:
#    Generate template : .\Create-AdminUsers.ps1 -GenerateTemplate -TemplatePath .\template.xlsx
#    Run provisioning  : .\Create-AdminUsers.ps1 -ExcelPath .\template.xlsx -GlobalDomain contoso.com
# ─────────────────────────────────────────────────────────────────────────────

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(HelpMessage = 'Path to the Excel input file.')]
    [string]$ExcelPath,

    [Parameter(HelpMessage = 'Default domain (e.g. contoso.com). Overridable per row in the Domain column.')]
    [string]$GlobalDomain,

    [Parameter(HelpMessage = 'Generate a blank Excel template and exit.')]
    [switch]$GenerateTemplate,

    [Parameter(HelpMessage = 'Output path for the generated template.')]
    [string]$TemplatePath = '.\AdminUsers-Template.xlsx'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Constants ────────────────────────────────────────────────────────────────

$script:RequiredModules = @(
    'Microsoft.Graph.Authentication'
    'Microsoft.Graph.Users'
    'Microsoft.Graph.Groups'
    'Microsoft.Graph.Identity.Governance'
    'Microsoft.Graph.Identity.DirectoryManagement'
    'ImportExcel'
)

$script:RequiredScopes = @(
    'User.ReadWrite.All'
    'Group.ReadWrite.All'
    'GroupMember.ReadWrite.All'
    'RoleManagement.ReadWrite.Directory'
    'Directory.ReadWrite.All'
)

$script:RoleCache  = @{}   # displayName  → role definition ID
$script:GroupCache = @{}   # name or GUID → object ID

# ─── UI Helpers ───────────────────────────────────────────────────────────────

function Write-Step { param([string]$Msg) Write-Host "▶ $Msg" -ForegroundColor Yellow }
function Write-Ok   { param([string]$Msg) Write-Host "✓ $Msg" -ForegroundColor Green }
function Write-Info { param([string]$Msg) Write-Host "· $Msg" -ForegroundColor Gray }
function Write-Warn { param([string]$Msg) Write-Host "⚠ $Msg" -ForegroundColor DarkYellow }
function Write-Fail { param([string]$Msg) Write-Host "✗ $Msg" -ForegroundColor Red }

function Show-Banner {
    # Inner content width (between │ and │). Must be >= the longest content line.
    $inner = 88

    # Helpers — padding is always computed, never hardcoded, so it can never go negative.
    function Write-BRow {
        param([string]$Text = '', [string]$Prefix = '  ', [System.ConsoleColor]$Color = 'Gray')
        $content = $Prefix + $Text
        $pad = [math]::Max(0, $inner - $content.Length)
        Write-Host ('│' + $content + (' ' * $pad) + '│') -ForegroundColor $Color
    }
    function Write-BBlank  { Write-Host ('│' + (' ' * $inner) + '│') -ForegroundColor DarkCyan }
    function Write-BSep    { Write-Host ('├' + ('─' * $inner) + '┤') -ForegroundColor DarkCyan }
    function Write-BTop    { Write-Host ('┌' + ('─' * $inner) + '┐') -ForegroundColor DarkCyan }
    function Write-BBot    { Write-Host ('└' + ('─' * $inner) + '┘') -ForegroundColor DarkCyan }
    function Write-BHeader {
        param([string]$Text)
        $pad = [math]::Max(0, $inner - $Text.Length)
        $lp  = [int][math]::Floor($pad / 2)
        $rp  = $pad - $lp
        Write-Host ('│' + (' ' * $lp) + $Text + (' ' * $rp) + '│') -ForegroundColor Cyan
    }

    Write-Host ''
    Write-Host ('╔' + ('═' * $inner) + '╗') -ForegroundColor Cyan
    Write-BHeader 'CREATE ADMIN USERS FROM EXCEL'
    Write-BHeader 'Entra ID Bulk Admin Account Provisioning'
    Write-Host ('╚' + ('═' * $inner) + '╝') -ForegroundColor Cyan
    Write-Host ''

    Write-BTop
    Write-BRow 'WHAT THIS SCRIPT DOES' -Color DarkCyan
    Write-BSep
    Write-BBlank
    Write-BRow 'Reads an Excel file row by row and creates Entra ID admin accounts.'
    Write-BRow 'Each account gets:'
    Write-BRow '· A structured UPN  →  cadm-<first3><last3>-<3digits>@domain'   -Prefix '    '
    Write-BRow '· A 24-character cryptographically secure password'              -Prefix '    '
    Write-BRow '· Optional group memberships (Object IDs, semicolon-separated)'  -Prefix '    '
    Write-BRow '· Optional permanent Entra role assignments'                     -Prefix '    '
    Write-BRow '· Optional PIM-eligible role assignments (no expiry)'            -Prefix '    '
    Write-BRow '· Optional manager assignment'                                   -Prefix '    '
    Write-BBlank
    Write-BSep
    Write-BRow 'EXCEL COLUMNS' -Color DarkCyan
    Write-BSep
    Write-BBlank
    Write-BRow 'Required  :  FirstName  |  LastName'
    Write-BRow 'Optional  :  Domain  |  DisplayName  |  Department  |  JobTitle'
    Write-BRow '              Manager  |  Groups  |  PermanentRoles  |  EligibleRoles' -Prefix ''
    Write-BRow 'Multi-value columns (Groups / Roles): separate entries with  ;'
    Write-BRow '! Groups must use Object IDs (GUIDs), not display names.' -Prefix '  ' -Color DarkYellow
    Write-BBlank
    Write-BSep
    Write-BRow 'HOW TO USE' -Color DarkCyan
    Write-BSep
    Write-BBlank
    Write-BRow '1. Generate a blank template:'
    Write-BRow '.\Create-AdminUsers.ps1 -GenerateTemplate' -Prefix '       ' -Color Yellow
    Write-BBlank
    Write-BRow '2. Fill in the Excel template and save it.'
    Write-BBlank
    Write-BRow '3. Run the script:'
    Write-BRow '.\Create-AdminUsers.ps1 -ExcelPath .\template.xlsx -GlobalDomain contoso.com' -Prefix '       ' -Color Yellow
    Write-BBlank
    Write-BSep
    Write-BRow 'OUTPUT' -Color DarkCyan
    Write-BSep
    Write-BBlank
    Write-BRow '· Accounts are listed in the console with UPN + password'
    Write-BRow '· A results file  AdminUsers-Results-<timestamp>.xlsx  is saved next to the input'
    Write-BRow '  file — it contains plaintext passwords.' -Prefix '  '
    Write-BRow '· Existing accounts (same UPN) are skipped automatically (idempotent).'
    Write-BBlank
    Write-BBot
    Write-Host ''
    Write-Host '  ⚠  The results file contains plaintext passwords — store it securely.' -ForegroundColor DarkYellow
    Write-Host ''
}

# ─── Logic Helpers ────────────────────────────────────────────────────────────

function Assert-RequiredModules {
    foreach ($mod in $script:RequiredModules) {
        if (-not (Get-Module -Name $mod -ListAvailable)) {
            Write-Step "Installing module: $mod"
            Install-Module -Name $mod -Force -Scope CurrentUser -Repository PSGallery
        }
        Import-Module -Name $mod -ErrorAction Stop
    }
}

function New-SecurePassword {
    [OutputType([string])]
    param([int]$Length = 24)

    $upper   = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $lower   = 'abcdefghijklmnopqrstuvwxyz'
    $digits  = '0123456789'
    $special = '!@#$%^&*()-_=+[]{}|;:,.<>?'
    $all     = $upper + $lower + $digits + $special

    $rng   = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = [byte[]]::new($Length * 4)
    $rng.GetBytes($bytes)

    $pwd = [System.Collections.Generic.List[char]]::new()

    # Guarantee at least one character from every class
    $i = 0
    foreach ($charset in @($upper, $lower, $digits, $special)) {
        $pwd.Add($charset[[int]($bytes[$i] % $charset.Length)])
        $i++
    }

    # Fill remaining length
    while ($pwd.Count -lt $Length) {
        if ($i -ge $bytes.Length) {
            $rng.GetBytes($bytes)
            $i = 0
        }
        $pwd.Add($all[[int]($bytes[$i] % $all.Length)])
        $i++
    }

    # Fisher-Yates shuffle
    $arr = $pwd.ToArray()
    $rng.GetBytes($bytes)
    for ($j = $arr.Length - 1; $j -gt 0; $j--) {
        $k   = [int]($bytes[$j % $bytes.Length] % ($j + 1))
        $tmp = $arr[$j]; $arr[$j] = $arr[$k]; $arr[$k] = $tmp
    }

    $rng.Dispose()
    return -join $arr
}

function Get-SafeUPNPart {
    [OutputType([string])]
    param([string]$Name, [int]$Length = 3)

    $clean = ($Name -replace '[^a-zA-Z0-9]', '').ToLower()
    if ($clean.Length -lt $Length) { $clean = $clean.PadRight($Length, 'x') }
    return $clean.Substring(0, $Length)
}

function New-AdminUPN {
    [OutputType([string])]
    param(
        [string]$FirstName,
        [string]$LastName,
        [string]$Domain
    )

    $p1  = Get-SafeUPNPart -Name $FirstName -Length 3
    $p2  = Get-SafeUPNPart -Name $LastName  -Length 3
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $numBytes = [byte[]]::new(4)
        $rng.GetBytes($numBytes)
        $num = ([System.BitConverter]::ToUInt32($numBytes, 0) % 900) + 100   # 100–999
        $upn = "cadm-$p1$p2-$num@$Domain"

        $escaped  = $upn.Replace("'", "''")
        $existing = Get-MgUser -Filter "userPrincipalName eq '$escaped'" `
                               -Select 'id' -ErrorAction SilentlyContinue
        if (-not $existing) {
            $rng.Dispose()
            return $upn
        }
        Write-Info "UPN $upn already taken — retrying…"
    }

    $rng.Dispose()
    throw "Could not generate a unique UPN for $FirstName $LastName after 20 attempts."
}

function Get-RoleDefinitionId {
    [OutputType([string])]
    param([string]$RoleName)

    if ($script:RoleCache.ContainsKey($RoleName)) { return $script:RoleCache[$RoleName] }

    $escaped = $RoleName.Replace("'", "''")
    $role    = Get-MgRoleManagementDirectoryRoleDefinition `
                   -Filter "displayName eq '$escaped'" -ErrorAction Stop

    if (-not $role) { throw "Entra role not found: '$RoleName'" }

    $script:RoleCache[$RoleName] = $role.Id
    return $role.Id
}

function Get-GroupObjectId {
    [OutputType([string])]
    param([string]$NameOrId)

    if ($script:GroupCache.ContainsKey($NameOrId)) { return $script:GroupCache[$NameOrId] }

    # Groups column only accepts Object IDs (GUIDs)
    if ($NameOrId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw "'$NameOrId' is not a valid Group Object ID (GUID). The Groups column requires Object IDs, not display names. Find the ID in Entra ID → Groups → <group> → Overview."
    }

    $script:GroupCache[$NameOrId] = $NameOrId
    return $NameOrId
}

function Resolve-ManagerId {
    [OutputType([string])]
    param([string]$ManagerRef)

    if ([string]::IsNullOrWhiteSpace($ManagerRef)) { return $null }

    # GUID → use directly
    if ($ManagerRef -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        return $ManagerRef
    }

    $escaped = $ManagerRef.Replace("'", "''")

    # Try UPN first, then display name
    $user = Get-MgUser -Filter "userPrincipalName eq '$escaped'" `
                       -Select 'id' -ErrorAction SilentlyContinue
    if ($user) { return $user.Id }

    $user = Get-MgUser -Filter "displayName eq '$escaped'" `
                       -Select 'id' -ErrorAction SilentlyContinue
    if ($user) { return $user.Id }

    throw "Manager not found: '$ManagerRef'"
}

function Select-Domain {
    [OutputType([string])]
    param()

    Write-Step "Fetching verified domains from Entra ID"
    try {
        $domains = Get-MgDomain -Select 'id,isDefault,isInitial,isVerified' -ErrorAction Stop |
                   Where-Object { $_.IsVerified } |
                   Sort-Object -Property @{Expression={$_.IsDefault}; Descending=$true}, Id
    } catch {
        Write-Warn "Could not retrieve domains: $_"
        return (Read-Host "Enter the default domain (e.g. contoso.com)")
    }

    if (-not $domains) {
        Write-Warn "No verified domains found in the tenant."
        return (Read-Host "Enter the default domain (e.g. contoso.com)")
    }

    Write-Host ''
    Write-Host '  Available verified domains:' -ForegroundColor Cyan
    Write-Host ''
    for ($i = 0; $i -lt $domains.Count; $i++) {
        $d      = $domains[$i]
        $suffix = if ($d.IsDefault) { ' (default)' } elseif ($d.IsInitial) { ' (initial)' } else { '' }
        $label  = '  {0,2}. {1}{2}' -f ($i + 1), $d.Id, $suffix
        $color  = if ($d.IsDefault) { 'Green' } else { 'Gray' }
        Write-Host $label -ForegroundColor $color
    }
    Write-Host ''

    while ($true) {
        $choice = Read-Host "  Select domain [1-$($domains.Count)]"
        if ($choice -match '^\d+$') {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $domains.Count) {
                $selected = $domains[$idx].Id
                Write-Ok "Domain selected: $selected"
                return $selected
            }
        }
        Write-Warn "  Invalid selection — enter a number between 1 and $($domains.Count)."
    }
}

function New-ExcelTemplate {
    param([string]$Path)

    $template = [PSCustomObject]@{
        FirstName      = ''
        LastName       = ''
        Domain         = ''
        DisplayName    = ''
        Department     = ''
        JobTitle       = ''
        Manager        = ''
        Groups         = ''
        PermanentRoles = ''
        EligibleRoles  = ''
    }

    $excelParams = @{
        Path          = $Path
        WorksheetName = 'AdminUsers'
        AutoSize      = $true
        BoldTopRow    = $true
        FreezeTopRow  = $true
        TableName     = 'AdminUsers'
        TableStyle    = 'Medium2'
    }

    $template | Export-Excel @excelParams
    Write-Ok "Template created: $Path"
}

# ─── Phase 0 — Modules & Auth ─────────────────────────────────────────────────

Write-Step "Checking required modules"
try { Assert-RequiredModules } catch { Write-Fail "Module setup failed: $_"; exit 1 }

if (-not $GenerateTemplate) {
    Write-Step "Connecting to Microsoft Graph"
    Write-Info "Required scopes: $($script:RequiredScopes -join ', ')"
    try {
        Connect-MgGraph -Scopes $script:RequiredScopes -ErrorAction Stop
        Write-Ok "Connected to Microsoft Graph"
    } catch {
        Write-Fail "Graph connection failed: $_"
        exit 1
    }
}

# ─── Phase 1 — Input ──────────────────────────────────────────────────────────

Show-Banner

if ($GenerateTemplate) {
    Write-Step "Generating Excel template"
    try { New-ExcelTemplate -Path $TemplatePath } catch { Write-Fail "Template creation failed: $_"; exit 1 }
    Write-Info "Fill in the template and re-run with: -ExcelPath '$TemplatePath'"
    exit 0
}

if (-not $ExcelPath) {
    $ExcelPath = Read-Host "Enter path to the Excel input file"
}
if (-not (Test-Path -Path $ExcelPath)) {
    Write-Fail "File not found: $ExcelPath"
    exit 1
}

if (-not $GlobalDomain) {
    $GlobalDomain = Select-Domain
}
if ([string]::IsNullOrWhiteSpace($GlobalDomain)) {
    Write-Fail "A domain is required."
    exit 1
}

# ─── Phase 2 — Import & Validate ──────────────────────────────────────────────

Write-Step "Importing Excel: $ExcelPath"

try {
    $rows = Import-Excel -Path $ExcelPath -ErrorAction Stop
} catch {
    Write-Fail "Failed to import Excel: $_"
    exit 1
}

if (-not $rows) {
    Write-Fail "No data found in the Excel file."
    exit 1
}

# Validate required columns exist
$firstRow = $rows | Select-Object -First 1
foreach ($col in @('FirstName', 'LastName')) {
    if ($null -eq $firstRow.PSObject.Properties[$col]) {
        Write-Fail "Required column '$col' not found. Use -GenerateTemplate to create a valid template."
        exit 1
    }
}

$validRows = [System.Collections.Generic.List[object]]::new()
$rowNum    = 1
foreach ($row in $rows) {
    $rowNum++
    if ([string]::IsNullOrWhiteSpace([string]$row.FirstName) -or
        [string]::IsNullOrWhiteSpace([string]$row.LastName)) {
        Write-Warn "Row $rowNum skipped — FirstName or LastName is empty."
        continue
    }
    $validRows.Add($row)
}

Write-Info "$($validRows.Count) valid row(s) to process."
if ($validRows.Count -eq 0) {
    Write-Fail "No valid rows to process."
    exit 1
}

# ─── Phase 3 — Create Users ───────────────────────────────────────────────────

$results = [System.Collections.Generic.List[PSObject]]::new()

foreach ($row in $validRows) {

    $domain = if (-not [string]::IsNullOrWhiteSpace([string]$row.Domain)) {
        ([string]$row.Domain).Trim()
    } else {
        $GlobalDomain
    }

    Write-Step "Processing: $([string]$row.FirstName) $([string]$row.LastName) [@$domain]"

    # ── Build UPN ────────────────────────────────────────────────────────────
    $upn = $null
    try {
        $upn = New-AdminUPN -FirstName ([string]$row.FirstName) `
                            -LastName  ([string]$row.LastName)  `
                            -Domain    $domain
    } catch {
        Write-Fail "  UPN generation failed: $_"
        $results.Add([PSCustomObject]@{
            UPN = "ERROR"; DisplayName = "$([string]$row.FirstName) $([string]$row.LastName)"
            Password = ''; Groups = ''; PermanentRoles = ''; EligibleRoles = ''
            Status = "Failed: $_"
        })
        continue
    }

    # ── Idempotency check ────────────────────────────────────────────────────
    $escapedUpn  = $upn.Replace("'", "''")
    $existingUser = Get-MgUser -Filter "userPrincipalName eq '$escapedUpn'" `
                               -Select 'id,displayName' -ErrorAction SilentlyContinue
    if ($existingUser) {
        Write-Warn "  $upn already exists — skipping."
        $results.Add([PSCustomObject]@{
            UPN = $upn; DisplayName = $existingUser.DisplayName
            Password = '(already existed)'; Groups = ''; PermanentRoles = ''; EligibleRoles = ''
            Status = 'Skipped'
        })
        continue
    }

    # ── Display name & mail nickname ─────────────────────────────────────────
    $displayName = if (-not [string]::IsNullOrWhiteSpace([string]$row.DisplayName)) {
        ([string]$row.DisplayName).Trim()
    } else {
        "CADM - $([string]$row.FirstName.Trim()) $([string]$row.LastName.Trim())"
    }
    $mailNick = ($upn -split '@')[0]
    $password = New-SecurePassword

    # ── Create user ──────────────────────────────────────────────────────────
    $userParams = @{
        UserPrincipalName = $upn
        DisplayName       = $displayName
        MailNickname      = $mailNick
        AccountEnabled    = $true
        PasswordPolicies  = 'DisablePasswordExpiration'
        PasswordProfile   = @{
            Password                      = $password
            ForceChangePasswordNextSignIn = $true
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$row.Department)) {
        $userParams['Department'] = ([string]$row.Department).Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$row.JobTitle)) {
        $userParams['JobTitle'] = ([string]$row.JobTitle).Trim()
    }

    $newUser = $null
    try {
        $newUser = New-MgUser @userParams
        Write-Ok "  Created: $upn"
    } catch {
        Write-Fail "  Failed to create $upn : $_"
        $results.Add([PSCustomObject]@{
            UPN = $upn; DisplayName = $displayName; Password = ''
            Groups = ''; PermanentRoles = ''; EligibleRoles = ''
            Status = "Failed: $_"
        })
        continue
    }

    # ── Group membership ─────────────────────────────────────────────────────
    $groupStatus = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace([string]$row.Groups)) {
        foreach ($grp in (([string]$row.Groups) -split ';')) {
            $grp = $grp.Trim()
            if ([string]::IsNullOrWhiteSpace($grp)) { continue }
            try {
                $groupId    = Get-GroupObjectId -NameOrId $grp
                $memberBody = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($newUser.Id)" }
                Invoke-MgGraphRequest -Method POST `
                    -Uri     "v1.0/groups/$groupId/members/`$ref" `
                    -Body    $memberBody -ErrorAction Stop
                $groupStatus.Add($grp)
                Write-Ok "  Added to group: $grp"
            } catch {
                Write-Warn "  Group '$grp': $_"
            }
        }
    }

    # ── Permanent role assignments ───────────────────────────────────────────
    $permRoleStatus = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace([string]$row.PermanentRoles)) {
        foreach ($role in (([string]$row.PermanentRoles) -split ';')) {
            $role = $role.Trim()
            if ([string]::IsNullOrWhiteSpace($role)) { continue }
            try {
                $roleDefId   = Get-RoleDefinitionId -RoleName $role
                $assignBody  = @{
                    RoleDefinitionId = $roleDefId
                    PrincipalId      = $newUser.Id
                    DirectoryScopeId = '/'
                }
                New-MgRoleManagementDirectoryRoleAssignment -BodyParameter $assignBody -ErrorAction Stop
                $permRoleStatus.Add($role)
                Write-Ok "  Permanent role: $role"
            } catch {
                Write-Warn "  Permanent role '$role': $_"
            }
        }
    }

    # ── PIM eligible role assignments ────────────────────────────────────────
    $eligRoleStatus = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace([string]$row.EligibleRoles)) {
        foreach ($role in (([string]$row.EligibleRoles) -split ';')) {
            $role = $role.Trim()
            if ([string]::IsNullOrWhiteSpace($role)) { continue }
            try {
                $roleDefId     = Get-RoleDefinitionId -RoleName $role
                $scheduleBody  = @{
                    Action           = 'adminAssign'
                    Justification    = 'Admin account provisioning'
                    RoleDefinitionId = $roleDefId
                    DirectoryScopeId = '/'
                    PrincipalId      = $newUser.Id
                    ScheduleInfo     = @{
                        StartDateTime = (Get-Date).ToUniversalTime().ToString('o')
                        Expiration    = @{ Type = 'noExpiration' }
                    }
                }
                New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest `
                    -BodyParameter $scheduleBody -ErrorAction Stop
                $eligRoleStatus.Add($role)
                Write-Ok "  Eligible (PIM) role: $role"
            } catch {
                Write-Warn "  Eligible role '$role': $_"
            }
        }
    }

    # ── Manager ──────────────────────────────────────────────────────────────
    if (-not [string]::IsNullOrWhiteSpace([string]$row.Manager)) {
        try {
            $managerId = Resolve-ManagerId -ManagerRef ([string]$row.Manager).Trim()
            if ($managerId) {
                $managerBody = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$managerId" }
                Invoke-MgGraphRequest -Method PUT `
                    -Uri  "v1.0/users/$($newUser.Id)/manager/`$ref" `
                    -Body $managerBody -ErrorAction Stop
                Write-Ok "  Manager set: $($row.Manager.Trim())"
            }
        } catch {
            Write-Warn "  Manager '$($row.Manager.Trim())': $_"
        }
    }

    $results.Add([PSCustomObject]@{
        UPN            = $upn
        DisplayName    = $displayName
        Password       = $password
        Groups         = ($groupStatus     -join '; ')
        PermanentRoles = ($permRoleStatus  -join '; ')
        EligibleRoles  = ($eligRoleStatus  -join '; ')
        Status         = 'Created'
    })
}

# ─── Phase 4 — Output ─────────────────────────────────────────────────────────

Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────────────' -ForegroundColor Cyan
Write-Host '  ADMIN ACCOUNT SUMMARY' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────────────' -ForegroundColor Cyan

foreach ($r in $results) {
    switch ($r.Status) {
        'Created' {
            Write-Host "`n  UPN        : " -NoNewline -ForegroundColor Gray; Write-Host $r.UPN -ForegroundColor Green
            Write-Host '  Display    : ' -NoNewline -ForegroundColor Gray; Write-Host $r.DisplayName
            Write-Host '  Password   : ' -NoNewline -ForegroundColor Gray; Write-Host $r.Password -ForegroundColor Yellow
            if ($r.Groups)         { Write-Host "  Groups     : $($r.Groups)"         -ForegroundColor Gray }
            if ($r.PermanentRoles) { Write-Host "  Perm.Roles : $($r.PermanentRoles)" -ForegroundColor Gray }
            if ($r.EligibleRoles)  { Write-Host "  PIM Roles  : $($r.EligibleRoles)"  -ForegroundColor Gray }
        }
        'Skipped' { Write-Warn "  $($r.UPN) — already exists, skipped" }
        default   { Write-Fail  "  $($r.UPN) — $($r.Status)" }
    }
}

# Export results Excel
$inputDir   = Split-Path -Parent (Resolve-Path -Path $ExcelPath)
$timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputPath = Join-Path $inputDir "AdminUsers-Results-$timestamp.xlsx"

$exportParams = @{
    Path          = $outputPath
    WorksheetName = 'Results'
    AutoSize      = $true
    BoldTopRow    = $true
    FreezeTopRow  = $true
    TableName     = 'Results'
    TableStyle    = 'Medium2'
}

try {
    $results | Export-Excel @exportParams
    Write-Host ''
    Write-Host '─────────────────────────────────────────────────────────────────────' -ForegroundColor Cyan
    Write-Host "  Results exported: $outputPath" -ForegroundColor Cyan
    Write-Host '─────────────────────────────────────────────────────────────────────' -ForegroundColor Cyan
} catch {
    Write-Warn "Could not export results Excel: $_"
}

Write-Host ''
Write-Host '⚠  STORE PASSWORDS AND THE RESULTS FILE IN A SECURE LOCATION.' -ForegroundColor Red
Write-Host '   The output Excel contains plaintext passwords.' -ForegroundColor Red
Write-Host ''
