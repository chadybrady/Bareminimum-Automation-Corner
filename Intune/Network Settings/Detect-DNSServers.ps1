<#
.SYNOPSIS
    Detection script: Checks if DNS is set to 1.1.1.1 / 8.8.8.8 on all active adapters.
    Exit 0 = compliant (no remediation needed), Exit 1 = non-compliant (triggers remediation).
    Output is visible in Intune portal under detection output.
#>

$PrimaryDNS = "1.1.1.1"
$SecondaryDNS = "8.8.8.8"

try {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

    if (-not $adapters) {
        Write-Output "No active adapters found"
        exit 0
    }

    $nonCompliant = @()

    foreach ($adapter in $adapters) {
        $dns = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4).ServerAddresses

        if ($dns.Count -lt 2 -or $dns[0] -ne $PrimaryDNS -or $dns[1] -ne $SecondaryDNS) {
            $current = if ($dns) { $dns -join ", " } else { "none" }
            $nonCompliant += "$($adapter.InterfaceDescription): $current"
        }
    }

    if ($nonCompliant.Count -gt 0) {
        Write-Output "Non-compliant: $($nonCompliant -join ' | ')"
        exit 1
    }

    Write-Output "Compliant: All adapters have DNS $PrimaryDNS, $SecondaryDNS"
    exit 0
}
catch {
    Write-Output "Detection failed: $_"
    exit 1
}
