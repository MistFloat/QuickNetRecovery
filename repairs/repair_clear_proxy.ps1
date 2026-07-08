function Invoke-RepairClearProxy {
    <#
    .SYNOPSIS
        关闭并清除 IE 代理和 WinHTTP 代理配置
    #>
    param([switch]$Quiet)

    if (-not $Quiet) { Write-Host "  [修复] 正在清理系统代理..." -ForegroundColor Yellow }

    $applied = @()

    # IE / 系统级代理
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" `
            -Name ProxyEnable -Value 0 -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" `
            -Name ProxyServer -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" `
            -Name ProxyOverride -ErrorAction SilentlyContinue
        $applied += "系统代理已关闭"
        if (-not $Quiet) { Write-Host "    → IE 代理已停用" -ForegroundColor Green }
    } catch {
        if (-not $Quiet) { Write-Host "    → IE 代理清理异常: $_" -ForegroundColor Red }
    }

    # WinHTTP 代理
    try {
        netsh winhttp reset proxy 2>&1 | Out-Null
        $applied += "WinHTTP 代理已还原默认"
        if (-not $Quiet) { Write-Host "    → WinHTTP 代理已还原" -ForegroundColor Green }
    } catch {
        if (-not $Quiet) { Write-Host "    → WinHTTP 还原失败: $_" -ForegroundColor Red }
    }

    return @{ success = $true; message = "所有代理设置已清除"; changes = $applied }
}
