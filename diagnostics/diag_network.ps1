function Audit-IPConfiguration {
    <#
    .SYNOPSIS
        第 2 层 —— IP 栈配置审计
    .DESCRIPTION
        验证默认网关存在性及可达性、DHCP 工作状态、是否存在 APIPA 兜底地址
    #>
    $problems = @()
    $snap    = @{}

    Write-Host "  [IP配置审计] 检查路由表、DHCP 状态、地址类型..." -ForegroundColor Cyan

    # 1. 默认路由 / 网关
    $defaultRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
    $snap.GatewayCount = $defaultRoutes.Count
    $gateIpList = $defaultRoutes | ForEach-Object { $_.NextHop }
    $snap.GatewayIPs = $gateIpList

    if (-not $defaultRoutes -or $defaultRoutes.Count -eq 0) {
        $problems += @{
            Code       = "nnc_no_gateway"
            Severity   = "error"
            Message    = "路由表中不存在默认网关条目"
            Treatments = @("repair_renew_dhcp", "repair_enable_adapter")
        }
    } else {
        Write-Host "    默认路由指向: $($gateIpList -join ', ')" -ForegroundColor Gray
        foreach ($gw in $gateIpList) {
            try {
                $alive = Test-Connection -ComputerName $gw -Count 1 -Quiet -ErrorAction SilentlyContinue
                if (-not $alive) {
                    Write-Host "    [WARN] 无法 ping 通网关 $gw" -ForegroundColor Yellow
                }
            } catch { }
        }
    }

    # 2. 各接口 DHCP 与 IP 快照
    $activeIps = Get-NetIPInterface -AddressFamily IPv4 -OperationalStatus Up -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceAlias -notmatch "Loopback|Bluetooth" }
    $snap.InterfaceCount = $activeIps.Count

    foreach ($ifc in $activeIps) {
        $addr = Get-NetIPAddress -InterfaceIndex $ifc.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $addrStr = if ($addr) { $addr.IPAddress } else { "空" }

        if ($ifc.Dhcp -ne "Enabled") {
            $problems += @{
                Code       = "sdhcp_disable"
                Severity   = "warning"
                Message    = "接口 '$($ifc.InterfaceAlias)' DHCP 已停用 (固定地址: $addrStr)"
                Treatments = @("repair_renew_dhcp")
            }
            Write-Host "    [WARN] $($ifc.InterfaceAlias)  DHCP=关闭  IP=$addrStr" -ForegroundColor Yellow
        } else {
            Write-Host "    [OK] $($ifc.InterfaceAlias)  DHCP=开启  IP=$addrStr" -ForegroundColor Green
        }
    }

    # 3. APIPA(169.254.x.x) 地址检测
    $allIpAddrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceAlias -notmatch "Loopback|Bluetooth" }
    foreach ($entry in $allIpAddrs) {
        if ($entry.IPAddress -match "^169\.254\.") {
            $problems += @{
                Code       = "nnc_apipa_address"
                Severity   = "error"
                Message    = "接口 '$($entry.InterfaceAlias)' 分配了 APIPA 地址 ($($entry.IPAddress))，DHCP 获取失败"
                Treatments = @("repair_renew_dhcp")
            }
            Write-Host "    [FAIL] $($entry.InterfaceAlias)  APIPA=$($entry.IPAddress)" -ForegroundColor Red
        }
    }

    $hasCritical = ($problems | Where-Object { $_.Severity -eq "error" }).Count -gt 0
    return @{
        Healthy  = -not $hasCritical
        Problems = $problems
        Raw      = $snap
        Brief    = if ($hasCritical) { "IP 配置异常" } else { "IP 配置正常" }
    }
}
