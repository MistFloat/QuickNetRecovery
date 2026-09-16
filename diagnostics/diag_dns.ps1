function Invoke-DiagDns {
    param([string[]]$Targets = @("baidu.com", "sina.com", "bilibili.com"))

    Write-Host "  [4/8 DNS] Server configuration and resolution..." -ForegroundColor Cyan
    $issues = @()
    $data = @{}
    $dnsService = Get-Service -Name "Dnscache" -ErrorAction SilentlyContinue
    $data.ServiceStatus = if ($dnsService) { [string]$dnsService.Status } else { "Missing" }
    if (-not $dnsService) {
        $issues += @{ Code = "dns_service_missing"; Severity = "error"; Message = "DNS Client service was not found"; Repairs = @() }
    }
    elseif ($dnsService.Status -ne "Running") {
        $issues += @{ Code = "dns_service_stopped"; Severity = "error"; Message = "DNS Client service is $($dnsService.Status)"; Repairs = @("repair_restart_services") }
        Write-Host "    [FAIL] DNS Client service: $($dnsService.Status)" -ForegroundColor Red
    }
    else {
        Write-Host "    [OK] DNS Client service is running" -ForegroundColor Green
    }

    $activeIndexes = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.HardwareInterface -eq $true -and $_.Status -eq "Up"
    } | ForEach-Object { $_.ifIndex })
    $dnsSettings = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $activeIndexes -contains $_.InterfaceIndex
    })
    $servers = @($dnsSettings.ServerAddresses | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $data.Servers = $servers

    foreach ($setting in $dnsSettings) {
        if (@($setting.ServerAddresses).Count -eq 0 -or $setting.ServerAddresses -contains "0.0.0.0") {
            $issues += @{ Code = "dns_no_server"; Severity = "error"; Message = "No usable DNS server on $($setting.InterfaceAlias)"; Repairs = @("repair_reset_dns", "repair_renew_dhcp") }
            Write-Host "    [FAIL] $($setting.InterfaceAlias): no usable DNS server" -ForegroundColor Red
        }
        else {
            Write-Host "    [DNS] $($setting.InterfaceAlias): $($setting.ServerAddresses -join ', ')" -ForegroundColor Gray
        }
    }

    if ($activeIndexes.Count -gt 0 -and $servers.Count -eq 0) {
        $issues += @{ Code = "dns_no_server_any"; Severity = "error"; Message = "No DNS server is configured on active adapters"; Repairs = @("repair_reset_dns", "repair_renew_dhcp") }
    }

    $workingServers = @()
    if ($Targets.Count -gt 0 -and (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) {
        foreach ($server in $servers) {
            try {
                $answer = Resolve-DnsName -Name $Targets[0] -Server $server -DnsOnly -QuickTimeout -ErrorAction Stop
                if (@($answer | Where-Object { $_.IPAddress }).Count -gt 0) {
                    $workingServers += $server
                    Write-Host "    [OK] DNS server $server answered" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "    [WARN] DNS server $server did not answer" -ForegroundColor Yellow
                $issues += @{ Code = "dns_server_unresponsive"; Severity = "warning"; Message = "DNS server did not answer: $server"; Repairs = @() }
            }
        }
    }
    $data.WorkingServers = $workingServers

    $resolvedTargets = @()
    foreach ($target in $Targets) {
        try {
            $addresses = [System.Net.Dns]::GetHostAddresses($target)
            if ($addresses.Count -gt 0) {
                $resolvedTargets += $target
                Write-Host "    [OK] $target -> $($addresses.IPAddressToString -join ', ')" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "    [FAIL] Cannot resolve $target" -ForegroundColor Red
            $issues += @{ Code = "dns_target_failed"; Severity = "warning"; Message = "Cannot resolve $target"; Repairs = @() }
        }
    }

    $data.ResolvedTargets = $resolvedTargets
    if ($Targets.Count -gt 0 -and $resolvedTargets.Count -eq 0) {
        $issues += @{ Code = "dns_resolution_failed"; Severity = "error"; Message = "DNS resolution failed for all targets"; Repairs = @("repair_reset_dns", "repair_renew_dhcp") }
    }

    $hasError = @($issues | Where-Object { $_.Severity -eq "error" }).Count -gt 0
    return @{
        Passed = -not $hasError
        Issues = $issues
        Raw = $data
        Summary = if ($hasError) { "DNS problem detected" } else { "DNS configuration and resolution OK" }
    }
}
