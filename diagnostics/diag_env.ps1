function Scan-SystemSettings {
    <#
    .SYNOPSIS
        第 4 层 —— 操作系统级网络环境排查
    .DESCRIPTION
        扫描系统代理配置、LSP/Winsock 健康状况、hosts 文件内容、核心网络服务运行状态
    #>
    $problems = @()
    $snap    = @{}

    Write-Host "  [系统环境排查] 代理 / Winsock / Hosts / 关键服务..." -ForegroundColor Cyan

    # 1. 系统代理状态
    $snap.Proxy = @{}
    try {
        $ieFlag = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" `
            -Name ProxyEnable -ErrorAction SilentlyContinue
        $ieAddr = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" `
            -Name ProxyServer -ErrorAction SilentlyContinue
        $proxyOn = $ieFlag.ProxyEnable -eq 1

        if ($proxyOn) {
            $svr = if ($ieAddr) { $ieAddr.ProxyServer } else { "未知地址" }
            $snap.Proxy.Active = $true
            $snap.Proxy.Address = $svr
            $problems += @{
                Code       = "ie_agency_config"
                Severity   = "warning"
                Message    = "系统级代理正在生效: $svr，可能影响部分网络访问"
                Treatments = @("repair_clear_proxy")
            }
            Write-Host "    [WARN] 代理已开启: $svr" -ForegroundColor Yellow
        } else {
            $snap.Proxy.Active = $false
            Write-Host "    [OK] 未启用系统代理" -ForegroundColor Green
        }
    } catch {
        $snap.Proxy.Active = $false
    }

    # 2. 关键 Windows 网络服务
    $svcCheckList = @{
        "Dhcp"              = "DHCP Client"
        "Dnscache"          = "DNS Client"
        "NlaSvc"            = "Network Location Awareness"
        "LanmanWorkstation" = "Workstation"
    }
    $snap.Services = @()
    foreach ($shortName in $svcCheckList.Keys) {
        try {
            $svcObj = Get-Service -Name $shortName -ErrorAction SilentlyContinue
            if ($svcObj -and $svcObj.Status -ne "Running") {
                $snap.Services += @{
                    Name     = $shortName
                    FullName = $svcCheckList[$shortName]
                    Status   = $svcObj.Status
                }
                $problems += @{
                    Code       = "sev_$shortName`_stopped"
                    Severity   = "error"
                    Message    = "关键服务 '$($svcCheckList[$shortName])' 处于 $($svcObj.Status) 状态"
                    Treatments = @("repair_restart_services")
                }
                Write-Host "    [FAIL] $($svcCheckList[$shortName]) 目前: $($svcObj.Status)" -ForegroundColor Red
            } elseif ($svcObj) {
                Write-Host "    [OK] $($svcCheckList[$shortName]) 正在运行" -ForegroundColor Green
            }
        } catch { }
    }

    # 3. LSP / Winsock 链安全性
    $snap.Winsock = @{}
    try {
        $rawCatalog = netsh winsock show catalog 2>&1 | Out-String
        $potentialHijack = $rawCatalog -match "劫持|hijack|malware" -or `
            $rawCatalog -match "分层服务提供程序.*\\[.*(?:未知|unknown).*\\]"
        if ($potentialHijack) {
            $snap.Winsock.Suspicious = $true
            $problems += @{
                Code       = "lsp_kidnapped"
                Severity   = "error"
                Message    = "Winsock LSP 目录中存在可疑条目"
                Treatments = @("repair_reset_winsock")
            }
            Write-Host "    [FAIL] LSP 链疑似被篡改" -ForegroundColor Red
        } else {
            $snap.Winsock.Suspicious = $false
            Write-Host "    [OK] LSP 链状态正常" -ForegroundColor Green
        }
    } catch { }

    # 4. hosts 文件清查
    $snap.Hosts = @{}
    $hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
    if (Test-Path $hostsFile) {
        $rawHosts = Get-Content $hostsFile -Raw -ErrorAction SilentlyContinue
        if ($rawHosts) {
            $unusualEntries = @()
            if ($rawHosts -match "127\.0\.0\.1\s+(baidu|sina|bilibili|google|facebook|twitter|youtube)") {
                $unusualEntries += "存在屏蔽知名站点的主机名映射"
            }
            if ($rawHosts -match "0\.0\.0\.0\s+(baidu|sina|bilibili)") {
                $unusualEntries += "存在将知名站点重定向至无效地址的条目"
            }
            if ($unusualEntries.Count -gt 0) {
                $snap.Hosts.Suspicious = $unusualEntries
                $problems += @{
                    Code       = "host_file_config"
                    Severity   = "warning"
                    Message    = "hosts 文件中发现异常记录: $($unusualEntries -join '; ')"
                    Treatments = @("repair_fix_hosts")
                }
                Write-Host "    [WARN] hosts 文件内容可疑" -ForegroundColor Yellow
            } else {
                Write-Host "    [OK] hosts 文件无异常" -ForegroundColor Green
            }
        }
    }

    $hasCritical = ($problems | Where-Object { $_.Severity -eq "error" }).Count -gt 0
    return @{
        Healthy  = -not $hasCritical
        Problems = $problems
        Raw      = $snap
        Brief    = if ($hasCritical) { "系统环境存在隐患" } else { "系统环境状态良好" }
    }
}
