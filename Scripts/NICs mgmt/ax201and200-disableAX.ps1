# Define the network adapter names for AX201 and AX200
$adapterNames = @("Intel(R) Wi-Fi 6 AX201 160MHz", "Intel(R) Wi-Fi 6 AX200 160MHz")

foreach ($adapterName in $adapterNames) {
    # Check if the network adapter exists on the device
    $adapter = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue

    if ($adapter) {
        Write-Host "Configuring adapter: $adapterName"
        # Change the advanced properties
        $adapter | Set-NetAdapterAdvancedProperty -DisplayName "802.11n/ac/ax Wireless Mode" -DisplayValue "802.11ac"
        $adapter | Set-NetAdapterAdvancedProperty -DisplayName "Preferred Band" -DisplayValue "3. Prefer 5GHz band"
    } else {
        Write-Host "Adapter not found: $adapterName"
    }
}