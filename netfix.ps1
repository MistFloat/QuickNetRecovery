<#
.SYNOPSIS
    NetQuickFix - Windows network diagnostics and repair.
#>

[CmdletBinding()]
param(
    [ValidateSet("interactive", "auto", "diagnostics")]
    [string]$RunAs,

    [switch]$NoPause
)

$script:MyDir          = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath     = Join-Path $script:MyDir "netfix.config.json"
$script:DiagDir        = Join-Path $script:MyDir "diagnostics"
$script:RepairDir      = Join-Path $script:MyDir "repairs"
$script:AllIssues      = @()
$script:CurrentLogPath = $null
$script:TranscriptOpen = $false

function Write-Banner {
    Clear-Host
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "      NetQuickFix - Network Quick Fix" -ForegroundColor Cyan
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section {
    param([string]$Title)
    Write-Host "`n--- $Title ---" -ForegroundColor White
}

function New-DefaultConfig {
    return [pscustomobject][ordered]@{
        run_mode      = "interactive"
        check_targets = @("baidu.com", "sina.com", "bilibili.com")
        proxy_timeout_ms = 4000
        remove_meta_on_proxy_failure = $true
        meta_adapter_patterns = @(
            "(?i)Meta.*(?:Tunnel|Channel)",
            "(?i)(?:Tunnel|Channel).*Meta"
        )
        repair_order  = @(
            "repair_remove_meta_tunnel",
            "repair_enable_adapter",
            "repair_renew_dhcp",
            "repair_reset_winsock",
            "repair_clear_proxy",
            "repair_reset_dns",
            "repair_restart_services",
            "repair_fix_hosts"
        )
        log_enabled   = $true
    }
}

function Read-Config {
    $config = New-DefaultConfig
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        Write-Host "[Config] File not found, using defaults" -ForegroundColor Yellow
        return $config
    }

    try {
        $loaded = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Host "[Config] Invalid JSON, using defaults: $($_.Exception.Message)" -ForegroundColor Yellow
        return $config
    }

    if ($loaded.run_mode -in @("interactive", "auto", "diagnostics")) {
        $config.run_mode = [string]$loaded.run_mode
    }

    $targets = @($loaded.check_targets | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) })
    if ($targets.Count -gt 0) {
        $config.check_targets = $targets
    }

    $timeoutValue = 0
    if ([int]::TryParse([string]$loaded.proxy_timeout_ms, [ref]$timeoutValue) -and $timeoutValue -ge 500 -and $timeoutValue -le 30000) {
        $config.proxy_timeout_ms = $timeoutValue
    }

    if ($loaded.PSObject.Properties.Name -contains "remove_meta_on_proxy_failure") {
        $config.remove_meta_on_proxy_failure = [bool]$loaded.remove_meta_on_proxy_failure
    }

    $metaPatterns = @($loaded.meta_adapter_patterns | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) })
    if ($metaPatterns.Count -gt 0) {
        $config.meta_adapter_patterns = $metaPatterns
    }

    $repairs = @($loaded.repair_order | Where-Object { $_ -is [string] -and $_ -match '^repair_[a-z0-9_]+$' })
    if ($repairs.Count -gt 0) {
        $config.repair_order = $repairs
    }

    if ($loaded.PSObject.Properties.Name -contains "log_enabled") {
        $config.log_enabled = [bool]$loaded.log_enabled
    }

    return $config
}

function Ensure-Admin {
    param(
        [string]$RunMode,
        [switch]$SkipPause
    )

    if ($env:SKIP_ADMIN_CHECK -eq "1") {
        Write-Host "[Admin] SKIPPED (test mode)" -ForegroundColor DarkGray
        return
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "[Admin] OK" -ForegroundColor Green
        return
    }

    Write-Host "[Admin] Requesting elevation..." -ForegroundColor Yellow
    $scriptPath = Join-Path $script:MyDir "netfix.ps1"
    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -RunAs $RunMode"
    if ($SkipPause) {
        $arguments += " -NoPause"
    }

    try {
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $processInfo.Arguments = $arguments
        $processInfo.Verb = "RunAs"
        [System.Diagnostics.Process]::Start($processInfo) | Out-Null
        exit 0
    }
    catch {
        throw "Administrator permission was not granted. $($_.Exception.Message)"
    }
}

function Start-RunLog {
    param($Config)

    if (-not $Config.log_enabled) {
        return
    }

    try {
        $logDir = Join-Path $script:MyDir "logs"
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null
        }
        $script:CurrentLogPath = Join-Path $logDir ("netfix-{0}-{1}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"), $PID)
        Start-Transcript -LiteralPath $script:CurrentLogPath -Force -ErrorAction Stop | Out-Null
        $script:TranscriptOpen = $true
        Write-Host "[Log] $script:CurrentLogPath" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "[Log] Could not start logging: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Stop-RunLog {
    if ($script:TranscriptOpen) {
        try { Stop-Transcript -ErrorAction Stop | Out-Null } catch {}
        $script:TranscriptOpen = $false
    }
}

function Get-NetQuickFixModuleFiles {
    $moduleFiles = @()
    foreach ($directory in @($script:DiagDir, $script:RepairDir)) {
        if (-not (Test-Path -LiteralPath $directory)) {
            throw "Required module directory is missing: $directory"
        }

        $moduleFiles += @(Get-ChildItem -LiteralPath $directory -Filter "*.ps1" -File | Sort-Object Name)
    }
    return $moduleFiles
}

function Run-Diagnostics {
    param($Config)

    $script:AllIssues = @()
    $results = @{}
    $targets = @($Config.check_targets)
    Write-Section "Diagnosing"

    $results.connectivity = Invoke-DiagConnectivity -Targets $targets
    $script:AllIssues += @($results.connectivity.Issues)
    Write-Host "  => $($results.connectivity.Summary)" -ForegroundColor $(if ($results.connectivity.Passed) { "Green" } else { "Red" })

    $results.hardware = Invoke-DiagHardware -MetaAdapterPatterns @($Config.meta_adapter_patterns)
    $script:AllIssues += @($results.hardware.Issues)
    Write-Host "  => $($results.hardware.Summary)" -ForegroundColor $(if ($results.hardware.Passed) { "Green" } else { "Red" })

    $results.network = Invoke-DiagNetwork
    $script:AllIssues += @($results.network.Issues)
    Write-Host "  => $($results.network.Summary)" -ForegroundColor $(if ($results.network.Passed) { "Green" } else { "Red" })

    $results.dhcp = Invoke-DiagDhcp
    $script:AllIssues += @($results.dhcp.Issues)
    Write-Host "  => $($results.dhcp.Summary)" -ForegroundColor $(if ($results.dhcp.Passed) { "Green" } else { "Red" })

    $results.dns = Invoke-DiagDns -Targets $targets
    $script:AllIssues += @($results.dns.Issues)
    Write-Host "  => $($results.dns.Summary)" -ForegroundColor $(if ($results.dns.Passed) { "Green" } else { "Red" })

    $results.hosts = Invoke-DiagHosts -Targets $targets
    $script:AllIssues += @($results.hosts.Issues)
    Write-Host "  => $($results.hosts.Summary)" -ForegroundColor $(if ($results.hosts.Passed) { "Green" } else { "Red" })

    $results.lsp = Invoke-DiagLsp
    $script:AllIssues += @($results.lsp.Issues)
    Write-Host "  => $($results.lsp.Summary)" -ForegroundColor $(if ($results.lsp.Passed) { "Green" } else { "Red" })

    $metaPresent = $results.hardware.Raw.MetaCount -gt 0
    $results.proxy = Invoke-DiagProxy `
        -Targets $targets `
        -TimeoutMs $Config.proxy_timeout_ms `
        -DirectConnectivityPassed $results.connectivity.Passed `
        -MetaAdapterPresent:$metaPresent `
        -RemoveMetaOnFailure:$Config.remove_meta_on_proxy_failure
    $script:AllIssues += @($results.proxy.Issues)
    Write-Host "  => $($results.proxy.Summary)" -ForegroundColor $(if ($results.proxy.Passed) { "Green" } else { "Red" })

    $results.environment = Invoke-DiagEnvironment
    $script:AllIssues += @($results.environment.Issues)
    Write-Host "  => $($results.environment.Summary)" -ForegroundColor $(if ($results.environment.Passed) { "Green" } else { "Red" })

    return $results
}

function Show-DiagnosticReport {
    Write-Section "Diagnostic Report"
    if ($script:AllIssues.Count -eq 0) {
        Write-Host "  No issues." -ForegroundColor Green
        return
    }

    Write-Host "  Found $($script:AllIssues.Count) issue(s):`n" -ForegroundColor Yellow
    $index = 0
    foreach ($issue in $script:AllIssues) {
        $index++
        $color = if ($issue.Severity -eq "error") { "Red" } else { "Yellow" }
        $label = if ($issue.Severity -eq "error") { "ERROR" } else { "WARN " }
        Write-Host ("  [{0,2}] [{1}] {2}" -f $index, $label, $issue.Message) -ForegroundColor $color
        if (@($issue.Repairs).Count -gt 0) {
            $names = $issue.Repairs | ForEach-Object { $_.Replace("repair_", "").Replace("_", " ") }
            Write-Host ("       Fix: {0}" -f ($names -join ", ")) -ForegroundColor DarkGray
        }
    }
}

function Get-RepairDisplayName {
    param([string]$Name)
    return ($Name -replace "^repair_", "" -replace "_", " ")
}

function Get-RecommendedRepairs {
    param(
        $Config,
        [switch]$ErrorsOnly
    )

    $repairs = @()
    foreach ($issue in $script:AllIssues) {
        if ($ErrorsOnly -and $issue.Severity -ne "error") {
            continue
        }
        foreach ($repair in @($issue.Repairs)) {
            if ($repair -and $repairs -notcontains $repair) {
                $repairs += $repair
            }
        }
    }

    $ordered = @()
    foreach ($configuredRepair in @($Config.repair_order)) {
        if ($repairs -contains $configuredRepair -and $ordered -notcontains $configuredRepair) {
            $ordered += $configuredRepair
        }
    }
    foreach ($repair in $repairs) {
        if ($ordered -notcontains $repair) {
            $ordered += $repair
        }
    }
    return $ordered
}

function Invoke-RepairByCode {
    param(
        [string]$RepairName,
        [switch]$Quiet
    )

    $path = Join-Path $script:RepairDir "$RepairName.ps1"
    if (-not (Test-Path -LiteralPath $path)) {
        return @{ success = $false; message = "Repair module is missing: $RepairName"; changes = @() }
    }

    $parts = $RepairName.Split("_")
    $functionName = "Invoke-"
    foreach ($part in $parts) {
        if ($part.Length -gt 0) {
            $functionName += $part.Substring(0, 1).ToUpper() + $part.Substring(1)
        }
    }

    if (-not (Get-Command -Name $functionName -CommandType Function -ErrorAction SilentlyContinue)) {
        return @{ success = $false; message = "Repair function is missing: $functionName"; changes = @() }
    }

    $repairParameters = @{ Quiet = [bool]$Quiet }
    if ($RepairName -eq "repair_remove_meta_tunnel") {
        $repairParameters.Patterns = @($script:ActiveConfig.meta_adapter_patterns)
        $repairParameters.Confirm = $false
    }
    elseif ($RepairName -eq "repair_fix_hosts") {
        $repairParameters.Targets = @($script:ActiveConfig.check_targets)
    }

    try {
        return & $functionName @repairParameters
    }
    catch {
        return @{ success = $false; message = "Exception: $($_.Exception.Message)"; changes = @() }
    }
}

function Wait-ForExitKey {
    param([switch]$Skip)

    if ($Skip -or [Console]::IsInputRedirected) {
        return
    }

    Write-Host "`nPress any key to close..." -ForegroundColor Gray
    try {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    catch {
        $null = Read-Host
    }
}

function Mode-Interactive {
    param(
        $Results,
        $Config,
        [switch]$SkipPause
    )

    Show-DiagnosticReport
    if ($script:AllIssues.Count -eq 0) {
        Wait-ForExitKey -Skip:$SkipPause
        return
    }

    $ordered = @(Get-RecommendedRepairs -Config $Config)
    if ($ordered.Count -eq 0) {
        Write-Host "`n  No safe automatic repair matches this result." -ForegroundColor Yellow
        Wait-ForExitKey -Skip:$SkipPause
        return
    }

    Write-Section "Select Repair"
    for ($index = 0; $index -lt $ordered.Count; $index++) {
        Write-Host ("  [{0}] {1}" -f ($index + 1), (Get-RepairDisplayName $ordered[$index])) -ForegroundColor White
    }
    Write-Host "  [A] All" -ForegroundColor Green
    Write-Host "  [0] Exit" -ForegroundColor Gray
    $choice = Read-Host "Choose (e.g. 1,2,3 or A)"

    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) {
        return
    }

    $selected = @()
    if ($choice -eq "A") {
        $selected = $ordered
    }
    else {
        foreach ($selectedIndex in ($choice -split "," | ForEach-Object { $_.Trim() -as [int] })) {
            if ($selectedIndex -ge 1 -and $selectedIndex -le $ordered.Count) {
                $repair = $ordered[$selectedIndex - 1]
                if ($selected -notcontains $repair) {
                    $selected += $repair
                }
            }
        }
    }

    if ($selected.Count -eq 0) {
        Write-Host "  No valid repair was selected." -ForegroundColor Yellow
        Wait-ForExitKey -Skip:$SkipPause
        return
    }

    Write-Section "Applying Repairs"
    foreach ($repair in $selected) {
        Write-Host ("  [{0}]" -f (Get-RepairDisplayName $repair)) -ForegroundColor Yellow
        $result = Invoke-RepairByCode $repair
        if ($result.success) {
            Write-Host "    OK: $($result.message)" -ForegroundColor Green
        }
        else {
            Write-Host "    FAIL: $($result.message)" -ForegroundColor Red
            foreach ($detail in @($result.errors)) {
                Write-Host "      $detail" -ForegroundColor DarkYellow
            }
        }
        Start-Sleep -Milliseconds 200
    }

    Write-Section "Verification"
    Write-Host "  Testing connectivity..." -ForegroundColor Cyan
    $verification = Invoke-DiagConnectivity -Targets @($Config.check_targets) -TimeoutMs 3000
    $proxyVerification = Invoke-DiagProxy -Targets @($Config.check_targets) -TimeoutMs $Config.proxy_timeout_ms -DirectConnectivityPassed $verification.Passed
    if ($verification.Passed -and $proxyVerification.Passed) {
        Write-Host "`n  Network and proxy checks passed." -ForegroundColor Green
    }
    else {
        Write-Host "`n  A connectivity or proxy problem remains. Review the log." -ForegroundColor Yellow
    }
    Wait-ForExitKey -Skip:$SkipPause
}

function Mode-Auto {
    param(
        $Results,
        $Config
    )

    # Warning-only repairs can represent intentional user configuration, so they
    # remain available in interactive mode but are ignored in automatic mode.
    $ordered = @(Get-RecommendedRepairs -Config $Config -ErrorsOnly)
    if ($ordered.Count -eq 0) {
        $errorCount = @($script:AllIssues | Where-Object { $_.Severity -eq "error" }).Count
        if ($errorCount -eq 0) {
            Write-Host "`n  No automatic repairs are needed." -ForegroundColor Green
        }
        else {
            Write-Host "`n  No safe automatic repair matches the detected errors." -ForegroundColor Yellow
        }
        return
    }

    Write-Section "Auto Repair"
    Write-Host "  Applying $($ordered.Count) repair(s)..."
    $successful = 0
    foreach ($repair in $ordered) {
        Write-Host ("  [{0}]" -f (Get-RepairDisplayName $repair)) -ForegroundColor Yellow
        $result = Invoke-RepairByCode $repair -Quiet
        if ($result.success) {
            Write-Host "    OK: $($result.message)" -ForegroundColor Green
            $successful++
        }
        else {
            Write-Host "    WARN: $($result.message)" -ForegroundColor DarkYellow
            foreach ($detail in @($result.errors)) {
                Write-Host "      $detail" -ForegroundColor DarkYellow
            }
        }
        Start-Sleep -Milliseconds 200
    }

    Write-Section "Verification"
    $verification = Invoke-DiagConnectivity -Targets @($Config.check_targets) -TimeoutMs 3000
    $proxyVerification = Invoke-DiagProxy -Targets @($Config.check_targets) -TimeoutMs $Config.proxy_timeout_ms -DirectConnectivityPassed $verification.Passed
    if ($verification.Passed -and $proxyVerification.Passed) {
        Write-Host "`n  Network and proxy checks passed. ($successful repair(s) succeeded)" -ForegroundColor Green
    }
    else {
        Write-Host "`n  A connectivity or proxy problem remains. Review the log." -ForegroundColor Yellow
    }
}

function Main {
    Write-Banner
    $config = Read-Config
    if (-not [string]::IsNullOrWhiteSpace($RunAs)) {
        $config.run_mode = $RunAs
    }
    $script:ActiveConfig = $config
    Write-Host "[Config] mode=$($config.run_mode); targets=$($config.check_targets -join ', ')" -ForegroundColor Gray

    Ensure-Admin -RunMode $config.run_mode -SkipPause:$NoPause
    Start-RunLog -Config $config
    try {
        # Dot-source in Main's scope so the imported functions remain visible to
        # the diagnostic and repair functions called below.
        foreach ($moduleFile in @(Get-NetQuickFixModuleFiles)) {
            . $moduleFile.FullName
            Write-Host "[Load] $($moduleFile.Name)" -ForegroundColor DarkGray
        }
        $results = Run-Diagnostics -Config $config
        switch ($config.run_mode) {
            "auto"        { Mode-Auto -Results $results -Config $config }
            "diagnostics" { Show-DiagnosticReport; Wait-ForExitKey -Skip:$NoPause }
            "interactive" { Mode-Interactive -Results $results -Config $config -SkipPause:$NoPause }
        }
    }
    catch {
        Write-Host "`n[Fatal] $($_.Exception.Message)" -ForegroundColor Red
        Wait-ForExitKey -Skip:$NoPause
        throw
    }
    finally {
        Stop-RunLog
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    Main
}
