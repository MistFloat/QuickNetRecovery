function Invoke-DiagHardware {
    Write-Host "  [Hardware] Scanning adapters..." -ForegroundColor Cyan
    $issues = @()
    $d = @{}
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue
    $d.AdapterCount = $adapters.Count
    $physical = $adapters | Where-Object { $_.HardwareInterface -eq $true }
    $enabled = $physical | Where-Object Status -eq "Up"
    $d.EnabledCount = $enabled.Count
    if ($enabled.Count -eq 0) {
        $issues += @{ Code = "nhc_no_enabled"; Severity = "error"; Message = "No connected physical adapters"; Repairs = @() }
    }

    $disabled = $physical | Where-Object { $_.Status -eq "Disabled" -and $_.Name -notmatch "Bluetooth|Loopback" }
    if ($disabled.Count -gt 0) {
        foreach ($a in $disabled) { Write-Host "    [WARN] Disabled: $($a.Name)" -ForegroundColor Yellow }
        $severity = if ($enabled.Count -eq 0) { "error" } else { "warning" }
        $repairs = if ($enabled.Count -eq 0) { @("repair_enable_adapter") } else { @() }
        $issues += @{ Code = "nhc_netcard_disable"; Severity = $severity; Message = "Disabled physical adapters: $($disabled.Name -join ', ')"; Repairs = $repairs }
    }

    $meta = $adapters | Where-Object { $_.Name -match "(?i)Meta.*Tunnel" -or $_.InterfaceDescription -match "(?i)Meta.*Tunnel" }
    $d.MetaCount = $meta.Count
    if ($meta.Count -gt 0) {
        foreach ($a in $meta) { Write-Host "    [META] $($a.Name) ($($a.Status))" -ForegroundColor DarkYellow }
        $issues += @{ Code = "nhc_meta_tunnel"; Severity = "warning"; Message = "Found Meta Tunnel adapter(s)"; Repairs = @("repair_remove_meta_tunnel") }
    }

    Write-Host "    Adapters: $($adapters.Count) Physical up: $($enabled.Count) Meta Tunnel: $($meta.Count)" -ForegroundColor Gray
    $hasError = @($issues | Where-Object { $_.Severity -eq "error" }).Count -gt 0
    return @{ Passed = -not $hasError; Issues = $issues; Raw = $d; Summary = if ($hasError) { "Hardware issues found" } else { "Hardware OK" } }
}
