function Invoke-RepairResetWinsock {
    <#
    .SYNOPSIS
        重建 Winsock 目录与 TCP/IP 协议栈
    #>
    param([switch]$Quiet)

    if (-not $Quiet) { Write-Host "  [修复] 正在重建 Winsock 与 IP 栈..." -ForegroundColor Yellow }

    $applied = @()

    # Winsock 目录恢复
    try {
        $wsResult = netsh winsock reset 2>&1 | Out-String
        $applied += "Winsock 目录已重置"
        if (-not $Quiet) { Write-Host "    → Winsock 重建完成" -ForegroundColor Green }
    } catch {
        if (-not $Quiet) { Write-Host "    → Winsock 重建失败: $_" -ForegroundColor Red }
    }

    # IP 协议栈恢复
    try {
        $ipResult = netsh int ip reset 2>&1 | Out-String
        $applied += "TCP/IP 协议栈已重置"
        if (-not $Quiet) { Write-Host "    → IP 栈重建完成" -ForegroundColor Green }
    } catch {
        if (-not $Quiet) { Write-Host "    → IP 栈重建失败: $_" -ForegroundColor Red }
    }

    return @{
        success = $true
        message = "Winsock 与协议栈已重建（可能需重启计算机生效）"
        changes = $applied
    }
}
