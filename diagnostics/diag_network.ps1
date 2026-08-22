function Invoke-DiagNetwork {
    Write-Host "  [Network] Checking gateway, DHCP, subnet..." -ForegroundColor Cyan
    $issues = @()
    $d = @{}
    $activeIndexes = @(Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.HardwareInterface -eq $true -and $_.Status -eq "Up" } |
        ForEach-Object { $_.ifIndex })
    $ifaces = @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $activeIndexes -contains $_.InterfaceIndex })
    $gws = @(Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Where-Object { $activeIndexes -contains $_.InterfaceIndex })
    $d.GatewayCount = $gws.Count
    if (-not $gws -or $gws.Count -eq 0) {
        $gatewayRepairs = if (@($ifaces | Where-Object { $_.Dhcp -eq "Enabled" }).Count -gt 0) { @("repair_renew_dhcp") } else { @() }
        $issues += @{ Code = "nnc_no_gateway"; Severity = "error"; Message = "No default gateway found on an active physical adapter"; Repairs = $gatewayRepairs }
    } else {
        Write-Host "    Gateway: $(($gws|%{$_.NextHop}) -join ', ')" -ForegroundColor Gray
    }

    foreach ($if in $ifaces) {
        $ip = Get-NetIPAddress -InterfaceIndex $if.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $ipStr = if ($ip) { $ip.IPAddress } else { "none" }
        if ($if.Dhcp -ne "Enabled") {
            $issues += @{ Code = "sdhcp_disable"; Severity = "warning"; Message = "Static IPv4 configuration on $($if.InterfaceAlias) (IP: $ipStr)"; Repairs = @() }
            Write-Host "    [WARN] $($if.InterfaceAlias) DHCP=OFF IP=$ipStr" -ForegroundColor Yellow
        } else {
            Write-Host "    [OK] $($if.InterfaceAlias) DHCP=ON IP=$ipStr" -ForegroundColor Green
        }
    }

    $allIPs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $activeIndexes -contains $_.InterfaceIndex }
    foreach ($ip in $allIPs) {
        if ($ip.IPAddress -match "^169\.254\.") {
            $issues += @{Code="nnc_apipa";Severity="error";Message="APIPA address on $($ip.InterfaceAlias) ($($ip.IPAddress))";Repairs=@("repair_renew_dhcp")}
            Write-Host "    [FAIL] $($ip.InterfaceAlias) APIPA $($ip.IPAddress)" -ForegroundColor Red
        }
    }
    $any = ($issues|Where-Object{$_.Severity-eq"error"}).Count -gt 0
    return @{Passed=-not$any;Issues=$issues;Raw=$d;Summary=if($any){"Network config issues"}else{"Network config OK"}}
}
