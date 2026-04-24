#Requires -Version 7.0

<#
.SYNOPSIS
  Downloads, packages (if needed), and uploads a Win32 app update to Intune for
  a specific SharePoint list item that has been approved.

.DESCRIPTION
  Intended to run as an Azure Automation Runbook (PS7 runtime), triggered by
  Power Automate when a Win32-App-Updates list item transitions to "Approved".
  Authenticates via System-Assigned Managed Identity.

  Winget path  : Fetches the installer URL from the official winget-pkgs manifest,
                 downloads the installer, wraps it with IntuneWinAppUtil.exe
                 (pre-staged in Blob Storage), and uploads the result to Intune.

  Manual path  : Downloads the pre-packaged .intunewin from the Blob Storage SAS URL
                 stored in ManualPackageUrl and uploads it to Intune directly.

  Both paths update the existing Win32LobApp entry in Intune (new content version),
  preserving assignments and policies.

.RUNBOOK SETUP
  Azure Automation variables required (Settings → Variables):
    Win32Updates_TenantId           – Entra tenant ID (GUID)
    Win32Updates_SharePointSiteId   – SharePoint site ID (GUID)
    Win32Updates_ListId             – SharePoint list ID (GUID)
    Win32Updates_StorageAccountName – Azure Storage account name
    Win32Updates_ContainerName      – Blob container name (e.g. win32-packages)

  Managed Identity Graph app roles required:
    Sites.ReadWrite.All
    DeviceManagementApps.ReadWrite.All

  Managed Identity Azure RBAC required:
    Storage Blob Data Reader  (on the Blob Storage container)

  Required Automation Account modules:
    Microsoft.Graph.Authentication

  Pre-staged Blob files:
    {ContainerName}/tools/IntuneWinAppUtil.exe

.PARAMETER ListItemId
  SharePoint list item ID for the app to deploy. Passed in by Power Automate.

.LOCAL USAGE
  ./Deploy-Win32AppUpdate.ps1 `
    -ListItemId '42' `
    -TenantId '00000000-...' `
    -SharePointSiteId '00000000-...' `
    -ListId '00000000-...' `
    -StorageAccountName 'mystorageaccount' `
    -ContainerName 'win32-packages'

.NOTES
  Author  : Bareminimum Automation Corner
  Version : 1.0
#>

[CmdletBinding()]
param(
    # SharePoint list item ID for the app to deploy (passed in by Power Automate).
    [Parameter(Mandatory = $true)]
    [string]$ListItemId,

    [string]$TenantId,
    [string]$SharePointSiteId,
    [string]$ListId,
    [string]$StorageAccountName,
    [string]$ContainerName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Constants ────────────────────────────────────────────────────────────────

$script:RequiredScopes    = @('Sites.ReadWrite.All', 'DeviceManagementApps.ReadWrite.All')
$script:WingetManifestApi = 'https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests'
$script:GraphBase         = 'https://graph.microsoft.com/v1.0'
$script:UploadChunkSize   = 6 * 1024 * 1024   # 6 MB per chunk

# Detect Azure Automation Runbook context
$script:IsRunbook = $false
try { if ($PSPrivateMetadata.JobId.Guid) { $script:IsRunbook = $true } } catch {}

# Temp folder for this job
$script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "Win32Deploy_$(New-Guid)"

# ─── UI / Output Helpers ──────────────────────────────────────────────────────

function Write-Out  { param([string]$m, [string]$c = 'White') if ($script:IsRunbook) { Write-Output $m } else { Write-Host $m -ForegroundColor $c } }
function Write-Step { param([string]$m) Write-Out "▶ $m" -c Yellow }
function Write-Ok   { param([string]$m) Write-Out "✓ $m" -c Green }
function Write-Info { param([string]$m) Write-Out "· $m" -c Gray }
function Write-Warn { param([string]$m) Write-Out "⚠ $m" -c DarkYellow }
function Write-Fail { param([string]$m) Write-Out "✗ $m" -c Red }

# ─── Helper Functions ─────────────────────────────────────────────────────────

function Get-AutomationVariableOrParam {
    param([string]$VariableName, [string]$ParamValue)
    if (-not [string]::IsNullOrWhiteSpace($ParamValue)) { return $ParamValue }
    if ($script:IsRunbook) { return Get-AutomationVariable -Name $VariableName }
    throw "Required value '$VariableName' not provided. Pass it as a parameter when running locally."
}

function Invoke-GraphRequest {
    param(
        [string]$Uri,
        [string]$Method = 'GET',
        [hashtable]$Body,
        [int]$MaxRetries = 3
    )
    $attempt = 0
    while ($true) {
        try {
            $params = @{ Uri = $Uri; Method = $Method }
            if ($Body) {
                $params.Body        = ($Body | ConvertTo-Json -Depth 10)
                $params.ContentType = 'application/json'
            }
            return Invoke-MgGraphRequest @params
        } catch {
            $attempt++
            $status = $_.Exception.Response?.StatusCode?.value__
            if ($attempt -lt $MaxRetries -and ($status -eq 429 -or $status -ge 500)) {
                $delay = [Math]::Pow(2, $attempt) * 3
                Write-Warn "Graph request failed (HTTP $status). Retrying in ${delay}s…"
                Start-Sleep -Seconds $delay
            } else { throw }
        }
    }
}

function Get-SharePointListItem {
    param([string]$SiteId, [string]$ListId, [string]$ItemId)
    $uri = "$script:GraphBase/sites/$SiteId/lists/$ListId/items/$ItemId`?expand=fields"
    return Invoke-GraphRequest -Uri $uri
}

function Set-SharePointListItem {
    param([string]$SiteId, [string]$ListId, [string]$ItemId, [hashtable]$Fields)
    $uri = "$script:GraphBase/sites/$SiteId/lists/$ListId/items/$ItemId/fields"
    Invoke-GraphRequest -Uri $uri -Method 'PATCH' -Body $Fields | Out-Null
}

function Connect-Graph {
    Write-Step 'Authenticating to Microsoft Graph'
    $params = @{ NoWelcome = $true }
    if ($script:IsRunbook) {
        $params.Identity = $true
    } else {
        $params.Scopes   = $script:RequiredScopes
        $params.TenantId = $script:Config.TenantId
    }
    Connect-MgGraph @params
    Write-Ok 'Authenticated'
}

# ─── Winget Helpers ───────────────────────────────────────────────────────────

function Get-WingetInstallerUrl {
    # Returns [hashtable] with InstallerUrl and InstallerType for the requested arch.
    param([string]$PackageId, [string]$Version, [string]$Architecture = 'x64')

    $parts       = $PackageId -split '\.', 2
    $publisher   = $parts[0]
    $packageName = $parts[1]
    $firstLetter = $publisher[0].ToString().ToLower()

    # List files in the version folder
    $folderUri = "$script:WingetManifestApi/$firstLetter/$publisher/$packageName/$Version"
    $files = Invoke-RestMethod -Uri $folderUri -Headers @{ 'User-Agent' = 'Win32AppUpdateAutomation/1.0' }

    # Prefer .installer.yaml; fall back to single .yaml manifest
    $manifestFile = $files | Where-Object { $_.name -like '*.installer.yaml' } | Select-Object -First 1
    if (-not $manifestFile) {
        $manifestFile = $files | Where-Object { $_.name -like '*.yaml' } | Select-Object -First 1
    }
    if (-not $manifestFile) { throw "No installer manifest found for $PackageId $Version" }

    # GitHub API returns content as base64
    $raw          = Invoke-RestMethod -Uri $manifestFile.url -Headers @{ 'User-Agent' = 'Win32AppUpdateAutomation/1.0' }
    $yamlContent  = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($raw.content -replace '\s'))

    # Parse InstallerUrl for the requested architecture using regex
    # Winget YAML lists installers as a sequence; scan for the arch block then extract URL
    $archPattern = "(?s)Architecture:\s*$Architecture.*?InstallerUrl:\s*(\S+)"
    $match       = [regex]::Match($yamlContent, $archPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    if (-not $match.Success) {
        # Fall back: grab the first InstallerUrl in the file
        $match = [regex]::Match($yamlContent, 'InstallerUrl:\s*(\S+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) { throw "Could not parse InstallerUrl from manifest for $PackageId $Version" }
        Write-Warn "Architecture '$Architecture' not found; falling back to first available installer"
    }

    $installerUrl  = $match.Groups[1].Value.Trim()
    $typeMatch     = [regex]::Match($yamlContent, 'InstallerType:\s*(\S+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $installerType = if ($typeMatch.Success) { $typeMatch.Groups[1].Value.Trim() } else { 'exe' }

    return @{ InstallerUrl = $installerUrl; InstallerType = $installerType }
}

function Invoke-WingetInstaller {
    # Downloads installer and wraps it as .intunewin using IntuneWinAppUtil.exe.
    # Returns path to the produced .intunewin file.
    param(
        [string]$PackageId,
        [string]$InstallerUrl,
        [string]$InstallerType,
        [string]$InstallCommand,
        [string]$IntuneWinAppUtilPath
    )

    $setupDir  = Join-Path $script:TempDir 'setup'
    $outputDir = Join-Path $script:TempDir 'output'
    New-Item -ItemType Directory -Path $setupDir, $outputDir -Force | Out-Null

    $extension     = if ($InstallerType -eq 'msi') { 'msi' } else { 'exe' }
    $installerPath = Join-Path $setupDir "setup.$extension"

    Write-Info "Downloading installer from $InstallerUrl"
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $installerPath -UseBasicParsing

    Write-Info 'Packaging with IntuneWinAppUtil.exe'
    $utilParams = @{
        FilePath     = $IntuneWinAppUtilPath
        ArgumentList = @('-c', $setupDir, '-s', $installerPath, '-o', $outputDir, '-q')
        Wait         = $true
        PassThru     = $true
        NoNewWindow  = $true
    }
    $proc = Start-Process @utilParams
    if ($proc.ExitCode -ne 0) { throw "IntuneWinAppUtil.exe exited with code $($proc.ExitCode)" }

    $intuneWin = Get-ChildItem -Path $outputDir -Filter '*.intunewin' | Select-Object -First 1
    if (-not $intuneWin) { throw 'IntuneWinAppUtil.exe did not produce a .intunewin file' }

    return $intuneWin.FullName
}

# ─── .intunewin Metadata Reader ───────────────────────────────────────────────

function Read-IntuneWinMetadata {
    # Extracts the encrypted content and encryption info from a .intunewin zip.
    # Returns a hashtable with paths and values needed for the Graph API upload.
    param([string]$IntuneWinPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($IntuneWinPath)

    try {
        # Detection.xml contains encryption info and file sizes
        $xmlEntry = $zip.Entries | Where-Object { $_.Name -eq 'Detection.xml' } | Select-Object -First 1
        if (-not $xmlEntry) { throw 'Detection.xml not found inside .intunewin' }

        $xmlStream  = $xmlEntry.Open()
        $xmlText    = [System.IO.StreamReader]::new($xmlStream).ReadToEnd()
        $xmlStream.Dispose()
        [xml]$xml   = $xmlText

        # Encrypted content file (inside IntuneWinPackage/Contents/)
        $contentEntry = $zip.Entries |
            Where-Object { $_.FullName -like 'IntuneWinPackage/Contents/*' -and $_.Length -gt 0 } |
            Select-Object -First 1
        if (-not $contentEntry) { throw 'Encrypted content file not found inside .intunewin' }

        # Extract encrypted content to temp file
        $encryptedPath = Join-Path $script:TempDir 'encrypted_content.bin'
        $contentStream = $contentEntry.Open()
        $fileStream    = [System.IO.File]::OpenWrite($encryptedPath)
        $contentStream.CopyTo($fileStream)
        $fileStream.Dispose()
        $contentStream.Dispose()

        $appInfo = $xml.ApplicationInfo
        return @{
            FileName            = $appInfo.FileName
            UnencryptedSize     = [long]$appInfo.UnencryptedContentSize
            EncryptedSize       = (Get-Item $encryptedPath).Length
            EncryptedFilePath   = $encryptedPath
            EncryptionInfo      = @{
                encryptionKey        = $appInfo.EncryptionInfo.EncryptionKey
                macKey               = $appInfo.EncryptionInfo.MacKey
                initializationVector = $appInfo.EncryptionInfo.InitializationVector
                mac                  = $appInfo.EncryptionInfo.Mac
                profileIdentifier    = $appInfo.EncryptionInfo.ProfileIdentifier
                fileDigest           = $appInfo.EncryptionInfo.FileDigest
                fileDigestAlgorithm  = $appInfo.EncryptionInfo.FileDigestAlgorithm
            }
        }
    } finally {
        $zip.Dispose()
    }
}

# ─── Azure Blob Chunked Upload ────────────────────────────────────────────────

function Invoke-AzureBlobChunkedUpload {
    param([string]$SasUri, [string]$FilePath)

    $fileStream = [System.IO.File]::OpenRead($FilePath)
    $buffer     = New-Object byte[] $script:UploadChunkSize
    $blockIds   = [System.Collections.Generic.List[string]]::new()
    $blockNum   = 0

    try {
        while (($bytesRead = $fileStream.Read($buffer, 0, $script:UploadChunkSize)) -gt 0) {
            $blockId     = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($blockNum.ToString('D6')))
            $blockIds.Add($blockId)
            $escapedId   = [Uri]::EscapeDataString($blockId)
            $blockUri    = "${SasUri}&comp=block&blockid=$escapedId"
            $blockData   = if ($bytesRead -eq $script:UploadChunkSize) { $buffer } else { $buffer[0..($bytesRead - 1)] }

            $attempt = 0
            while ($true) {
                try {
                    $params = @{
                        Uri         = $blockUri
                        Method      = 'PUT'
                        Body        = $blockData
                        ContentType = 'application/octet-stream'
                        Headers     = @{ 'x-ms-blob-type' = 'BlockBlob' }
                    }
                    Invoke-RestMethod @params | Out-Null
                    break
                } catch {
                    $attempt++
                    if ($attempt -ge 3) { throw }
                    Start-Sleep -Seconds ([Math]::Pow(2, $attempt))
                }
            }
            $blockNum++
        }
    } finally {
        $fileStream.Dispose()
    }

    # Commit all blocks as a block list
    $blockListXml = '<?xml version="1.0" encoding="utf-8"?><BlockList>' +
        (($blockIds | ForEach-Object { "<Latest>$_</Latest>" }) -join '') +
        '</BlockList>'

    $params = @{
        Uri         = "${SasUri}&comp=blocklist"
        Method      = 'PUT'
        Body        = [System.Text.Encoding]::UTF8.GetBytes($blockListXml)
        ContentType = 'text/xml; charset=utf-8'
    }
    Invoke-RestMethod @params | Out-Null
    Write-Ok "Uploaded $blockNum chunk(s) to Azure Blob Storage"
}

# ─── Intune Content Version Upload ───────────────────────────────────────────

function Invoke-IntuneContentVersionUpload {
    # Uploads a .intunewin to an existing Intune Win32LobApp as a new content version.
    param([string]$IntuneAppId, [string]$IntuneWinPath)

    $appBase = "$script:GraphBase/deviceAppManagement/mobileApps/$IntuneAppId/microsoft.graph.win32LobApp"

    Write-Step 'Reading .intunewin metadata'
    $meta = Read-IntuneWinMetadata -IntuneWinPath $IntuneWinPath

    # 1. Create new content version
    Write-Info 'Creating Intune content version'
    $contentVersion = Invoke-GraphRequest -Uri "$appBase/contentVersions" -Method 'POST' -Body @{}
    $cvId = $contentVersion.id
    Write-Info "Content version ID: $cvId"

    # 2. Create file entry
    Write-Info 'Creating Intune content file entry'
    $fileBody = @{
        '@odata.type'    = '#microsoft.graph.mobileAppContentFile'
        name             = $meta.FileName
        size             = $meta.UnencryptedSize
        sizeEncrypted    = $meta.EncryptedSize
        isDependency     = $false
    }
    $fileEntry = Invoke-GraphRequest -Uri "$appBase/contentVersions/$cvId/files" -Method 'POST' -Body $fileBody
    $fileId    = $fileEntry.id

    # 3. Wait for Azure Storage URI
    Write-Info 'Waiting for Azure Storage upload URI…'
    $maxWait   = 60
    $waited    = 0
    do {
        Start-Sleep -Seconds 3
        $waited    += 3
        $fileEntry  = Invoke-GraphRequest -Uri "$appBase/contentVersions/$cvId/files/$fileId"
        if ($waited -ge $maxWait) { throw 'Timed out waiting for azureStorageUri from Intune' }
    } while ($fileEntry.uploadState -ne 'azureStorageUriRequestSuccess')

    $storageUri = $fileEntry.azureStorageUri
    Write-Ok 'Azure Storage URI received'

    # 4. Upload encrypted content in chunks
    Write-Step "Uploading encrypted package ($([Math]::Round($meta.EncryptedSize / 1MB, 1)) MB)"
    Invoke-AzureBlobChunkedUpload -SasUri $storageUri -FilePath $meta.EncryptedFilePath

    # 5. Commit the file with encryption info
    Write-Info 'Committing file to Intune'
    $commitBody = @{
        fileEncryptionInfo = $meta.EncryptionInfo
    }
    Invoke-GraphRequest -Uri "$appBase/contentVersions/$cvId/files/$fileId/commit" -Method 'POST' -Body $commitBody | Out-Null

    # 6. Wait for commit to complete
    Write-Info 'Waiting for commit confirmation…'
    $waited = 0
    do {
        Start-Sleep -Seconds 3
        $waited   += 3
        $fileEntry = Invoke-GraphRequest -Uri "$appBase/contentVersions/$cvId/files/$fileId"
        if ($fileEntry.uploadState -eq 'commitFileFailed') {
            throw 'Intune file commit failed (commitFileFailed). Check the Intune portal for details.'
        }
        if ($waited -ge 120) { throw 'Timed out waiting for Intune file commit' }
    } while ($fileEntry.uploadState -ne 'commitFileSuccess')
    Write-Ok 'File committed successfully'

    # 7. Update app to use the new committed content version
    Write-Info 'Updating app to committed content version'
    $patchBody = @{
        '@odata.type'            = '#microsoft.graph.win32LobApp'
        committedContentVersion  = $cvId
    }
    Invoke-GraphRequest -Uri "$script:GraphBase/deviceAppManagement/mobileApps/$IntuneAppId" -Method 'PATCH' -Body $patchBody | Out-Null
    Write-Ok "App updated to content version $cvId"
}

# ─── Blob Storage Download ────────────────────────────────────────────────────

function Get-BlobFile {
    # Downloads a file from Azure Blob Storage using a SAS URL.
    param([string]$SasUrl, [string]$DestinationPath)
    Write-Info "Downloading from Blob Storage: $([System.Uri]::new($SasUrl).AbsolutePath)"
    Invoke-WebRequest -Uri $SasUrl -OutFile $DestinationPath -UseBasicParsing
}

function Get-IntuneWinAppUtil {
    # Downloads IntuneWinAppUtil.exe from the tools/ folder in Blob Storage.
    param([string]$StorageAccountName, [string]$ContainerName)

    # Build a SAS URL using the Managed Identity token for Azure Storage
    $tokenUri = "https://storage.azure.com/"
    $token    = (Invoke-RestMethod -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$tokenUri" `
        -Headers @{ Metadata = 'true' }).access_token

    $blobUri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/tools/IntuneWinAppUtil.exe"
    $destPath = Join-Path $script:TempDir 'IntuneWinAppUtil.exe'

    $headers = @{ Authorization = "Bearer $token" }
    Invoke-WebRequest -Uri $blobUri -Headers $headers -OutFile $destPath -UseBasicParsing
    return $destPath
}

# ─── Main ─────────────────────────────────────────────────────────────────────

Write-Step "Win32 App Deployment — ListItemId: $ListItemId"

# Resolve configuration
$script:Config = @{
    TenantId           = Get-AutomationVariableOrParam -VariableName 'Win32Updates_TenantId'           -ParamValue $TenantId
    SharePointSiteId   = Get-AutomationVariableOrParam -VariableName 'Win32Updates_SharePointSiteId'   -ParamValue $SharePointSiteId
    ListId             = Get-AutomationVariableOrParam -VariableName 'Win32Updates_ListId'             -ParamValue $ListId
    StorageAccountName = Get-AutomationVariableOrParam -VariableName 'Win32Updates_StorageAccountName' -ParamValue $StorageAccountName
    ContainerName      = Get-AutomationVariableOrParam -VariableName 'Win32Updates_ContainerName'      -ParamValue $ContainerName
}

# Create working temp directory
New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

try {
    Connect-Graph

    # ─── Read SharePoint Item ─────────────────────────────────────────────────

    Write-Step 'Reading SharePoint list item'
    $item   = Get-SharePointListItem -SiteId $script:Config.SharePointSiteId -ListId $script:Config.ListId -ItemId $ListItemId
    $fields = $item.fields

    $appName         = $fields.AppName
    $intuneAppId     = $fields.IntuneAppId
    $source          = $fields.Source
    $availableVer    = $fields.AvailableVersion
    $wingetPkgId     = $fields.WingetPackageId
    $manualPkgUrl    = $fields.ManualPackageUrl
    $installCmd      = $fields.InstallCommand
    $architecture    = if ($fields.Architecture) { $fields.Architecture } else { 'x64' }

    Write-Info "App      : $appName"
    Write-Info "Source   : $source"
    Write-Info "Version  : $availableVer"
    Write-Info "IntuneId : $intuneAppId"

    if ([string]::IsNullOrWhiteSpace($intuneAppId)) { throw 'IntuneAppId is empty. Add the Intune Graph app ID to the SharePoint list item.' }
    if ($fields.Status -notin @('Approved', 'Deploying')) {
        throw "Item status is '$($fields.Status)'. Expected 'Approved' or 'Deploying'."
    }

    # Mark as Deploying (idempotent — safe to set again if already Deploying)
    Set-SharePointListItem -SiteId $script:Config.SharePointSiteId -ListId $script:Config.ListId -ItemId $ListItemId -Fields @{
        Status      = 'Deploying'
        LastUpdated = (Get-Date -Format 'o')
    }

    # ─── Obtain .intunewin ────────────────────────────────────────────────────

    $intuneWinPath = $null

    if ($source -eq 'Manual') {
        Write-Step 'Downloading .intunewin from Blob Storage'
        if ([string]::IsNullOrWhiteSpace($manualPkgUrl)) { throw 'ManualPackageUrl is empty for a Manual-source app.' }
        $intuneWinPath = Join-Path $script:TempDir 'package.intunewin'
        Get-BlobFile -SasUrl $manualPkgUrl -DestinationPath $intuneWinPath
        Write-Ok 'Package downloaded'

    } elseif ($source -eq 'Winget') {
        Write-Step "Fetching Winget installer for $wingetPkgId $availableVer"
        if ([string]::IsNullOrWhiteSpace($wingetPkgId)) { throw 'WingetPackageId is empty for a Winget-source app.' }

        $installer = Get-WingetInstallerUrl -PackageId $wingetPkgId -Version $availableVer -Architecture $architecture
        Write-Info "Installer URL  : $($installer.InstallerUrl)"
        Write-Info "Installer type : $($installer.InstallerType)"

        Write-Step 'Downloading IntuneWinAppUtil.exe from Blob Storage'
        $utilPath = Get-IntuneWinAppUtil -StorageAccountName $script:Config.StorageAccountName -ContainerName $script:Config.ContainerName

        $intuneWinPath = Invoke-WingetInstaller -PackageId $wingetPkgId `
            -InstallerUrl  $installer.InstallerUrl `
            -InstallerType $installer.InstallerType `
            -InstallCommand $installCmd `
            -IntuneWinAppUtilPath $utilPath
        Write-Ok ".intunewin created: $intuneWinPath"

    } else {
        throw "Unknown Source value '$source'. Expected 'Winget' or 'Manual'."
    }

    # ─── Upload to Intune ─────────────────────────────────────────────────────

    Write-Step "Uploading new content version to Intune app '$appName'"
    Invoke-IntuneContentVersionUpload -IntuneAppId $intuneAppId -IntuneWinPath $intuneWinPath

    # ─── Update SharePoint List ───────────────────────────────────────────────

    Write-Step 'Updating SharePoint list item'
    Set-SharePointListItem -SiteId $script:Config.SharePointSiteId -ListId $script:Config.ListId -ItemId $ListItemId -Fields @{
        Status         = 'Deployed'
        CurrentVersion = $availableVer
        LastUpdated    = (Get-Date -Format 'o')
    }

    Write-Ok "[$appName] Deployment complete — version $availableVer is now live in Intune"

    # Emit structured result for Power Automate
    [PSCustomObject]@{
        Success          = $true
        AppName          = $appName
        DeployedVersion  = $availableVer
        ListItemId       = $ListItemId
    } | ConvertTo-Json -Compress | Write-Output

} catch {
    Write-Fail "Deployment failed: $_"

    # Mark item as Failed in SharePoint so the operator can see it
    try {
        Set-SharePointListItem -SiteId $script:Config.SharePointSiteId -ListId $script:Config.ListId -ItemId $ListItemId -Fields @{
            Status      = 'Failed'
            Notes       = "Deployment error: $($_.Exception.Message)"
            LastUpdated = (Get-Date -Format 'o')
        }
    } catch {
        Write-Warn "Could not update SharePoint item to Failed: $_"
    }

    # Emit failure result for Power Automate
    [PSCustomObject]@{
        Success   = $false
        AppName   = $fields.AppName
        Error     = $_.Exception.Message
        ListItemId = $ListItemId
    } | ConvertTo-Json -Compress | Write-Output

    throw  # Re-throw so the Automation job is marked as Failed

} finally {
    # Clean up temp files
    if (Test-Path $script:TempDir) {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
