Write-Host "# Created By: Tim Hjort, 2026"
Write-Host "# This script creates a Microsoft 365 group through the Entra module."
Write-Host "# It can disable welcome emails and set SharePoint site provisioning to on-demand."
Write-Host ""

$requiredModules = @(
    'Microsoft.Entra'
)

foreach ($module in $requiredModules) {
    if (-not (Get-Module -Name $module -ListAvailable)) {
        Write-Host "Installing module: $module"
        Install-Module -Name $module -Force -Scope CurrentUser
    } else {
        Write-Host "Module $module is already installed."
    }
}

Import-Module Microsoft.Entra

function Read-YesNo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [bool]$DefaultYes = $true
    )

    $suffix = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }

    while ($true) {
        $response = (Read-Host "$Prompt $suffix").Trim()
        if ([string]::IsNullOrWhiteSpace($response)) {
            return $DefaultYes
        }

        switch ($response.ToLowerInvariant()) {
            'y' { return $true }
            'yes' { return $true }
            'n' { return $false }
            'no' { return $false }
            default { Write-Host "Please answer y or n." -ForegroundColor Yellow }
        }
    }
}

function Read-RequiredValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    while ($true) {
        $value = (Read-Host $Prompt).Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }

        Write-Host "Value cannot be empty." -ForegroundColor Yellow
    }
}

function Read-ValidMailNickname {
    while ($true) {
        $nickname = (Read-Host 'Enter mail nickname (alias, no spaces)').Trim()
        if ([string]::IsNullOrWhiteSpace($nickname)) {
            Write-Host "Mail nickname cannot be empty." -ForegroundColor Yellow
            continue
        }

        # Graph restriction: disallow these chars ->  @ () \ [] " ; : <> , SPACE
        if ($nickname -match '[ @\(\)\\\[\]";:<>\,]') {
            Write-Host 'Mail nickname contains invalid characters. Avoid: @ () \ [] " ; : <> , and spaces.' -ForegroundColor Yellow
            continue
        }

        return $nickname
    }
}

Connect-Entra -Scopes @('Group.ReadWrite.All')
Write-Host 'Connected to Microsoft Entra.' -ForegroundColor Green
Write-Host ''

$displayName = Read-RequiredValue -Prompt 'Enter group display name'
$mailNickname = Read-ValidMailNickname
$description = (Read-Host 'Enter group description (optional)').Trim()

$isPrivate = Read-YesNo -Prompt 'Should the group be Private?' -DefaultYes $true
$disableWelcomeEmail = Read-YesNo -Prompt 'Disable welcome emails for new members?' -DefaultYes $true
$provisionSiteOnDemand = Read-YesNo -Prompt 'Enable SharePoint ProvisionSiteOnDemand (avoid automatic site creation now)?' -DefaultYes $true
$hideGroupInOutlook = Read-YesNo -Prompt 'Hide the group in Outlook?' -DefaultYes $false
$subscribeNewMembers = Read-YesNo -Prompt 'Auto-subscribe new members to conversations?' -DefaultYes $false

$resourceBehaviorOptions = @()
if ($disableWelcomeEmail) { $resourceBehaviorOptions += 'WelcomeEmailDisabled' }
if ($provisionSiteOnDemand) { $resourceBehaviorOptions += 'ProvisionSiteOnDemand' }
if ($hideGroupInOutlook) { $resourceBehaviorOptions += 'HideGroupInOutlook' }
if ($subscribeNewMembers) { $resourceBehaviorOptions += 'SubscribeNewGroupMembers' }

$groupParams = @{
    DisplayName = $displayName
    MailEnabled = $true
    MailNickname = $mailNickname
    SecurityEnabled = $false
    GroupTypes = @('Unified')
    Visibility = if ($isPrivate) { 'Private' } else { 'Public' }
}

if (-not [string]::IsNullOrWhiteSpace($description)) {
    $groupParams.Description = $description
}

if ($resourceBehaviorOptions.Count -gt 0) {
    $groupParams.ResourceBehaviorOptions = $resourceBehaviorOptions
}

Write-Host ''
Write-Host 'Creating Microsoft 365 group...' -ForegroundColor Cyan
$newGroup = New-EntraGroup @groupParams

Write-Host ''
Write-Host 'Group created successfully.' -ForegroundColor Green
Write-Host "Group ID: $($newGroup.Id)"
Write-Host "Display Name: $($newGroup.DisplayName)"
Write-Host "Mail Nickname: $($newGroup.MailNickname)"
Write-Host "Visibility: $($groupParams.Visibility)"
Write-Host "ResourceBehaviorOptions: $($resourceBehaviorOptions -join ', ')"
Write-Host ''
Write-Host 'Teams is not provisioned by this script.' -ForegroundColor Yellow
if ($provisionSiteOnDemand) {
    Write-Host 'SharePoint site provisioning is set to on-demand.' -ForegroundColor Yellow
}
Write-Host 'Done.'

