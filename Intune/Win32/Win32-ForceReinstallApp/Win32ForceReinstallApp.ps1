#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Forces reinstall of a Win32 app by removing registry keys and artifacts

.DESCRIPTION
    This script removes Intune Win32 app registry entries and artifacts to force a reinstall.
    It cleans up detection rules, installation status, and cached data for the specified app.
    
    Based on the excellent research and methods from:
    - Johan Arwidmark (Deployment Research): https://www.deploymentresearch.com/force-application-reinstall-in-microsoft-intune-win32-apps/
    - Rudy Ooms (Call4Cloud): https://call4cloud.nl/retry-failed-win32app-installation/
    
    This script implements the latest techniques including:
    - Proper GRS (Global Re-evaluation Schedule) hash discovery
    - User SID-specific registry cleanup
    - Support for both old and new log formats
    - Comprehensive file and folder cleanup

.PARAMETER AppId
    The Intune App ID (GUID) of the Win32 app to force reinstall
    Can be found in Intune portal URL when viewing the app

.EXAMPLE
    .\Win32ForceReinstallApp.ps1 -AppId "12345678-1234-1234-1234-123456789012"

.NOTES
    Author: Bareminimum Solutions (Enhanced with expert techniques)
    Requires: Administrator privileges
    Version: 2.0
    
    IMPORTANT: You MUST also clean up detection rule artifacts manually:
    - Delete files/folders that the detection rule checks
    - Remove registry keys used for detection
    - Uninstall MSI products if using MSI detection
    
    Credits:
    - GRS hash discovery method: Rudy Ooms (@Mister_MDM)
    - User SID approach: Johan Arwidmark
    - AppWorkload.log parsing: Community contributions
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")]
    [string]$AppId
)

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    
    # Ensure valid color names
    $validColors = @("Black", "DarkBlue", "DarkGreen", "DarkCyan", "DarkRed", "DarkMagenta", "DarkYellow", "Gray", "DarkGray", "Blue", "Green", "Cyan", "Red", "Magenta", "Yellow", "White")
    
    if ($Color -in $validColors) {
        Write-Host $Message -ForegroundColor $Color
    } else {
        Write-Host $Message -ForegroundColor White
    }
}

# Function to get GRS hash from Intune logs (based on Rudy Ooms' method)
function Get-AppGRSHash {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppId
    )
    
    Write-ColorOutput "Searching for GRS hash in Intune logs..." "Yellow"
    
    # Try AppWorkload.log first (newer method)
    $logPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
    $appWorkloadLogs = Get-ChildItem -Path $logPath -Filter "AppWorkload*.log" -File -ErrorAction SilentlyContinue | 
                       Sort-Object LastWriteTime -Descending | 
                       Select-Object -ExpandProperty FullName

    if ($appWorkloadLogs) {
        Write-ColorOutput "Checking AppWorkload logs..." "Gray"
        foreach ($logFile in $appWorkloadLogs) {
            $pattern = "\[Win32App\]\[GRSManager\] Found GRS value: .+ at key .+\\GRS\\(.+?)\\$AppId"
            $logMatches = Select-String -Path $logFile -Pattern $pattern -AllMatches
            
            if ($logMatches) {
                foreach ($match in $logMatches.Matches) {
                    if ($match.Groups[1].Value) {
                        $hash = $match.Groups[1].Value.Trim() -replace '\\\+', '+'
                        Write-ColorOutput "✓ Found GRS hash: $hash" "Green"
                        return $hash
                    }
                }
            }
        }
    }
    
    # Fallback to IntuneManagementExtension logs (older method)
    $intuneLogList = Get-ChildItem -Path $logPath -Filter "IntuneManagementExtension*.log" -File -ErrorAction SilentlyContinue | 
                     Sort-Object LastWriteTime -Descending | 
                     Select-Object -ExpandProperty FullName

    if ($intuneLogList) {
        Write-ColorOutput "Checking IntuneManagementExtension logs..." "Gray"
        foreach ($intuneLog in $intuneLogList) {
            $appMatch = Select-String -Path $intuneLog -Pattern "\[Win32App\]\[GRSManager\] App with id: $AppId is not expired." -Context 0, 1
            if ($appMatch) {
                foreach ($match in $appMatch) {
                    $LineNumber = $match.LineNumber
                    $Hash = Get-Content $intuneLog | Select-Object -Skip $LineNumber -First 1
                    if ($Hash) {
                        $hash = $Hash.Replace('+','\+')
                        Write-ColorOutput "✓ Found GRS hash: $hash" "Green"
                        return $hash
                    }
                }
            }
        }
    }

    Write-ColorOutput "- Unable to find GRS hash in logs" "Yellow"
    return $null
}

# Function to get all user SIDs from Win32Apps registry
function Get-UserSIDs {
    $path = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps"
    if (Test-Path $path) {
        return (Get-ChildItem $path -ErrorAction SilentlyContinue).PSChildName
    }
    return @()
}

# Function to remove registry key if it exists
function Remove-RegistryKeyIfExists {
    param(
        [string]$Path,
        [string]$Description
    )
    
    try {
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-ColorOutput "✓ Removed: $Description" "Green"
            return $true
        } else {
            Write-ColorOutput "- Not found: $Description" "Yellow"
            return $false
        }
    } catch {
        Write-ColorOutput "✗ Failed to remove: $Description - $($_.Exception.Message)" "Red"
        return $false
    }
}

# Function to remove file/folder if it exists
function Remove-PathIfExists {
    param(
        [string]$Path,
        [string]$Description
    )
    
    try {
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-ColorOutput "✓ Removed: $Description" "Green"
            return $true
        } else {
            Write-ColorOutput "- Not found: $Description" "Yellow"
            return $false
        }
    } catch {
        Write-ColorOutput "✗ Failed to remove: $Description - $($_.Exception.Message)" "Red"
        return $false
    }
}

# Main script execution
Write-ColorOutput "=" * 80 "Cyan"
Write-ColorOutput "Win32 App Force Reinstall Script" "Cyan"
Write-ColorOutput "=" * 80 "Cyan"
Write-ColorOutput "App ID: $AppId" "White"
Write-ColorOutput ""

# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-ColorOutput "✗ This script must be run as Administrator!" "Red"
    exit 1
}

$removedItems = 0
$totalItems = 0

Write-ColorOutput "Starting cleanup process..." "Yellow"
Write-ColorOutput ""

# Get all user SIDs from Win32Apps registry
$userSIDs = Get-UserSIDs
if ($userSIDs.Count -eq 0) {
    Write-ColorOutput "✗ No user SIDs found in Win32Apps registry" "Red"
    Write-ColorOutput "This could mean:" "White"
    Write-ColorOutput "- No Intune apps have been deployed to this device" "Gray"
    Write-ColorOutput "- The Intune Management Extension is not properly configured" "Gray"
    exit 1
}

Write-ColorOutput "Found $($userSIDs.Count) user SID(s) in Win32Apps registry" "White"

# Get GRS hash for the app
$grsHash = Get-AppGRSHash -AppId $AppId

# Clean up app-specific registry entries for each user
foreach ($userSID in $userSIDs) {
    Write-ColorOutput ""
    Write-ColorOutput "Processing user SID: $userSID" "Cyan"
    Write-ColorOutput "-" * 50 "Gray"
    
    $userPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\$userSID"
    
    # Remove app registry entries (using wildcard to catch all revisions)
    $appKeys = Get-ChildItem -Path $userPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "$AppId*" }
    
    if ($appKeys) {
        foreach ($appKey in $appKeys) {
            $totalItems++
            if (Remove-RegistryKeyIfExists -Path $appKey.PSPath -Description "App registry entry ($($appKey.PSChildName))") {
                $removedItems++
            }
        }
    } else {
        Write-ColorOutput "- No app registry entries found for this user" "Yellow"
    }
    
    # Remove GRS entries if hash was found
    if ($grsHash) {
        $grsPath = "$userPath\GRS\$grsHash"
        $totalItems++
        if (Remove-RegistryKeyIfExists -Path $grsPath -Description "GRS entry ($grsHash)") {
            $removedItems++
        }
        
        # Also check for app-specific GRS entries
        $grsAppPath = "$grsPath\$AppId"
        if (Test-Path $grsAppPath) {
            $totalItems++
            if (Remove-RegistryKeyIfExists -Path $grsAppPath -Description "GRS app-specific entry") {
                $removedItems++
            }
        }
    } else {
        Write-ColorOutput "- Skipping GRS cleanup (hash not found)" "Yellow"
    }
}

Write-ColorOutput ""
Write-ColorOutput "Cleaning up additional registry paths..." "Yellow"
Write-ColorOutput "-" * 50 "Gray"

# Additional registry cleanup paths (updated based on expert recommendations)
$additionalPaths = @(
    @{
        Path = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Reports\$AppId"
        Description = "SideCar policy reports"
    },
    @{
        Path = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Execution\$AppId"
        Description = "SideCar policy execution"
    }
)

foreach ($regPath in $additionalPaths) {
    $totalItems++
    if (Remove-RegistryKeyIfExists -Path $regPath.Path -Description $regPath.Description) {
        $removedItems++
    }
}

Write-ColorOutput ""
Write-ColorOutput "Cleaning up files and folders..." "Yellow"
Write-ColorOutput "-" * 50 "Gray"

# File/folder paths to clean up
$filePaths = @(
    @{
        Path = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension-$AppId.log"
        Description = "Intune Management Extension log for app"
    },
    @{
        Path = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\AppWorkload-$AppId.log"
        Description = "AppWorkload log for app"
    },
    @{
        Path = "$env:ProgramData\Microsoft\IntuneManagementExtension\Content\Incoming\$AppId"
        Description = "Intune incoming content folder"
    },
    @{
        Path = "$env:ProgramData\Microsoft\IntuneManagementExtension\Content\Staging\$AppId"
        Description = "Intune staging content folder"
    },
    @{
        Path = "$env:TEMP\IntuneManagementExtension\$AppId"
        Description = "Temp files for app"
    },
    @{
        Path = "$env:LOCALAPPDATA\Temp\IntuneManagementExtension\$AppId"
        Description = "Local temp files for app"
    }
)

foreach ($filePath in $filePaths) {
    $totalItems++
    if (Remove-PathIfExists -Path $filePath.Path -Description $filePath.Description) {
        $removedItems++
    }
}

Write-ColorOutput ""
Write-ColorOutput "Additional cleanup operations..." "Yellow"
Write-ColorOutput "-" * 50 "Gray"

# Stop and restart Intune Management Extension service
try {
    $totalItems++
    $service = Get-Service -Name "IntuneManagementExtension" -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq "Running") {
            Stop-Service -Name "IntuneManagementExtension" -Force -ErrorAction Stop
            Start-Sleep -Seconds 3
            Start-Service -Name "IntuneManagementExtension" -ErrorAction Stop
            Write-ColorOutput "✓ Restarted Intune Management Extension service" "Green"
            $removedItems++
        } else {
            Start-Service -Name "IntuneManagementExtension" -ErrorAction Stop
            Write-ColorOutput "✓ Started Intune Management Extension service" "Green"
            $removedItems++
        }
    } else {
        Write-ColorOutput "- Intune Management Extension service not found" "Yellow"
    }
} catch {
    Write-ColorOutput "✗ Failed to restart Intune Management Extension service - $($_.Exception.Message)" "Red"
}

# Clear Windows Update cache related to the app (if applicable)
try {
    $totalItems++
    $wuCachePath = "$env:WINDIR\SoftwareDistribution\Download\*"
    if (Test-Path $wuCachePath) {
        # Stop Windows Update service temporarily
        Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        
        # Clear download cache (be careful - this affects all updates)
        # Remove-Item -Path $wuCachePath -Recurse -Force -ErrorAction SilentlyContinue
        
        # Restart Windows Update service
        Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
        Write-ColorOutput "✓ Windows Update service cycled (cache preserved)" "Green"
        $removedItems++
    }
} catch {
    Write-ColorOutput "- Windows Update service cycling skipped" "Yellow"
}

Write-ColorOutput ""
Write-ColorOutput "=" * 80 "Cyan"
Write-ColorOutput "Cleanup Summary" "Cyan"
Write-ColorOutput "=" * 80 "Cyan"
Write-ColorOutput "Items processed: $totalItems" "White"
Write-ColorOutput "Items removed: $removedItems" "Green"
Write-ColorOutput "Items not found: $($totalItems - $removedItems)" "Yellow"
Write-ColorOutput ""

if ($removedItems -gt 0) {
    Write-ColorOutput "✓ Cleanup completed successfully!" "Green"
    Write-ColorOutput ""
    Write-ColorOutput "IMPORTANT: Detection Rule Cleanup Required" "Red"
    Write-ColorOutput "=" * 60 "Red"
    Write-ColorOutput "The registry cleanup is complete, but you MUST also:" "White"
    Write-ColorOutput ""
    Write-ColorOutput "1. Remove or modify the detection rule artifacts:" "Yellow"
    Write-ColorOutput "   - If using file detection: Delete the target file/folder" "Gray"
    Write-ColorOutput "   - If using registry detection: Delete the target registry key" "Gray"
    Write-ColorOutput "   - If using MSI detection: Uninstall the MSI product" "Gray"
    Write-ColorOutput "   - If using script detection: Ensure script returns failure" "Gray"
    Write-ColorOutput ""
    Write-ColorOutput "2. Wait 5-10 minutes for Intune sync" "Yellow"
    Write-ColorOutput "3. Force sync from:" "Yellow"
    Write-ColorOutput "   - Company Portal app, or" "Gray"
    Write-ColorOutput "   - Settings > Accounts > Access work or school" "Gray"
    Write-ColorOutput "4. Check for the app in Company Portal" "Yellow"
    Write-ColorOutput ""
    Write-ColorOutput "Note: If detection rules still show 'installed', the app" "White"
    Write-ColorOutput "      will not reinstall even after this cleanup!" "White"
} else {
    Write-ColorOutput "! No items were removed - app may already be clean" "Yellow"
    Write-ColorOutput "This could mean:" "White"
    Write-ColorOutput "- App was never installed on this device" "Gray"
    Write-ColorOutput "- App has already been cleaned up" "Gray"
    Write-ColorOutput "- App ID is incorrect" "Gray"
}

Write-ColorOutput ""
Write-ColorOutput "Script completed at $(Get-Date)" "Gray"