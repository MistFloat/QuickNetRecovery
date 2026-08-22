function Invoke-DiagConnectivity {
    param(
        [string[]]$Targets = @("baidu.com", "sina.com", "bilibili.com"),
        [ValidateRange(250, 30000)]
        [int]$TimeoutMs = 2000
    )

    Write-Host "  [Connectivity] Targets: $($Targets -join ', ')" -ForegroundColor Cyan
    $results = @()
    $anyOk = $false
    foreach ($target in $Targets) {
        $dnsOk = $false
        $reachable = $false
        try {
            $addresses = [System.Net.Dns]::GetHostAddresses($target)
            $dnsOk = $addresses.Count -gt 0
        }
        catch {}

        if ($dnsOk) {
            $client = $null
            $waitHandle = $null
            try {
                $client = New-Object System.Net.Sockets.TcpClient
                $asyncResult = $client.BeginConnect($target, 443, $null, $null)
                $waitHandle = $asyncResult.AsyncWaitHandle
                if ($waitHandle.WaitOne($TimeoutMs, $false) -and $client.Connected) {
                    $client.EndConnect($asyncResult)
                    $reachable = $true
                    $anyOk = $true
                }
            }
            catch {}
            finally {
                if ($waitHandle) { $waitHandle.Close() }
                if ($client) { $client.Close() }
            }
        }

        $status = if ($reachable) { "[OK]" } else { "[FAIL]" }
        $color = if ($reachable) { "Green" } else { "Red" }
        Write-Host "    $status $target DNS:$dnsOk TCP:$reachable" -ForegroundColor $color
        $results += @{ Target = $target; DnsResolved = $dnsOk; Reachable = $reachable }
    }

    $issues = @()
    if (-not $anyOk) {
        # Generic failure alone is not enough evidence for a destructive repair.
        # The deeper diagnostic layers attach cause-specific recommendations.
        $issues += @{ Code = "conn_all_fail"; Severity = "error"; Message = "All targets unreachable"; Repairs = @() }
    }
    else {
        foreach ($failedTarget in ($results | Where-Object { -not $_.Reachable })) {
            $safeCode = $failedTarget.Target.Replace('.', '_')
            $issues += @{ Code = "conn_${safeCode}_fail"; Severity = "warning"; Message = "Cannot reach $($failedTarget.Target)"; Repairs = @() }
        }
    }

    return @{
        Passed  = $anyOk
        Issues  = $issues
        Raw     = $results
        Summary = if ($anyOk) { "Connectivity OK" } else { "All targets unreachable" }
    }
}
