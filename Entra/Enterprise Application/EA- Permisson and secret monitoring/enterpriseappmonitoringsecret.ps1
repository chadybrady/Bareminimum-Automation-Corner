#Created by Tim Hjort, 2024
#Requirements#
# 1. Create a new Automation Account in Azure
# 2. Create a new Runbook in the Automation Account
# 3. Add the script to the Runbook
# 4. Create the following variables in the Automation Account:
#    - TenantID
#    - msgraph-clientcred-appid
#    - msgraph-clientcred-appsecret (IMPORTANT: Create as an ENCRYPTED variable)
#    - TeamsChannelUri
#    - TimeZoneId (Optional - defaults to 'Central Standard Time')
# 5. Create a new schedule in the Automation Account
# 6. Add the Runbook to the schedule
# 7. Run the schedule
# 8. Monitor the Teams channel for alerts
# 9. Enjoy

#Enterprise app requirements and permissions needed:
# 1. The script requires the following permissions:
# Application.Read.All
# Directory.Read.All
# User.Read.All

# Security Note: Consider using Managed Identity instead of client secrets for the
# Automation Account itself. This eliminates the need to manage the app secret rotation.
# See: https://learn.microsoft.com/en-us/azure/automation/enable-managed-identity-for-automation


##Change these variables to customize the report using $False or $True
$UserIncludeSecrets = $true
$UserIncludeCertificates = $true
$UserIncludeAPIPermissions = $true
$UserIncludeUserGroupAssignments = $true
$SkipNotificationIfNoExpiring = $false  # Set to $true to skip Teams notification when nothing is expiring
##

# Token expiration tracking
$script:TokenExpiresAt = $null
$script:CurrentAccessToken = $null

$TenantID = Get-AutomationVariable -Name 'TenantID'
$AppID = Get-AutomationVariable -Name "msgraph-clientcred-appid"
$AppSecret = Get-AutomationVariable -Name "msgraph-clientcred-appsecret"
$TeamsWebhookUri = Get-AutomationVariable -Name "TeamsChannelUri"

# Try to get optional timezone variable, default to Central Standard Time
try {
    $TimeZoneId = Get-AutomationVariable -Name 'TimeZoneId' -ErrorAction Stop
} catch {
    $TimeZoneId = 'Central Standard Time'
    Write-Verbose "TimeZoneId variable not found, using default: $TimeZoneId"
}

$expirationThresholdInDays = 30

Function Connect-MSGraphAPI {
    param (
        [Parameter(Mandatory = $true)][string]$AppID,
        [Parameter(Mandatory = $true)][string]$TenantID,
        [Parameter(Mandatory = $true)][string]$AppSecret
    )
    begin {
        $TokenUri = "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token"
        $ReqTokenBody = @{
            Grant_Type    = "client_credentials"
            Scope         = "https://graph.microsoft.com/.default"
            client_Id     = $AppID
            Client_Secret = $AppSecret
        } 
    }
    Process {
        try {
            Write-Host "Connecting to the Graph API"
            $Response = Invoke-RestMethod -Uri $TokenUri -Method POST -Body $ReqTokenBody -ErrorAction Stop
            
            # Set token expiration (subtract 5 minutes for safety margin)
            $script:TokenExpiresAt = (Get-Date).AddSeconds($Response.expires_in - 300)
            $script:CurrentAccessToken = $Response.access_token
            
            return $Response
        }
        catch {
            Write-Error "Failed to connect to Microsoft Graph API: $($_.Exception.Message)"
            throw
        }
    }
}

Function Test-TokenExpired {
    if ($null -eq $script:TokenExpiresAt) {
        return $true
    }
    return (Get-Date) -ge $script:TokenExpiresAt
}

Function Get-ValidAccessToken {
    param (
        [Parameter(Mandatory = $true)][string]$AppID,
        [Parameter(Mandatory = $true)][string]$TenantID,
        [Parameter(Mandatory = $true)][string]$AppSecret
    )
    
    if (Test-TokenExpired) {
        Write-Host "Token expired or not available, refreshing..."
        $tokenResponse = Connect-MSGraphAPI -AppID $AppID -TenantID $TenantID -AppSecret $AppSecret
        return $tokenResponse.access_token
    }
    return $script:CurrentAccessToken
}

Function Invoke-GraphAPIWithRetry {
    param (
        [Parameter(Mandatory = $true)][hashtable]$RequestParams,
        [int]$MaxRetries = 3,
        [int]$BaseDelaySeconds = 5
    )
    
    $retryCount = 0
    while ($retryCount -lt $MaxRetries) {
        try {
            $result = Invoke-RestMethod @RequestParams -ErrorAction Stop
            return $result
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            
            # Handle throttling (429) and server errors (5xx)
            if ($statusCode -eq 429 -or ($statusCode -ge 500 -and $statusCode -lt 600)) {
                $retryCount++
                $delay = $BaseDelaySeconds * [Math]::Pow(2, $retryCount)
                
                # Check for Retry-After header
                $retryAfter = $_.Exception.Response.Headers['Retry-After']
                if ($retryAfter) {
                    $delay = [int]$retryAfter
                }
                
                Write-Warning "Request throttled or server error (attempt $retryCount of $MaxRetries). Waiting $delay seconds..."
                Start-Sleep -Seconds $delay
            }
            else {
                # Non-retryable error
                throw
            }
        }
    }
    
    throw "Max retries ($MaxRetries) exceeded for Graph API request"
}

Function Get-MSGraphRequest {
    param (
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$AccessToken
    )
    begin {
        $allPages = [System.Collections.Generic.List[object]]::new()
        $ReqTokenBody = @{
            Headers = @{
                "Content-Type"  = "application/json"
                "Authorization" = "Bearer $($AccessToken)"
            }
            Method  = "Get"
            Uri     = $Uri
        }
    }
    process {
        try {
            Write-Verbose "GET request at endpoint: $Uri"
            $data = Invoke-GraphAPIWithRetry -RequestParams $ReqTokenBody
            
            while ($data.'@odata.nextLink') {
                if ($data.value) {
                    foreach ($item in $data.value) {
                        $allPages.Add($item)
                    }
                }
                $ReqTokenBody.Uri = $data.'@odata.nextLink'
                $data = Invoke-GraphAPIWithRetry -RequestParams $ReqTokenBody
                # Rate limiting protection
                Start-Sleep -Milliseconds 500
            }
            
            if ($data.value) {
                foreach ($item in $data.value) {
                    $allPages.Add($item)
                }
            }
        }
        catch {
            Write-Error "Failed to retrieve data from Graph API ($Uri): $($_.Exception.Message)"
            throw
        }
    }
    end {
        Write-Verbose "Returning $($allPages.Count) results"
        return $allPages
    }
}

$script:ServicePrincipalCache = @{}
Function Get-ServicePrincipalByAppId {
    param (
        [Parameter(Mandatory = $true)][string]$AppId,
        [Parameter(Mandatory = $true)][string]$AccessToken
    )

    if ([string]::IsNullOrWhiteSpace($AppId)) {
        return $null
    }

    if ($script:ServicePrincipalCache.ContainsKey($AppId)) {
        return $script:ServicePrincipalCache[$AppId]
    }

    try {
        $uri = 'https://graph.microsoft.com/v1.0/servicePrincipals?$filter=appId eq ''{0}''&$select=id,displayName,appId,appRoles,oauth2PermissionScopes,appRoleAssignmentRequired' -f $AppId
        $servicePrincipal = Get-MSGraphRequest -AccessToken $AccessToken -Uri $uri | Select-Object -First 1
        $script:ServicePrincipalCache[$AppId] = $servicePrincipal
        return $servicePrincipal
    }
    catch {
        Write-Warning "Failed to retrieve service principal for AppId $AppId : $($_.Exception.Message)"
        return $null
    }
}

# Initial token acquisition with validation
try {
    $tokenResponse = Connect-MSGraphAPI -AppID $AppID -TenantID $TenantID -AppSecret $AppSecret
    
    if (-not $tokenResponse.access_token) {
        throw "Failed to obtain access token - response did not contain access_token"
    }
    
    Write-Host "Successfully authenticated to Microsoft Graph API"
}
catch {
    Write-Error "Authentication failed: $($_.Exception.Message)"
    throw "Cannot continue without valid authentication"
}

# Initialize result collections using List for better performance
$results = [System.Collections.Generic.List[object]]::new()
$permissionRows = [System.Collections.Generic.List[object]]::new()
$assignmentRows = [System.Collections.Generic.List[object]]::new()

# Get all applications
try {
    $applications = Get-MSGraphRequest -AccessToken $tokenResponse.access_token -Uri "https://graph.microsoft.com/v1.0/applications/"
    Write-Host "Retrieved $($applications.Count) applications"
}
catch {
    Write-Error "Failed to retrieve applications: $($_.Exception.Message)"
    throw
}

$currentTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, $TimeZoneId)

foreach ($app in $applications | Sort-Object displayName) {
    # Refresh token if needed before processing each app
    $currentAccessToken = Get-ValidAccessToken -AppID $AppID -TenantID $TenantID -AppSecret $AppSecret
    
    # Process password credentials (secrets)
    $passwordCreds = $app.passwordCredentials | Where-Object { $_.endDateTime }
    
    # Process key credentials (certificates)
    $keyCreds = $app.keyCredentials | Where-Object { $_.endDateTime }
    
    if (-not $passwordCreds -and -not $keyCreds) {
        continue
    }

    $expiringSecrets = [System.Collections.Generic.List[object]]::new()
    $expiringCertificates = [System.Collections.Generic.List[object]]::new()
    
    # Check expiring secrets
    foreach ($cred in $passwordCreds) {
        $endDate = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]$cred.endDateTime, $TimeZoneId)
        if ($endDate -is [system.array]) {
            $endDate = $endDate[0]
        }

        $timeSpan = New-TimeSpan -Start $currentTime -End $endDate
        $daysUntilExpiration = [int][Math]::Floor($timeSpan.TotalDays)
        if ($daysUntilExpiration -le $expirationThresholdInDays) {
            $expiringSecrets.Add([PSCustomObject]@{
                KeyId      = $cred.KeyId
                EndDate    = $endDate
                DaysUntil  = $daysUntilExpiration
                Type       = 'Secret'
                Hint       = $cred.hint
            })
        }
    }
    
    # Check expiring certificates
    foreach ($cred in $keyCreds) {
        $endDate = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]$cred.endDateTime, $TimeZoneId)
        if ($endDate -is [system.array]) {
            $endDate = $endDate[0]
        }

        $timeSpan = New-TimeSpan -Start $currentTime -End $endDate
        $daysUntilExpiration = [int][Math]::Floor($timeSpan.TotalDays)
        if ($daysUntilExpiration -le $expirationThresholdInDays) {
            $expiringCertificates.Add([PSCustomObject]@{
                KeyId       = $cred.KeyId
                EndDate     = $endDate
                DaysUntil   = $daysUntilExpiration
                Type        = 'Certificate'
                DisplayName = $cred.displayName
                Thumbprint  = if ($cred.customKeyIdentifier) { [System.Convert]::ToBase64String($cred.customKeyIdentifier) } else { 'N/A' }
            })
        }
    }

    if ($expiringSecrets.Count -eq 0 -and $expiringCertificates.Count -eq 0) {
        continue
    }

    # Get owners
    try {
        $ownerUri = 'https://graph.microsoft.com/v1.0/applications/{0}/owners?$select=displayName,userPrincipalName,mail' -f $app.id
        $owners = Get-MSGraphRequest -AccessToken $currentAccessToken -Uri $ownerUri
        $ownerDisplay = if ($owners -and $owners.Count -gt 0) {
            ($owners | ForEach-Object {
                if ($_.userPrincipalName) {
                    "{0} ({1})" -f $_.displayName, $_.userPrincipalName
                }
                elseif ($_.mail) {
                    "{0} ({1})" -f $_.displayName, $_.mail
                }
                else {
                    $_.displayName
                }
            }) -join ', '
        }
        else {
            'No owners assigned'
        }
    }
    catch {
        Write-Warning "Failed to retrieve owners for app $($app.displayName): $($_.Exception.Message)"
        $ownerDisplay = 'Error retrieving owners'
    }

    $servicePrincipal = Get-ServicePrincipalByAppId -AppId $app.appId -AccessToken $currentAccessToken
    $isRequired = if ($servicePrincipal -and $servicePrincipal.appRoleAssignmentRequired) { 'Yes' } else { 'No' }
    $localDelegatedPermissions = [System.Collections.Generic.List[string]]::new()
    $localApplicationPermissions = [System.Collections.Generic.List[string]]::new()

    if ($app.requiredResourceAccess) {
        foreach ($resource in $app.requiredResourceAccess) {
            if (-not $resource.resourceAccess) {
                continue
            }

            $resourceSp = Get-ServicePrincipalByAppId -AppId $resource.resourceAppId -AccessToken $currentAccessToken
            $resourceName = if ($resourceSp -and $resourceSp.displayName) { $resourceSp.displayName } else { $resource.resourceAppId }

            foreach ($permission in $resource.resourceAccess) {
                switch ($permission.type) {
                    'Scope' {
                        $permissionName = $permission.id
                        if ($resourceSp -and $resourceSp.oauth2PermissionScopes) {
                            $scope = $resourceSp.oauth2PermissionScopes | Where-Object { $_.id -eq $permission.id }
                            if ($scope) {
                                $permissionName = $scope.adminConsentDisplayName
                                if (-not $permissionName) { $permissionName = $scope.value }
                            }
                        }
                        if (-not $permissionName) { $permissionName = $permission.id }

                        $localDelegatedPermissions.Add("{0}: {1}" -f $resourceName, $permissionName)
                        $permissionRows.Add([PSCustomObject]@{
                            AppDisplayName  = $app.displayName
                            Resource        = $resourceName
                            PermissionType  = 'Delegated'
                            PermissionName  = $permissionName
                        })
                    }
                    'Role' {
                        $permissionName = $permission.id
                        if ($resourceSp -and $resourceSp.appRoles) {
                            $role = $resourceSp.appRoles | Where-Object { $_.id -eq $permission.id }
                            if ($role) {
                                $permissionName = $role.displayName
                                if (-not $permissionName) { $permissionName = $role.value }
                            }
                        }
                        if (-not $permissionName) { $permissionName = $permission.id }

                        $localApplicationPermissions.Add("{0}: {1}" -f $resourceName, $permissionName)
                        $permissionRows.Add([PSCustomObject]@{
                            AppDisplayName  = $app.displayName
                            Resource        = $resourceName
                            PermissionType  = 'Application'
                            PermissionName  = $permissionName
                        })
                    }
                }
            }
        }
    }

    $localAssignments = [System.Collections.Generic.List[string]]::new()
    if ($servicePrincipal) {
        try {
            $assignmentUri = 'https://graph.microsoft.com/v1.0/servicePrincipals/{0}/appRoleAssignedTo?$select=principalId,principalDisplayName,principalType,appRoleId' -f $servicePrincipal.id
            $assignments = Get-MSGraphRequest -AccessToken $currentAccessToken -Uri $assignmentUri
            foreach ($assignment in $assignments) {
                $principalName = if ($assignment.principalDisplayName) { $assignment.principalDisplayName } else { $assignment.principalId }
                $roleLabel = $null
                if ($assignment.appRoleId -and $servicePrincipal.appRoles) {
                    $roleMatch = $servicePrincipal.appRoles | Where-Object { $_.id -eq $assignment.appRoleId }
                    if ($roleMatch) {
                        $roleLabel = $roleMatch.displayName
                        if (-not $roleLabel) { $roleLabel = $roleMatch.value }
                    }
                }
                if (-not $roleLabel) {
                    $roleLabel = 'Default'
                }

                $localAssignments.Add("{0} ({1}) - {2}" -f $principalName, $assignment.principalType, $roleLabel)
                $assignmentRows.Add([PSCustomObject]@{
                    AppDisplayName        = $app.displayName
                    PrincipalType         = $assignment.principalType
                    PrincipalDisplayName  = $principalName
                    Role                  = $roleLabel
                })
            }
        }
        catch {
            Write-Warning "Failed to retrieve assignments for app $($app.displayName): $($_.Exception.Message)"
        }
    }

    $delegatedSummary = if ($localDelegatedPermissions.Count -gt 0) { ($localDelegatedPermissions | Sort-Object -Unique) -join '; ' } else { 'None' }
    $applicationSummary = if ($localApplicationPermissions.Count -gt 0) { ($localApplicationPermissions | Sort-Object -Unique) -join '; ' } else { 'None' }
    $assignmentSummary = if ($localAssignments.Count -gt 0) { ($localAssignments | Sort-Object -Unique) -join '; ' } else { 'None' }

    # Add expiring secrets to results
    foreach ($secret in $expiringSecrets | Sort-Object DaysUntil, EndDate) {
        $daysUntilValue = if ($secret.DaysUntil -is [system.array]) { [int]$secret.DaysUntil[0] } else { [int]$secret.DaysUntil }

        $results.Add([PSCustomObject]@{
            AppId                  = $app.id
            DisplayName            = $app.displayName
            CredentialType         = 'Secret'
            CredentialKeyId        = $secret.KeyId
            CredentialHint         = $secret.Hint
            DaysUntil              = $daysUntilValue
            Expiration             = $secret.EndDate.ToString('yyyy-MM-dd HH:mm')
            Owners                 = $ownerDisplay
            IsRequired             = $isRequired
            DelegatedPermissions   = $delegatedSummary
            ApplicationPermissions = $applicationSummary
            Assignments            = $assignmentSummary
        })
    }
    
    # Add expiring certificates to results
    foreach ($cert in $expiringCertificates | Sort-Object DaysUntil, EndDate) {
        $daysUntilValue = if ($cert.DaysUntil -is [system.array]) { [int]$cert.DaysUntil[0] } else { [int]$cert.DaysUntil }

        $results.Add([PSCustomObject]@{
            AppId                  = $app.id
            DisplayName            = $app.displayName
            CredentialType         = 'Certificate'
            CredentialKeyId        = $cert.KeyId
            CredentialHint         = $cert.DisplayName
            DaysUntil              = $daysUntilValue
            Expiration             = $cert.EndDate.ToString('yyyy-MM-dd HH:mm')
            Owners                 = $ownerDisplay
            IsRequired             = $isRequired
            DelegatedPermissions   = $delegatedSummary
            ApplicationPermissions = $applicationSummary
            Assignments            = $assignmentSummary
        })
    }
}

# Check if we should skip notification when nothing is expiring
if ($SkipNotificationIfNoExpiring -and $results.Count -eq 0) {
    Write-Host "No expiring credentials found within $expirationThresholdInDays days. Skipping notification."
    return
}

# Build sections for the Teams message
$sections = [System.Collections.Generic.List[object]]::new()

if ($UserIncludeSecrets -eq $true) {
    $secretResults = $results | Where-Object { $_.CredentialType -eq 'Secret' }
    if ($secretResults) {
        $secretTable = ($secretResults |
            Sort-Object DisplayName, DaysUntil |
            Select-Object DisplayName, CredentialKeyId, @{Name = 'DaysUntil'; Expression = { [string]$_.DaysUntil }}, Expiration, Owners, IsRequired |
            ConvertTo-Html -Fragment | Out-String).Trim()

        $sections.Add(@{
            Title   = 'Expiring Secrets'
            Content = $secretTable
        })
    }
}

if ($UserIncludeCertificates -eq $true) {
    $certResults = $results | Where-Object { $_.CredentialType -eq 'Certificate' }
    if ($certResults) {
        $certTable = ($certResults |
            Sort-Object DisplayName, DaysUntil |
            Select-Object DisplayName, CredentialKeyId, CredentialHint, @{Name = 'DaysUntil'; Expression = { [string]$_.DaysUntil }}, Expiration, Owners, IsRequired |
            ConvertTo-Html -Fragment | Out-String).Trim()

        $sections.Add(@{
            Title   = 'Expiring Certificates'
            Content = $certTable
        })
    }
}

if ($UserIncludeAPIPermissions -eq $true) {
    if ($permissionRows.Count -gt 0) {
        $permissionTable = ($permissionRows |
            Sort-Object AppDisplayName, PermissionType, Resource, PermissionName |
            ConvertTo-Html -Fragment | Out-String).Trim()

        $sections.Add(@{
            Title   = 'API Permissions'
            Content = $permissionTable
        })
    }
}

if ($UserIncludeUserGroupAssignments -eq $true) {
    if ($assignmentRows.Count -gt 0) {
        $assignmentTable = ($assignmentRows |
            Sort-Object AppDisplayName, PrincipalType, PrincipalDisplayName |
            ConvertTo-Html -Fragment | Out-String).Trim()

        $sections.Add(@{
            Title   = 'User and Group Assignments'
            Content = $assignmentTable
        })
    }
}

# Count statistics
$secretCount = ($results | Where-Object { $_.CredentialType -eq 'Secret' }).Count
$certCount = ($results | Where-Object { $_.CredentialType -eq 'Certificate' }).Count
$totalCredCount = $results.Count
$uniqueApps = @($results | Select-Object -ExpandProperty DisplayName -Unique)
$appCount = $uniqueApps.Count

# Build Adaptive Card for Teams (modern format replacing deprecated MessageCard)
$adaptiveCardBody = [System.Collections.Generic.List[object]]::new()

# Header
$adaptiveCardBody.Add(@{
    type = "TextBlock"
    size = "Large"
    weight = "Bolder"
    text = "Credential Expiration Alert"
    wrap = $true
})

# Summary
$summaryText = "$totalCredCount credential(s) ($secretCount secret(s), $certCount certificate(s)) across $appCount app(s) expiring within $expirationThresholdInDays days"
$adaptiveCardBody.Add(@{
    type = "TextBlock"
    text = $summaryText
    wrap = $true
    spacing = "Medium"
})

# Add sections
if ($sections.Count -gt 0) {
    foreach ($section in $sections) {
        $adaptiveCardBody.Add(@{
            type = "TextBlock"
            text = "**$($section.Title)**"
            wrap = $true
            spacing = "Large"
            weight = "Bolder"
        })
        
        # For HTML content, we need to simplify for Adaptive Cards
        # Convert HTML table to a more readable format
        $adaptiveCardBody.Add(@{
            type = "TextBlock"
            text = $section.Content
            wrap = $true
            spacing = "Small"
        })
    }
} else {
    $adaptiveCardBody.Add(@{
        type = "TextBlock"
        text = "No expiring credentials within the configured window."
        wrap = $true
        spacing = "Medium"
    })
}

# Build the Adaptive Card structure
$adaptiveCard = @{
    type = "message"
    attachments = @(
        @{
            contentType = "application/vnd.microsoft.card.adaptive"
            contentUrl = $null
            content = @{
                '$schema' = "http://adaptivecards.io/schemas/adaptive-card.json"
                type = "AdaptiveCard"
                version = "1.4"
                body = $adaptiveCardBody
                msteams = @{
                    width = "Full"
                }
            }
        }
    )
}

$TeamMessageBody = ConvertTo-Json $adaptiveCard -Depth 10

try {
    $parameters = @{
        "URI"         = $TeamsWebhookUri
        "Method"      = 'POST'
        "Body"        = $TeamMessageBody
        "ContentType" = 'application/json'
    }

    $response = Invoke-RestMethod @parameters -ErrorAction Stop
    Write-Host "Successfully sent notification to Teams channel"
}
catch {
    Write-Error "Failed to send Teams notification: $($_.Exception.Message)"
    
    # Fallback to legacy MessageCard format if Adaptive Card fails
    Write-Host "Attempting fallback to legacy MessageCard format..."
    
    $textTable = if ($sections.Count -gt 0) {
        ($sections | ForEach-Object { "<h3>{0}</h3>{1}" -f $_.Title, $_.Content }) -join '<br />'
    } else {
        'No expiring credentials within the configured window.'
    }
    
    $legacyCard = [PSCustomObject][Ordered]@{
        "@type"      = "MessageCard"
        "@context"   = "http://schema.org/extensions"
        "themeColor" = 'c13d29'
        "title"      = ('{0} credential(s) across {1} app(s) expiring within {2} days' -f $totalCredCount, $appCount, $expirationThresholdInDays)
        "text"       = $textTable
    }
    
    $legacyMessageBody = ConvertTo-Json $legacyCard -Depth 5
    
    try {
        $legacyParams = @{
            "URI"         = $TeamsWebhookUri
            "Method"      = 'POST'
            "Body"        = $legacyMessageBody
            "ContentType" = 'application/json'
        }
        
        Invoke-RestMethod @legacyParams -ErrorAction Stop
        Write-Host "Successfully sent notification using legacy MessageCard format"
    }
    catch {
        Write-Error "Failed to send Teams notification with fallback format: $($_.Exception.Message)"
        throw
    }
}

Write-Host "Script completed successfully. Processed $($applications.Count) applications, found $totalCredCount expiring credential(s)."
