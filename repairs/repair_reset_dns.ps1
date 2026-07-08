function Invoke-RepairResetDns {
    <#
    .SYNOPSIS
        将 DNS 配置还原为自动获取，并清理本地缓存
    .DESCRIPTION
        对所有非环回/蓝牙接口调用 ResetServerAddresses，然后执行 ipconfig /flushdns
    #>
    param([switch]$Quiet)

    if (-not $Quiet) { Write-Host "  [修复] 正在重置 DNS 解析配置..." -ForegroundColor Yellow }

    $applied = @()

    # 清空本地 DNS 缓存
    try {
        ipconfig /flushdns 2>&1 | Out-Null
        $applied += "DNS 缓存已刷新"
        if (-not $Quiet) { Write-Host "    → 已刷新 DNS 缓存" -ForegroundColor Green }
    } catch { }

    # 对每个 IPv4 接口恢复自动 DNS
    $ifaces = Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceAlias -notmatch "Loopback|Bluetooth" }
    foreach ($iface in $ifaces) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $iface.InterfaceIndex -ResetServerAddresses -ErrorAction SilentlyContinue
            $applied += "接口 DNS 已还原: $($iface.InterfaceAlias)"
            if (-not $Quiet) { Write-Host "    → 还原 DNS: $($iface.InterfaceAlias)" -ForegroundColor Green }
        } catch {
            try {
                netsh interface ip set dns "$($iface.InterfaceAlias)" dhcp 2>&1 | Out-Null
                $applied += "接口 DNS(netsh) 已还原: $($iface.InterfaceAlias)"
            } catch { }
        }
    }

    return @{ success = $true; message = "DNS 配置已恢复为自动获取"; changes = $applied }
}
