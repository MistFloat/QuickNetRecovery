<#
.SYNOPSIS
    Installs or removes the event-driven NetQuickFix scheduled task.
.DESCRIPTION
    The task starts NetQuickFix in automatic mode 30 seconds after Windows logs
    NetworkProfile event 10001 (network disconnected).
#>

[CmdletBinding()]
param(
    [switch]$Remove,
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"
$taskName = "NetworkDisconnectRunScript"
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mainScript = Join-Path $projectDir "netfix.ps1"
$powerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $ValidateOnly -and -not (Test-IsAdministrator)) {
    Write-Host "Requesting administrator permission..." -ForegroundColor Yellow
    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
    if ($Remove) { $arguments += " -Remove" }

    try {
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $powerShellPath
        $processInfo.Arguments = $arguments
        $processInfo.Verb = "RunAs"
        [System.Diagnostics.Process]::Start($processInfo) | Out-Null
        exit 0
    }
    catch {
        throw "Administrator permission was not granted. $($_.Exception.Message)"
    }
}

$scheduler = New-Object -ComObject "Schedule.Service"
$scheduler.Connect()
$rootFolder = $scheduler.GetFolder("\")

if ($Remove) {
    try {
        $rootFolder.GetTask($taskName) | Out-Null
        $rootFolder.DeleteTask($taskName, 0)
        Write-Host "Scheduled task removed: $taskName" -ForegroundColor Green
    }
    catch {
        if ($_.Exception.HResult -eq -2147024894) {
            Write-Host "Scheduled task is not installed: $taskName" -ForegroundColor Yellow
        }
        else {
            throw
        }
    }
    exit 0
}

if (-not (Test-Path -LiteralPath $mainScript)) {
    throw "Main script not found: $mainScript"
}
if (-not (Test-Path -LiteralPath $powerShellPath)) {
    throw "Windows PowerShell not found: $powerShellPath"
}

$taskDefinition = $scheduler.NewTask(0)
$taskDefinition.RegistrationInfo.Description = "Run NetQuickFix after a network disconnect event"
$taskDefinition.RegistrationInfo.Author = "NetQuickFix"

$taskDefinition.Principal.UserId = "SYSTEM"
$taskDefinition.Principal.LogonType = 5       # TASK_LOGON_SERVICE_ACCOUNT
$taskDefinition.Principal.RunLevel = 1       # TASK_RUNLEVEL_HIGHEST

$taskDefinition.Settings.Enabled = $true
$taskDefinition.Settings.StartWhenAvailable = $true
$taskDefinition.Settings.DisallowStartIfOnBatteries = $false
$taskDefinition.Settings.StopIfGoingOnBatteries = $false
$taskDefinition.Settings.ExecutionTimeLimit = "PT5M"
$taskDefinition.Settings.MultipleInstances = 2 # TASK_INSTANCES_IGNORE_NEW

$logName = "Microsoft-Windows-NetworkProfile/Operational"
$providerName = "Microsoft-Windows-NetworkProfile"
$subscription = "<QueryList><Query Id='0' Path='$logName'><Select Path='$logName'>*[System[Provider[@Name='$providerName'] and EventID=10001]]</Select></Query></QueryList>"
$trigger = $taskDefinition.Triggers.Create(0) # TASK_TRIGGER_EVENT
$trigger.Id = "NetworkDisconnected"
$trigger.Enabled = $true
$trigger.Subscription = $subscription
$trigger.Delay = "PT30S"

$action = $taskDefinition.Actions.Create(0) # TASK_ACTION_EXEC
$action.Path = $powerShellPath
$action.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$mainScript`" -RunAs auto -NoPause"
$action.WorkingDirectory = $projectDir

if ($ValidateOnly) {
    [xml]$taskDefinition.XmlText | Out-Null
    Write-Host "Scheduled task definition: OK" -ForegroundColor Green
    exit 0
}

# TASK_CREATE_OR_UPDATE = 6; TASK_LOGON_SERVICE_ACCOUNT = 5
$rootFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, "SYSTEM", $null, 5, $null) | Out-Null

$registeredTask = $rootFolder.GetTask($taskName)
if (-not $registeredTask.Enabled) {
    throw "The scheduled task was registered but is disabled."
}

Write-Host "Scheduled task installed successfully." -ForegroundColor Green
Write-Host "  Name:       $taskName"
Write-Host "  Event:      $providerName / 10001"
Write-Host "  Delay:      30 seconds"
Write-Host "  Account:    SYSTEM (highest privileges)"
Write-Host "  Action:     netfix.ps1 -RunAs auto -NoPause"
Write-Host "  Remove:     .\install_task.ps1 -Remove" -ForegroundColor Gray
