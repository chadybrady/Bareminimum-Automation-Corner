# Bulk rename existing Android devices to Android-SERIAL format
# This script queries devices by Azure AD group membership (device objects in groups)
# Install-Module Microsoft.Graph.Beta -Force
# Connect-MgBetaGraph -Scopes "DeviceManagementManagedDevices.PrivilegedOperations.All", "Group.Read.All", "GroupMember.Read.All", "Device.Read.All"

# Configuration - Define Azure AD groups that contain device objects
$groupConfigs = @(
    @{ GroupId = ""; Description = "" }
    # Add more group IDs as needed
)

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow

$totalSuccessful = 0
$totalFailed = 0
$totalSkipped = 0
$allResults = @()

# Function to process individual devices
function Process-Device {
    param(
        [string]$DeviceId,
        [string]$SerialNumber, 
        [string]$CurrentName,
        [string]$OperatingSystem,
        [string]$Source,
        [int]$Counter,
        [int]$Total
    )
    
    Write-Host "`nProcessing device $Counter/$Total from $Source" -ForegroundColor White
    Write-Host "  Current Name: $CurrentName" -ForegroundColor Gray
    Write-Host "  Serial: $SerialNumber" -ForegroundColor Gray
    Write-Host "  OS: $OperatingSystem" -ForegroundColor Gray
    
    $result = [PSCustomObject]@{
        Source = $Source
        DeviceId = $DeviceId
        CurrentName = $CurrentName
        SerialNumber = $SerialNumber
        NewName = ""
        Status = ""
        Error = ""
    }
    
    # Validate required fields
    if ([string]::IsNullOrWhiteSpace($DeviceId)) {
        Write-Host "  ⚠️  Skipping - No Device ID" -ForegroundColor Yellow
        $result.Status = "Skipped"
        $result.Error = "No Device ID"
        $script:totalSkipped++
        return $result
    }
    
    # Validate serial number is available
    if ([string]::IsNullOrWhiteSpace($SerialNumber)) {
        Write-Host "  ⚠️  Skipping - No serial number" -ForegroundColor Yellow
        $result.Status = "Skipped"
        $result.Error = "No serial number"
        $script:totalSkipped++
        return $result
    }
    
    # Create new name: Android-SERIAL (Change $newName to your desired format)
    $newName = "Android-$SerialNumber"
    $result.NewName = $newName
    
    Write-Host "  New Name: $newName" -ForegroundColor Cyan
    
    # Check if already correctly named
    if ($CurrentName -eq $newName) {
        Write-Host "  ✓ Already correctly named - skipping" -ForegroundColor Green
        $result.Status = "Already Correct"
        return $result
    }
    
    # Attempt to rename
    try {
        Set-MgBetaDeviceManagementManagedDeviceName -ManagedDeviceId $DeviceId -DeviceName $newName
        Write-Host "  ✅ Successfully renamed: $CurrentName → $newName" -ForegroundColor Green
        $result.Status = "Success"
        $script:totalSuccessful++
    }
    catch {
        Write-Host "  ❌ Failed to rename: $($_.Exception.Message)" -ForegroundColor Red
        $result.Status = "Failed"
        $result.Error = $_.Exception.Message
        $script:totalFailed++
    }
    
    # Rate limiting
    Start-Sleep -Milliseconds 500
    
    return $result
}

# Process devices from Azure AD group membership (device objects)
foreach ($groupConfig in $groupConfigs) {
    $groupId = $groupConfig.GroupId
    $description = $groupConfig.Description
    
    Write-Host "`n=== Processing: $description ===" -ForegroundColor Cyan
    Write-Host "Group ID: $groupId" -ForegroundColor Gray
    
    # Get the group by ID
    try {
        $targetGroup = Get-MgBetaGroup -GroupId $groupId
        Write-Host "Found group: $($targetGroup.DisplayName)" -ForegroundColor Green
    } catch {
        Write-Host "Group not found: $groupId" -ForegroundColor Yellow
        continue
    }
    
    # Get all members of the group (devices)
    Write-Host "Getting group members..." -ForegroundColor Gray
    $groupMembers = Get-MgBetaGroupMember -GroupId $groupId -All
    
    # Filter for device objects
    $deviceMembers = $groupMembers | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.device' }
    Write-Host "Found $($deviceMembers.Count) devices in group" -ForegroundColor Green
    
    if ($deviceMembers.Count -eq 0) {
        Write-Host "No devices found in group" -ForegroundColor Yellow
        continue
    }
    
    # Get Android devices from Intune by matching Entra ID devices
    Write-Host "Getting Android devices from Intune..." -ForegroundColor Gray
    $allAndroidDevices = Get-MgBetaDeviceManagementManagedDevice -Filter "operatingSystem eq 'Android'" -All
    
    $groupDevices = @()
    foreach ($deviceMember in $deviceMembers) {
        $objectId = $deviceMember.Id
        $displayName = $deviceMember.AdditionalProperties.displayName

        # Fetch the full device object from Entra ID to get the Device ID
        try {
            $aadDevice = Get-MgBetaDevice -DeviceId $objectId
            $entraDeviceId = $aadDevice.DeviceId
            Write-Host "  Device: $displayName" -ForegroundColor Gray
            Write-Host "    Object ID: $objectId" -ForegroundColor Gray
            Write-Host "    Device ID: $entraDeviceId" -ForegroundColor Gray
        } catch {
            Write-Host "  Error fetching device object for ${objectId}: $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        if ([string]::IsNullOrWhiteSpace($entraDeviceId)) {
            Write-Host "  Warning: No Device ID found after lookup" -ForegroundColor Yellow
            continue
        }

        # Now match in Intune
        try {
            $intuneDevice = $allAndroidDevices | Where-Object { $_.AzureADDeviceId -eq $entraDeviceId }
            if ($intuneDevice) {
                Write-Host "  Found Android device: $($intuneDevice.DeviceName)" -ForegroundColor Green
                $groupDevices += $intuneDevice
            } else {
                Write-Host "  Device not found or not Android: $displayName" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  Error accessing device ${entraDeviceId}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    # Remove duplicates
    $uniqueDevices = $groupDevices | Sort-Object Id -Unique
    Write-Host "Found $($uniqueDevices.Count) unique Android devices for this group" -ForegroundColor Green
    
    if ($uniqueDevices.Count -eq 0) {
        Write-Host "No Android devices found for this group" -ForegroundColor Yellow
        continue
    }
    
    # Process each device
    $counter = 0
    foreach ($device in $uniqueDevices) {
        $counter++
        Write-Progress -Activity "Processing $description" -Status "$counter of $($uniqueDevices.Count)" -PercentComplete (($counter / $uniqueDevices.Count) * 100)
        
        $result = Process-Device -DeviceId $device.Id -SerialNumber $device.SerialNumber -CurrentName $device.DeviceName -OperatingSystem $device.OperatingSystem -Source $description -Counter $counter -Total $uniqueDevices.Count
        $allResults += $result
    }
}

# Summary Report
Write-Host "`n" + "="*80 -ForegroundColor Cyan
Write-Host "RENAME SUMMARY REPORT" -ForegroundColor Cyan  
Write-Host "="*80 -ForegroundColor Cyan
Write-Host "Successfully renamed: $totalSuccessful" -ForegroundColor Green
Write-Host "Failed renames: $totalFailed" -ForegroundColor Red
Write-Host "Skipped devices: $totalSkipped" -ForegroundColor Yellow
Write-Host "Total processed: $($allResults.Count)" -ForegroundColor White

# Export results
$timestamp = Get-Date -Format "yyyyMMdd-HHmm"
$resultsFile = "AndroidDeviceRename_Results_$timestamp.csv"
$allResults | Export-Csv -Path $resultsFile -NoTypeInformation
Write-Host "`n📄 Full results exported to: $resultsFile" -ForegroundColor Green

# Show sample of renamed devices
$successfulRenames = $allResults | Where-Object { $_.Status -eq "Success" }
if ($successfulRenames.Count -gt 0) {
    Write-Host "`nSample of successfully renamed devices:" -ForegroundColor Green
    $successfulRenames | Select-Object -First 10 | ForEach-Object {
        Write-Host "  $($_.CurrentName) → $($_.NewName)" -ForegroundColor Gray
    }
    
    if ($successfulRenames.Count -gt 10) {
        Write-Host "  ... and $($successfulRenames.Count - 10) more (see CSV for full list)" -ForegroundColor Gray
    }
}

# Show failed renames if any
$failedRenames = $allResults | Where-Object { $_.Status -eq "Failed" }
if ($failedRenames.Count -gt 0) {
    Write-Host "`nFailed renames - top error reasons:" -ForegroundColor Red
    $failedRenames | Group-Object Error | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) devices" -ForegroundColor Red
    }
}

Write-Host "`n✅ Bulk rename operation completed!" -ForegroundColor Green
Write-Host "Device names will sync to physical devices on their next check-in with Intune." -ForegroundColor Gray

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Update your enrollment profiles to use {{DEVICETYPE}}-{{SERIAL}} template" -ForegroundColor Gray
Write-Host "2. New Android enrollments will automatically use 'Android-SerialNumber' format" -ForegroundColor Gray
Write-Host "3. This matches the iOS naming convention" -ForegroundColor Gray

Disconnect-MgBetaGraph