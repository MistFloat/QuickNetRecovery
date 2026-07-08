function Invoke-RepairEnableAdapter {
    <#
    .SYNOPSIS
        启用处于禁用状态的网络适配器
    #>
    param([switch]$Quiet)

    if (-not $Quiet) { Write-Host "  [修复] 正在查找被停用的网卡..." -ForegroundColor Yellow }

    $inactiveNics = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.Status -eq "Disabled" -and $_.Name -notmatch "Bluetooth|Loopback"
    }

    if (-not $inactiveNics) {
        if (-not $Quiet) { Write-Host "    → 所有网卡均处于可用状态" -ForegroundColor Green }
        return @{ success = $true; message = "没有需要激活的网卡"; changes = @() }
    }

    $applied = @()
    foreach ($nic in $inactiveNics) {
        try {
            Enable-NetAdapter -Name $nic.Name -Confirm:$false -ErrorAction SilentlyContinue
            $applied += "已激活网卡: $($nic.Name)"
            if (-not $Quiet) { Write-Host "    → 已激活: $($nic.Name)" -ForegroundColor Green }
        } catch {
            if (-not $Quiet) { Write-Host "    → 激活失败: $($nic.Name) - $_" -ForegroundColor Red }
        }
    }

    return @{ success = $applied.Count -gt 0; message = "已激活 $($applied.Count) 个网卡"; changes = $applied }
}
