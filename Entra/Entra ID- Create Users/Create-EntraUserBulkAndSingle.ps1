#Requires -Version 7.0
<#!
.SYNOPSIS
    Creates cloud-only Microsoft Entra ID member users individually or in bulk.

.DESCRIPTION
    Creates one user from prompts or multiple users from a CSV or XLSX file. Existing
    user principal names are skipped, generated initial passwords require a change at
    first sign-in, and managers can be assigned after the user-creation phase.

    This script creates cloud-only Member users only. It does not invite guest users,
    assign licenses, add group memberships, update existing users, or delete users.

.PARAMETER Mode
    Input mode. Auto displays a menu when SourcePath is not supplied.

.PARAMETER SourcePath
    Path to a CSV or XLSX bulk source file.

.PARAMETER WorksheetName
    Worksheet to import from an XLSX file. Defaults to the first worksheet.

.PARAMETER ResultPath
    Path for the password-free results CSV. Defaults to the script directory.

.PARAMETER HandoffFilePath
    Path for the generated-password CSV. Defaults to the script directory.

.PARAMETER TenantId
    Optional tenant ID or verified tenant domain for Microsoft Graph sign-in.

.PARAMETER AuthenticationMode
    Microsoft Graph sign-in method. Auto prompts only if a suitable session is not open.

.PARAMETER AllowPlainTextPasswordExport
    Explicitly acknowledges that HandoffFilePath stores plaintext passwords. Required
    for non-WhatIf runs because passwords must be handed to the operator securely.

.EXAMPLE
    ./Create-EntraUserBulkAndSingle.ps1 -Mode Single -WhatIf
    Previews an interactively entered user without changing Entra ID.

.EXAMPLE
    ./Create-EntraUserBulkAndSingle.ps1 -SourcePath ./UserImportTemplate.csv -AllowPlainTextPasswordExport
    Creates valid source users, writes password-free results and a separate plaintext
    password handoff CSV. Securely distribute and delete the password file immediately.

.NOTES
    Requires: Microsoft.Graph.Authentication, Microsoft.Graph.Users; ImportExcel only for XLSX.
    Microsoft Graph API: v1.0
    Required delegated scopes: User.ReadWrite.All
    Idempotent: Yes. Existing UPNs are skipped and never changed.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateSet('Auto', 'Single', 'Csv', 'Excel')]
    [string] $Mode = 'Auto',

    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $SourcePath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $WorksheetName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ResultPath = (Join-Path $PSScriptRoot ("EntraUserResults-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $HandoffFilePath = (Join-Path $PSScriptRoot ("EntraUserPasswords-DELETE-AFTER-USE-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $TenantId,

    [Parameter()]
    [ValidateSet('Auto', 'Browser', 'DeviceCode')]
    [string] $AuthenticationMode = 'Auto',

    [Parameter()]
    [switch] $AllowPlainTextPasswordExport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RequiredScopes = @('User.ReadWrite.All')
$script:RequiredColumns = @('UserPrincipalName', 'DisplayName', 'GivenName', 'Surname')
$script:InputColumnAliases = @{
    UserPrincipalName          = @('UserPrincipalName', 'Användarens inloggningsnamn')
    DisplayName                = @('DisplayName', 'Visningsnamn', 'Namn')
    GivenName                  = @('GivenName', 'Förnamn')
    Surname                    = @('Surname', 'Efternamn')
    MailNickname               = @('MailNickname', 'Inloggningsnamn före Windows 2000')
    UsageLocation              = @('UsageLocation')
    CompanyName                = @('CompanyName', 'Företag')
    Department                 = @('Department', 'Avdelning')
    JobTitle                   = @('JobTitle', 'Befattning')
    AboutMe                    = @('AboutMe', 'Beskrivning')
    City                       = @('City', 'Ort')
    PostalCode                 = @('PostalCode', 'Postnummer')
    BusinessPhone              = @('BusinessPhone', 'BusinessPhones', 'Telefonnummer')
    MobilePhone                = @('MobilePhone', 'Mobilnummer')
    Mail                       = @('Mail', 'E-postadress')
    AccountEnabled             = @('AccountEnabled')
    ManagerUserPrincipalName   = @('ManagerUserPrincipalName')
    UserType                   = @('UserType')
    SourceCreationMarker       = @('Redan Skapad:')
}
$script:Results = [System.Collections.Generic.List[object]]::new()
$script:PasswordResults = [System.Collections.Generic.List[object]]::new()
$script:GeneratedPasswords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

function Write-Step {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "▶ $Message" -ForegroundColor Yellow
}

function Write-Ok {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Info {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "· $Message" -ForegroundColor Gray
}

function Write-Warn {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "⚠ $Message" -ForegroundColor DarkYellow
}

function ConvertTo-Boolean {
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [bool] $Default
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string] $Value)) {
        return $Default
    }

    switch -Regex (([string] $Value).Trim()) {
        '^(true|yes|y|1)$' { return $true }
        '^(false|no|n|0)$' { return $false }
        default { throw "'$Value' is not a valid Boolean value. Use true or false." }
    }
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory)] [object] $InputObject,
        [Parameter(Mandatory)] [string] $Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return ''
    }

    return ([string] $property.Value).Trim()
}

function Get-InputValue {
    param(
        [Parameter(Mandatory)] [object] $InputObject,
        [Parameter(Mandatory)] [string] $Name
    )

    $aliases = $script:InputColumnAliases[$Name]
    if ($null -eq $aliases) { $aliases = @($Name) }

    foreach ($alias in $aliases) {
        $value = Get-PropertyValue -InputObject $InputObject -Name $alias
        if ($value) { return $value }
    }

    return ''
}

function Get-SourceCreationMarkerStatus {
    param([Parameter(Mandatory)] [object] $InputObject)

    $marker = Get-InputValue -InputObject $InputObject -Name 'SourceCreationMarker'
    if (-not $marker) { return 'Eligible' }
    if ($marker -match '^(ja|yes|true|1|created|skapad)$') { return 'AlreadyCreated' }
    return 'Invalid'
}

function New-InitialPassword {
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()
    $lower = 'abcdefghijkmnopqrstuvwxyz'.ToCharArray()
    $number = '23456789'.ToCharArray()
    $symbol = '!@#$%*-_+'.ToCharArray()
    $all = $upper + $lower + $number + $symbol

    do {
        $characters = [System.Collections.Generic.List[char]]::new()
        foreach ($set in @($upper, $lower, $number, $symbol)) {
            $characters.Add($set[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($set.Length)])
        }

        while ($characters.Count -lt 20) {
            $characters.Add($all[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($all.Length)])
        }

        for ($index = $characters.Count - 1; $index -gt 0; $index--) {
            $swapIndex = [System.Security.Cryptography.RandomNumberGenerator]::GetInt32($index + 1)
            $temporary = $characters[$index]
            $characters[$index] = $characters[$swapIndex]
            $characters[$swapIndex] = $temporary
        }

        $password = -join $characters
    } while (-not $script:GeneratedPasswords.Add($password))

    return $password
}

function Get-MailNickname {
    param(
        [Parameter(Mandatory)] [string] $Value,
        [Parameter(Mandatory)] [int] $RowNumber
    )

    $nickname = ($Value -replace '[^a-zA-Z0-9._-]', '')
    if ([string]::IsNullOrWhiteSpace($nickname)) {
        throw ('Row {0}: MailNickname is empty after removing unsupported characters.' -f $RowNumber)
    }

    return $nickname.Substring(0, [Math]::Min(64, $nickname.Length))
}

function Get-NormalizedUserRecord {
    param(
        [Parameter(Mandatory)] [object] $InputObject,
        [Parameter(Mandatory)] [int] $RowNumber
    )

    foreach ($column in $script:RequiredColumns) {
        if ([string]::IsNullOrWhiteSpace((Get-InputValue -InputObject $InputObject -Name $column))) {
            throw ('Row {0}: Required value ''{1}'' is empty.' -f $RowNumber, $column)
        }
    }

    $upn = Get-InputValue -InputObject $InputObject -Name 'UserPrincipalName'
    if ($upn -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        throw ('Row {0}: UserPrincipalName ''{1}'' is not a valid UPN format.' -f $RowNumber, $upn)
    }

    $usageLocation = Get-InputValue -InputObject $InputObject -Name 'UsageLocation'
    if ($usageLocation -and $usageLocation -notmatch '^[A-Za-z]{2}$') {
        throw ('Row {0}: UsageLocation ''{1}'' must be a two-letter ISO country/region code.' -f $RowNumber, $usageLocation)
    }

    $userType = Get-InputValue -InputObject $InputObject -Name 'UserType'
    if ($userType -and $userType -ne 'Member') {
        throw ('Row {0}: UserType must be ''Member''. Guest invitations are out of scope for this script.' -f $RowNumber)
    }

    $mailNickname = Get-InputValue -InputObject $InputObject -Name 'MailNickname'
    if (-not $mailNickname) {
        $mailNickname = $upn.Split('@')[0]
    }

    $mail = Get-InputValue -InputObject $InputObject -Name 'Mail'
    if ($mail -and $mail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        throw ('Row {0}: E-postadress/Mail ''{1}'' is not a valid email address format.' -f $RowNumber, $mail)
    }

    return [PSCustomObject]@{
        SourceRow               = $RowNumber
        UserPrincipalName       = $upn.ToLowerInvariant()
        DisplayName             = Get-InputValue -InputObject $InputObject -Name 'DisplayName'
        GivenName               = Get-InputValue -InputObject $InputObject -Name 'GivenName'
        Surname                 = Get-InputValue -InputObject $InputObject -Name 'Surname'
        MailNickname            = Get-MailNickname -Value $mailNickname -RowNumber $RowNumber
        UsageLocation           = $usageLocation.ToUpperInvariant()
        CompanyName             = Get-InputValue -InputObject $InputObject -Name 'CompanyName'
        Department              = Get-InputValue -InputObject $InputObject -Name 'Department'
        JobTitle                = Get-InputValue -InputObject $InputObject -Name 'JobTitle'
        AboutMe                 = Get-InputValue -InputObject $InputObject -Name 'AboutMe'
        City                    = Get-InputValue -InputObject $InputObject -Name 'City'
        PostalCode              = Get-InputValue -InputObject $InputObject -Name 'PostalCode'
        BusinessPhones          = @(Get-InputValue -InputObject $InputObject -Name 'BusinessPhone' | Where-Object { $_ })
        MobilePhone             = Get-InputValue -InputObject $InputObject -Name 'MobilePhone'
        Mail                    = $mail.ToLowerInvariant()
        AccountEnabled          = ConvertTo-Boolean -Value (Get-InputValue -InputObject $InputObject -Name 'AccountEnabled') -Default $true
        ManagerUserPrincipalName = (Get-InputValue -InputObject $InputObject -Name 'ManagerUserPrincipalName').ToLowerInvariant()
    }
}

function Select-InputMode {
    if ($Mode -ne 'Auto') { return $Mode }
    if ($SourcePath) {
        return if ([IO.Path]::GetExtension($SourcePath) -match '^\.csv$') { 'Csv' } else { 'Excel' }
    }

    Write-Host ''
    Write-Host '1. Create a single user interactively'
    Write-Host '2. Create users from CSV'
    Write-Host '3. Create users from Excel'
    $choice = Read-Host 'Choose an option [1/2/3]'
    switch ($choice) {
        '1' { return 'Single' }
        '2' { return 'Csv' }
        '3' { return 'Excel' }
        default { throw "Invalid selection '$choice'." }
    }
}

function Get-SingleUserInput {
    $record = [ordered]@{}
    foreach ($column in $script:RequiredColumns) {
        do { $record[$column] = Read-Host "$column (required)" } while ([string]::IsNullOrWhiteSpace($record[$column]))
    }
    foreach ($column in @('MailNickname', 'UsageLocation', 'CompanyName', 'Department', 'JobTitle', 'ManagerUserPrincipalName')) {
        $record[$column] = Read-Host "$column (optional)"
    }
    $record['AccountEnabled'] = Read-Host 'AccountEnabled [true]'
    return ,(Get-NormalizedUserRecord -InputObject ([PSCustomObject] $record) -RowNumber 1)
}

function Get-BulkUserInput {
    param([Parameter(Mandatory)][ValidateSet('Csv', 'Excel')][string] $InputMode)

    $path = $SourcePath
    if (-not $path) { $path = Read-Host "Path to $InputMode file" }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Source file '$path' does not exist." }

    if ($InputMode -eq 'Csv') {
        $rawRecords = @(Import-Csv -LiteralPath $path)
    }
    else {
        if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
            throw "XLSX input requires the ImportExcel module. Install it with: Install-Module ImportExcel -Scope CurrentUser"
        }
        Import-Module ImportExcel -ErrorAction Stop
        $excelParams = @{ Path = $path }
        if ($WorksheetName) { $excelParams.WorksheetName = $WorksheetName }
        $rawRecords = @(Import-Excel @excelParams)
    }

    if ($rawRecords.Count -eq 0) { throw "Source file '$path' contains no data rows." }
    $records = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $rawRecords.Count; $index++) {
        $rawRecord = $rawRecords[$index]
        $rowNumber = $index + 2
        $markerStatus = Get-SourceCreationMarkerStatus -InputObject $rawRecord
        if ($markerStatus -eq 'AlreadyCreated') {
            Add-SourceResult -InputObject $rawRecord -RowNumber $rowNumber -Status 'Skipped' -SourceDisposition 'SkippedBySourceMarker' -FailureMessage 'Source marker indicates that this account has already been created.'
            continue
        }
        if ($markerStatus -eq 'Invalid') {
            $marker = Get-InputValue -InputObject $rawRecord -Name 'SourceCreationMarker'
            Add-SourceResult -InputObject $rawRecord -RowNumber $rowNumber -Status 'Failed' -SourceDisposition 'InvalidSourceMarker' -FailureMessage "Source marker '$marker' is invalid. Leave it blank or use Ja, Yes, True, 1, Created, or Skapad."
            continue
        }

        try {
            $records.Add((Get-NormalizedUserRecord -InputObject $rawRecord -RowNumber $rowNumber))
        }
        catch {
            Add-SourceResult -InputObject $rawRecord -RowNumber $rowNumber -Status 'Failed' -SourceDisposition 'InvalidInput' -FailureMessage $_.Exception.Message
            Write-Warn "Could not validate source row ${rowNumber}: $($_.Exception.Message)"
        }
    }
    $duplicates = @($records | Group-Object UserPrincipalName | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) { throw "Source contains duplicate UPN(s): $($duplicates.Name -join ', ')." }
    return @($records)
}

function Install-RequiredGraphModules {
    foreach ($moduleName in @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Users')) {
        if (-not (Get-Module -ListAvailable -Name $moduleName)) {
            Write-Step "Installing required module '$moduleName' for the current user"
            try {
                Install-Module -Name $moduleName -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
            }
            catch {
                throw "Could not install '$moduleName'. Install it manually and rerun the script. $($_.Exception.Message)"
            }
        }
        Import-Module -Name $moduleName -ErrorAction Stop
    }
}

function Connect-EntraGraph {
    Install-RequiredGraphModules
    $context = Get-MgContext -ErrorAction SilentlyContinue
    $requiredScopesGranted = $context -and (@($script:RequiredScopes | Where-Object { $_ -notin $context.Scopes }).Count -eq 0)
    $correctTenant = -not $TenantId -or $context.TenantId -eq $TenantId
    if ($requiredScopesGranted -and $correctTenant) {
        Write-Info "Using existing Microsoft Graph connection for '$($context.Account)'."
        Write-Info "Tenant: $($context.TenantId)"
        return
    }

    Write-Step 'Connecting to Microsoft Graph'
    Write-Info "Required delegated scope: $($script:RequiredScopes -join ', ')"
    $connectParams = @{ Scopes = $script:RequiredScopes; NoWelcome = $true }
    if ($TenantId) { $connectParams.TenantId = $TenantId }

    $selectedAuthenticationMode = $AuthenticationMode
    if ($selectedAuthenticationMode -eq 'Auto') {
        Write-Host '1. Browser sign-in'
        Write-Host '2. Device-code sign-in'
        $choice = Read-Host 'Choose authentication method [1]'
        if ([string]::IsNullOrWhiteSpace($choice) -or $choice -eq '1') { $selectedAuthenticationMode = 'Browser' }
        elseif ($choice -eq '2') { $selectedAuthenticationMode = 'DeviceCode' }
        else { throw "Invalid authentication selection '$choice'." }
    }
    if ($selectedAuthenticationMode -eq 'DeviceCode') { $connectParams.UseDeviceCode = $true }

    try {
        Connect-MgGraph @connectParams
        $newContext = Get-MgContext
        if (-not $newContext -or @($script:RequiredScopes | Where-Object { $_ -notin $newContext.Scopes }).Count -gt 0) {
            throw 'Microsoft Graph connected without User.ReadWrite.All. Reconnect and grant/admin-consent the requested scope.'
        }
        Write-Ok "Connected to Microsoft Graph as '$($newContext.Account)' in tenant '$($newContext.TenantId)'."
    }
    catch {
        throw "Microsoft Graph connection failed. $($_.Exception.Message)"
    }
}

function Find-EntraUserByUpn {
    param([Parameter(Mandatory)][string] $UserPrincipalName)
    $escapedUpn = $UserPrincipalName.Replace("'", "''")
    return Get-MgUser -Filter "userPrincipalName eq '$escapedUpn'" -Property 'id,userPrincipalName,displayName' -Top 1 |
        Select-Object -First 1
}

function Add-Result {
    param(
        [Parameter(Mandatory)][object] $Record,
        [Parameter(Mandatory)][ValidateSet('Created', 'Skipped', 'Failed', 'Planned')][string] $Status,
        [string] $ObjectId,
        [string] $ManagerStatus = 'NotRequested',
        [string] $ProfileStatus = 'NotRequested',
        [string] $SourceDisposition = 'Eligible',
        [string] $SourceMarker,
        [string] $FailureMessage
    )
    $script:Results.Add([PSCustomObject]@{
        SourceRow = $Record.SourceRow; UserPrincipalName = $Record.UserPrincipalName; DisplayName = $Record.DisplayName
        ObjectId = $ObjectId; Status = $Status; SourceDisposition = $SourceDisposition; SourceMarker = $SourceMarker
        ProfileStatus = $ProfileStatus; ManagerStatus = $ManagerStatus; Error = $FailureMessage
    })
}

function Add-SourceResult {
    param(
        [Parameter(Mandatory)][object] $InputObject,
        [Parameter(Mandatory)][int] $RowNumber,
        [Parameter(Mandatory)][ValidateSet('Skipped', 'Failed')][string] $Status,
        [Parameter(Mandatory)][string] $SourceDisposition,
        [Parameter(Mandatory)][string] $FailureMessage
    )

    $script:Results.Add([PSCustomObject]@{
        SourceRow = $RowNumber
        UserPrincipalName = Get-InputValue -InputObject $InputObject -Name 'UserPrincipalName'
        DisplayName = Get-InputValue -InputObject $InputObject -Name 'DisplayName'
        ObjectId = ''
        Status = $Status
        SourceDisposition = $SourceDisposition
        SourceMarker = Get-InputValue -InputObject $InputObject -Name 'SourceCreationMarker'
        ProfileStatus = 'NotRequested'
        ManagerStatus = 'NotRequested'
        Error = $FailureMessage
    })
}

function Export-ProvisioningResults {
    $script:Results | Export-Csv -LiteralPath $ResultPath -NoTypeInformation -Encoding utf8
    Write-Ok "Password-free results exported to '$ResultPath'."
    if (-not $WhatIfPreference -and $script:PasswordResults.Count -gt 0) {
        $script:PasswordResults | Export-Csv -LiteralPath $HandoffFilePath -NoTypeInformation -Encoding utf8
        Write-Warn "PLAINTEXT PASSWORDS exported to '$HandoffFilePath'. Securely distribute it, then delete it immediately."
    }

    $summary = $script:Results | Group-Object Status | ForEach-Object { "$($_.Name): $($_.Count)" }
    Write-Host "Summary — $($summary -join '; ')" -ForegroundColor Cyan
}

# ─── Gather and Validate Input ───────────────────────────────────────────────
try {
    $selectedMode = Select-InputMode
    Write-Step "Gathering $selectedMode input"
    $records = @(if ($selectedMode -eq 'Single') { Get-SingleUserInput } else { Get-BulkUserInput -InputMode $selectedMode })
    Write-Ok "Validated $($records.Count) user record(s)."

    if ($records.Count -eq 0) {
        Write-Info 'No eligible source rows remain after source-marker and input validation.'
        Export-ProvisioningResults
        $script:Results
        return
    }

    if (-not $WhatIfPreference -and -not $AllowPlainTextPasswordExport) {
        throw 'Password creation requires -AllowPlainTextPasswordExport. The separate password CSV contains plaintext credentials; securely distribute it and delete it immediately.'
    }

    Connect-EntraGraph

    # ─── Create Users ───────────────────────────────────────────────────────
    Write-Step 'Creating users'
    foreach ($record in $records) {
        try {
            $existing = Find-EntraUserByUpn -UserPrincipalName $record.UserPrincipalName
            if ($existing) {
                Write-Warn "$($record.UserPrincipalName) already exists; skipping."
                Add-Result -Record $record -Status 'Skipped' -ObjectId $existing.Id
                continue
            }

            $password = New-InitialPassword
            $body = @{
                accountEnabled = $record.AccountEnabled; displayName = $record.DisplayName; givenName = $record.GivenName
                surname = $record.Surname; userPrincipalName = $record.UserPrincipalName; mailNickname = $record.MailNickname
                passwordProfile = @{ password = $password; forceChangePasswordNextSignIn = $true }
            }
            if ($record.UsageLocation) { $body.usageLocation = $record.UsageLocation }
            if ($record.CompanyName) { $body.companyName = $record.CompanyName }
            if ($record.Department) { $body.department = $record.Department }
            if ($record.JobTitle) { $body.jobTitle = $record.JobTitle }
            if ($record.City) { $body.city = $record.City }
            if ($record.PostalCode) { $body.postalCode = $record.PostalCode }
            if ($record.BusinessPhones.Count -gt 0) { $body.businessPhones = $record.BusinessPhones }
            if ($record.MobilePhone) { $body.mobilePhone = $record.MobilePhone }
            if ($record.Mail) { $body.mail = $record.Mail }

            if ($PSCmdlet.ShouldProcess($record.UserPrincipalName, 'Create Microsoft Entra ID user')) {
                $newUser = New-MgUser -BodyParameter $body
                $profileStatus = 'NotRequested'
                $profileFailureMessage = ''
                if ($record.AboutMe) {
                    if ($PSCmdlet.ShouldProcess($newUser.Id, 'Set Microsoft Entra ID user profile description')) {
                        try {
                            Update-MgUser -UserId $newUser.Id -BodyParameter @{ aboutMe = $record.AboutMe }
                            $profileStatus = 'Updated'
                        }
                        catch {
                            $profileStatus = 'Failed'
                            $profileFailureMessage = "User was created, but aboutMe could not be set. $($_.Exception.Message)"
                            Write-Warn "Created $($record.UserPrincipalName), but could not set aboutMe: $($_.Exception.Message)"
                        }
                    }
                    else {
                        $profileStatus = 'Planned'
                    }
                }

                Add-Result -Record $record -Status 'Created' -ObjectId $newUser.Id -ProfileStatus $profileStatus -FailureMessage $profileFailureMessage
                $script:PasswordResults.Add([PSCustomObject]@{ UserPrincipalName = $record.UserPrincipalName; InitialPassword = $password })
                Write-Ok "Created $($record.UserPrincipalName)."
            }
            else {
                $profileStatus = 'NotRequested'
                if ($record.AboutMe) {
                    $PSCmdlet.ShouldProcess($record.UserPrincipalName, 'Set Microsoft Entra ID user profile description after creation') | Out-Null
                    $profileStatus = 'Planned'
                }
                Add-Result -Record $record -Status 'Planned' -ProfileStatus $profileStatus
            }
        }
        catch {
            Add-Result -Record $record -Status 'Failed' -FailureMessage $_.Exception.Message
            Write-Warn "Could not create $($record.UserPrincipalName): $($_.Exception.Message)"
        }
    }

    # ─── Assign Managers ────────────────────────────────────────────────────
    Write-Step 'Assigning managers'
    foreach ($result in @($script:Results | Where-Object { $_.Status -eq 'Created' -and $_.UserPrincipalName })) {
        $record = $records | Where-Object UserPrincipalName -eq $result.UserPrincipalName | Select-Object -First 1
        if (-not $record.ManagerUserPrincipalName) { continue }
        try {
            $manager = Find-EntraUserByUpn -UserPrincipalName $record.ManagerUserPrincipalName
            if (-not $manager) { throw "Manager '$($record.ManagerUserPrincipalName)' was not found." }
            $uri = "https://graph.microsoft.com/v1.0/users/$($result.ObjectId)/manager/`$ref"
            $body = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($manager.Id)" }
            if ($PSCmdlet.ShouldProcess($result.UserPrincipalName, "Assign manager $($record.ManagerUserPrincipalName)")) {
                Invoke-MgGraphRequest -Method PUT -Uri $uri -Body $body -ContentType 'application/json'
                $result.ManagerStatus = 'Assigned'
            }
            else { $result.ManagerStatus = 'Planned' }
        }
        catch {
            $result.ManagerStatus = 'Failed'
            $result.Error = $_.Exception.Message
            Write-Warn "Could not assign manager to $($result.UserPrincipalName): $($_.Exception.Message)"
        }
    }

    # ─── Export Results ─────────────────────────────────────────────────────
    Export-ProvisioningResults
    $script:Results
}
catch {
    Write-Error "User provisioning stopped: $($_.Exception.Message)"
    throw
}
