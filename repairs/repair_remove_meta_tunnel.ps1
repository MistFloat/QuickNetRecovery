function Invoke-RepairRemoveMetaTunnel {
    <#
    .SYNOPSIS
        移除 Meta Tunnel 虚拟网络适配器
    .DESCRIPTION
        扫描并禁用/卸载 Meta Tunnel、TUN、TAP 等可能干扰正常网络的虚拟网卡
    #>
    param([switch]$Quiet)

    $matched = $false
    $vNics = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "Meta.*Tunnel|TUN|TAP|虚拟网卡" }

    if (-not $vNics) {
        if (-not $Quiet) { Write-Host "  [修复] 未检测到虚拟隧道网卡" -ForegroundColor Green }
        return @{ success = $true; message = "无需要处理的虚拟适配器"; changes = @() }
    }

    $applied = @()
    foreach ($vnic in $vNics) {
        if (-not $Quiet) { Write-Host "  [修复] 正在处理虚拟适配器: $($vnic.Name)" -ForegroundColor Yellow }

        # 步骤 1: 先禁用该适配器
        try {
            Disable-NetAdapter -Name $vnic.Name -Confirm:$false -ErrorAction SilentlyContinue
            $applied += "已停用适配器: $($vnic.Name)"
            if (-not $Quiet) { Write-Host "    → 适配器已停用" -ForegroundColor Gray }
        } catch {
            if (-not $Quiet) { Write-Host "    → 停用失败: $_" -ForegroundColor Red }
        }

        # 步骤 2: 通过 PnP 接口卸载设备
        try {
            $device = Get-PnpDevice -ErrorAction SilentlyContinue |
                Where-Object { $_.FriendlyName -eq $vnic.Name -or $_.Name -eq $vnic.Name }
            if ($device) {
                Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                $device | Remove-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue
                $applied += "PnP 设备已移除: $($device.FriendlyName)"
                if (-not $Quiet) { Write-Host "    → PnP 设备已移除" -ForegroundColor Green }
            } else {
                # 备选方案：WMI 卸载
                $wmiObj = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq $vnic.Name }
                if ($wmiObj) {
                    Invoke-CimMethod -InputObject $wmiObj -MethodName "Uninstall" -ErrorAction SilentlyContinue | Out-Null
                    $applied += "已通过 WMI 卸载: $($vnic.Name)"
                    if (-not $Quiet) { Write-Host "    → WMI 卸载成功" -ForegroundColor Green }
                }
            }
        } catch {
            if (-not $Quiet) { Write-Host "    → 设备卸载异常: $_" -ForegroundColor DarkYellow }
        }

        $matched = $true
    }

    return @{
        success = $true
        message = if ($matched) { "虚拟网卡处理完毕" } else { "未发现虚拟网卡" }
        changes = $applied
    }
}
