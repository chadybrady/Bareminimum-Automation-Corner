BeforeAll {
  $scriptPath = Join-Path $PSScriptRoot '..' 'AzureConfigDrift.ps1'
  $tokens = $null
  $parseErrors = $null
  $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath, [ref]$tokens, [ref]$parseErrors
  )
  if ($parseErrors.Count -gt 0) {
    throw "Could not parse AzureConfigDrift.ps1: $($parseErrors -join '; ')"
  }

  $requiredFunctions = @(
    'Write-Out', 'Write-Info', 'Write-Ok', 'Write-Step', 'Write-Fail',
    'Ensure-Folder', 'Write-JsonFile', 'Export-CsvUtf8', 'Assert-SafeBaselineName',
    'Get-RequiredScopesForEndpoints', 'Invoke-Snapshot', 'Compare-Snapshots',
    'Export-DriftReport', 'Get-AvailableBaselines', 'Get-GraphPropValue',
    'Get-AuditActorLookup'
  )
  foreach ($functionName in $requiredFunctions) {
    $functionAst = $scriptAst.Find({
      param($node)
      $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq $functionName
    }, $true)
    if (-not $functionAst) { throw "Function '$functionName' was not found." }
    . ([scriptblock]::Create($functionAst.Extent.Text))
  }

  $script:IsRunbook = $false
  $script:EndpointLabels = @{
    Good = 'Good endpoint'
    Broken = 'Broken endpoint'
  }
  $script:EndpointScopes = @{
    EntraCA = @('Policy.Read.All')
    IntuneCompliance = @('DeviceManagementConfiguration.Read.All')
  }
}

Describe 'AzureConfigDrift safeguards' {
  It 'rejects unsafe baseline names' {
    { Assert-SafeBaselineName -Name '..' } | Should -Throw
    { Assert-SafeBaselineName -Name 'valid-baseline_2026' } | Should -Not -Throw
  }

  It 'returns only scopes for selected endpoints' {
    $scopes = Get-RequiredScopesForEndpoints -SelectedEndpoints @('EntraCA')
    $scopes | Should -Be @('Policy.Read.All')
  }

  It 'adds audit permission only when requested' {
    $scopes = Get-RequiredScopesForEndpoints -SelectedEndpoints @('EntraCA') -IncludeAudit
    $scopes | Should -Contain 'AuditLog.Read.All'
    $scopes.Count | Should -Be 2
  }

  It 'rejects an incomplete snapshot' {
    $script:Collectors = @{
      Good = { [pscustomobject]@{ id = 'good-1' } }
      Broken = { throw 'simulated endpoint failure' }
    }
    $runFolder = Join-Path $TestDrive 'incomplete-snapshot'
    New-Item -ItemType Directory -Path $runFolder | Out-Null

    {
      Invoke-Snapshot -SelectedEndpoints @('Good', 'Broken') -RunFolder $runFolder
    } | Should -Throw '*Snapshot incomplete*'
  }
}

Describe 'AzureConfigDrift reports and storage contracts' {
  It 'writes a CSV with headers when there is no drift' {
    $runFolder = Join-Path $TestDrive 'empty-report'
    New-Item -ItemType Directory -Path $runFolder | Out-Null
    $rows = [System.Collections.Generic.List[pscustomobject]]::new()

    Export-DriftReport -Rows $rows -RunFolder $runFolder -SelectedEndpoints @('EntraCA')

    Test-Path (Join-Path $runFolder 'DriftReport.csv') | Should -BeTrue
    (Get-Content (Join-Path $runFolder 'DriftReport.csv') -First 1) | Should -Match 'Endpoint.*ChangeType'
  }

  It 'keeps StorageContext as an object parameter' {
    $parameter = (Get-Command Get-AvailableBaselines).Parameters['StorageCtx']
    $parameter.ParameterType | Should -Be ([object])
  }
}

Describe 'AzureConfigDrift audit attribution' {
  It 'uses the newest audit event for a resource' {
    function global:Get-GraphPaged {
      param([string]$Uri)
      if ($Uri -like '*directoryAudits*') {
        return @(
          [pscustomobject]@{
            activityDateTime = '2026-07-30T10:00:00Z'
            initiatedBy = [pscustomobject]@{ user = [pscustomobject]@{ userPrincipalName = 'old@example.com' } }
            targetResources = @([pscustomobject]@{ id = 'resource-1' })
          },
          [pscustomobject]@{
            activityDateTime = '2026-07-31T10:00:00Z'
            initiatedBy = [pscustomobject]@{ user = [pscustomobject]@{ userPrincipalName = 'new@example.com' } }
            targetResources = @([pscustomobject]@{ id = 'resource-1' })
          }
        )
      }
      return @()
    }

    $lookup = Get-AuditActorLookup
    $lookup['resource-1'].Actor | Should -Be 'new@example.com'
  }
}
