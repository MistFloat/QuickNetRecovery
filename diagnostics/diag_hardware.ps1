function Test-NetQuickFixMetaName {
    param(
        [string]$Name,
        [string[]]$Patterns
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    foreach ($pattern in $Patterns) {
        try {
            if ($Name -match $pattern) { return $true }
        }
        catch {}
    }
    return $false
}

function Invoke-DiagHardware {
    param(
        [string[]]$MetaAdapterPatterns = @(
            "(?i)Meta.*(?:Tunnel|Channel)",
            "(?i)(?:Tunnel|Channel).*Meta"
        )
    )

    Write-Host "  [1/8 Hardware] Adapter, link and device status..." -ForegroundColor Cyan
    $issues = @()
    $data = @{}
    $adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue)
    $physical = @($adapters | Where-Object { $_.HardwareInterface -eq $true -and -not $_.Hidden })
    $connected = @($physical | Where-Object { $_.Status -eq "Up" -and $_.AdminStatus -eq "Up" })
    $disabled = @($physical | Where-Object { $_.Status -eq "Disabled" -or $_.AdminStatus -eq "Down" })
    $linkDown = @($physical | Where-Object { $_.AdminStatus -eq "Up" -and $_.Status -ne "Up" })

    $data.AdapterCount = $adapters.Count
    $data.PhysicalCount = $physical.Count
    $data.ConnectedCount = $connected.Count

    if ($physical.Count -eq 0) {
        $issues += @{ Code = "hardware_no_physical"; Severity = "error"; Message = "No physical network adapter was found"; Repairs = @() }
    }
    elseif ($connected.Count -eq 0) {
        if ($disabled.Count -gt 0) {
            $issues += @{ Code = "hardware_adapter_disabled"; Severity = "error"; Message = "All usable physical adapters are disabled"; Repairs = @("repair_enable_adapter") }
        }
        if ($linkDown.Count -gt 0) {
            $names = $linkDown.Name -join ", "
            $issues += @{ Code = "hardware_link_down"; Severity = "error"; Message = "Network link is disconnected on: $names"; Repairs = @() }
        }
    }
    elseif ($disabled.Count -gt 0) {
        $issues += @{ Code = "hardware_adapter_disabled_optional"; Severity = "warning"; Message = "Other physical adapters are disabled: $($disabled.Name -join ', ')"; Repairs = @() }
    }

    foreach ($adapter in $physical) {
        $state = "$($adapter.Status)/$($adapter.MediaConnectionState)"
        $color = if ($adapter.Status -eq "Up") { "Green" } elseif ($adapter.Status -eq "Disabled") { "Yellow" } else { "Red" }
        Write-Host "    [$state] $($adapter.Name) - $($adapter.InterfaceDescription)" -ForegroundColor $color
    }

    $deviceErrors = @(Get-CimInstance Win32_NetworkAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.PhysicalAdapter -eq $true -and $_.ConfigManagerErrorCode -notin @(0, $null)
    })
    foreach ($device in $deviceErrors) {
        $issues += @{ Code = "hardware_device_error"; Severity = "error"; Message = "Device Manager error $($device.ConfigManagerErrorCode): $($device.Name)"; Repairs = @() }
        Write-Host "    [FAIL] Device Manager code $($device.ConfigManagerErrorCode): $($device.Name)" -ForegroundColor Red
    }

    $metaDevices = @()
    foreach ($adapter in $adapters) {
        if ((Test-NetQuickFixMetaName -Name $adapter.Name -Patterns $MetaAdapterPatterns) -or
            (Test-NetQuickFixMetaName -Name $adapter.InterfaceDescription -Patterns $MetaAdapterPatterns)) {
            $metaDevices += [pscustomobject]@{
                AdapterName = $adapter.Name
                FriendlyName = $adapter.InterfaceDescription
                InstanceId = $adapter.PnPDeviceID
                Status = $adapter.Status
            }
        }
    }

    $pnpMeta = @(Get-PnpDevice -Class Net -ErrorAction SilentlyContinue | Where-Object {
        Test-NetQuickFixMetaName -Name $_.FriendlyName -Patterns $MetaAdapterPatterns
    })
    foreach ($device in $pnpMeta) {
        if ($metaDevices.InstanceId -notcontains $device.InstanceId) {
            $metaDevices += [pscustomobject]@{
                AdapterName = $null
                FriendlyName = $device.FriendlyName
                InstanceId = $device.InstanceId
                Status = $device.Status
            }
        }
    }

    $data.MetaDevices = @($metaDevices)
    $data.MetaCount = $metaDevices.Count
    foreach ($meta in $metaDevices) {
        Write-Host "    [INFO] Meta adapter: $($meta.FriendlyName) [$($meta.InstanceId)]" -ForegroundColor DarkYellow
    }

    $hasError = @($issues | Where-Object { $_.Severity -eq "error" }).Count -gt 0
    return @{
        Passed = -not $hasError
        Issues = $issues
        Raw = $data
        Summary = if ($hasError) { "Hardware or link problem detected" } else { "Hardware and link OK" }
    }
}
