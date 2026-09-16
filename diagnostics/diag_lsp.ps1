function Invoke-DiagLsp {
    Write-Host "  [6/8 LSP] Winsock catalog integrity..." -ForegroundColor Cyan
    $issues = @()
    $data = @{}
    $catalogOutput = @(& netsh.exe winsock show catalog 2>&1)
    $catalogExitCode = $LASTEXITCODE
    $catalogText = $catalogOutput -join "`n"
    $data.ExitCode = $catalogExitCode

    if ($catalogExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($catalogText)) {
        $issues += @{ Code = "lsp_catalog_unreadable"; Severity = "error"; Message = "Winsock catalog cannot be read"; Repairs = @("repair_reset_winsock") }
        return @{ Passed = $false; Issues = $issues; Raw = $data; Summary = "Winsock catalog cannot be read" }
    }

    $providerPaths = @()
    # Only inspect provider-path fields. Namespace descriptions may contain DLL
    # resource references that are not loadable providers on newer Windows.
    $pathMatches = [regex]::Matches($catalogText, '(?im)^\s*(?:Provider Path|\u63d0\u4f9b\u7a0b\u5e8f\u8def\u5f84)\s*:\s*((?:%SystemRoot%|[A-Z]:\\)[^\r\n]*?\.dll)\s*$')
    foreach ($match in $pathMatches) {
        $path = [Environment]::ExpandEnvironmentVariables($match.Groups[1].Value.Trim())
        if ($providerPaths -notcontains $path) { $providerPaths += $path }
    }
    $data.ProviderPaths = $providerPaths

    if ($catalogText -notmatch '(?i)mswsock\.dll') {
        $issues += @{ Code = "lsp_core_provider_missing"; Severity = "error"; Message = "Core Winsock provider mswsock.dll is missing from the catalog"; Repairs = @("repair_reset_winsock") }
    }

    foreach ($path in $providerPaths) {
        if (-not (Test-Path -LiteralPath $path)) {
            $issues += @{ Code = "lsp_provider_file_missing"; Severity = "error"; Message = "Winsock provider file is missing: $path"; Repairs = @("repair_reset_winsock") }
            continue
        }

        $signature = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction SilentlyContinue
        $isSystemProvider = $path.StartsWith($env:SystemRoot, [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $isSystemProvider) {
            $issues += @{ Code = "lsp_third_party_provider"; Severity = "warning"; Message = "Third-party Winsock provider should be reviewed: $path"; Repairs = @() }
        }
        if ($signature -and $signature.Status -ne "Valid") {
            $issues += @{ Code = "lsp_provider_signature"; Severity = "warning"; Message = "Winsock provider signature status $($signature.Status): $path"; Repairs = @() }
        }
    }

    $chainLengths = @([regex]::Matches($catalogText, '(?im)Protocol Chain Length:\s*(-?\d+)') | ForEach-Object { [int]$_.Groups[1].Value })
    if (@($chainLengths | Where-Object { $_ -lt 1 }).Count -gt 0) {
        $issues += @{ Code = "lsp_invalid_chain"; Severity = "error"; Message = "Winsock catalog contains an invalid protocol chain"; Repairs = @("repair_reset_winsock") }
    }

    $data.ProviderCount = $providerPaths.Count
    Write-Host "    [OK] Winsock catalog readable; provider DLLs: $($providerPaths.Count)" -ForegroundColor Green
    $hasError = @($issues | Where-Object { $_.Severity -eq "error" }).Count -gt 0
    return @{
        Passed = -not $hasError
        Issues = $issues
        Raw = $data
        Summary = if ($hasError) { "Winsock/LSP integrity problem detected" } else { "Winsock/LSP catalog OK" }
    }
}
