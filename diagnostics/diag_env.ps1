function Invoke-DiagEnv {
    Write-Host "  [Environment] Proxy, Winsock, Hosts, Services..." -ForegroundColor Cyan
    $issues = @(); $d = @{}
    try {
        $ie = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -ErrorAction SilentlyContinue
        $srv = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyServer -ErrorAction SilentlyContinue
        if ($ie.ProxyEnable -eq 1) {
            $p = if ($srv) { $srv.ProxyServer } else { "unknown" }
            $issues += @{Code="ie_agency_config";Severity="warning";Message="System proxy enabled: $p";Repairs=@("repair_clear_proxy")}
            Write-Host "    [WARN] Proxy: $p" -ForegroundColor Yellow
        } else { Write-Host "    [OK] Proxy disabled" -ForegroundColor Green }
    } catch {}
    $svcs = @{Dhcp="DHCP Client";Dnscache="DNS Client";NlaSvc="NLA Service";LanmanWorkstation="Workstation"}
    foreach ($s in $svcs.Keys) {
        try { $sv = Get-Service $s -ErrorAction SilentlyContinue; if ($sv -and $sv.Status -ne "Running") {
            $issues += @{Code="sev_${s}_stopped";Severity="error";Message="$($svcs[$s]) is $($sv.Status)";Repairs=@("repair_restart_services")}
            Write-Host "    [FAIL] $($svcs[$s]) $($sv.Status)" -ForegroundColor Red
        } elseif ($sv) { Write-Host "    [OK] $($svcs[$s]) Running" -ForegroundColor Green } } catch {}
    }
    $hp = "$env:SystemRoot\System32\drivers\etc\hosts"
    if (Test-Path $hp) {
        $hc = Get-Content $hp -Raw -ErrorAction SilentlyContinue
        if ($hc -match "(127\.0\.0\.1|0\.0\.0\.0)\s+(baidu|sina|bilibili)") {
            $issues += @{Code="host_file_config";Severity="warning";Message="Suspicious entries in hosts file";Repairs=@("repair_fix_hosts")}
            Write-Host "    [WARN] hosts has suspicious entries" -ForegroundColor Yellow
        } else { Write-Host "    [OK] hosts file OK" -ForegroundColor Green }
    }
    $any = ($issues|Where-Object{$_.Severity-eq"error"}).Count -gt 0
    return @{Passed=-not$any;Issues=$issues;Raw=$d;Summary=if($any){"Environment issues found"}else{"Environment OK"}}
}
