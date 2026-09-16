function Test-NetQuickFixGatewayPing {
    param(
        [string]$Address,
        [int]$TimeoutMs = 1200
    )

    $ping = $null
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send($Address, $TimeoutMs)
        return $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success
    }
    catch { return $false }
    finally { if ($ping) { $ping.Dispose() } }
}

function Invoke-DiagNetwork {
    Write-Host "  [2/8 Network] IP address, route and gateway..." -ForegroundColor Cyan
    $issues = @()
    $data = @{}
    $activeAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.HardwareInterface -eq $true -and $_.Status -eq "Up"
    })
    $activeIndexes = @($activeAdapters | ForEach-Object { $_.ifIndex })
    $interfaces = @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $activeIndexes -contains $_.InterfaceIndex
    })
    $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred -ErrorAction SilentlyContinue | Where-Object {
        $activeIndexes -contains $_.InterfaceIndex
    })
    $routes = @(Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Where-Object {
        $activeIndexes -contains $_.InterfaceIndex -and $_.NextHop -ne "0.0.0.0"
    } | Sort-Object RouteMetric)

    $data.ActiveAdapterCount = $activeAdapters.Count
    $data.AddressCount = $addresses.Count
    $data.GatewayCount = $routes.Count

    if ($activeAdapters.Count -gt 0 -and $addresses.Count -eq 0) {
        $issues += @{ Code = "network_no_ipv4"; Severity = "error"; Message = "No usable IPv4 address on an active adapter"; Repairs = @("repair_renew_dhcp") }
    }

    foreach ($address in $addresses) {
        $interface = $interfaces | Where-Object { $_.InterfaceIndex -eq $address.InterfaceIndex } | Select-Object -First 1
        $mode = if ($interface -and $interface.Dhcp -eq "Enabled") { "DHCP" } else { "Static" }
        Write-Host "    [IP] $($address.InterfaceAlias): $($address.IPAddress)/$($address.PrefixLength) ($mode)" -ForegroundColor Gray
        if ($address.IPAddress -match '^169\.254\.') {
            $issues += @{ Code = "network_apipa"; Severity = "error"; Message = "APIPA address on $($address.InterfaceAlias): $($address.IPAddress)"; Repairs = @("repair_renew_dhcp") }
        }
    }

    if ($activeAdapters.Count -gt 0 -and $routes.Count -eq 0) {
        $hasDhcp = @($interfaces | Where-Object { $_.Dhcp -eq "Enabled" }).Count -gt 0
        $repairs = if ($hasDhcp) { @("repair_renew_dhcp") } else { @() }
        $issues += @{ Code = "network_no_gateway"; Severity = "error"; Message = "No default IPv4 gateway on an active physical adapter"; Repairs = $repairs }
    }

    foreach ($route in $routes) {
        $reachable = Test-NetQuickFixGatewayPing -Address $route.NextHop
        $data["Gateway_$($route.NextHop)"] = $reachable
        if ($reachable) {
            Write-Host "    [OK] Gateway $($route.NextHop) is reachable" -ForegroundColor Green
        }
        else {
            Write-Host "    [WARN] Gateway $($route.NextHop) did not answer ICMP" -ForegroundColor Yellow
            $issues += @{ Code = "network_gateway_no_ping"; Severity = "warning"; Message = "Gateway $($route.NextHop) did not answer ICMP; it may block ping"; Repairs = @() }
        }
    }

    $duplicates = @($addresses | Group-Object IPAddress | Where-Object { $_.Count -gt 1 })
    foreach ($duplicate in $duplicates) {
        $issues += @{ Code = "network_duplicate_local_ip"; Severity = "warning"; Message = "IPv4 address appears on multiple local interfaces: $($duplicate.Name)"; Repairs = @() }
    }

    $hasError = @($issues | Where-Object { $_.Severity -eq "error" }).Count -gt 0
    return @{
        Passed = -not $hasError
        Issues = $issues
        Raw = $data
        Summary = if ($hasError) { "Network configuration problem detected" } else { "Network configuration OK" }
    }
}
