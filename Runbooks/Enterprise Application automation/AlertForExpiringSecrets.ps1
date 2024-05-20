$TenantID = Get-AutomationVariable -Name 'TenantName'
$AppID = Get-AutomationVariable -Name "msgraph-clientcred-appid"
$AppSecret = Get-AutomationVariable -Name "msgraph-clientcred-appsecret"
$URL = Get-AutomationVariable -Name "TeamsChannelUri"

Function Connect-MSGraphAPI {
    param (
        [system.string]$AppID,
        [system.string]$TenantID,
        [system.string]$AppSecret
    )
    begin {
        $URI = "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token"
        $ReqTokenBody = @{
            Grant_Type    = "client_credentials"
            Scope         = "https://graph.microsoft.com/.default"
            client_Id     = $AppID
            Client_Secret = $AppSecret
        } 
    }
    Process {
        Write-Host "Connecting to the Graph API"
        $Response = Invoke-RestMethod -Uri $URI -Method POST -Body $ReqTokenBody
    }
    End{
        $Response
    }
}


$tokenResponse = Connect-MSGraphAPI -AppID $AppID -TenantID $TenantID -AppSecret $AppSecret
Function Get-MSGraphRequest {
    param (
        [system.string]$Uri,
        [system.string]$AccessToken
    )
    begin {
        [System.Array]$allPages = @()
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
        write-verbose "GET request at endpoint: $Uri"
        $data = Invoke-RestMethod @ReqTokenBody
        while ($data.'@odata.nextLink') {
            $allPages += $data.value
            $ReqTokenBody.Uri = $data.'@odata.nextLink'
            $Data = Invoke-RestMethod @ReqTokenBody
            # to avoid throttling, the loop will sleep for 3 seconds
            Start-Sleep -Seconds 3
        }
        $allPages += $data.value
    }
    end {
        Write-Verbose "Returning all results"
        $allPages
    }
}

# Assuming you have a list of applications in the variable "$applications"
# Modify the code to only show applications expiring in 180 days
$array = @()
$applications = Get-MSGraphRequest -AccessToken $tokenResponse.access_token -Uri "https://graph.microsoft.com/v1.0/applications/"
$Applications | Sort-Object displayName | Foreach-Object {
    #If there are more than one password credentials, we need to get the expiration of each one
    if ($_.passwordCredentials.endDateTime.count -gt 1) {
        $endDates = $_.passwordCredentials.endDateTime
        [int[]]$daysUntilExpiration = @()
        # Assuming $_.passwordCredentials.endDateTime is a DateTime object
foreach ($Date in $endDates) {
    if ($Date -ne $null) {
        $Date = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]$Date, 'Central Standard Time')
        $daysUntilExpiration += (New-TimeSpan -Start ([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now, "Central Standard Time")) -End $Date).Days
    }
}
    }
    Elseif ($_.passwordCredentials.endDateTime.count -eq 1) {
        $Date = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($_.passwordCredentials.endDateTime, 'Central Standard Time')
        $daysUntilExpiration = (New-TimeSpan -Start ([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now, "Central Standard Time")) -End $Date).Days 
    }

    if ($daysUntilExpiration -le 30) {
        $array += $_ | Select-Object id, displayName, @{
            name = "daysUntil"; 
            expr = { $daysUntilExpiration } 
        }
    }
}

$textTable = $array | Sort-Object daysUntil | select-object displayName, daysUntil | ConvertTo-Html
$JSONBody = [PSCustomObject][Ordered]@{
    "@type"      = "MessageCard"
    "@context"   = "<http://schema.org/extensions>"
    "themeColor" = '0078D7'
    "title"      = "$($Array.count) App Secrets areExpiring Soon"
    "text"       = "$textTable"
}

$TeamMessageBody = ConvertTo-Json $JSONBody

$parameters = @{
    "URI"         = "$URL"
    "Method"      = 'POST'
    "Body"        = $TeamMessageBody
    "ContentType" = 'application/json'
}

Invoke-RestMethod @parameters