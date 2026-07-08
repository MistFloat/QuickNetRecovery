function Invoke-RepairRestartServices {
    <#
    .SYNOPSIS
        重启关键 Windows 网络服务
    .DESCRIPTION
        依次重启 DHCP Client、DNS Client、NLA、Workstation、Server 等核心系统服务
    #>
    param([switch]$Quiet)

    if (-not $Quiet) { Write-Host "  [修复] 正在重启关键系统服务..." -ForegroundColor Yellow }

    $svcMap = @{
        "Dhcp"              = "DHCP Client"
        "Dnscache"          = "DNS Client"
        "NlaSvc"            = "Network Location Awareness"
        "LanmanWorkstation" = "Workstation"
        "LanmanServer"      = "Server"
    }

    $applied = @()
    foreach ($svcName in $svcMap.Keys) {
        try {
            $svcObj = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svcObj -and $svcObj.Status -eq "Running") {
                Restart-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                $applied += "已重新启动: $($svcMap[$svcName])"
                if (-not $Quiet) { Write-Host "    → 已重启: $($svcMap[$svcName])" -ForegroundColor Green }
            } elseif ($svcObj) {
                Start-Service -Name $svcName -ErrorAction SilentlyContinue
                $applied += "已启动: $($svcMap[$svcName])"
                if (-not $Quiet) { Write-Host "    → 已启动: $($svcMap[$svcName])" -ForegroundColor Green }
            }
        } catch {
            if (-not $Quiet) { Write-Host "    → 操作失败: $($svcMap[$svcName]) - $_" -ForegroundColor Red }
        }
    }

    return @{ success = $applied.Count -gt 0; message = "已处理 $($applied.Count) 个系统服务"; changes = $applied }
}
