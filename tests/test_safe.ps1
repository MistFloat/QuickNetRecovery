[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $projectDir "netfix.ps1")
. (Join-Path $projectDir "diagnostics\diag_proxy.ps1")
. (Join-Path $projectDir "diagnostics\diag_hardware.ps1")
. (Join-Path $projectDir "diagnostics\diag_hosts.ps1")
. (Join-Path $projectDir "repairs\repair_fix_hosts.ps1")
. (Join-Path $projectDir "repairs\repair_remove_meta_tunnel.ps1")

function Assert-NetQuickFix {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) { throw $Message }
}

$metaPatterns = @("(?i)Meta.*(?:Tunnel|Channel)", "(?i)(?:Tunnel|Channel).*Meta")
Assert-NetQuickFix (Test-NetQuickFixMetaName -Name "Meta Tunnel" -Patterns $metaPatterns) "Meta Tunnel was not recognized"
Assert-NetQuickFix (Test-NetQuickFixMetaName -Name "Meta Channel" -Patterns $metaPatterns) "Meta Channel was not recognized"
Assert-NetQuickFix (Test-NetQuickFixRepairMetaName -Name "Channel Meta" -Patterns $metaPatterns) "Reverse Meta Channel name was not recognized"

$proxyResult = Invoke-DiagProxy `
    -Targets @("baidu.com") `
    -TimeoutMs 300 `
    -DirectConnectivityPassed $true `
    -MetaAdapterPresent `
    -RemoveMetaOnFailure `
    -ProxyUris @("http://127.0.0.1:65534")
$proxyRepairs = @($proxyResult.Issues | ForEach-Object { $_.Repairs } | Select-Object -Unique)
Assert-NetQuickFix (-not $proxyResult.Passed) "Closed proxy endpoint was not detected"
Assert-NetQuickFix ($proxyRepairs -contains "repair_clear_proxy") "Proxy cleanup was not recommended"
Assert-NetQuickFix ($proxyRepairs -contains "repair_remove_meta_tunnel") "Meta removal was not linked to proxy failure"
$script:AllIssues = @($proxyResult.Issues)
$autoRepairs = @(Get-RecommendedRepairs -Config (New-DefaultConfig) -ErrorsOnly)
Assert-NetQuickFix ($autoRepairs -contains "repair_clear_proxy") "Automatic mode omitted proxy cleanup"
Assert-NetQuickFix ($autoRepairs -contains "repair_remove_meta_tunnel") "Automatic mode omitted Meta removal"

$noMetaRemoval = Invoke-DiagProxy `
    -Targets @("baidu.com") `
    -TimeoutMs 300 `
    -DirectConnectivityPassed $true `
    -MetaAdapterPresent `
    -ProxyUris @("http://127.0.0.1:65534")
$noMetaRepairs = @($noMetaRemoval.Issues | ForEach-Object { $_.Repairs })
Assert-NetQuickFix ($noMetaRepairs -notcontains "repair_remove_meta_tunnel") "Disabled Meta-removal setting was ignored"

$inconclusive = Invoke-DiagProxy `
    -Targets @("baidu.com") `
    -TimeoutMs 300 `
    -DirectConnectivityPassed $false `
    -MetaAdapterPresent `
    -RemoveMetaOnFailure `
    -ProxyUris @("http://127.0.0.1:65533") `
    -TcpProbe { param($Uri, $Timeout) return $true } `
    -HttpProbe { param($Uri, $Target, $Timeout) return [pscustomobject]@{ Success = $false; StatusCode = $null; Error = "Simulated upstream outage" } }
$inconclusiveRepairs = @($inconclusive.Issues | ForEach-Object { $_.Repairs })
Assert-NetQuickFix (-not $inconclusive.ProxyFailureConfirmed) "General outage was incorrectly classified as a confirmed proxy failure"
Assert-NetQuickFix ($inconclusiveRepairs -notcontains "repair_remove_meta_tunnel") "Meta removal was recommended for an inconclusive outage"

$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("NetQuickFixTest-" + [Guid]::NewGuid().ToString("N"))
$tempHosts = Join-Path $tempDir "hosts"
try {
    New-Item -ItemType Directory -Path $tempDir -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectDir "tests\fixtures\hosts_blocked.txt") -Destination $tempHosts -ErrorAction Stop
    $before = Invoke-DiagHosts -Targets @("baidu.com", "bilibili.com") -HostsPath $tempHosts
    Assert-NetQuickFix (-not $before.Passed) "Blocked hosts targets were not detected"

    $repair = Invoke-RepairFixHosts -Targets @("baidu.com", "bilibili.com") -HostsPath $tempHosts -Quiet
    Assert-NetQuickFix $repair.success "hosts repair failed"
    $after = Invoke-DiagHosts -Targets @("baidu.com", "bilibili.com") -HostsPath $tempHosts
    Assert-NetQuickFix $after.Passed "hosts repair did not clear blocked targets"
    $finalContent = Get-Content -LiteralPath $tempHosts -Raw
    Assert-NetQuickFix ($finalContent -match "localhost") "hosts repair removed an unrelated hostname"
    Assert-NetQuickFix ($finalContent -match "example\.com") "hosts repair removed an unrelated entry"
}
finally {
    if (Test-Path -LiteralPath $tempDir) {
        Get-ChildItem -LiteralPath $tempDir -File | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
        Remove-Item -LiteralPath $tempDir -Force
    }
}

Write-Host "Safe diagnostic tests: PASS" -ForegroundColor Green
