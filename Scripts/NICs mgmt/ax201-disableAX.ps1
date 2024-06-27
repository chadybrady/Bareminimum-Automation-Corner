# Disable Wi-Fi 6 on Intel AX201 by setting it to 802.11ac
$adapterName = "Intel(R) Wi-Fi 6 AX201 160MHz"

# Get the network adapter
$adapter = Get-NetAdapter -Name $adapterName

# Change the advanced properties
$adapter | Set-NetAdapterAdvancedProperty -DisplayName "802.11n/ac/ax Wireless Mode" -DisplayValue "802.11ac"
$adapter | Set-NetAdapterAdvancedProperty -DisplayName "Preferred Band" -DisplayValue "3. Prefer 5GHz band"