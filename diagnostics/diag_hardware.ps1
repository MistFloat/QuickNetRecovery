function Inspect-NetAdapterHealth {
    <#
    .SYNOPSIS
        第 1 层 —— 网络适配器物理状态检查
    .DESCRIPTION
        核实网卡启用情况、物理链路连接状况、以及是否存在 Meta Tunnel 等虚拟适配器干扰
    #>
    $problems = @()
    $meta     = @{}

    Write-Host "  [适配器检查] 枚举所有网络接口..." -ForegroundColor Cyan

    $allNics = Get-NetAdapter -ErrorAction SilentlyContinue
    $meta.TotalCount = $allNics.Count

    # 1. 确认是否有处于活动状态的网卡
    $activeNics = $allNics | Where-Object { $_.Status -eq "Up" }
    $meta.ActiveCount = $activeNics.Count

    if ($activeNics.Count -eq 0) {
        $problems += @{
            Code       = "nhc_no_enabled_adapter"
            Severity   = "error"
            Message    = "未找到任何处于启用且连接状态的网络适配器"
            Treatments = @("repair_enable_adapter")
        }
    }

    # 2. 检查被禁用的网卡（跳过蓝牙、环回接口）
    $offlineNics = $allNics | Where-Object {
        $_.Status -eq "Disabled" -and $_.Name -notmatch "Bluetooth|Loopback"
    }
    $meta.OfflineList = $offlineNics | ForEach-Object { $_.Name }
    if ($offlineNics.Count -gt 0) {
        foreach ($nic in $offlineNics) {
            Write-Host "    [WARN] 已禁用: $($nic.Name)" -ForegroundColor Yellow
        }
        $problems += @{
            Code       = "nhc_netcard_disable"
            Severity   = "error"
            Message    = "存在被禁用的网卡: $($offlineNics | ForEach-Object { $_.Name } | Join-String -Separator ', ')"
            Treatments = @("repair_enable_adapter")
        }
    }

    # 3. 搜索 Meta Tunnel / TUN 类虚拟网卡
    $virtualNics = $allNics | Where-Object {
        $_.Name -match "Meta.*Tunnel|TUN|TAP|虚拟网卡"
    }
    $meta.VirtualList = $virtualNics | ForEach-Object {
        @{ Name = $_.Name; Status = $_.Status }
    }
    if ($virtualNics.Count -gt 0) {
        foreach ($nic in $virtualNics) {
            Write-Host "    [META] 虚拟适配器: $($nic.Name) 当前=$($nic.Status)" -ForegroundColor DarkYellow
        }
        $problems += @{
            Code       = "nhc_meta_tunnel_found"
            Severity   = "warning"
            Message    = "检测到 Meta Tunnel 类虚拟网卡，可能干扰正常网络"
            Treatments = @("repair_remove_meta_tunnel")
        }
    }

    # 4. 物理层链路状态
    $physNics = $allNics | Where-Object {
        $_.InterfaceType -eq 6 -or $_.InterfaceType -eq 71 -or
        $_.Name -match "Ethernet|Wi.Fi|WLAN|以太网|无线"
    }
    $physLinked = $physNics | Where-Object {
        $_.MediaConnectState -eq 1 -or $_.Status -eq "Up"
    }
    $meta.PhysLinkedCount = $physLinked.Count

    if ($physLinked.Count -eq 0 -and $activeNics.Count -gt 0) {
        $physLabels = $physNics | ForEach-Object { $_.Name }
        if ($physLabels.Count -gt 0) {
            Write-Host "    [WARN] 物理链路无连接: $($physLabels -join ', ')" -ForegroundColor Yellow
            $problems += @{
                Code       = "nhc_physical_disconnected"
                Severity   = "warning"
                Message    = "物理网卡无网络信号（检查网线或 WiFi 是否连接）"
                Treatments = @()
            }
        }
    }

    # 打印汇总信息
    if ($virtualNics.Count -gt 0) {
        foreach ($nic in $virtualNics) {
            Write-Host "    [META] $($nic.Name) ($($nic.Status))" -ForegroundColor DarkYellow
        }
    }
    Write-Host "    共 $($allNics.Count) 个适配器 | 活动中 $($activeNics.Count) | 虚拟 $($virtualNics.Count)" -ForegroundColor Gray

    $hasCritical = ($problems | Where-Object { $_.Severity -eq "error" }).Count -gt 0
    return @{
        Healthy  = -not $hasCritical
        Problems = $problems
        Raw      = $meta
        Brief    = if ($hasCritical) { "适配器/硬件异常" } else { "适配器/硬件正常" }
    }
}
