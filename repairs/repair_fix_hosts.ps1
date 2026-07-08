function Invoke-RepairFixHosts {
    <#
    .SYNOPSIS
        检查并修复 hosts 文件中的异常条目
    .DESCRIPTION
        对当前 hosts 做一次快照备份，然后过滤掉可能拦截正常访问的可疑记录
    #>
    param([switch]$Quiet)

    $hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
    if (-not (Test-Path $hostsFile)) {
        return @{ success = $true; message = "hosts 文件不存在，无需操作"; changes = @() }
    }

    if (-not $Quiet) { Write-Host "  [修复] 正在审查 hosts 文件内容..." -ForegroundColor Yellow }
    $applied = @()

    # 做一份时间戳备份
    $snapFile = "$hostsFile.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
    try {
        Copy-Item -Path $hostsFile -Destination $snapFile -Force -ErrorAction SilentlyContinue
        $applied += "备份文件已创建: $snapFile"
        if (-not $Quiet) { Write-Host "    → 备份: $snapFile" -ForegroundColor Gray }
    } catch { }

    # 读取内容并剔除锁定知名域名的行
    try {
        $lines = Get-Content -Path $hostsFile -ErrorAction SilentlyContinue
        $clean = $lines | Where-Object {
            $_ -notmatch "^\s*0\.0\.0\.0\s+(baidu|sina|bilibili)" -and
            $_ -notmatch "^\s*127\.0\.0\.1\s+(baidu|sina|bilibili)" -and
            $_ -notmatch "^\s*::\s+(baidu|sina|bilibili)"
        }

        if ($clean.Count -ne $lines.Count) {
            $delta = $lines.Count - $clean.Count
            $clean | Set-Content -Path $hostsFile -Force -ErrorAction SilentlyContinue
            $applied += "已清除 $delta 条可疑 hosts 记录"
            if (-not $Quiet) { Write-Host "    → 已清除 $delta 条可疑记录" -ForegroundColor Green }
        } else {
            if (-not $Quiet) { Write-Host "    → hosts 内容无异常" -ForegroundColor Green }
        }
    } catch {
        if (-not $Quiet) { Write-Host "    → hosts 处理失败: $_" -ForegroundColor Red }
    }

    return @{ success = $true; message = "hosts 文件审查完毕"; changes = $applied }
}
