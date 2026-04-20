<#!
.SYNOPSIS
    Tests Microsoft Entra enterprise applications and generates a governance report.

.DESCRIPTION
    This script evaluates enterprise applications (service principals) in Microsoft Entra ID and produces
    a detailed HTML report that highlights inventory, ownership, credential hygiene, usage, permissions,
    naming standards, and governance recommendations. The goal is to give customers a base framework
    for improving application lifecycle management and security posture.

.PARAMETER OutputPath
    Directory where the HTML report will be written. Defaults to the current directory.

.PARAMETER TenantId
    Optional tenant identifier used when establishing the Microsoft Graph connection.

.PARAMETER NamePattern
    Optional regular expression used to validate enterprise application naming standards.

.PARAMETER InactiveDaysThreshold
    Number of days without sign-in activity after which an application is considered stale.

.PARAMETER SecretWarningDays
    Number of days before credential expiry to flag a warning.

.PARAMETER SecretCriticalDays
    Number of days before credential expiry to flag a critical failure.

.EXAMPLE
    .\Test-EnterpriseApplications.ps1 -OutputPath "C:\\Reports" -NamePattern "^(APP|ENT)-[A-Z0-9-]+$"

.NOTES
    Author: Bareminimum Solutions
    Date: October 16, 2025
    Requires: Microsoft.Graph PowerShell modules
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$NamePattern,

    [Parameter(Mandatory = $false)]
    [int]$InactiveDaysThreshold = 90,

    [Parameter(Mandatory = $false)]
    [int]$SecretWarningDays = 45,

    [Parameter(Mandatory = $false)]
    [int]$SecretCriticalDays = 7
)

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications, Microsoft.Graph.Identity.DirectoryManagement

$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Applications',
    'Microsoft.Graph.Identity.DirectoryManagement'
)

Write-Host "Checking required modules..." -ForegroundColor Cyan
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing module: $module" -ForegroundColor Yellow
        Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $module -Force
}

$graphScopes = @(
    'Application.Read.All',
    'Directory.Read.All',
    'AuditLog.Read.All'
)

$testResults = @{
    TestDate          = Get-Date
    TenantInfo        = @{}
    Inventory         = @{}
    Ownership         = @{}
    Credentials       = @{}
    Naming            = @{}
    Usage             = @{}
    Permissions       = @{}
    Governance        = @{}
    Recommendations   = @{}
    Summary           = @{
        TotalTests   = 0
        PassedTests  = 0
        FailedTests  = 0
        WarningTests = 0
    }
}

$script:EnterpriseApps = @()
$script:AppsWithoutOwners = @()
$script:ExpiredCredentials = @()
$script:ExpiringCredentials = @()
$script:StaleApplications = @()
$script:NonCompliantNames = @()
$script:HighPrivilegeGrants = @()

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$TestName,
        [Parameter(Mandatory = $true)][ValidateSet('Pass','Fail','Warning')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Details,
        [Parameter(Mandatory = $false)][object]$Data
    )

    $result = @{
        TestName  = $TestName
        Status    = $Status
        Details   = $Details
        Data      = $Data
        Timestamp = Get-Date
    }

    if (-not $testResults[$Category].ContainsKey('Tests')) {
        $testResults[$Category].Tests = @()
    }

    $testResults[$Category].Tests += $result
    $testResults.Summary.TotalTests++

    switch ($Status) {
        'Pass'    { $testResults.Summary.PassedTests++ }
        'Fail'    { $testResults.Summary.FailedTests++ }
        'Warning' { $testResults.Summary.WarningTests++ }
    }
}

function Connect-ToGraph {
    param([string]$TenantId)

    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

    if ($TenantId) {
        Connect-MgGraph -Scopes $graphScopes -TenantId $TenantId
    } else {
        Connect-MgGraph -Scopes $graphScopes
    }

    $context = Get-MgContext
    Write-Host "Connected to tenant: $($context.TenantId)" -ForegroundColor Green
}

function Get-EnterpriseApplications {
    Write-Host "Collecting enterprise applications (service principals)..." -ForegroundColor Cyan

    $uri = 'https://graph.microsoft.com/beta/servicePrincipals?$filter=servicePrincipalType eq ''Application''&$select=id,displayName,appId,accountEnabled,createdDateTime,appOwnerOrganizationId,appRoleAssignmentRequired,signInActivity,passwordCredentials,keyCredentials,tags'
    $apps = @()

    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        $apps += $response.value
        $uri = $response.'@odata.nextLink'
    } while ($uri)

    $script:EnterpriseApps = $apps
    Write-Host "Retrieved $($script:EnterpriseApps.Count) enterprise applications." -ForegroundColor Green
}

function Test-Inventory {
    Write-Host "Evaluating inventory metrics..." -ForegroundColor Cyan

    $totalApps = $script:EnterpriseApps.Count
    $enabledApps = ($script:EnterpriseApps | Where-Object { $_.accountEnabled }).Count
    $disabledApps = $totalApps - $enabledApps

    $recentThreshold = (Get-Date).AddDays(-30)
    $recentApps = ($script:EnterpriseApps | Where-Object { $_.createdDateTime -and ([DateTime]$_.createdDateTime -ge $recentThreshold) }).Count

    $inventorySummary = [PSCustomObject]@{
        TotalApplications = $totalApps
        Enabled           = $enabledApps
        Disabled          = $disabledApps
        CreatedLast30Days = $recentApps
    }

    if ($totalApps -gt 0) {
        Add-TestResult -Category 'Inventory' -TestName 'Enterprise Application Inventory' -Status 'Pass' -Details "Inventory discovered. Enabled: $enabledApps, Disabled: $disabledApps, NewLast30Days: $recentApps." -Data $inventorySummary
    } else {
        Add-TestResult -Category 'Inventory' -TestName 'Enterprise Application Inventory' -Status 'Fail' -Details 'No enterprise applications were found in the tenant.' -Data $inventorySummary
    }

    $testResults.Inventory.Summary = $inventorySummary
}

function Test-Ownership {
    Write-Host "Reviewing application owners..." -ForegroundColor Cyan

    $appsWithoutOwners = @()

    foreach ($app in $script:EnterpriseApps) {
        try {
            $owners = Get-MgServicePrincipalOwner -ServicePrincipalId $app.id -All -ErrorAction Stop
            if (-not $owners) {
                $appsWithoutOwners += [PSCustomObject]@{
                    DisplayName = $app.displayName
                    AppId       = $app.appId
                    ObjectId    = $app.id
                }
            }
        }
        catch {
            Add-TestResult -Category 'Ownership' -TestName "Owner Lookup Failure: $($app.displayName)" -Status 'Warning' -Details "Could not retrieve owners for app $($app.displayName): $($_.Exception.Message)"
        }
    }

    $script:AppsWithoutOwners = $appsWithoutOwners

    if ($appsWithoutOwners.Count -eq 0) {
        Add-TestResult -Category 'Ownership' -TestName 'Ownership Coverage' -Status 'Pass' -Details 'All enterprise applications have at least one owner.'
    } else {
        $detailLines = ($appsWithoutOwners | Select-Object -First 10 | ForEach-Object { "Missing owner: $($_.DisplayName) ($($_.AppId))" }) -join "`n"
        $status = if ($appsWithoutOwners.Count -gt 0) { if ($appsWithoutOwners.Count -gt 5) { 'Fail' } else { 'Warning' } } else { 'Pass' }
        Add-TestResult -Category 'Ownership' -TestName 'Ownership Coverage' -Status $status -Details ("$($appsWithoutOwners.Count) applications lack owners.`n" + $detailLines) -Data $appsWithoutOwners
    }

    $testResults.Ownership.Summary = @{ MissingOwners = $appsWithoutOwners.Count }
}

function Test-Credentials {
    Write-Host "Assessing application credentials..." -ForegroundColor Cyan

    $now = Get-Date
    $passwordCredentialList = @()
    $certificateCredentialList = @()

    foreach ($app in $script:EnterpriseApps) {
        if ($app.passwordCredentials) {
            foreach ($cred in $app.passwordCredentials) {
                $passwordCredentialList += [PSCustomObject]@{
                    DisplayName  = $app.displayName
                    AppId        = $app.appId
                    ObjectId     = $app.id
                    CredentialId = $cred.keyId
                    Type         = 'ClientSecret'
                    EndDate      = if ($cred.endDateTime) { [DateTime]$cred.endDateTime } else { $null }
                    StartDate    = if ($cred.startDateTime) { [DateTime]$cred.startDateTime } else { $null }
                }
            }
        }

        if ($app.keyCredentials) {
            foreach ($cred in $app.keyCredentials) {
                $certificateCredentialList += [PSCustomObject]@{
                    DisplayName  = $app.displayName
                    AppId        = $app.appId
                    ObjectId     = $app.id
                    CredentialId = $cred.keyId
                    Type         = 'Certificate'
                    EndDate      = if ($cred.endDateTime) { [DateTime]$cred.endDateTime } else { $null }
                    StartDate    = if ($cred.startDateTime) { [DateTime]$cred.startDateTime } else { $null }
                }
            }
        }
    }

    $allCredentials = $passwordCredentialList + $certificateCredentialList

    foreach ($cred in $allCredentials) {
        if ($cred.EndDate) {
            $cred | Add-Member -NotePropertyName ExpiresInDays -NotePropertyValue ([math]::Round(($cred.EndDate - $now).TotalDays, 0))
        } else {
            $cred | Add-Member -NotePropertyName ExpiresInDays -NotePropertyValue $null
        }
    }

    $expired = $allCredentials | Where-Object { $_.EndDate -and $_.EndDate -lt $now }
    $expiring = $allCredentials | Where-Object { $_.EndDate -and $_.EndDate -ge $now -and ($_.EndDate - $now).TotalDays -le $SecretWarningDays }
    $critical = $allCredentials | Where-Object { $_.EndDate -and $_.EndDate -ge $now -and ($_.EndDate - $now).TotalDays -le $SecretCriticalDays }

    $script:ExpiredCredentials = $expired
    $script:ExpiringCredentials = $expiring

    $details = @()
    if ($expired.Count -gt 0) {
        $details += "$($expired.Count) expired credentials detected."
    }
    if ($expiring.Count -gt 0) {
        $details += "$($expiring.Count) credentials expire within $SecretWarningDays days."
    }
    if ($critical.Count -gt 0) {
        $details += "$($critical.Count) credentials expire within $SecretCriticalDays days (critical threshold)."
    }
    if (-not $details) {
        $details = @('No credentials are expired or nearing expiry.')
    }

    $status = if ($expired.Count -gt 0 -or $critical.Count -gt 0) { 'Fail' } elseif ($expiring.Count -gt 0) { 'Warning' } else { 'Pass' }
    Add-TestResult -Category 'Credentials' -TestName 'Credential Hygiene' -Status $status -Details ($details -join " `n") -Data $allCredentials

    $testResults.Credentials.Summary = @{
        TotalCredentials  = $allCredentials.Count
        Expired           = $expired.Count
        ExpiringSoon      = $expiring.Count
        CriticalThreshold = $critical.Count
    }
}

function Test-Naming {
    Write-Host "Validating naming conventions..." -ForegroundColor Cyan

    if (-not $NamePattern) {
        Add-TestResult -Category 'Naming' -TestName 'Naming Standard' -Status 'Warning' -Details 'No naming pattern was provided. Specify -NamePattern to enforce naming standards.'
        return
    }

    $nonCompliant = $script:EnterpriseApps | Where-Object { $_.displayName -and $_.displayName -notmatch $NamePattern }
    $script:NonCompliantNames = $nonCompliant

    if ($nonCompliant.Count -eq 0) {
        Add-TestResult -Category 'Naming' -TestName 'Naming Standard' -Status 'Pass' -Details 'All enterprise applications comply with the provided naming pattern.'
    } else {
        $examples = ($nonCompliant | Select-Object -First 10 | ForEach-Object { "Non-compliant: $($_.displayName)" }) -join "`n"
        Add-TestResult -Category 'Naming' -TestName 'Naming Standard' -Status 'Warning' -Details ("$($nonCompliant.Count) applications do not match the naming pattern $NamePattern.`n" + $examples) -Data $nonCompliant
    }

    $testResults.Naming.Summary = @{ NonCompliant = $nonCompliant.Count }
}

function Test-Usage {
    Write-Host "Reviewing application usage patterns..." -ForegroundColor Cyan

    $now = Get-Date
    $staleApps = @()

    foreach ($app in $script:EnterpriseApps) {
        $lastSignIn = $null
        if ($app.signInActivity -and $app.signInActivity.lastSignInDateTime) {
            $lastSignIn = [DateTime]$app.signInActivity.lastSignInDateTime
        }

        $createdDate = if ($app.createdDateTime) { [DateTime]$app.createdDateTime } else { $null }

        if (-not $lastSignIn) {
            if ($createdDate -and ($now - $createdDate).TotalDays -le 14) {
                continue
            }
            $staleApps += [PSCustomObject]@{
                DisplayName     = $app.displayName
                AppId           = $app.appId
                ObjectId        = $app.id
                LastSignIn      = $null
                CreatedDate     = $createdDate
                DaysSinceSignIn = $null
            }
        } else {
            $daysSince = ($now - $lastSignIn).TotalDays
            if ($daysSince -gt $InactiveDaysThreshold) {
                $staleApps += [PSCustomObject]@{
                    DisplayName     = $app.displayName
                    AppId           = $app.appId
                    ObjectId        = $app.id
                    LastSignIn      = $lastSignIn
                    CreatedDate     = $createdDate
                    DaysSinceSignIn = [math]::Round($daysSince,0)
                }
            }
        }
    }

    $script:StaleApplications = $staleApps

    if ($staleApps.Count -eq 0) {
        Add-TestResult -Category 'Usage' -TestName 'Inactive Applications' -Status 'Pass' -Details "No applications exceeded $InactiveDaysThreshold days without sign-in activity."
    } else {
        $detailLines = ($staleApps | Select-Object -First 10 | ForEach-Object {
            $lastSeen = if ($_.LastSignIn) { $_.LastSignIn.ToString('yyyy-MM-dd') } else { 'Never' }
            "Inactive: $($_.DisplayName) - LastSignIn: $lastSeen"
        }) -join "`n"
        Add-TestResult -Category 'Usage' -TestName 'Inactive Applications' -Status 'Warning' -Details ("$($staleApps.Count) applications show no sign-in within $InactiveDaysThreshold days.`n" + $detailLines) -Data $staleApps
    }

    $testResults.Usage.Summary = @{ StaleApplications = $staleApps.Count }
}

function Test-Permissions {
    Write-Host "Reviewing consented permissions..." -ForegroundColor Cyan

    $permissionGrants = @()
    $uri = 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants?$select=id,clientId,consentType,scope,resourceId,principalId'

    try {
        do {
            $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
            $permissionGrants += $response.value
            $uri = $response.'@odata.nextLink'
        } while ($uri)
    }
    catch {
        Add-TestResult -Category 'Permissions' -TestName 'Permission Grant Access' -Status 'Warning' -Details "Unable to retrieve OAuth permission grants: $($_.Exception.Message)"
        return
    }

    $appLookup = @{}
    foreach ($app in $script:EnterpriseApps) {
        $appLookup[$app.id] = $app
    }

    $highPrivilegeScopes = @(
        'Directory.AccessAsUser.All',
        'Directory.ReadWrite.All',
        'Directory.Read.All',
        'Group.ReadWrite.All',
        'RoleManagement.ReadWrite.Directory',
        'Policy.ReadWrite.ApplicationConfiguration',
        'Application.ReadWrite.All',
        'AppRoleAssignment.ReadWrite.All'
    )

    $adminConsents = $permissionGrants | Where-Object { $_.consentType -eq 'AllPrincipals' }
    $flagged = @()

    foreach ($grant in $adminConsents) {
        $scopes = @()
        if ($grant.scope) {
            $scopes = $grant.scope -split ' '
        }
        $matchedScopes = $scopes | Where-Object { $highPrivilegeScopes -contains $_ }
        if ($matchedScopes) {
            $app = $appLookup[$grant.clientId]
            if ($app) {
                $flagged += [PSCustomObject]@{
                    DisplayName = $app.displayName
                    AppId       = $app.appId
                    ObjectId    = $app.id
                    Scopes      = ($matchedScopes -join ', ')
                }
            }
        }
    }

    $script:HighPrivilegeGrants = $flagged

    if ($flagged.Count -eq 0) {
        Add-TestResult -Category 'Permissions' -TestName 'High Privilege Consents' -Status 'Pass' -Details 'No admin-consented high privilege delegated permissions were detected.'
    } else {
        $examples = ($flagged | Select-Object -First 10 | ForEach-Object { "High privilege consent: $($_.DisplayName) -> $($_.Scopes)" }) -join "`n"
        Add-TestResult -Category 'Permissions' -TestName 'High Privilege Consents' -Status 'Warning' -Details ("$($flagged.Count) applications hold tenant-wide high privilege scopes.`n" + $examples) -Data $flagged
    }

    $testResults.Permissions.Summary = @{ HighPrivilegeConsents = $flagged.Count }
}

function Test-Governance {
    Write-Host "Assessing governance signals..." -ForegroundColor Cyan

    $disabledApps = $script:EnterpriseApps | Where-Object { $_.accountEnabled -eq $false }
    $appsRequiringAssignment = $script:EnterpriseApps | Where-Object { $_.appRoleAssignmentRequired -eq $true }

    $details = @(
        "Disabled applications: $($disabledApps.Count)",
        "Applications requiring assignments: $($appsRequiringAssignment.Count)"
    )

    Add-TestResult -Category 'Governance' -TestName 'Governance Snapshot' -Status 'Pass' -Details ($details -join ' | ') -Data @{
        DisabledApps            = $disabledApps
        AssignmentRequiredApps  = $appsRequiringAssignment
    }

    $testResults.Governance.Summary = @{
        DisabledApps           = $disabledApps.Count
        AssignmentRequiredApps = $appsRequiringAssignment.Count
    }
}

function Build-Recommendations {
    Write-Host "Building recommendations..." -ForegroundColor Cyan

    $recommendations = @()

    if ($script:AppsWithoutOwners.Count -gt 0) {
        $recommendations += "Assign owners to $($script:AppsWithoutOwners.Count) ownerless applications to improve accountability."
    }
    if ($script:ExpiredCredentials.Count -gt 0) {
        $recommendations += "Rotate $($script:ExpiredCredentials.Count) expired credentials immediately to restore connectivity." 
    }
    elseif ($script:ExpiringCredentials.Count -gt 0) {
        $recommendations += "Plan rotation for $($script:ExpiringCredentials.Count) credentials expiring in the next $SecretWarningDays days." 
    }
    if ($script:StaleApplications.Count -gt 0) {
        $recommendations += "Review $($script:StaleApplications.Count) inactive applications for retirement or revalidation." 
    }
    if ($NamePattern -and $script:NonCompliantNames.Count -gt 0) {
        $recommendations += "Rename $($script:NonCompliantNames.Count) applications that do not match the naming convention $NamePattern." 
    }
    if ($script:HighPrivilegeGrants.Count -gt 0) {
        $recommendations += "Reassess high privilege delegated consents granted to $($script:HighPrivilegeGrants.Count) applications." 
    }

    if (-not $recommendations) {
        $recommendations = @('No critical remediation items detected. Maintain periodic reviews to keep governance healthy.')
    }

    Add-TestResult -Category 'Recommendations' -TestName 'Actionable Next Steps' -Status 'Pass' -Details ($recommendations -join " `n")
    $testResults.Recommendations.Summary = @{ Count = $recommendations.Count }
}

function Generate-HTMLReport {
    param(
        [Parameter(Mandatory = $true)][object]$Results,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $fileName = "EnterpriseAppReport_$timestamp.html"
    $fullPath = Join-Path -Path $OutputPath -ChildPath $fileName

    $summary = $Results.Summary
    $tenantId = if ($Results.TenantInfo.TenantId) { $Results.TenantInfo.TenantId } else { (Get-MgContext).TenantId }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <title>Enterprise Application Governance Report</title>
    <style>
        body { font-family: Segoe UI, Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background: #ffffff; padding: 32px; box-shadow: 0 0 12px rgba(0,0,0,0.08); }
        h1 { color: #0b6aa2; border-bottom: 3px solid #0b6aa2; padding-bottom: 12px; }
        h2 { color: #0b6aa2; margin-top: 36px; border-left: 4px solid #0b6aa2; padding-left: 10px; }
        .summary-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin: 24px 0; }
        .summary-card { background: linear-gradient(135deg, #0078d4 0%, #005a9e 100%); color: #ffffff; padding: 20px; border-radius: 8px; text-align: center; }
        .summary-card h3 { margin: 0; font-size: 2em; }
        .summary-card p { margin: 8px 0 0; font-size: 0.95em; }
        .pass { background: linear-gradient(135deg, #2f9d59 0%, #3ecf7f 100%); }
        .warning { background: linear-gradient(135deg, #f59e0b 0%, #fbbf24 100%); }
        .fail { background: linear-gradient(135deg, #dc2626 0%, #f87171 100%); }
        table { width: 100%; border-collapse: collapse; margin-top: 16px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #0b6aa2; color: #ffffff; text-align: left; padding: 12px; }
        td { padding: 12px; border-bottom: 1px solid #e5e7eb; vertical-align: top; }
        tr:nth-child(even) { background-color: #f9fafb; }
        .status-pass { color: #2f9d59; font-weight: 600; }
        .status-fail { color: #dc2626; font-weight: 600; }
        .status-warning { color: #f59e0b; font-weight: 600; }
        .footer { margin-top: 40px; text-align: center; color: #6b7280; font-size: 0.9em; border-top: 1px solid #d1d5db; padding-top: 16px; }
        .badge { padding: 4px 8px; border-radius: 12px; font-size: 0.8em; font-weight: 600; }
        .badge-pass { background-color: #d1fae5; color: #047857; }
        .badge-fail { background-color: #fee2e2; color: #b91c1c; }
        .badge-warning { background-color: #fef3c7; color: #b45309; }
        pre { margin: 0; white-space: pre-wrap; font-size: 0.9em; font-family: "Segoe UI", Arial, sans-serif; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Enterprise Application Governance Report</h1>
        <p><strong>Generated:</strong> $($Results.TestDate.ToString('yyyy-MM-dd HH:mm:ss'))</p>
        <p><strong>Tenant ID:</strong> $tenantId</p>

        <div class="summary-grid">
            <div class="summary-card">
                <h3>$($summary.TotalTests)</h3>
                <p>Total Checks</p>
            </div>
            <div class="summary-card pass">
                <h3>$($summary.PassedTests)</h3>
                <p>Passing</p>
            </div>
            <div class="summary-card fail">
                <h3>$($summary.FailedTests)</h3>
                <p>Failing</p>
            </div>
            <div class="summary-card warning">
                <h3>$($summary.WarningTests)</h3>
                <p>Warnings</p>
            </div>
        </div>
"@

    $categories = @(
        @{ Name = 'Inventory'; Title = 'Inventory Overview' },
        @{ Name = 'Ownership'; Title = 'Ownership and Accountability' },
        @{ Name = 'Credentials'; Title = 'Credential Hygiene' },
        @{ Name = 'Naming'; Title = 'Naming and Classification' },
        @{ Name = 'Usage'; Title = 'Usage and Activity' },
        @{ Name = 'Permissions'; Title = 'Permissions and Consents' },
        @{ Name = 'Governance'; Title = 'Governance Indicators' },
        @{ Name = 'Recommendations'; Title = 'Actionable Recommendations' }
    )

    foreach ($category in $categories) {
        $tests = $Results[$category.Name].Tests
        if (-not $tests) { continue }

        $html += @"
        <div class="test-category">
            <h2>$($category.Title)</h2>
            <table>
                <thead>
                    <tr>
                        <th>Check</th>
                        <th>Status</th>
                        <th>Details</th>
                    </tr>
                </thead>
                <tbody>
"@

        foreach ($test in $tests) {
            $statusClass = "status-$($test.Status.ToLower())"
            $badgeClass = "badge-$($test.Status.ToLower())"
            $details = [System.Net.WebUtility]::HtmlEncode($test.Details)
            $details = $details -replace "`n", "<br />"

            $html += @"
                    <tr>
                        <td>$($test.TestName)</td>
                        <td><span class="badge $badgeClass">$($test.Status)</span></td>
                        <td><pre>$details</pre></td>
                    </tr>
"@
        }

        $html += @"
                </tbody>
            </table>
        </div>
"@
    }

    $html += @"
        <div class="footer">
            Bareminimum Solutions &middot; Enterprise Application Governance Framework &middot; $([DateTime]::UtcNow.ToString('yyyy'))
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $fullPath -Encoding UTF8
    Write-Host "Report generated: $fullPath" -ForegroundColor Green
    return $fullPath
}

try {
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "Enterprise Application Testing Framework" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan

    Connect-ToGraph -TenantId $TenantId

    $context = Get-MgContext
    $testResults.TenantInfo = @{
        TenantId = $context.TenantId
        Account  = $context.Account
        Scopes   = $context.Scopes
    }

    Get-EnterpriseApplications
    Test-Inventory
    Test-Ownership
    Test-Credentials
    Test-Naming
    Test-Usage
    Test-Permissions
    Test-Governance
    Build-Recommendations

    Write-Host "Generating HTML report..." -ForegroundColor Cyan
    $reportPath = Generate-HTMLReport -Results $testResults -OutputPath $OutputPath

    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "Summary" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "Total Checks : $($testResults.Summary.TotalTests)" -ForegroundColor White
    Write-Host "Passing      : $($testResults.Summary.PassedTests)" -ForegroundColor Green
    Write-Host "Warnings     : $($testResults.Summary.WarningTests)" -ForegroundColor Yellow
    Write-Host "Failing      : $($testResults.Summary.FailedTests)" -ForegroundColor Red
    Write-Host "Report saved : $reportPath" -ForegroundColor Cyan

    $openReport = Read-Host "Open the report now? (Y/N)"
    if ($openReport -match '^[Yy]$') {
        Start-Process $reportPath
    }
}
catch {
    Write-Host "Error during execution: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
}
finally {
    Write-Host "Disconnecting from Microsoft Graph..." -ForegroundColor Cyan
    Disconnect-MgGraph
}
