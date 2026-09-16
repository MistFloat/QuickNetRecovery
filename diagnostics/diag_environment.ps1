function Invoke-DiagEnvironment {
    Write-Host "  [8/8 Environment] System and proxy variables..." -ForegroundColor Cyan
    $issues = @()
    $data = @{}
    $proxyVariables = @()

    foreach ($scope in @("Process", "User", "Machine")) {
        $variables = [Environment]::GetEnvironmentVariables($scope)
        foreach ($name in @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY")) {
            if ($variables.Contains($name) -and -not [string]::IsNullOrWhiteSpace([string]$variables[$name])) {
                $value = [string]$variables[$name]
                $proxyVariables += [pscustomobject]@{ Scope = $scope; Name = $name; Value = $value }
                if ($name -ne "NO_PROXY" -and @(ConvertTo-NetQuickFixProxyUris -Value $value).Count -eq 0) {
                    $issues += @{ Code = "environment_invalid_proxy"; Severity = "error"; Message = "Invalid $scope environment variable $name=$value"; Repairs = @("repair_clear_proxy") }
                }
            }
        }
    }
    $data.ProxyVariables = $proxyVariables

    foreach ($name in @("TEMP", "TMP")) {
        $value = [Environment]::GetEnvironmentVariable($name, "Process")
        if ([string]::IsNullOrWhiteSpace($value) -or -not (Test-Path -LiteralPath $value)) {
            $issues += @{ Code = "environment_temp_invalid"; Severity = "warning"; Message = "$name does not point to an existing directory"; Repairs = @() }
        }
    }

    $systemRoot = [Environment]::GetEnvironmentVariable("SystemRoot", "Process")
    if ([string]::IsNullOrWhiteSpace($systemRoot) -or -not (Test-Path -LiteralPath $systemRoot)) {
        $issues += @{ Code = "environment_systemroot_invalid"; Severity = "error"; Message = "SystemRoot is missing or invalid"; Repairs = @() }
    }

    $comSpec = [Environment]::GetEnvironmentVariable("ComSpec", "Process")
    if ([string]::IsNullOrWhiteSpace($comSpec) -or -not (Test-Path -LiteralPath $comSpec)) {
        $issues += @{ Code = "environment_comspec_invalid"; Severity = "warning"; Message = "ComSpec is missing or invalid"; Repairs = @() }
    }

    if ($proxyVariables.Count -eq 0) {
        Write-Host "    [OK] No proxy environment variables are set" -ForegroundColor Green
    }
    else {
        foreach ($variable in $proxyVariables) {
            Write-Host "    [INFO] $($variable.Scope)/$($variable.Name)=$($variable.Value)" -ForegroundColor Gray
        }
    }

    $hasError = @($issues | Where-Object { $_.Severity -eq "error" }).Count -gt 0
    return @{
        Passed = -not $hasError
        Issues = $issues
        Raw = $data
        Summary = if ($hasError) { "Environment variable problem detected" } else { "Environment variables OK" }
    }
}
