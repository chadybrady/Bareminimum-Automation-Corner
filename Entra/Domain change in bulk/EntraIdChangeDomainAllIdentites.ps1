#Requires -Version 5.1

<#
.SYNOPSIS
    Changes the domain on all identities in an Entra ID tenant.

.DESCRIPTION
    This script changes the primary domain on all identities in an Entra ID / Exchange Online
    tenant. It targets:
      - Entra ID user accounts (UPN + mail attribute)
      - Shared mailboxes
      - User mailboxes
      - Distribution groups
      - Microsoft 365 groups
      - Mail contacts
      - Mail-enabled security groups

    The script will prompt the admin to select a source domain (change FROM) and a target
    domain (change TO), show a preview, request confirmation, then process all objects.

.NOTES
    Required modules: Microsoft.Graph, ExchangeOnlineManagement
    Required permissions:
      - Entra ID: User.ReadWrite.All, Group.ReadWrite.All, Directory.ReadWrite.All
      - Exchange Online: Exchange Administrator
#>

[CmdletBinding()]
param (
    [switch]$WhatIf,
    [switch]$SkipExchangeOnline,
    [switch]$SkipEntraID
)

# ─────────────────────────────────────────────────────────────────────────────
# REGION: Helpers
# ─────────────────────────────────────────────────────────────────────────────

$script:LogLines    = [System.Collections.Generic.List[string]]::new()
$script:ChangesMade = 0
$script:Errors      = 0
$script:Skipped     = 0

function Write-Status {
    param(
        [string]$Message,
        [ValidateSet('Info','Success','Warning','Error','Header','Step')]
        [string]$Type = 'Info'
    )
    $timestamp = Get-Date -Format 'HH:mm:ss'
    switch ($Type) {
        'Header'  { Write-Host "`n══════════════════════════════════════════════════════" -ForegroundColor Cyan
                    Write-Host "  $Message" -ForegroundColor Cyan
                    Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Cyan }
        'Step'    { Write-Host "`n── $Message" -ForegroundColor Yellow }
        'Info'    { Write-Host "  [$timestamp] $Message" -ForegroundColor Gray }
        'Success' { Write-Host "  [$timestamp] [OK]  $Message" -ForegroundColor Green }
        'Warning' { Write-Host "  [$timestamp] [!!]  $Message" -ForegroundColor Yellow }
        'Error'   { Write-Host "  [$timestamp] [ERR] $Message" -ForegroundColor Red }
    }
    $script:LogLines.Add("[$timestamp][$Type] $Message")
}

function Show-Progress {
    param([int]$Current, [int]$Total, [string]$Activity, [string]$Status)
    $pct = if ($Total -gt 0) { [int](($Current / $Total) * 100) } else { 0 }
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $pct -CurrentOperation "$Current / $Total"
}

function Save-Log {
    param([string]$FromDomain, [string]$ToDomain)
    $logDir  = Split-Path -Parent $MyInvocation.ScriptName
    $logFile = Join-Path $logDir ("DomainChange_{0}_to_{1}_{2}.log" -f `
        $FromDomain, $ToDomain, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $script:LogLines | Out-File -FilePath $logFile -Encoding UTF8
    Write-Status "Log saved to: $logFile" -Type Info
}

# ─────────────────────────────────────────────────────────────────────────────
# REGION: Prerequisites
# ─────────────────────────────────────────────────────────────────────────────

function Assert-Modules {
    Write-Status "Checking required PowerShell modules..." -Type Step

    $required = @{
        'Microsoft.Graph.Users'          = '2.0.0'
        'Microsoft.Graph.Groups'         = '2.0.0'
        'Microsoft.Graph.Identity.DirectoryManagement' = '2.0.0'
        'ExchangeOnlineManagement'       = '3.0.0'
    }

    foreach ($mod in $required.GetEnumerator()) {
        $installed = Get-Module -ListAvailable -Name $mod.Key |
                     Sort-Object Version -Descending | Select-Object -First 1
        if (-not $installed) {
            Write-Status "Module '$($mod.Key)' is not installed. Attempting install..." -Type Warning
            try {
                Install-Module -Name $mod.Key -MinimumVersion $mod.Value `
                    -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
                Write-Status "Installed '$($mod.Key)'" -Type Success
            } catch {
                Write-Status "Failed to install '$($mod.Key)': $_" -Type Error
                throw "Cannot continue without required module: $($mod.Key)"
            }
        } else {
            Write-Status "Module '$($mod.Key)' v$($installed.Version) — OK" -Type Info
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# REGION: Connect
# ─────────────────────────────────────────────────────────────────────────────

function Connect-Services {
    Write-Status "Connecting to Microsoft services..." -Type Step

    # Entra ID via Microsoft Graph
    if (-not $SkipEntraID) {
        try {
            Write-Status "Connecting to Microsoft Graph..." -Type Info
            Connect-MgGraph -Scopes @(
                'User.ReadWrite.All',
                'Group.ReadWrite.All',
                'Directory.ReadWrite.All'
            ) -ErrorAction Stop -NoWelcome
            $ctx = Get-MgContext
            Write-Status "Microsoft Graph connected as: $($ctx.Account)" -Type Success
        } catch {
            Write-Status "Failed to connect to Microsoft Graph: $_" -Type Error
            throw
        }
    }

    # Exchange Online
    if (-not $SkipExchangeOnline) {
        try {
            Write-Status "Connecting to Exchange Online..." -Type Info
            $session = Get-ConnectionInformation -ErrorAction SilentlyContinue |
                       Where-Object { $_.State -eq 'Connected' }
            if (-not $session) {
                Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
            }
            Write-Status "Exchange Online connected." -Type Success
        } catch {
            Write-Status "Failed to connect to Exchange Online: $_" -Type Error
            throw
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# REGION: Domain selection
# ─────────────────────────────────────────────────────────────────────────────

function Select-Domains {
    Write-Status "Retrieving verified domains from tenant..." -Type Step

    $domains = Get-MgDomain -All | Where-Object { $_.IsVerified -eq $true } |
               Sort-Object Id

    if ($domains.Count -eq 0) {
        throw "No verified domains found in the tenant."
    }

    Write-Host "`n  Available verified domains:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $domains.Count; $i++) {
        $default    = if ($domains[$i].IsDefault)       { " [DEFAULT]"  } else { "" }
        $initial    = if ($domains[$i].IsInitial)       { " [INITIAL / onmicrosoft.com]" } else { "" }
        $federated  = if ($domains[$i].AuthenticationType -eq 'Federated') { " [FEDERATED]" } else { "" }
        Write-Host ("    [{0,2}]  {1}{2}{3}{4}" -f ($i+1), $domains[$i].Id, $default, $initial, $federated) `
            -ForegroundColor White
    }

    # --- Source domain ---
    Write-Host ""
    do {
        $fromInput = Read-Host "  Select the domain to change FROM (number)"
        $fromIdx   = [int]$fromInput - 1
    } while ($fromIdx -lt 0 -or $fromIdx -ge $domains.Count)

    $fromDomain = $domains[$fromIdx].Id
    Write-Status "Source domain selected: $fromDomain" -Type Info

    # --- Target domain ---
    Write-Host ""
    Write-Host "  Remaining domains to change TO:" -ForegroundColor Cyan
    $targetDomains = $domains | Where-Object { $_.Id -ne $fromDomain }
    for ($i = 0; $i -lt $targetDomains.Count; $i++) {
        $default   = if ($targetDomains[$i].IsDefault)  { " [DEFAULT]"  } else { "" }
        $initial   = if ($targetDomains[$i].IsInitial)  { " [INITIAL / onmicrosoft.com]" } else { "" }
        Write-Host ("    [{0,2}]  {1}{2}{3}" -f ($i+1), $targetDomains[$i].Id, $default, $initial) `
            -ForegroundColor White
    }

    Write-Host ""
    do {
        $toInput = Read-Host "  Select the domain to change TO (number)"
        $toIdx   = [int]$toInput - 1
    } while ($toIdx -lt 0 -or $toIdx -ge $targetDomains.Count)

    $toDomain = $targetDomains[$toIdx].Id
    Write-Status "Target domain selected: $toDomain" -Type Info

    return @{ From = $fromDomain; To = $toDomain }
}

# ─────────────────────────────────────────────────────────────────────────────
# REGION: Discovery — Entra ID users
# ─────────────────────────────────────────────────────────────────────────────

function Get-EntraUsersForDomain {
    param([string]$Domain)

    Write-Status "Discovering Entra ID users with domain '@$Domain'..." -Type Info

    # endsWith is an advanced Graph query — requires ConsistencyLevel + CountVariable
    $users = Get-MgUser -All `
        -Filter "endsWith(userPrincipalName,'@$Domain')" `
        -ConsistencyLevel eventual -CountVariable ignored `
        -Property Id, DisplayName, UserPrincipalName, Mail, ProxyAddresses, UserType, OnPremisesSyncEnabled `
        -ErrorAction SilentlyContinue

    # Also catch users whose mail (not UPN) uses the domain but UPN does not
    $mailUsers = Get-MgUser -All `
        -Filter "endsWith(mail,'@$Domain')" `
        -ConsistencyLevel eventual -CountVariable ignored `
        -Property Id, DisplayName, UserPrincipalName, Mail, ProxyAddresses, UserType, OnPremisesSyncEnabled `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.UserPrincipalName -notlike "*@$Domain" }

    $all = @($users) + @($mailUsers) | Sort-Object Id -Unique
    Write-Status "Found $($all.Count) Entra ID user(s) for domain '$Domain'" -Type Info
    return $all
}

# ─────────────────────────────────────────────────────────────────────────────
# REGION: Discovery — Entra ID groups
# ─────────────────────────────────────────────────────────────────────────────

function Get-EntraGroupsForDomain {
    param([string]$Domain)

    Write-Status "Discovering Entra ID groups (M365 groups) with domain '@$Domain'..." -Type Info

    $groups = Get-MgGroup -All `
        -Filter "endsWith(mail,'@$Domain')" `
        -ConsistencyLevel eventual -CountVariable ignored `
        -Property Id, DisplayName, Mail, ProxyAddresses, GroupTypes `
        -ErrorAction SilentlyContinue

    Write-Status "Found $($groups.Count) Entra ID group(s) for domain '$Domain'" -Type Info
    return $groups
}

# ─────────────────────────────────────────────────────────────────────────────
# REGION: Discovery — Exchange Online recipients
# ─────────────────────────────────────────────────────────────────────────────

function Get-ExchangeRecipientsForDomain {
    param([string]$Domain)

    Write-Status "Discovering Exchange Online recipients with domain '@$Domain'..." -Type Info

    $recipients = Get-Recipient -ResultSize Unlimited -ErrorAction SilentlyContinue |
        Where-Object {
            $_.EmailAddresses -match "@$Domain" -or
            $_.PrimarySmtpAddress -like "*@$Domain"
        }

    $grouped = $recipients | Group-Object RecipientTypeDetails

    foreach ($g in $grouped) {
        Write-Status "  $($g.Name): $($g.Count) object(s)" -Type Info
    }

    return $recipients
}

# ─────────────────────────────────────────────────────────────────────────────
# REGION: Process — Entra ID users
# ─────────────────────────────────────────────────────────────────────────────

function Update-EntraUser {
    param(
        $User,
        [string]$FromDomain,
        [string]$ToDomain,
        [switch]$WhatIf
    )

    $changed  = $false
    $oldUpn   = $User.UserPrincipalName
    $newUpn   = $oldUpn

    # Change UPN if it uses the source domain
    if ($oldUpn -like "*@$FromDomain") {
        $newUpn = $oldUpn -replace "@$FromDomain$", "@$ToDomain"
    }

    # Build updated proxy addresses:
    #   - Primary (SMTP: uppercase) with old domain → rename to new domain
    #   - All smtp: aliases (any domain) → remove entirely
    #   - Non-SMTP types (X500:, SIP:, etc.) → keep unchanged
    $aliasesToRemove = @($User.ProxyAddresses | Where-Object { $_ -cmatch "^smtp:" })
    $newProxies = $User.ProxyAddresses | ForEach-Object {
        if ($_ -cmatch "^SMTP:.*@$FromDomain$") {
            $_ -replace "@$FromDomain$", "@$ToDomain"
        } elseif ($_ -cmatch "^smtp:") {
            # drop all SMTP aliases — no output
        } else {
            $_
        }
    }

    # Determine new mail value
    $newMail = if ($User.Mail -like "*@$FromDomain") {
        $User.Mail -replace "@$FromDomain$", "@$ToDomain"
    } else { $User.Mail }

    $upnChanged  = $newUpn  -ne $oldUpn
    $mailChanged = $newMail -ne $User.Mail

    if (-not $upnChanged -and -not $mailChanged) {
        $script:Skipped++
        return
    }

    $displayStr = "User: $($User.DisplayName) ($oldUpn)"

    if ($WhatIf) {
        $aliasInfo = if ($aliasesToRemove.Count -gt 0) { " + remove $($aliasesToRemove.Count) alias(es)" } else { "" }
        Write-Status "[WHATIF] Would change $displayStr  =>  $newUpn$aliasInfo" -Type Warning
        return
    }

    try {
        # proxyAddresses / email addresses are always managed by Exchange Online for mailbox
        # users (and by on-premises AD for synced accounts). Never send proxyAddresses via
        # Graph here — Update-ExchangeRecipient handles that for every object type.
        $body = @{}
        if ($upnChanged)  { $body['userPrincipalName'] = $newUpn }
        if ($mailChanged) { $body['mail']              = $newMail }

        if ($body.Count -gt 0) {
            Update-MgUser -UserId $User.Id -BodyParameter $body -ErrorAction Stop
        }

        Write-Status "Updated $displayStr  =>  $newUpn" -Type Success
        $script:ChangesMade++
    } catch {
        Write-Status "Failed to update $displayStr : $_" -Type Error
        $script:Errors++
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# REGION: Process — Entra ID groups
# ─────────────────────────────────────────────────────────────────────────────

function Update-EntraGroup {
    param(
        $Group,
        [string]$FromDomain,
        [string]$ToDomain,
        [switch]$WhatIf
    )

    $oldMail = $Group.Mail
    if (-not $oldMail -or $oldMail -notlike "*@$FromDomain") {
        $script:Skipped++
        return
    }

    $newMail    = $oldMail -replace "@$FromDomain$", "@$ToDomain"
    $newProxies = $Group.ProxyAddresses | ForEach-Object {
        if ($_ -cmatch "^SMTP:.*@$FromDomain$") {
            $_ -replace "@$FromDomain$", "@$ToDomain"
        } elseif ($_ -cmatch "^smtp:") {
            # drop all SMTP aliases — no output
        } else {
            $_
        }
    }
    $aliasesToRemove = @($Group.ProxyAddresses | Where-Object { $_ -cmatch "^smtp:" })

    $displayStr = "Group: $($Group.DisplayName) ($oldMail)"

    if ($WhatIf) {
        $aliasInfo = if ($aliasesToRemove.Count -gt 0) { " + remove $($aliasesToRemove.Count) alias(es)" } else { "" }
        Write-Status "[WHATIF] Would change $displayStr  =>  $newMail$aliasInfo" -Type Warning
        return
    }

    # Both 'mail' and 'proxyAddresses' are managed by Exchange Online for all mail-enabled
    # group types (Unified / M365 groups, mail-enabled security groups, distribution groups).
    # Attempting to patch either via Graph returns 400 or 403. Skip Graph entirely here —
    # Update-ExchangeRecipient handles every group type via Set-UnifiedGroup /
    # Set-DistributionGroup with the appropriate Exchange Online cmdlets.
    Write-Status "Skipping Graph update for $displayStr — email attributes managed by Exchange Online" -Type Info
    $script:Skipped++
    return
}

# ─────────────────────────────────────────────────────────────────────────────
# REGION: Process — Exchange Online recipients
# ─────────────────────────────────────────────────────────────────────────────

function Update-ExchangeRecipient {
    param(
        $Recipient,
        [string]$FromDomain,
        [string]$ToDomain,
        [switch]$WhatIf
    )

    $oldPrimary = $Recipient.PrimarySmtpAddress
    $identity   = $Recipient.Identity
    $type       = $Recipient.RecipientTypeDetails
    $displayStr = "$type : $($Recipient.DisplayName) ($oldPrimary)"

    $primaryChange = $oldPrimary -like "*@$FromDomain"
    $smtpAliasCount = @($Recipient.EmailAddresses | Where-Object { $_ -cmatch "^smtp:" }).Count

    if (-not $primaryChange -and $smtpAliasCount -eq 0) {
        $script:Skipped++
        return
    }

    # Build the complete new address list:
    #   SMTP: (primary, uppercase) — renamed to new domain (if applicable)
    #   smtp: (aliases, lowercase) — dropped entirely
    #   All other types (X500:, SIP:, SPO:, etc.) — kept unchanged
    $newPrimary   = if ($primaryChange) {
        $oldPrimary -replace "@$([regex]::Escape($FromDomain))$", "@$ToDomain"
    } else { $oldPrimary }

    # Keep only non-SMTP entries (X500:, SIP:, etc.) — we'll supply the primary ourselves
    $nonSmtpAddresses = @($Recipient.EmailAddresses | Where-Object { $_ -cnotmatch "^(SMTP|smtp):" })
    $newAddressList   = @("SMTP:$newPrimary") + $nonSmtpAddresses

    if ($WhatIf) {
        $aliasInfo = if ($smtpAliasCount -gt 0) { " + remove $smtpAliasCount alias(es)" } else { "" }
        Write-Status "[WHATIF] Would change $displayStr  =>  $newPrimary$aliasInfo" -Type Warning
        return
    }

    try {
        switch -Wildcard ($type) {
            { $_ -in 'SharedMailbox','UserMailbox' } {
                # Disable the email address policy so Exchange doesn't override our changes
                # or block the removal of smtp: aliases.
                Set-Mailbox -Identity $identity -EmailAddressPolicyEnabled $false -ErrorAction Stop
                # Set entire address list in one call: new primary + non-SMTP entries only.
                # This atomically renames the primary and removes all smtp: aliases.
                Set-Mailbox -Identity $identity -EmailAddresses $newAddressList -ErrorAction Stop
            }
            { $_ -in 'MailUniversalDistributionGroup','MailUniversalSecurityGroup' } {
                Set-DistributionGroup -Identity $identity `
                    -EmailAddresses $newAddressList `
                    -BypassSecurityGroupManagerCheck `
                    -ErrorAction Stop
            }
            "GroupMailbox" {
                # M365 Unified Groups — set primary; alias cleanup handled by Exchange internally
                Set-UnifiedGroup -Identity $identity `
                    -PrimarySmtpAddress $newPrimary `
                    -EmailAddresses $newAddressList `
                    -ErrorAction Stop
            }
            "MailContact" {
                Set-MailContact -Identity $identity `
                    -WindowsEmailAddress $newPrimary `
                    -ErrorAction Stop
            }
            default {
                Write-Status "Unhandled recipient type '$type' for: $($Recipient.DisplayName)" -Type Warning
                $script:Skipped++
                return
            }
        }

        Write-Status "Updated $displayStr  =>  $newPrimary" -Type Success
        $script:ChangesMade++
    } catch {
        Write-Status "Failed to update $displayStr : $_" -Type Error
        $script:Errors++
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# REGION: Summary
# ─────────────────────────────────────────────────────────────────────────────

function Show-Summary {
    param([string]$FromDomain, [string]$ToDomain, [bool]$WasWhatIf)

    $mode = if ($WasWhatIf) { " [WHATIF — no changes applied]" } else { "" }

    Write-Host ""
    Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Run summary$mode" -ForegroundColor Cyan
    Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Domain change : @$FromDomain  →  @$ToDomain" -ForegroundColor White
    Write-Host ("  Updated       : {0}" -f $script:ChangesMade) -ForegroundColor Green
    Write-Host ("  Skipped       : {0}" -f $script:Skipped)     -ForegroundColor Yellow
    Write-Host ("  Errors        : {0}" -f $script:Errors)       -ForegroundColor $(if ($script:Errors -gt 0) { 'Red' } else { 'Gray' })
    Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# REGION: Main
# ─────────────────────────────────────────────────────────────────────────────

Clear-Host
Write-Status "Entra ID — Bulk Domain Change Script" -Type Header
if ($WhatIf) {
    Write-Host "  *** RUNNING IN WHATIF MODE — NO CHANGES WILL BE MADE ***" -ForegroundColor Magenta
    Write-Host ""
}

try {
    # 1. Verify modules
    Assert-Modules

    # 2. Connect
    Connect-Services

    # 3. Domain selection
    $domains = Select-Domains
    $fromDomain = $domains.From
    $toDomain   = $domains.To

    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ("  Change FROM : @{0}" -f $fromDomain) -ForegroundColor White
    Write-Host ("  Change TO   : @{0}" -f $toDomain)   -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor DarkGray

    # 4. Confirmation
    if (-not $WhatIf) {
        Write-Host ""
        $confirmation = Read-Host "  Type YES to proceed (or anything else to abort)"
        if ($confirmation -ne 'YES') {
            Write-Status "Aborted by user." -Type Warning
            return
        }
    }

    # 5. Discover objects
    Write-Status "Discovering all objects — this may take a moment...$(if ($WhatIf) { ' [WHATIF]' })" -Type Header

    $entraUsers  = if (-not $SkipEntraID)        { Get-EntraUsersForDomain   -Domain $fromDomain } else { @() }
    $entraGroups = if (-not $SkipEntraID)        { Get-EntraGroupsForDomain  -Domain $fromDomain } else { @() }
    $exRecipients = if (-not $SkipExchangeOnline) { Get-ExchangeRecipientsForDomain -Domain $fromDomain } else { @() }

    $totalObjects = $entraUsers.Count + $entraGroups.Count + $exRecipients.Count

    Write-Host ""
    Write-Host "  Discovery complete:" -ForegroundColor Cyan
    Write-Host ("    Entra ID users  : {0}" -f $entraUsers.Count)   -ForegroundColor White
    Write-Host ("    Entra ID groups : {0}" -f $entraGroups.Count)  -ForegroundColor White
    Write-Host ("    EXO recipients  : {0}" -f $exRecipients.Count) -ForegroundColor White
    Write-Host ("    Total           : {0}" -f $totalObjects)        -ForegroundColor Yellow
    Write-Host ""

    if ($totalObjects -eq 0) {
        Write-Status "No objects found with domain '@$fromDomain'. Nothing to do." -Type Warning
        return
    }

    # 6. Process Entra ID users
    if ($entraUsers.Count -gt 0) {
        Write-Status "Processing Entra ID users ($($entraUsers.Count))...$(if ($WhatIf) { ' [WHATIF]' })" -Type Header
        $i = 0
        foreach ($user in $entraUsers) {
            $i++
            Show-Progress -Current $i -Total $entraUsers.Count `
                -Activity "Updating Entra ID users" -Status $user.UserPrincipalName

            Update-EntraUser -User $user -FromDomain $fromDomain -ToDomain $toDomain `
                -WhatIf:$WhatIf
        }
        Write-Progress -Activity "Updating Entra ID users" -Completed
    }

    # 7. Process Entra ID groups
    if ($entraGroups.Count -gt 0) {
        Write-Status "Processing Entra ID groups ($($entraGroups.Count))...$(if ($WhatIf) { ' [WHATIF]' })" -Type Header
        $i = 0
        foreach ($group in $entraGroups) {
            $i++
            Show-Progress -Current $i -Total $entraGroups.Count `
                -Activity "Updating Entra ID groups" -Status $group.DisplayName

            Update-EntraGroup -Group $group -FromDomain $fromDomain -ToDomain $toDomain `
                -WhatIf:$WhatIf
        }
        Write-Progress -Activity "Updating Entra ID groups" -Completed
    }

    # 8. Process Exchange Online recipients
    if ($exRecipients.Count -gt 0) {
        Write-Status "Processing Exchange Online recipients ($($exRecipients.Count))...$(if ($WhatIf) { ' [WHATIF]' })" -Type Header
        $i = 0
        foreach ($recip in $exRecipients) {
            $i++
            Show-Progress -Current $i -Total $exRecipients.Count `
                -Activity "Updating EXO recipients" -Status $recip.DisplayName

            Update-ExchangeRecipient -Recipient $recip -FromDomain $fromDomain `
                -ToDomain $toDomain -WhatIf:$WhatIf
        }
        Write-Progress -Activity "Updating EXO recipients" -Completed
    }

    # 9. Summary
    Show-Summary -FromDomain $fromDomain -ToDomain $toDomain -WasWhatIf $WhatIf.IsPresent

    # 10. Save log
    Save-Log -FromDomain $fromDomain -ToDomain $toDomain

} catch {
    Write-Status "Script terminated with an unhandled error: $_" -Type Error
    Write-Status $_.ScriptStackTrace -Type Error
    exit 1
}
