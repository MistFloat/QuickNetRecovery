function Invoke-RepairClearProxy {
    param([switch]$Quiet)
    if (-not $Quiet) { Write-Host "  [Repair] Clearing proxy settings..." -ForegroundColor Yellow }
    $changes = @()
    $errors = @()
    $internetSettings = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    try {
        Set-ItemProperty -LiteralPath $internetSettings -Name ProxyEnable -Value 0 -ErrorAction Stop
        Set-ItemProperty -LiteralPath $internetSettings -Name AutoDetect -Value 0 -ErrorAction SilentlyContinue
        Remove-ItemProperty -LiteralPath $internetSettings -Name ProxyServer -ErrorAction SilentlyContinue
        Remove-ItemProperty -LiteralPath $internetSettings -Name AutoConfigURL -ErrorAction SilentlyContinue
        $changes += "User proxy cleared"
    }
    catch { $errors += "User proxy: $($_.Exception.Message)" }

    & netsh.exe winhttp reset proxy 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $changes += "WinHTTP proxy reset" } else { $errors += "WinHTTP reset failed with exit code $LASTEXITCODE" }

    foreach ($scope in @("Process", "User", "Machine")) {
        foreach ($name in @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY")) {
            try {
                if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, $scope))) {
                    [Environment]::SetEnvironmentVariable($name, $null, $scope)
                    $changes += "Removed $scope/$name"
                }
            }
            catch { $errors += "$scope/${name}: $($_.Exception.Message)" }
        }
    }

    $message = if ($errors.Count -eq 0) { "Proxy settings cleared" } else { "Proxy reset completed with errors" }
    return @{success=$errors.Count-eq0;message=$message;changes=$changes;errors=$errors}
}
