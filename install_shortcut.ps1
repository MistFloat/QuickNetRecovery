<#
.SYNOPSIS
    Creates or removes the NetQuickFix desktop shortcut.
#>

[CmdletBinding()]
param(
    [switch]$Remove
)

$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mainScript = Join-Path $projectDir "netfix.ps1"
$desktopDir = [Environment]::GetFolderPath("Desktop")
$shortcutName = ((0x7F51, 0x7EDC, 0x5FEB, 0x901F, 0x4FEE, 0x590D | ForEach-Object { [char]$_ }) -join '')
$shortcutPath = Join-Path $desktopDir "$shortcutName.lnk"

if ($Remove) {
    if (Test-Path -LiteralPath $shortcutPath) {
        Remove-Item -LiteralPath $shortcutPath -Force
        Write-Host "Desktop shortcut removed: $shortcutPath" -ForegroundColor Green
    }
    else {
        Write-Host "Desktop shortcut does not exist: $shortcutPath" -ForegroundColor Yellow
    }
    exit 0
}

if (-not (Test-Path -LiteralPath $mainScript)) {
    throw "Main script not found: $mainScript"
}

$powerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path -LiteralPath $powerShellPath)) {
    throw "Windows PowerShell not found: $powerShellPath"
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powerShellPath
$shortcut.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$mainScript`" -RunAs interactive"
$shortcut.WorkingDirectory = $projectDir
$shortcut.Description = "Launch NetQuickFix network diagnostics and repair"
$shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,18"
$shortcut.Save()

if (-not (Test-Path -LiteralPath $shortcutPath)) {
    throw "Shortcut creation failed: $shortcutPath"
}

Write-Host "Desktop shortcut created: $shortcutPath" -ForegroundColor Green
