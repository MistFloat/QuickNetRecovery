function Invoke-DiagDhcp {
    Write-Host "  [3/8 DHCP] Service and lease state..." -ForegroundColor Cyan
    $issues = @()
    $data = @{}

    $service = Get-Service -Name "Dhcp" -ErrorAction SilentlyContinue
    $data.ServiceStatus = if ($service) { [string]$service.Status } else { "Missing" }
    if (-not $service) {
        $issues += @{ Code = "dhcp_service_missing"; Severity = "error"; Message = "DHCP Client service was not found"; Repairs = @() }
    }
    elseif ($service.Status -ne "Running") {
        $issues += @{ Code = "dhcp_service_stopped"; Severity = "error"; Message = "DHCP Client service is $($service.Status)"; Repairs = @("repair_restart_services") }
        Write-Host "    [FAIL] DHCP Client service: $($service.Status)" -ForegroundColor Red
    }
    else {
        Write-Host "    [OK] DHCP Client service is running" -ForegroundColor Green
    }

    $activeIndexes = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.HardwareInterface -eq $true -and $_.Status -eq "Up"
    } | ForEach-Object { $_.ifIndex })
    $dhcpInterfaces = @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $activeIndexes -contains $_.InterfaceIndex -and $_.Dhcp -eq "Enabled"
    })
    $data.DhcpInterfaceCount = $dhcpInterfaces.Count

    foreach ($interface in $dhcpInterfaces) {
        $leaseAddresses = @(Get-NetIPAddress -InterfaceIndex $interface.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
            $_.IPAddress -notmatch '^169\.254\.' -and $_.AddressState -eq "Preferred"
        })
        if ($leaseAddresses.Count -eq 0) {
            $issues += @{ Code = "dhcp_no_lease"; Severity = "error"; Message = "No valid DHCP lease on $($interface.InterfaceAlias)"; Repairs = @("repair_renew_dhcp", "repair_restart_services") }
            Write-Host "    [FAIL] $($interface.InterfaceAlias): no valid DHCP lease" -ForegroundColor Red
        }
        else {
            Write-Host "    [OK] $($interface.InterfaceAlias): $($leaseAddresses.IPAddress -join ', ')" -ForegroundColor Green
        }
    }

    if ($dhcpInterfaces.Count -eq 0) {
        Write-Host "    [INFO] No active adapter uses DHCP" -ForegroundColor Gray
    }

    $hasError = @($issues | Where-Object { $_.Severity -eq "error" }).Count -gt 0
    return @{
        Passed = -not $hasError
        Issues = $issues
        Raw = $data
        Summary = if ($hasError) { "DHCP problem detected" } else { "DHCP service and leases OK" }
    }
}
