<#
.SYNOPSIS
    Exports Microsoft Entra Conditional Access documentation.

.DESCRIPTION
    Reads Conditional Access policies, the groups referenced by those policies,
    and the tenant authentication-methods policy through Microsoft Graph. It
    writes a Markdown document and CSV inventories. It makes no Entra changes.

.PARAMETER OutputPath
    Folder in which the documentation files are created.

.PARAMETER IncludeAllGroups
    Include every Entra group in the group inventory. By default, only groups
    directly referenced by a Conditional Access policy are documented.

.PARAMETER IncludeGroupMembers
    Include members of the documented groups in a separate CSV. This may contain
    personal data, so it is off by default.

.EXAMPLE
    ./Export-ConditionalAccessDocumentation.ps1 -Verbose
    Exports policies, referenced groups, and authentication methods.

.EXAMPLE
    ./Export-ConditionalAccessDocumentation.ps1 -IncludeAllGroups -IncludeGroupMembers
    Exports all groups and a separate membership inventory.

.NOTES
    Requires: PowerShell 7+ and Microsoft.Graph.Authentication.
    Permissions: Policy.Read.All, Group.Read.All, Directory.Read.All.
    Idempotent: Yes. Files are regenerated from read-only Graph queries.
    Conditional Access endpoints currently use the Microsoft Graph beta API.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputPath = (Join-Path $PSScriptRoot ("Entra-CA-Export-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [Parameter()]
    [switch] $IncludeAllGroups,

    [Parameter()]
    [switch] $IncludeGroupMembers
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-GraphCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Uri
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $nextUri = $Uri
    while ($nextUri) {
        Write-Verbose "[$($MyInvocation.MyCommand)] Reading $nextUri"
        $response = Invoke-MgGraphRequest -Method GET -Uri $nextUri -OutputType PSObject
        foreach ($item in @($response.value)) { $items.Add($item) }
        # Graph omits @odata.nextLink on the final page. Under StrictMode, direct
        # access to an omitted property is a terminating error.
        $nextLinkProperty = $response.PSObject.Properties['@odata.nextLink']
        $nextUri = if ($null -ne $nextLinkProperty) { $nextLinkProperty.Value } else { $null }
    }
    return $items
}

function ConvertTo-CompactJson {
    [CmdletBinding()]
    param([Parameter()][AllowNull()] $Value)
    if ($null -eq $Value) { return '' }
    return ($Value | ConvertTo-Json -Depth 30 -Compress)
}

function ConvertTo-MarkdownJson {
    [CmdletBinding()]
    param([Parameter()][AllowNull()] $Value)
    if ($null -eq $Value) { return '_None_' }
    $fence = [string]::new([char]96, 3)
    return "$fence`json`n$($Value | ConvertTo-Json -Depth 30)`n$fence"
}

function Get-ReferencedGroupIds {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Policies)

    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($policy in $Policies) {
        $users = $policy.conditions.users
        foreach ($id in @($users.includeGroups) + @($users.excludeGroups)) {
            if ($id) { [void]$ids.Add([string]$id) }
        }
    }
    return $ids
}

try {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw "The Microsoft.Graph.Authentication module is required. Install it with: Install-Module Microsoft.Graph -Scope CurrentUser"
    }

    Import-Module Microsoft.Graph.Authentication
    $scopes = 'Policy.Read.All', 'Group.Read.All', 'Directory.Read.All'
    Write-Verbose "[$($MyInvocation.MyCommand)] Signing in to Microsoft Graph with read-only scopes."
    Connect-MgGraph -Scopes $scopes -NoWelcome | Out-Null

    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    $timestamp = Get-Date -Format 'o'
    $policies = Get-GraphCollection -Uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies'
    Write-Verbose "[$($MyInvocation.MyCommand)] Found $($policies.Count) Conditional Access policies."
    $authenticationMethods = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -OutputType PSObject

    $groups = [System.Collections.Generic.List[object]]::new()
    if ($IncludeAllGroups) {
        $groups = Get-GraphCollection -Uri 'https://graph.microsoft.com/v1.0/groups?$select=id,displayName,description,mailEnabled,securityEnabled,groupTypes,membershipRule,membershipRuleProcessingState,visibility,createdDateTime'
    }
    else {
        foreach ($id in Get-ReferencedGroupIds -Policies $policies) {
            try {
                $groups.Add((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$id`?`$select=id,displayName,description,mailEnabled,securityEnabled,groupTypes,membershipRule,membershipRuleProcessingState,visibility,createdDateTime" -OutputType PSObject))
            }
            catch {
                Write-Warning "Unable to resolve referenced group '$id'. It may have been deleted or be inaccessible."
                $groups.Add([PSCustomObject]@{ id = $id; displayName = '[Unresolved group]' })
            }
        }
    }

    $policyRows = foreach ($policy in $policies) {
        [PSCustomObject]@{
            Id               = $policy.id
            DisplayName      = $policy.displayName
            State            = $policy.state
            CreatedDateTime  = $policy.createdDateTime
            ModifiedDateTime = $policy.modifiedDateTime
            Conditions       = ConvertTo-CompactJson $policy.conditions
            GrantControls    = ConvertTo-CompactJson $policy.grantControls
            SessionControls  = ConvertTo-CompactJson $policy.sessionControls
        }
    }
    $groupRows = foreach ($group in $groups) {
        [PSCustomObject]@{
            Id                            = $group.id
            DisplayName                   = $group.displayName
            Description                   = $group.description
            SecurityEnabled               = $group.securityEnabled
            MailEnabled                   = $group.mailEnabled
            GroupTypes                    = (@($group.groupTypes) -join '; ')
            MembershipRule                = $group.membershipRule
            MembershipRuleProcessingState = $group.membershipRuleProcessingState
            Visibility                    = $group.visibility
            CreatedDateTime               = $group.createdDateTime
        }
    }
    $policyRows | Export-Csv -NoTypeInformation -Encoding utf8BOM -Path (Join-Path $OutputPath 'conditional-access-policies.csv')
    $groupRows | Export-Csv -NoTypeInformation -Encoding utf8BOM -Path (Join-Path $OutputPath 'groups.csv')

    if ($IncludeGroupMembers) {
        $memberRows = foreach ($group in $groups) {
            if ($group.displayName -eq '[Unresolved group]') { continue }
            foreach ($member in Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/groups/$($group.id)/members?`$select=id,displayName,userPrincipalName") {
                [PSCustomObject]@{ GroupId = $group.id; GroupName = $group.displayName; MemberId = $member.id; MemberName = $member.displayName; UserPrincipalName = $member.userPrincipalName; ObjectType = $member.'@odata.type' }
            }
        }
        $memberRows | Export-Csv -NoTypeInformation -Encoding utf8BOM -Path (Join-Path $OutputPath 'group-members.csv')
    }

    $md = [System.Text.StringBuilder]::new()
    [void]$md.AppendLine('# Microsoft Entra Conditional Access documentation')
    [void]$md.AppendLine()
    [void]$md.AppendLine("Generated: $timestamp")
    [void]$md.AppendLine()
    [void]$md.AppendLine('## Conditional Access policies')
    foreach ($policy in $policies | Sort-Object displayName) {
        [void]$md.AppendLine()
        [void]$md.AppendLine("### $($policy.displayName)")
        [void]$md.AppendLine()
        [void]$md.AppendLine("- **ID:** $([char]96)$($policy.id)$([char]96)")
        [void]$md.AppendLine("- **State:** $($policy.state)")
        [void]$md.AppendLine("- **Created:** $($policy.createdDateTime)")
        [void]$md.AppendLine("- **Last modified:** $($policy.modifiedDateTime)")
        [void]$md.AppendLine()
        [void]$md.AppendLine('#### Conditions')
        [void]$md.AppendLine((ConvertTo-MarkdownJson $policy.conditions))
        [void]$md.AppendLine('#### Grant controls')
        [void]$md.AppendLine((ConvertTo-MarkdownJson $policy.grantControls))
        [void]$md.AppendLine('#### Session controls')
        [void]$md.AppendLine((ConvertTo-MarkdownJson $policy.sessionControls))
    }
    [void]$md.AppendLine()
    [void]$md.AppendLine('## Groups')
    [void]$md.AppendLine()
    foreach ($group in $groups | Sort-Object displayName) {
        [void]$md.AppendLine("### $($group.displayName)")
        [void]$md.AppendLine()
        [void]$md.AppendLine((ConvertTo-MarkdownJson $group))
    }
    [void]$md.AppendLine('## Authentication methods policy')
    [void]$md.AppendLine()
    [void]$md.AppendLine((ConvertTo-MarkdownJson $authenticationMethods))
    $md.ToString() | Set-Content -Encoding utf8 -Path (Join-Path $OutputPath 'conditional-access-documentation.md')

    [PSCustomObject]@{
        OutputPath       = (Resolve-Path $OutputPath).Path
        PolicyCount      = @($policies).Count
        GroupCount       = @($groups).Count
        GroupMembersUsed = [bool]$IncludeGroupMembers
        Success          = $true
    }
}
catch {
    Write-Error "Conditional Access export failed: $($_.Exception.Message)"
    throw
}
