function Test-NetQuickFixRepairMetaName {
    param(
        [string]$Name,
        [string[]]$Patterns
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    foreach ($pattern in $Patterns) {
        try { if ($Name -match $pattern) { return $true } } catch {}
    }
    return $false
}

function Invoke-RepairRemoveMetaTunnel {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param(
        [switch]$Quiet,
        [string[]]$Patterns = @(
            "(?i)Meta.*(?:Tunnel|Channel)",
            "(?i)(?:Tunnel|Channel).*Meta"
        )
    )

    $adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue | Where-Object {
        (Test-NetQuickFixRepairMetaName -Name $_.Name -Patterns $Patterns) -or
        (Test-NetQuickFixRepairMetaName -Name $_.InterfaceDescription -Patterns $Patterns)
    })
    $pnpDevices = @(Get-PnpDevice -Class Net -ErrorAction SilentlyContinue | Where-Object {
        Test-NetQuickFixRepairMetaName -Name $_.FriendlyName -Patterns $Patterns
    })

    foreach ($adapter in $adapters) {
        if ($adapter.PnPDeviceID -and $pnpDevices.InstanceId -notcontains $adapter.PnPDeviceID) {
            $pnpDevices += [pscustomobject]@{
                FriendlyName = $adapter.InterfaceDescription
                InstanceId = $adapter.PnPDeviceID
                Status = $adapter.Status
            }
        }
    }

    $pnpDevices = @($pnpDevices | Where-Object { $_.InstanceId } | Sort-Object InstanceId -Unique)
    if ($pnpDevices.Count -eq 0) {
        if (-not $Quiet) { Write-Host "  [Repair] No Meta Tunnel/Channel device found" -ForegroundColor Green }
        return @{ success = $true; message = "No Meta Tunnel/Channel device found"; changes = @(); errors = @() }
    }

    $changes = @()
    $errors = @()
    foreach ($device in $pnpDevices) {
        $adapter = $adapters | Where-Object { $_.PnPDeviceID -eq $device.InstanceId } | Select-Object -First 1
        $displayName = if ($device.FriendlyName) { $device.FriendlyName } else { $device.InstanceId }
        if (-not $PSCmdlet.ShouldProcess("$displayName [$($device.InstanceId)]", "Remove network device")) {
            $changes += "Would remove: $displayName [$($device.InstanceId)]"
            continue
        }

        if (-not $Quiet) { Write-Host "  [Repair] Removing: $displayName" -ForegroundColor Yellow }
        if ($adapter -and $adapter.Status -ne "Disabled") {
            try {
                Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                $changes += "Disabled adapter: $($adapter.Name)"
            }
            catch { $errors += "Disable $($adapter.Name): $($_.Exception.Message)" }
        }

        $removeOutput = @(& pnputil.exe /remove-device $device.InstanceId 2>&1)
        if ($LASTEXITCODE -eq 0) {
            $changes += "Removed device: $displayName [$($device.InstanceId)]"
        }
        else {
            $details = ($removeOutput -join " ").Trim()
            $errors += "Remove $displayName failed with exit code $LASTEXITCODE. $details"
        }
    }

    $message = "Processed $($pnpDevices.Count) Meta Tunnel/Channel device(s)"
    if ($errors.Count -gt 0) { $message += "; errors $($errors.Count)" }
    return @{ success = $errors.Count -eq 0; message = $message; changes = $changes; errors = $errors }
}
