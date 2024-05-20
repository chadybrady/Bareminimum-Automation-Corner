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
# Assuming you have a list of application IDs or names in the variable "$specifiedApps"
# Modify the code to only show applications expiring in 180 days

$array = @()
$applications = Get-MSGraphRequest -AccessToken $tokenResponse.access_token -Uri "https://graph.microsoft.com/v1.0/applications/"
$specifiedApps = @("0e6e5e31-6a06-497c-929b-4997b9024191", "260316ab-38b3-4da4-9a84-ca1fa0356f37", "7248b0a6-18c9-4d2c-a249-af142bb06570", "0df54fb2-6e95-4bca-921b-bb2c07bd9cd6", "20eeb85c-8423-4bc5-87d5-0b1b4b5c0ca2", "a3064511-3536-43a6-aa87-8facaf04afeb", "6397861e-0ddb-4950-8def-49dddb1aaa94", "e2665cd4-069e-48a7-89c6-13c4d084f8e6", "3757ce27-061e-478c-9ea9-4cd3d0575b45", "35f3c690-0e84-4665-a837-2e45fe046369", "6a3c345e-e087-4bc7-9afa-f68b6942cdc2", "48b30983-9996-4406-b897-a6b63eb784ea", "349540fb-d80b-4a56-bc0b-1c2ab6fb1c55", "047a2f39-30c1-4fbc-b6e2-8d4f40e9e4aa", "c8120e38-3d75-49a8-a4e3-595fbe504a38", "cae03a3e-0f73-47da-9638-b7e84b6d3d59")  # Replace with your specified app IDs or names

$applications | Sort-Object displayName | Foreach-Object {
    # Check if the application ID or name is in the specifiedApps list
    if ($specifiedApps -contains $_.id -or $specifiedApps -contains $_.displayName) {
        # If there are more than one password credentials, get the expiration of each one
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
        elseif ($_.passwordCredentials.endDateTime.count -eq 1) {
            $Date = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($_.passwordCredentials.endDateTime, 'Central Standard Time')
            $daysUntilExpiration = (New-TimeSpan -Start ([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now, "Central Standard Time")) -End $Date).Days 
        }

        if ($daysUntilExpiration -le 920) {
            $array += $_ | Select-Object id, displayName, @{
                name = "daysUntil"; 
                expr = { $daysUntilExpiration } 
            }
        }
    }
}

# Now $array contains the specified applications expiring in 30 days or less

$textTable = $array | Sort-Object daysUntil | select-object displayName, daysUntil | ConvertTo-Html
$JSONBody = [PSCustomObject][Ordered]@{
    "@type"      = "MessageCard"
    "@context"   = "<http://schema.org/extensions>"
    "themeColor" = '0078D7'
    "title"      = "$($Array.count) Current status of App Secrets"
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