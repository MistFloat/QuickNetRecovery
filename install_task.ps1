<#
.SYNOPSIS
    安装 / 移除 QuickNet 定时任务 —— 断网时自动触发诊断与修复
.DESCRIPTION
    向 Windows 计划任务库注册一个事件驱动的定时任务：
    - 标识: NetworkDisconnectRunScript
    - 权限: 提权运行
    - 触发条件: Microsoft-Windows-NetworkProfile/Operational 通道中
                NetworkProfile 源发出事件 ID 10001（网络断开连接）
    - 执行动作: 以 auto 模式无窗口运行 QuickNet
#>

param(
    [switch]$Remove  # 删除已安装的任务
)

$JobName   = "NetworkDisconnectRunScript"
$OwnFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptRef = Join-Path $OwnFolder "netfix.ps1"

# ============================================================
# 移除任务
# ============================================================
if ($Remove) {
    $existingCheck = schtasks /query /tn $JobName 2>&1
    if ($LASTEXITCODE -eq 0) {
        schtasks /delete /tn $JobName /f
        Write-Host "[完成] 定时任务已移除: $JobName" -ForegroundColor Green
    } else {
        Write-Host "[信息] 定时任务未注册: $JobName" -ForegroundColor Yellow
    }
    exit 0
}

# ============================================================
# 安装任务
# ============================================================
Write-Host "QuickNet 事件驱动任务安装程序" -ForegroundColor Cyan
Write-Host ""

# 管理员身份校验
$whoAmI   = [Security.Principal.WindowsIdentity]::GetCurrent()
$role     = New-Object Security.Principal.WindowsPrincipal($whoAmI)
if (-not $role.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[错误] 需要管理员身份才能注册计划任务" -ForegroundColor Red
    Write-Host "按任意键退出..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# 主脚本文件存在性检查
if (-not (Test-Path $ScriptRef)) {
    Write-Host "[错误] 找不到核心脚本: $ScriptRef" -ForegroundColor Red
    exit 1
}

# 先清理已有任务
$existingCheck = schtasks /query /tn $JobName 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "[信息] 已有同名任务，将替换为新版本..." -ForegroundColor Yellow
    schtasks /delete /tn $JobName /f
}

# 拼接执行命令
$execLine = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptRef`" -RunAs auto"

# 事件过滤器
# /sc ONEVENT     = 事件为触发器
# /ec             = 事件通道
# /mo             = XPath 过滤 (Provider=NetworkProfile, EventID=10001)
# /ru SYSTEM      = 执行身份为 SYSTEM
# /rl HIGHEST     = 以最高特权级运行
# /f              = 有同名任务时直接覆盖
# /delay 0000:30  = 事件触发后等待 30 秒才开始执行
$eventQuery = "*[System[Provider[@Name='NetworkProfile'] and EventID=10001]]"

$creationResult = schtasks /create `
    /tn $JobName `
    /tr $execLine `
    /sc ONEVENT `
    /ec "Microsoft-Windows-NetworkProfile/Operational" `
    /mo $eventQuery `
    /ru SYSTEM `
    /rl HIGHEST `
    /f `
    /delay 0000:30 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "[完成] 事件驱动任务已成功创建!" -ForegroundColor Green
    Write-Host ""
    Write-Host "任务摘要:" -ForegroundColor Cyan
    Write-Host "  名称: $JobName" -ForegroundColor White
    Write-Host "  触发通道: Microsoft-Windows-NetworkProfile/Operational" -ForegroundColor White
    Write-Host "  触发事件: 10001（网络断开）" -ForegroundColor White
    Write-Host "  冷却延迟: 30 秒" -ForegroundColor White
    Write-Host "  实际执行: netfix.ps1 -RunAs auto" -ForegroundColor White
    Write-Host "  执行账户: SYSTEM / 最高权限" -ForegroundColor White
    Write-Host ""
    Write-Host "网络断开时将自动触发诊断修复流程" -ForegroundColor Green
    Write-Host "要移除请运行: .\install_task.ps1 -Remove" -ForegroundColor Gray
} else {
    Write-Host "[错误] 任务注册失败:" -ForegroundColor Red
    Write-Host $creationResult -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
