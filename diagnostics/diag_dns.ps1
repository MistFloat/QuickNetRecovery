function Invoke-DiagDns {
    param([string[]]$Targets = @("baidu.com", "sina.com", "bilibili.com"))

    Write-Host "  [DNS] Checking DNS resolution..." -ForegroundColor Cyan
    $issues = @()
    $data = @{}
    $activeIndexes = @(Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.HardwareInterface -eq $true -and $_.Status -eq "Up" } |
        ForEach-Object { $_.ifIndex })
    $dnsSvrs = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $activeIndexes -contains $_.InterfaceIndex }
    foreach ($ds in $dnsSvrs) {
        if (@($ds.ServerAddresses).Count -gt 0) {
            Write-Host "    $($ds.InterfaceAlias): $($ds.ServerAddresses -join ', ')" -ForegroundColor Gray
            if ($ds.ServerAddresses -contains "0.0.0.0") {
                $issues += @{ Code = "sdns_no_server"; Severity = "error"; Message = "No usable DNS server on $($ds.InterfaceAlias)"; Repairs = @("repair_reset_dns", "repair_renew_dhcp") }
            }
        }
        else {
            Write-Host "    [FAIL] $($ds.InterfaceAlias): no DNS server" -ForegroundColor Red
            $issues += @{ Code = "sdns_no_server"; Severity = "error"; Message = "No DNS server on $($ds.InterfaceAlias)"; Repairs = @("repair_reset_dns", "repair_renew_dhcp") }
        }
    }

    $anyResolved = $false
    foreach ($target in $Targets) {
        try {
            $addresses = [System.Net.Dns]::GetHostAddresses($target)
            if ($addresses.Count -gt 0) {
                $anyResolved = $true
                Write-Host "    [OK] $target -> $($addresses.IPAddressToString -join ', ')" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "    [FAIL] $target" -ForegroundColor Red
        }
    }

    if (-not $anyResolved) {
        $issues += @{ Code = "sdns_resolve_all_fail"; Severity = "error"; Message = "DNS resolution failed for all targets"; Repairs = @("repair_reset_dns", "repair_renew_dhcp") }
    }

    return @{ Passed = $anyResolved; Issues = $issues; Raw = $data; Summary = if ($anyResolved) { "DNS OK" } else { "DNS failed" } }
}
