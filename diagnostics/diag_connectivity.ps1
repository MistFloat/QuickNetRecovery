function Test-InternetReachability {
    <#
    .SYNOPSIS
        第 0 层 —— 互联网可达性探测
    .DESCRIPTION
        依次对 baidu.com / sina.com / bilibili.com 进行域名解析与端口连通测试，
        任意一个站点可达即判定网络正常。
    #>
    param(
        [string[]]$Targets = @("baidu.com", "sina.com", "bilibili.com"),
        [int]$TimeoutMs = 2000
    )

    $records = @()
    $globalHealthy = $false

    Write-Host "  [连通探测] 目标列表: $($Targets -join ', ')" -ForegroundColor Cyan

    foreach ($hostname in $Targets) {
        $dnsResult = $false
        $portOpen = $false

        try {
            $addrList = [System.Net.Dns]::GetHostAddresses($hostname)
            $dnsResult = $addrList.Count -gt 0
        } catch {
            $dnsResult = $false
        }

        if ($dnsResult) {
            try {
                $socket = New-Object System.Net.Sockets.TcpClient
                $connOp = $socket.BeginConnect($hostname, 443, $null, $null)
                $timedOut = $connOp.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
                if ($timedOut -and $socket.Connected) {
                    $socket.EndConnect($connOp)
                    $portOpen = $true
                    $globalHealthy = $true
                }
                $socket.Close()
            } catch {
                $portOpen = $false
            }
        }

        $mark  = if ($portOpen) { "[OK]" } else { "[FAIL]" }
        $color = if ($portOpen) { "Green" } else { "Red" }
        Write-Host "    $mark $hostname  DNS:$dnsResult  Port:$portOpen" -ForegroundColor $color

        $records += @{
            Target      = $hostname
            DnsResolved = $dnsResult
            Connected   = $portOpen
        }
    }

    $problems = @()
    if (-not $globalHealthy) {
        $problems += @{
            Code       = "conn_all_fail"
            Severity   = "error"
            Message    = "所有探测目标均不可达 ($($Targets -join ', '))"
            Treatments = @("repair_remove_meta_tunnel","repair_enable_adapter","repair_renew_dhcp","repair_reset_winsock","repair_clear_proxy","repair_reset_dns","repair_restart_services","repair_fix_hosts")
        }
    } else {
        $downTargets = $records | Where-Object { -not $_.Connected }
        foreach ($dt in $downTargets) {
            $problems += @{
                Code       = "conn_$($dt.Target.Replace('.','_'))_fail"
                Severity   = "warning"
                Message    = "$($dt.Target) 端口不可达"
                Treatments = @("repair_reset_dns","repair_clear_proxy")
            }
        }
    }

    return @{
        Healthy  = $globalHealthy
        Problems = $problems
        Raw      = $records
        Brief    = if ($globalHealthy) { "互联网连通正常" } else { "全部检测站点不通" }
    }
}
