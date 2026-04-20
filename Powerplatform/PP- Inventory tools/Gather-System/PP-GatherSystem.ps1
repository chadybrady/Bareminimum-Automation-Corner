<#
.SYNOPSIS
    Combined Power Platform Export Script
.DESCRIPTION
    Exports Power Apps and Power Automate flows with their connectors to CSV, by environment.
    Prompts user for environment target. Shows clear status updates for user experience.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string]$FilePath = "./PowerPlatformExport.csv"
)

$ErrorActionPreference = "Stop"

function Write-Colored {
    param([string]$M, [string]$C = "White")
    Write-Host $M -ForegroundColor $C
}

function Install-RequiredModules {
    $modules = @("Microsoft.PowerApps.Administration.PowerShell", "Microsoft.Entra")
    foreach ($module in $modules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Colored "Installing $module ..." "Cyan"
            Install-Module -Name $module -AllowClobber -Force -Scope CurrentUser
        }
    }
}

function Connect-Services {
    Write-Colored "Connecting to Power Platform..." "Green"
    Add-PowerAppsAccount
    Write-Colored "Connecting to Entra (for user lookup)..." "Green"
    Connect-Entra -Scopes 'User.Read.All'
}

function Get-UserDetails {
    param([string]$UserId)
    if (-not $UserId) { return @{DisplayName = "System/Unknown"; UserPrincipalName = "N/A"} }
    try {
        $user = Get-EntraUser -UserId $UserId -Property Id,DisplayName,UserPrincipalName -ErrorAction Stop
        return @{DisplayName = $user.DisplayName; UserPrincipalName = $user.UserPrincipalName}
    } catch {
        try {
            $sp = Get-EntraServicePrincipal -ServicePrincipalId $UserId -Property Id,DisplayName,AppId -ErrorAction Stop
            return @{DisplayName = "$($sp.DisplayName) (Service Principal)"; UserPrincipalName = $sp.AppId}
        } catch {
            return @{DisplayName = "Unknown Creator"; UserPrincipalName = $UserId}
        }
    }
}

function Disconnect-Services {
    Write-Colored "Disconnecting from Entra..." "Yellow"
    Disconnect-Entra
    Write-Colored "Disconnecting from Power Apps..." "Yellow"
    Remove-PowerAppsAccount
}

try {
    Write-Colored "🟩 Starting Power Platform Export Script..." "Green"
    Install-RequiredModules
    Connect-Services

    # Gather all environments
    Write-Colored "Retrieving all available Power Platform environments..." "Cyan"
    $envObjs = Get-AdminPowerAppEnvironment
    if (-not $envObjs -or $envObjs.Count -eq 0) {
        Write-Colored "No environments found. Exiting." "Red"
        return
    }
    $envNames = $envObjs.DisplayName
    Write-Colored "Available environments:" "Cyan"
    $displayList = @()
    for ($i=0; $i -lt $envNames.Count; $i++) {
        Write-Host (" [{0}] {1}" -f ($i+1), $envNames[$i]) -ForegroundColor White
        $displayList += $envObjs[$i]
    }
    Write-Host (" [A] ALL ENVIRONMENTS") -ForegroundColor Yellow
    $validChoices = @(1..$envNames.Count | ForEach-Object { $_.ToString() }) + 'A'

    do {
        $choice = Read-Host "Enter the number of the environment to export (or 'A' for all)"
    } while (-not ($validChoices -contains $choice.ToUpper()))

    $selected = @()
    if ($choice.ToUpper() -eq 'A') {
        $selected = $envObjs.EnvironmentName
    } else {
        $selected = $envObjs[([int]$choice)-1].EnvironmentName
    }

    # Legacy-friendly environment name display
    $envDisplayArr = @()
    foreach ($sel in $selected) {
        foreach ($envObj in $envObjs) {
            if ($envObj.EnvironmentName -eq $sel) {
                $envDisplayArr += $envObj.DisplayName
            }
        }
    }
    $envDisplay = $envDisplayArr -join ', '
    Write-Colored "Exporting from: $envDisplay" "Yellow"

    $ExportRows = @()
    foreach ($env in $selected) {
        Write-Colored "Retrieving Power Apps from environment: $env ..." "Cyan"
        try {
            $Apps = Get-AdminPowerApp -EnvironmentName $env
        } catch {
            Write-Colored "Error getting apps for $env $($_.Exception.Message)" "Red"; continue
        }
        if (-not $Apps -or !$Apps.Count -or $Apps.Count -eq 0) {
            Write-Colored "No apps found in $env" "Yellow"; continue
        }
        $Count = 0
        $TotalApps = $Apps.Count
        foreach ($App in $Apps) {
            $Count++
            if ($TotalApps -gt 0) {
                Write-Progress -Activity "Processing Power Apps" -Status "App $Count of $TotalApps $($App.DisplayName)" -PercentComplete (($Count / $TotalApps) * 100)
            }
            $ConnRefs = $null
            try { $ConnRefs = $App.Internal.properties.connectionReferences } catch { $ConnRefs = $null }

            if ($App.Owner -and $App.Owner.Id) {
                $OwnerId = $App.Owner.Id
            } else {
                $OwnerId = $null
            }

            $Owner = Get-UserDetails -UserId $OwnerId

            if ($ConnRefs -and $ConnRefs.PSObject.Properties.Count -gt 0) {
                foreach ($Conn in $ConnRefs.PSObject.Properties) {
                    $ConnInfo = $Conn.Value
                    $ExportRows += [PSCustomObject]@{
                        Type            = "PowerApp"
                        Environment     = $env
                        ItemId          = $App.AppName
                        DisplayName     = $App.DisplayName
                        OwnerId         = $OwnerId
                        OwnerDisplayName= $Owner.DisplayName
                        OwnerPrincipal  = $Owner.UserPrincipalName
                        CreatedTime     = $App.CreatedTime
                        LastModifiedTime= $App.LastModifiedTime
                        ConnectorKey    = $Conn.Name
                        ConnectorType   = $ConnInfo.ConnectorName
                        ConnectorDisplay= $ConnInfo.DisplayName
                    }
                }
            } else {
                $ExportRows += [PSCustomObject]@{
                    Type            = "PowerApp"
                    Environment     = $env
                    ItemId          = $App.AppName
                    DisplayName     = $App.DisplayName
                    OwnerId         = $OwnerId
                    OwnerDisplayName= $Owner.DisplayName
                    OwnerPrincipal  = $Owner.UserPrincipalName
                    CreatedTime     = $App.CreatedTime
                    LastModifiedTime= $App.LastModifiedTime
                    ConnectorKey    = ""
                    ConnectorType   = ""
                    ConnectorDisplay= ""
                }
            }

            if ($TotalApps -gt 50 -and $Count % 10 -eq 0) {
                Start-Sleep -Seconds 1
            }
        }

        Write-Colored "Retrieving flows from environment: $env ..." "Cyan"
        try {
            $Flows = Get-AdminFlow -EnvironmentName $env
        } catch {
            Write-Colored "Error getting flows for $env $($_.Exception.Message)" "Red"; continue
        }
        if (-not $Flows -or !$Flows.Count -or $Flows.Count -eq 0) {
            Write-Colored "No flows found in $env" "Yellow"; continue
        }
        $Count = 0
        $TotalFlows = $Flows.Count
        foreach ($Flow in $Flows) {
            $Count++
            if ($TotalFlows -gt 0) {
                Write-Progress -Activity "Processing Flows" -Status "Flow $Count of $TotalFlows $($Flow.DisplayName)" -PercentComplete (($Count / $TotalFlows) * 100)
            }
            $Connectors = $null
            try {
                if ($Flow.Internal.properties.connectionReferences) {
                    $Connectors = $Flow.Internal.properties.connectionReferences
                } else {
                    $FlowInfo = Get-AdminFlow -FlowName $Flow.FlowName -EnvironmentName $Flow.EnvironmentName
                    $Connectors = $FlowInfo.Internal.properties.connectionReferences
                }
            } catch {
                $Connectors = $null
            }

            $UserId = $Flow.CreatedBy.UserID
            $User = Get-UserDetails -UserId $UserId

            if ($Connectors -and $Connectors.PSObject.Properties.Count -gt 0) {
                foreach ($Connector in $Connectors.PSObject.Properties) {
                    $ExportRows += [PSCustomObject]@{
                        Type            = "PowerAutomate"
                        Environment     = $env
                        ItemId          = $Flow.FlowName
                        DisplayName     = $Flow.DisplayName
                        OwnerId         = $UserId
                        OwnerDisplayName= $User.DisplayName
                        OwnerPrincipal  = $User.UserPrincipalName
                        CreatedTime     = $Flow.CreatedTime
                        LastModifiedTime= $Flow.LastModifiedTime
                        ConnectorKey    = $Connector.Name
                        ConnectorType   = $Connector.Value.ConnectorName
                        ConnectorDisplay= $Connector.Value.DisplayName
                    }
                }
            } else {
                $ExportRows += [PSCustomObject]@{
                    Type            = "PowerAutomate"
                    Environment     = $env
                    ItemId          = $Flow.FlowName
                    DisplayName     = $Flow.DisplayName
                    OwnerId         = $UserId
                    OwnerDisplayName= $User.DisplayName
                    OwnerPrincipal  = $User.UserPrincipalName
                    CreatedTime     = $Flow.CreatedTime
                    LastModifiedTime= $Flow.LastModifiedTime
                    ConnectorKey    = ""
                    ConnectorType   = ""
                    ConnectorDisplay= ""
                }
            }

            if ($TotalFlows -gt 50 -and $Count % 10 -eq 0) {
                Start-Sleep -Seconds 1
            }
        }
    }

    Write-Colored "Exporting $($ExportRows.Count) rows to $FilePath..." "Cyan"
    $ExportRows | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
    Write-Colored "Export completed: $FilePath" "Green"

} catch {
    Write-Colored "Script failed: $($_.Exception.Message)" "Red"
} finally {
    Disconnect-Services
    Write-Colored "Script completed." "Green"
}