function ConvertTo-NetQuickFixProxyUris {
    param([string]$Value)

    $uris = @()
    if ([string]::IsNullOrWhiteSpace($Value)) { return $uris }
    $entries = @($Value -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($entry in $entries) {
        $candidate = $entry.Trim()
        if ($candidate -match '^(?i)(http|https)=(.+)$') {
            $scheme = $matches[1].ToLowerInvariant()
            $candidate = "${scheme}://$($matches[2])"
        }
        elseif ($candidate -match '^(?i)(socks|socks5)=') {
            continue
        }
        elseif ($candidate -notmatch '^[a-z][a-z0-9+.-]*://') {
            $candidate = "http://$candidate"
        }

        $uri = $null
        if ([Uri]::TryCreate($candidate, [UriKind]::Absolute, [ref]$uri) -and $uri.Host -and $uri.Port -gt 0) {
            if ($uris.AbsoluteUri -notcontains $uri.AbsoluteUri) { $uris += $uri }
        }
    }
    return $uris
}

function Get-NetQuickFixProxyConfiguration {
    param(
        [string[]]$Targets,
        [string[]]$ProxyUris
    )

    $uris = @()
    $sources = @()
    $invalidValues = @()
    if ($PSBoundParameters.ContainsKey("ProxyUris")) {
        foreach ($value in @($ProxyUris)) {
            $parsed = @(ConvertTo-NetQuickFixProxyUris -Value $value)
            if ($parsed.Count -eq 0) { $invalidValues += $value } else { $uris += $parsed }
        }
        return [pscustomobject]@{ Configured = $ProxyUris.Count -gt 0; Uris = @($uris | Sort-Object AbsoluteUri -Unique); Sources = @("Override"); InvalidValues = $invalidValues }
    }

    $internetSettingsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    $internetSettings = Get-ItemProperty -LiteralPath $internetSettingsPath -ErrorAction SilentlyContinue
    if ($internetSettings -and $internetSettings.ProxyEnable -eq 1) {
        $sources += "InternetSettings"
        if ([string]::IsNullOrWhiteSpace([string]$internetSettings.ProxyServer)) {
            $invalidValues += "ProxyEnable=1 with an empty ProxyServer"
        }
        else {
            $parsed = @(ConvertTo-NetQuickFixProxyUris -Value ([string]$internetSettings.ProxyServer))
            if ($parsed.Count -eq 0) { $invalidValues += [string]$internetSettings.ProxyServer } else { $uris += $parsed }
        }
    }

    $usesAutomaticProxy = $internetSettings -and (
        -not [string]::IsNullOrWhiteSpace([string]$internetSettings.AutoConfigURL) -or
        $internetSettings.AutoDetect -eq 1
    )
    if ($usesAutomaticProxy) {
        $sources += $(if ($internetSettings.AutoDetect -eq 1) { "AutoDetect/PAC" } else { "PAC" })
        try {
            $systemProxy = [System.Net.WebRequest]::GetSystemWebProxy()
            foreach ($target in $Targets) {
                $targetUri = New-Object Uri("https://$target/")
                if (-not $systemProxy.IsBypassed($targetUri)) {
                    $effectiveUri = $systemProxy.GetProxy($targetUri)
                    if ($effectiveUri -and $effectiveUri.AbsoluteUri -ne $targetUri.AbsoluteUri) { $uris += $effectiveUri }
                }
            }
        }
        catch { $invalidValues += [string]$internetSettings.AutoConfigURL }
    }

    $winHttpOutput = @(& netsh.exe winhttp show proxy 2>&1)
    if ($LASTEXITCODE -eq 0) {
        $winHttpText = $winHttpOutput -join "`n"
        $endpointMatches = [regex]::Matches($winHttpText, '(?i)(?:https?://)?(?:localhost|(?:\d{1,3}\.){3}\d{1,3}|[a-z0-9.-]+|\[[0-9a-f:]+\]):\d{1,5}')
        if ($endpointMatches.Count -gt 0) {
            $sources += "WinHTTP"
            foreach ($endpointMatch in $endpointMatches) {
                $parsed = @(ConvertTo-NetQuickFixProxyUris -Value $endpointMatch.Value)
                if ($parsed.Count -gt 0) { $uris += $parsed }
            }
        }
    }

    foreach ($scope in @("Process", "User", "Machine")) {
        $variables = [Environment]::GetEnvironmentVariables($scope)
        foreach ($name in @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY")) {
            if ($variables.Contains($name) -and -not [string]::IsNullOrWhiteSpace([string]$variables[$name])) {
                $sources += "$scope/$name"
                $parsed = @(ConvertTo-NetQuickFixProxyUris -Value ([string]$variables[$name]))
                if ($parsed.Count -eq 0) { $invalidValues += [string]$variables[$name] } else { $uris += $parsed }
            }
        }
    }

    return [pscustomobject]@{
        Configured = $sources.Count -gt 0
        Uris = @($uris | Sort-Object AbsoluteUri -Unique)
        Sources = @($sources | Select-Object -Unique)
        InvalidValues = @($invalidValues | Select-Object -Unique)
    }
}

function Test-NetQuickFixProxyTcp {
    param(
        [Uri]$ProxyUri,
        [int]$TimeoutMs
    )

    $client = $null
    $waitHandle = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $client.BeginConnect($ProxyUri.DnsSafeHost, $ProxyUri.Port, $null, $null)
        $waitHandle = $asyncResult.AsyncWaitHandle
        if (-not $waitHandle.WaitOne($TimeoutMs, $false) -or -not $client.Connected) { return $false }
        $client.EndConnect($asyncResult)
        return $true
    }
    catch { return $false }
    finally {
        if ($waitHandle) { $waitHandle.Close() }
        if ($client) { $client.Close() }
    }
}

function Test-NetQuickFixHttpViaProxy {
    param(
        [Uri]$ProxyUri,
        [string]$Target,
        [int]$TimeoutMs
    )

    $response = $null
    try {
        $request = [System.Net.HttpWebRequest]::Create("https://$Target/")
        $request.Method = "GET"
        $request.Timeout = $TimeoutMs
        $request.ReadWriteTimeout = $TimeoutMs
        $request.AllowAutoRedirect = $false
        $request.UserAgent = "NetQuickFix/1.0"
        $webProxy = New-Object System.Net.WebProxy($ProxyUri.AbsoluteUri, $true)
        $webProxy.UseDefaultCredentials = $true
        $request.Proxy = $webProxy
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        $statusCode = [int]$response.StatusCode
        return [pscustomobject]@{ Success = $statusCode -notin @(407, 502, 503, 504); StatusCode = $statusCode; Error = $null }
    }
    catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            $response = [System.Net.HttpWebResponse]$_.Exception.Response
            $statusCode = [int]$response.StatusCode
            return [pscustomobject]@{ Success = $statusCode -notin @(407, 502, 503, 504); StatusCode = $statusCode; Error = $_.Exception.Message }
        }
        return [pscustomobject]@{ Success = $false; StatusCode = $null; Error = $_.Exception.Message }
    }
    catch {
        return [pscustomobject]@{ Success = $false; StatusCode = $null; Error = $_.Exception.Message }
    }
    finally { if ($response) { $response.Close() } }
}

function Invoke-DiagProxy {
    param(
        [string[]]$Targets = @("baidu.com", "sina.com", "bilibili.com"),
        [ValidateRange(250, 30000)]
        [int]$TimeoutMs = 4000,
        [switch]$MetaAdapterPresent,
        [switch]$RemoveMetaOnFailure,
        [Nullable[bool]]$DirectConnectivityPassed = $null,
        [string[]]$ProxyUris,
        [scriptblock]$TcpProbe,
        [scriptblock]$HttpProbe
    )

    Write-Host "  [7/8 IE Proxy] Configuration and real proxy access..." -ForegroundColor Cyan
    $issues = @()
    $data = @{}
    if ($PSBoundParameters.ContainsKey("ProxyUris")) {
        $configuration = Get-NetQuickFixProxyConfiguration -Targets $Targets -ProxyUris $ProxyUris
    }
    else {
        $configuration = Get-NetQuickFixProxyConfiguration -Targets $Targets
    }
    $data.Sources = $configuration.Sources
    $data.ProxyUris = @($configuration.Uris.AbsoluteUri)
    $data.InvalidValues = $configuration.InvalidValues

    foreach ($invalidValue in $configuration.InvalidValues) {
        $issues += @{ Code = "proxy_invalid_config"; Severity = "error"; Message = "Invalid proxy setting: $invalidValue"; Repairs = @("repair_clear_proxy") }
    }

    if (-not $configuration.Configured) {
        Write-Host "    [OK] No IE, PAC or environment proxy is configured" -ForegroundColor Green
        return @{
            Passed = $true; Issues = $issues; Raw = $data; Summary = "No proxy configured"
            ProxyConfigured = $false; ProxyFailed = $false; ProxyFailureConfirmed = $false
        }
    }

    if ($configuration.Uris.Count -eq 0) {
        $repairs = @()
        $repairs += "repair_clear_proxy"
        if ($MetaAdapterPresent -and $RemoveMetaOnFailure) { $repairs += "repair_remove_meta_tunnel" }
        $issues += @{ Code = "proxy_endpoint_missing"; Severity = "error"; Message = "Proxy is configured but no usable endpoint could be resolved"; Repairs = $repairs }
        return @{
            Passed = $false; Issues = $issues; Raw = $data; Summary = "Proxy configuration is invalid"
            ProxyConfigured = $true; ProxyFailed = $true; ProxyFailureConfirmed = $true
        }
    }

    $endpointResults = @()
    $anyProxyWorks = $false
    $anyTcpReachable = $false
    foreach ($proxyUri in $configuration.Uris) {
        $tcpReachable = if ($TcpProbe) {
            [bool](& $TcpProbe $proxyUri $TimeoutMs)
        }
        else {
            Test-NetQuickFixProxyTcp -ProxyUri $proxyUri -TimeoutMs $TimeoutMs
        }
        if ($tcpReachable) { $anyTcpReachable = $true }
        $httpResults = @()
        if ($tcpReachable) {
            foreach ($target in $Targets) {
                $httpResult = if ($HttpProbe) {
                    & $HttpProbe $proxyUri $target $TimeoutMs
                }
                else {
                    Test-NetQuickFixHttpViaProxy -ProxyUri $proxyUri -Target $target -TimeoutMs $TimeoutMs
                }
                $httpResults += [pscustomobject]@{ Target = $target; Success = $httpResult.Success; StatusCode = $httpResult.StatusCode; Error = $httpResult.Error }
                if ($httpResult.Success) {
                    $anyProxyWorks = $true
                    break
                }
            }
        }

        $endpointResults += [pscustomobject]@{
            ProxyUri = $proxyUri.AbsoluteUri
            TcpReachable = $tcpReachable
            HttpResults = $httpResults
        }
        if ($tcpReachable -and $anyProxyWorks) {
            Write-Host "    [OK] $($proxyUri.AbsoluteUri) can access the Internet" -ForegroundColor Green
        }
        elseif (-not $tcpReachable) {
            Write-Host "    [FAIL] Proxy endpoint is unreachable: $($proxyUri.AbsoluteUri)" -ForegroundColor Red
        }
        else {
            Write-Host "    [FAIL] Proxy accepts TCP but cannot reach test sites: $($proxyUri.AbsoluteUri)" -ForegroundColor Red
        }
    }
    $data.EndpointResults = $endpointResults

    $proxyFailureConfirmed = -not $anyProxyWorks -and (
        -not $anyTcpReachable -or $DirectConnectivityPassed -eq $true
    )
    if (-not $anyProxyWorks) {
        $severity = if ($proxyFailureConfirmed) { "error" } else { "warning" }
        $repairs = @()
        if ($proxyFailureConfirmed) { $repairs += "repair_clear_proxy" }
        if ($proxyFailureConfirmed -and $MetaAdapterPresent -and $RemoveMetaOnFailure) { $repairs += "repair_remove_meta_tunnel" }
        $message = if ($proxyFailureConfirmed) {
            "Configured proxy cannot access any test target"
        }
        else {
            "Proxy access failed, but direct connectivity also failed; proxy failure is not confirmed"
        }
        $issues += @{
            Code = if ($proxyFailureConfirmed) { "proxy_access_failed" } else { "proxy_access_inconclusive" }
            Severity = $severity
            Message = $message
            Repairs = $repairs
        }
    }

    return @{
        Passed = $anyProxyWorks
        Issues = $issues
        Raw = $data
        Summary = if ($anyProxyWorks) { "Configured proxy is working" } else { "Configured proxy has failed" }
        ProxyConfigured = $true
        ProxyFailed = -not $anyProxyWorks
        ProxyFailureConfirmed = $proxyFailureConfirmed
    }
}
