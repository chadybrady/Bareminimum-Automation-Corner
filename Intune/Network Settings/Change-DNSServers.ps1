<#
.SYNOPSIS
    Remediation script: Sets static DNS (1.1.1.1 / 8.8.8.8) on all active adapters.
    Use with Intune Proactive Remediations paired with Detect-DNSServers.ps1.
    Exit 0 = success, Exit 1 = failure. Output is visible in Intune portal.
#>

$PrimaryDNS = "1.1.1.1"
$SecondaryDNS = "8.8.8.8"
$results = @()

try {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

    if (-not $adapters) {
        Write-Output "No active adapters found"
        exit 1
    }

    foreach ($adapter in $adapters) {
        $name = $adapter.InterfaceDescription
        $index = $adapter.ifIndex

        Set-DnsClientServerAddress -InterfaceIndex $index -ServerAddresses ($PrimaryDNS, $SecondaryDNS)

        # Use CIM to lock static DNS so DHCP cannot override
        $cim = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "InterfaceIndex = $index"
        if ($cim.DHCPEnabled) {
            $cim | Invoke-CimMethod -MethodName SetDNSServerSearchOrder -Arguments @{ DNSServerSearchOrder = @($PrimaryDNS, $SecondaryDNS) } | Out-Null
        }

        $results += "$name : $PrimaryDNS, $SecondaryDNS"
    }

    Write-Output "DNS set on $($results.Count) adapter(s): $($results -join ' | ')"
    exit 0
}
catch {
    Write-Output "Failed: $_"
    exit 1
}
