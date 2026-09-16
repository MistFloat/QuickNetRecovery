function Invoke-DiagHosts {
    param(
        [string[]]$Targets = @("baidu.com", "sina.com", "bilibili.com"),
        [string]$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    )

    Write-Host "  [5/8 HOSTS] File syntax and target overrides..." -ForegroundColor Cyan
    $issues = @()
    $data = @{}
    $data.Path = $HostsPath

    if (-not (Test-Path -LiteralPath $HostsPath)) {
        $issues += @{ Code = "hosts_missing"; Severity = "error"; Message = "hosts file is missing"; Repairs = @() }
        return @{ Passed = $false; Issues = $issues; Raw = $data; Summary = "hosts file is missing" }
    }

    try {
        $lines = @(Get-Content -LiteralPath $HostsPath -ErrorAction Stop)
    }
    catch {
        $issues += @{ Code = "hosts_unreadable"; Severity = "error"; Message = "Cannot read hosts file: $($_.Exception.Message)"; Repairs = @() }
        return @{ Passed = $false; Issues = $issues; Raw = $data; Summary = "hosts file cannot be read" }
    }

    $entries = @()
    $malformed = @()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $content = ($lines[$index] -split '#', 2)[0].Trim()
        if ([string]::IsNullOrWhiteSpace($content)) { continue }
        $parts = @($content -split '\s+' | Where-Object { $_ })
        $ip = $null
        if ($parts.Count -lt 2 -or -not [System.Net.IPAddress]::TryParse($parts[0], [ref]$ip)) {
            $malformed += ($index + 1)
            continue
        }
        foreach ($hostName in $parts[1..($parts.Count - 1)]) {
            $entries += [pscustomobject]@{ IPAddress = $parts[0]; HostName = $hostName.ToLowerInvariant(); Line = $index + 1 }
        }
    }

    if ($malformed.Count -gt 0) {
        $issues += @{ Code = "hosts_malformed"; Severity = "warning"; Message = "Malformed hosts entries on line(s): $($malformed -join ', ')"; Repairs = @() }
    }

    $targetNames = @($Targets | ForEach-Object { $_.Trim().ToLowerInvariant() })
    $blocked = @($entries | Where-Object {
        $_.IPAddress -in @("0.0.0.0", "127.0.0.1", "::", "::1") -and
        $targetNames -contains $_.HostName
    })
    foreach ($entry in $blocked) {
        $issues += @{ Code = "hosts_target_blocked"; Severity = "error"; Message = "hosts blocks $($entry.HostName) on line $($entry.Line)"; Repairs = @("repair_fix_hosts") }
    }

    $conflicts = @($entries | Group-Object HostName | Where-Object {
        @($_.Group.IPAddress | Select-Object -Unique).Count -gt 1
    })
    foreach ($conflict in $conflicts) {
        $issues += @{ Code = "hosts_conflict"; Severity = "warning"; Message = "hosts contains conflicting addresses for $($conflict.Name)"; Repairs = @() }
    }

    $data.EntryCount = $entries.Count
    $data.BlockedTargets = $blocked
    $data.MalformedLines = $malformed
    if ($issues.Count -eq 0) {
        Write-Host "    [OK] hosts file is readable and does not override test targets" -ForegroundColor Green
    }
    else {
        Write-Host "    [WARN] hosts issues found: $($issues.Count)" -ForegroundColor Yellow
    }

    $hasError = @($issues | Where-Object { $_.Severity -eq "error" }).Count -gt 0
    return @{
        Passed = -not $hasError
        Issues = $issues
        Raw = $data
        Summary = if ($hasError) { "hosts file problem detected" } else { "hosts file OK" }
    }
}
