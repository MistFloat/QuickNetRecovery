<#
.SYNOPSIS
    QuickNet —— Windows 端网络故障自愈工具
.DESCRIPTION
    按层次递进排查网络异常，同时提供人工分步修正与无人值守全自动修正两种执行方式。
    特有机制：识别到 Meta Tunnel 虚拟适配器时自动执行移除操作。
.PARAMETER RunAs
    覆盖配置文件预设的执行策略。接受 "auto"（无人值守自动修复）或 "interactive"（人工确认交互模式）两个值。
    常用于系统计划任务等无人工介入的场景。
#>

param(
    [ValidateSet("auto", "interactive")]
    [string]$RunAs
)

# ============================================================
# 环境准备
# ============================================================
$script:BasePath       = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:SettingsFile   = Join-Path $script:BasePath "netfix.config.json"
$script:CheckScriptDir = Join-Path $script:BasePath "diagnostics"
$script:FixScriptDir   = Join-Path $script:BasePath "repairs"
$script:ProblemList    = @()
$script:ActivityLog    = @()

# ============================================================
# 基础辅助
# ============================================================
function Append-Trace {
    param([string]$Text)
    $stamp = Get-Date -Format "HH:mm:ss.fff"
    $script:ActivityLog += "[$stamp] $Text"
}

function Show-TitleScreen {
    Clear-Host
    Write-Host "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓" -ForegroundColor Cyan
    Write-Host "┃      QuickNet  系统网络故障自检修复      ┃" -ForegroundColor Cyan
    Write-Host "┃    分层诊断  ·  智能匹配  ·  一键恢复    ┃" -ForegroundColor Cyan
    Write-Host "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛" -ForegroundColor Cyan
    Write-Host ""
}

function Print-Block {
    param([string]$Label)
    Write-Host ""
    Write-Host "▸ $Label" -ForegroundColor White
}

# ============================================================
# 加载用户配置
# ============================================================
function Import-UserSettings {
    if (-not (Test-Path $script:SettingsFile)) {
        Write-Host "[设置] 配置文件缺失，回退至内置默认值" -ForegroundColor Yellow
        return @{
            run_mode      = "interactive"
            check_targets = @("baidu.com", "sina.com", "bilibili.com")
            repair_order  = @(
                "repair_remove_meta_tunnel", "repair_enable_adapter",
                "repair_renew_dhcp", "repair_reset_winsock",
                "repair_clear_proxy", "repair_reset_dns",
                "repair_restart_services", "repair_fix_hosts"
            )
            log_enabled   = $true
        }
    }

    try {
        $cfg = Get-Content $script:SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Host "[设置] 已成功解析配置文件" -ForegroundColor DarkGray
        Write-Host "       当前策略: $($cfg.run_mode)" -ForegroundColor DarkGray
        return $cfg
    } catch {
        Write-Host "[设置] JSON 解析出错: $_" -ForegroundColor Red
        exit 1
    }
}

# ============================================================
# 提权检测
# ============================================================
function Assert-Administrator {
    $whoAmI = [Security.Principal.WindowsIdentity]::GetCurrent()
    $role   = New-Object Security.Principal.WindowsPrincipal($whoAmI)
    $elevated = $role.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $elevated) {
        Write-Host "[权限] 当前未以管理员身份运行，正在请求提升..." -ForegroundColor Yellow
        $launchInfo = New-Object System.Diagnostics.ProcessStartInfo
        $launchInfo.FileName = "powershell.exe"
        $launchInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($script:BasePath)\netfix.ps1`""
        $launchInfo.Verb = "RunAs"
        try {
            [System.Diagnostics.Process]::Start($launchInfo) | Out-Null
        } catch {
            Write-Host "[权限] 提权请求失败: $_" -ForegroundColor Red
            Write-Host "建议右键脚本选择「以管理员身份运行」" -ForegroundColor Red
            pause
        }
        exit
    }
    Write-Host "[权限] 当前已具备管理员身份" -ForegroundColor Green
}

# ============================================================
# 动态加载子模块
# ============================================================
function Import-SubModules {
    $checkFiles = Get-ChildItem -Path $script:CheckScriptDir -Filter "*.ps1" -ErrorAction SilentlyContinue
    foreach ($item in $checkFiles) {
        try {
            . $item.FullName
            Write-Host "[模块] 检测组件: $($item.Name)" -ForegroundColor DarkGray
        } catch {
            Write-Host "[模块] 加载检测组件异常: $($item.Name) - $_" -ForegroundColor Red
            exit 1
        }
    }

    $fixFiles = Get-ChildItem -Path $script:FixScriptDir -Filter "*.ps1" -ErrorAction SilentlyContinue
    foreach ($item in $fixFiles) {
        try {
            . $item.FullName
            Write-Host "[模块] 修复组件: $($item.Name)" -ForegroundColor DarkGray
        } catch {
            Write-Host "[模块] 加载修复组件异常: $($item.Name) - $_" -ForegroundColor Red
            exit 1
        }
    }
}

# ============================================================
# 分层式全面检查
# ============================================================
function Execute-AllChecks {
    $snapshot = @{}

    Print-Block "健康检查阶段"
    Write-Host ""

    # 第 0 层：互联网连通性（最快，如通过则直接结束）
    $snapshot.reachability = Test-InternetReachability
    $script:ProblemList += $snapshot.reachability.Problems
    Write-Host "  状况: $($snapshot.reachability.Brief)" -ForegroundColor $(if ($snapshot.reachability.Healthy) { "Green" } else { "Red" })

    if ($snapshot.reachability.Healthy) {
        Write-Host ""
        Write-Host "  当前网络可达，后续检查跳过。" -ForegroundColor Green
        return $snapshot
    }

    # 第 1 层：适配器/硬件
    Write-Host ""
    $snapshot.adapter = Inspect-NetAdapterHealth
    $script:ProblemList += $snapshot.adapter.Problems
    Write-Host "  状况: $($snapshot.adapter.Brief)" -ForegroundColor $(if ($snapshot.adapter.Healthy) { "Green" } else { "Red" })

    # 第 2 层：IP/网关/DHCP
    Write-Host ""
    $snapshot.ipstack = Audit-IPConfiguration
    $script:ProblemList += $snapshot.ipstack.Problems
    Write-Host "  状况: $($snapshot.ipstack.Brief)" -ForegroundColor $(if ($snapshot.ipstack.Healthy) { "Green" } else { "Red" })

    # 第 3 层：域名解析
    Write-Host ""
    $snapshot.namespace = Verify-DnsResolution
    $script:ProblemList += $snapshot.namespace.Problems
    Write-Host "  状况: $($snapshot.namespace.Brief)" -ForegroundColor $(if ($snapshot.namespace.Healthy) { "Green" } else { "Red" })

    # 第 4 层：操作系统级环境
    Write-Host ""
    $snapshot.environment = Scan-SystemSettings
    $script:ProblemList += $snapshot.environment.Problems
    Write-Host "  状况: $($snapshot.environment.Brief)" -ForegroundColor $(if ($snapshot.environment.Healthy) { "Green" } else { "Red" })

    return $snapshot
}

# ============================================================
# 输出检查报告
# ============================================================
function Present-CheckReport {
    param($Snapshot)

    Print-Block "检查结论"
    Write-Host ""

    if ($script:ProblemList.Count -eq 0) {
        Write-Host "  ✓ 系统网络各项指标正常" -ForegroundColor Green
        return
    }

    Write-Host "  本次检测共定位 $($script:ProblemList.Count) 项潜在异常：" -ForegroundColor Yellow
    Write-Host ""

    $criticalItems = $script:ProblemList | Where-Object { $_.Severity -eq "error" }
    $minimumItems  = $script:ProblemList | Where-Object { $_.Severity -eq "warning" }

    $counter = 0
    foreach ($item in ($criticalItems + $minimumItems)) {
        $counter++
        $color = if ($item.Severity -eq "error") { "Red" } else { "Yellow" }
        $tag   = if ($item.Severity -eq "error") { "严重" } else { "提醒" }

        Write-Host ("  [{0,2}] [{1}] {2}" -f $counter, $tag, $item.Message) -ForegroundColor $color

        if ($item.Treatments.Count -gt 0) {
            $treatNames = $item.Treatments | ForEach-Object {
                $_.Replace("repair_", "").Replace("_", " ")
            }
            Write-Host ("       推荐操作: {0}" -f ($treatNames -join ", ")) -ForegroundColor DarkGray
        }
        Write-Host ""
    }
}

# ============================================================
# 按名称触发修复
# ============================================================
function Format-FixLabel {
    param([string]$FixCode)
    return $FixCode -replace "^repair_", "" -replace "_", " "
}

function Trigger-SingleFix {
    param([string]$FixCode, [switch]$Silent)

    $scriptFile = Join-Path $script:FixScriptDir "$FixCode.ps1"
    if (-not (Test-Path $scriptFile)) {
        Write-Host "  [略过] 找不到对应修复脚本: $FixCode" -ForegroundColor DarkGray
        return $null
    }

    $fn = "Invoke-$($FixCode -replace '(?:^|-|\.)(.)',{ $args[0].Groups[1].Value.ToUpper() })"
    try {
        $outcome = & $fn -Quiet:$Silent
        Append-Trace "执行修复 $FixCode : $($outcome.message)"
        return $outcome
    } catch {
        Write-Host "  [异常] 修复动作执行出错: $_" -ForegroundColor Red
        Append-Trace "修复 $FixCode 异常: $_"
        return @{ success = $false; message = "运行异常: $_"; changes = @() }
    }
}

# ============================================================
# 人工交互式流程
# ============================================================
function Launch-GuidedFlow {
    param($Snapshot, $Settings)

    Present-CheckReport -Snapshot $Snapshot

    if ($script:ProblemList.Count -eq 0) {
        Write-Host "按任意键结束..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }

    # 汇总全部推荐修复项
    $candidateFixes = @()
    foreach ($p in $script:ProblemList) {
        foreach ($r in $p.Treatments) {
            if ($r -and $candidateFixes -notcontains $r) {
                $candidateFixes += $r
            }
        }
    }

    # 按预设优先级排序
    $prioritized = @()
    foreach ($entry in $Settings.repair_order) {
        if ($candidateFixes -contains $entry) {
            $prioritized += $entry
        }
    }
    foreach ($leftover in $candidateFixes) {
        if ($prioritized -notcontains $leftover) {
            $prioritized += $leftover
        }
    }

    Print-Block "请选择修复项"
    Write-Host ""
    Write-Host "  根据诊断结果，建议依次执行以下修复：" -ForegroundColor Cyan

    for ($n = 0; $n -lt $prioritized.Count; $n++) {
        $label = Format-FixLabel -FixCode $prioritized[$n]
        Write-Host ("  [{0}] {1}" -f ($n + 1), $label) -ForegroundColor White
    }
    Write-Host "  [A] 快速修复（一次性执行上述全部操作）" -ForegroundColor Green
    Write-Host "  [0] 不执行任何修复，直接退出" -ForegroundColor Gray
    Write-Host ""

    $input = Read-Host "请输入你的选择（可多选用逗号分隔，如 1,3,5）"

    if ($input -eq "0" -or $input -eq "") {
        Write-Host "已取消，本次不做任何修复。" -ForegroundColor Gray
        return
    }

    $toExecute = @()
    if ($input -eq "A" -or $input -eq "a") {
        $toExecute = $prioritized
        Write-Host "  已选择：全部修复" -ForegroundColor Green
    } else {
        $nums = $input -split "," | ForEach-Object { $_.Trim() -as [int] }
        foreach ($num in $nums) {
            if ($num -ge 1 -and $num -le $prioritized.Count) {
                $toExecute += $prioritized[$num - 1]
            }
        }
    }

    if ($toExecute.Count -eq 0) {
        Write-Host "未选中任何有效修复项。" -ForegroundColor Yellow
        return
    }

    Print-Block "正在执行修复"
    Write-Host ""
    $fixOutcomes = @()

    foreach ($fix in $toExecute) {
        $label = Format-FixLabel -FixCode $fix
        Write-Host ("  [{0}]" -f $label) -ForegroundColor Yellow

        $outcome = Trigger-SingleFix -FixCode $fix
        $fixOutcomes += @{ FixCode = $fix; Outcome = $outcome }

        if ($outcome -and $outcome.success) {
            Write-Host "    ✓ $($outcome.message)" -ForegroundColor Green
        } elseif ($outcome) {
            Write-Host "    ✗ $($outcome.message)" -ForegroundColor Red
        }

        Start-Sleep -Milliseconds 300
    }

    # 修复完成后二次确认
    Print-Block "修复结果确认"
    Write-Host ""
    Write-Host "  重新验证互联网连通状况..." -ForegroundColor Cyan
    $recheck = Test-InternetReachability -TimeoutMs 3000

    if ($recheck.Healthy) {
        Write-Host ""
        Write-Host "  █████ 网络已恢复正常！█████" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "  ⚠ 当前仍未恢复正常连通，可尝试重启计算机或检查物理链路" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "按任意键结束..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ============================================================
# 无人值守自动修复
# ============================================================
function Launch-AutoFlow {
    param($Snapshot, $Settings)

    if ($Snapshot.reachability.Healthy) {
        Write-Host ""
        Write-Host "  █████ 互联网通路正常，不执行修复 █████" -ForegroundColor Green
        return
    }

    # 汇总推荐修复
    $candidateFixes = @()
    foreach ($p in $script:ProblemList) {
        foreach ($r in $p.Treatments) {
            if ($r -and $candidateFixes -notcontains $r) {
                $candidateFixes += $r
            }
        }
    }

    if ($candidateFixes.Count -eq 0) {
        Write-Host ""
        Write-Host "  ⚠ 未匹配到可用的修复策略" -ForegroundColor Yellow
        return
    }

    # 按优先级排列
    $prioritized = @()
    foreach ($entry in $Settings.repair_order) {
        if ($candidateFixes -contains $entry) {
            $prioritized += $entry
        }
    }
    foreach ($leftover in $candidateFixes) {
        if ($prioritized -notcontains $leftover) {
            $prioritized += $leftover
        }
    }

    Print-Block "全自动修复中"
    Write-Host ""
    Write-Host "  即将依次执行 $($prioritized.Count) 个修复动作..." -ForegroundColor Cyan
    Write-Host ""

    $okCount = 0
    $ngCount = 0
    foreach ($fix in $prioritized) {
        $label = Format-FixLabel -FixCode $fix
        Write-Host ("  [{0}]" -f $label) -ForegroundColor Yellow

        $outcome = Trigger-SingleFix -FixCode $fix -Silent

        if ($outcome -and $outcome.success) {
            Write-Host "    ✓ $($outcome.message)" -ForegroundColor Green
            $okCount++
        } elseif ($outcome) {
            Write-Host "    ⚠ $($outcome.message)" -ForegroundColor DarkYellow
            $ngCount++
        }

        Start-Sleep -Milliseconds 200
    }

    # 二次核验
    Print-Block "修复后核验"
    Write-Host ""
    Write-Host "  重新检测网络连通状况..." -ForegroundColor Cyan
    $recheck = Test-InternetReachability -TimeoutMs 3000

    Write-Host ""
    if ($recheck.Healthy) {
        Write-Host "  █████ 互联网已恢复！累计执行 $okCount 项修复 █████" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ 网络依旧不通，可尝试重启操作系统" -ForegroundColor Yellow
        Write-Host "  成功: $okCount | 未成功: $ngCount" -ForegroundColor Gray
    }
}

# ============================================================
# 持久化活动记录
# ============================================================
function Dump-ActivityLog {
    param([string]$Policy)
    if (-not (Import-UserSettings).log_enabled) { return }

    $logFolder = Join-Path $script:BasePath "logs"
    if (-not (Test-Path $logFolder)) {
        New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
    }

    $logName = Join-Path $logFolder "quicknet_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $content = @"
===== QuickNet 运行记录 =====
时间戳: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
执行策略: $Policy
异常项数量: $($script:ProblemList.Count)

$(($script:ProblemList | ForEach-Object { "[$($_.Severity)] $($_.Message)" }) -join "`n")

$(($script:ActivityLog) -join "`n")
"@

    try {
        $content | Out-File -FilePath $logName -Encoding UTF8
    } catch { }
}

# ============================================================
# 统一入口
# ============================================================
function Entry {
    param([string]$RunAs)

    Show-TitleScreen

    # 1. 用户配置
    $settings = Import-UserSettings

    # 命令行的 RunAs 参数会覆盖配置文件
    if ($RunAs) {
        $settings.run_mode = $RunAs
    }

    # 2. 确认管理员身份
    Assert-Administrator

    # 3. 载入所有诊断 / 修复子脚本
    Write-Host ""
    Print-Block "载入子模块"
    Import-SubModules

    # 4. 逐层诊断
    Write-Host ""
    $snapshot = Execute-AllChecks

    # 5. 按策略执行
    Write-Host ""
    switch ($settings.run_mode) {
        "auto" {
            Launch-AutoFlow -Snapshot $snapshot -Settings $settings
            break
        }
        "interactive" {
            Launch-GuidedFlow -Snapshot $snapshot -Settings $settings
            break
        }
        default {
            Write-Host "未识别的运行策略: $($settings.run_mode)" -ForegroundColor Red
            Write-Host "请在 netfix.config.json 中把 run_mode 填为 'interactive' 或 'auto'" -ForegroundColor Yellow
        }
    }

    # 6. 落盘日志
    Dump-ActivityLog -Policy $settings.run_mode
}

# 启动
Entry -RunAs $RunAs
