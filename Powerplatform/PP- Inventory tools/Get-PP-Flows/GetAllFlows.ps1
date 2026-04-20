<#
.SYNOPSIS
    Export Power Automate flows and their connectors to a CSV, by environment.
.DESCRIPTION
    Prompts user for environment target. Shows clear status updates for user experience.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string]$FilePath = "./FlowsExport.csv"
)

$ErrorActionPreference = "Stop"

# Function for colored output
function Write-Colored {
    param([string]$M, [string]$C = "White")
    Write-Host $M -ForegroundColor $C
}

# Function to install required modules
function Install-RequiredModules {
    $modules = @("Microsoft.PowerApps.Administration.PowerShell", "Microsoft.Entra")
    foreach ($module in $modules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Colored "Installing $module ..." "Cyan"
            Install-Module -Name $module -AllowClobber -Force -Scope CurrentUser
        }
    }
}

# Function to connect services
function Connect-Services {
    Write-Colored "Connecting to Power Platform..." "Green"
    Add-PowerAppsAccount
    Write-Colored "Connecting to Microsoft Entra..." "Green"
    Connect-Entra -Scopes 'User.Read.All'
}

# Function to get user details
function Get-UserDetails {
    param([string]$UserId)
    if (-not $UserId) {
        return @{DisplayName = "System/Unknown"; UserPrincipalName = "N/A"}
    }
    try {
        $user = Get-EntraUser -UserId $UserId -Property Id,DisplayName,UserPrincipalName -ErrorAction Stop
        return @{DisplayName = $user.DisplayName; UserPrincipalName = $user.UserPrincipalName}
    }
    catch {
        try {
            $sp = Get-EntraServicePrincipal -ServicePrincipalId $UserId -Property Id,DisplayName,AppId -ErrorAction Stop
            return @{DisplayName = "$($sp.DisplayName) (Service Principal)"; UserPrincipalName = $sp.AppId}
        }
        catch {
            return @{DisplayName = "Unknown Creator"; UserPrincipalName = $UserId}
        }
    }
}

# Function to disconnect services
function Disconnect-Services {
    Write-Colored "Disconnecting from Entra..." "Yellow"
    Disconnect-Entra
    Write-Colored "Disconnecting from PowerApps..." "Yellow"
    Remove-PowerAppsAccount
}

# Main execution
try {
    Write-Colored "🟩 Starting Power Automate Flows Export Script..." "Green"
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
    Write-Colored "Exporting flows from: $envDisplay" "Yellow"

    $ConnectorExport = @()
    foreach ($env in $selected) {
        Write-Colored "Retrieving flows from environment: $env ..." "Cyan"
        try {
            $Flows = Get-AdminFlow -EnvironmentName $env
        } catch {
            Write-Colored "Error getting flows for $env $($_.Exception.Message)" "Red"; continue
        }
        # --- FINAL DIVISION-BY-ZERO FIX ---
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
            
            # Try to get connectors (from initial or detailed info)
            try {
                $Connectors = $null
                if ($Flow.Internal.properties.connectionReferences) {
                    $Connectors = $Flow.Internal.properties.connectionReferences
                } else {
                    $FlowInfo = Get-AdminFlow -FlowName $Flow.FlowName -EnvironmentName $Flow.EnvironmentName
                    $Connectors = $FlowInfo.Internal.properties.connectionReferences
                }
            }
            catch {
                $Connectors = $null
            }

            # Get user info
            $UserId = $Flow.CreatedBy.UserID
            $User = Get-UserDetails -UserId $UserId

            if ($Connectors -and $Connectors.PSObject.Properties.Count -gt 0) {
                foreach ($Connector in $Connectors.PSObject.Properties) {
                    $ConnectorExport += [PSCustomObject]@{
                        FlowID            = $Flow.FlowName
                        FlowName          = $Flow.DisplayName
                        Enabled           = $Flow.Enabled
                        Environment       = $Flow.EnvironmentName
                        UserID            = $UserId
                        UserDisplayName   = $User.DisplayName
                        UserPrincipalName = $User.UserPrincipalName
                        ConnectorName     = $Connector.Name
                        ConnectorType     = $Connector.Value.ConnectorName
                        ConnectorDisplay  = $Connector.Value.DisplayName
                    }
                }
            } else {
                # Export flows with no connectors for completeness
                $ConnectorExport += [PSCustomObject]@{
                    FlowID            = $Flow.FlowName
                    FlowName          = $Flow.DisplayName
                    Enabled           = $Flow.Enabled
                    Environment       = $Flow.EnvironmentName
                    UserID            = $UserId
                    UserDisplayName   = $User.DisplayName
                    UserPrincipalName = $User.UserPrincipalName
                    ConnectorName     = ""
                    ConnectorType     = ""
                    ConnectorDisplay  = ""
                }
            }

            if ($TotalFlows -gt 50 -and $Count % 10 -eq 0) {
                Start-Sleep -Seconds 1
            }
        }
    }

    # Export to CSV
    $ConnectorExport | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
    Write-Colored "Export completed: $FilePath" "Green"
    Write-Colored "Total rows exported: $($ConnectorExport.Count)" "Cyan"
}
catch {
    Write-Colored "Script failed: $($_.Exception.Message)" "Red"
}
finally {
    Disconnect-Services
    Write-Colored "Script completed." "Green"
}
