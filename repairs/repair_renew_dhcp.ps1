function Invoke-RepairRenewDhcp {
    <#
    .SYNOPSIS
        强制重新获取 IP 地址租约
    #>
    param([switch]$Quiet)

    if (-not $Quiet) { Write-Host "  [修复] 重新申请 DHCP 地址..." -ForegroundColor Yellow }

    $applied = @()

    # 释放当前租约
    try {
        if (-not $Quiet) { Write-Host "    → 正在释放旧 IP..." -ForegroundColor Gray }
        $stepRelease = ipconfig /release 2>&1 | Out-String
        $applied += "已断开当前 DHCP 租约"
        Start-Sleep -Milliseconds 500
    } catch {
        if (-not $Quiet) { Write-Host "    → 释放失败: $_" -ForegroundColor Red }
    }

    # 重新获取
    try {
        if (-not $Quiet) { Write-Host "    → 正在获取新 IP..." -ForegroundColor Gray }
        $stepRenew = ipconfig /renew 2>&1 | Out-String
        $applied += "已重新获取 DHCP 配置"
    } catch {
        if (-not $Quiet) { Write-Host "    → 续租失败: $_" -ForegroundColor Red }
    }

    # 把静态 IP 接口也切回 DHCP
    try {
        $manualIps = Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.Dhcp -eq "Disabled" -and $_.InterfaceAlias -notmatch "Loopback|Bluetooth" }
        foreach ($iface in $manualIps) {
            netsh interface ip set address "$($iface.InterfaceAlias)" dhcp 2>&1 | Out-Null
            $applied += "接口恢复 DHCP: $($iface.InterfaceAlias)"
            if (-not $Quiet) { Write-Host "    → 恢复 DHCP: $($iface.InterfaceAlias)" -ForegroundColor Green }
        }
    } catch { }

    return @{ success = $true; message = "IP 地址刷新完毕"; changes = $applied }
}
