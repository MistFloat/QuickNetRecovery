function Invoke-RepairRemoveMetaTunnel {
    param([switch]$Quiet)
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "(?i)Meta.*Tunnel" -or $_.InterfaceDescription -match "(?i)Meta.*Tunnel"
    }
    if (-not $adapters) { if (-not $Quiet) { Write-Host "  [Repair] No Meta Tunnel adapters found" -ForegroundColor Green }; return @{success=$true;message="Nothing to remove";changes=@()} }
    $changes = @()
    $errors = @()
    foreach ($a in $adapters) {
        if (-not $Quiet) { Write-Host "  [Repair] Processing: $($a.Name)" -ForegroundColor Yellow }
        try {
            Disable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction Stop
            $changes += "Disabled: $($a.Name)"
        }
        catch { $errors += "Disable $($a.Name): $($_.Exception.Message)" }

        try {
            $pnp = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
                $_.FriendlyName -eq $a.Name -or $_.FriendlyName -eq $a.InterfaceDescription
            }
            if ($pnp -and (Get-Command Remove-PnpDevice -ErrorAction SilentlyContinue)) {
                $pnp | Remove-PnpDevice -Confirm:$false -ErrorAction Stop
                $changes += "Removed PnP: $($a.Name)"
            }
            else {
                $wmi = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $a.Name }
                if ($wmi) {
                    Invoke-CimMethod -InputObject $wmi -MethodName Uninstall -ErrorAction Stop | Out-Null
                    $changes += "Removed WMI: $($a.Name)"
                }
            }
        }
        catch {
            $errors += "Remove $($a.Name): $($_.Exception.Message)"
            if (-not $Quiet) { Write-Host "    PnP removal failed: $($_.Exception.Message)" -ForegroundColor DarkYellow }
        }
    }
    $message = "Processed $($adapters.Count) Meta Tunnel adapter(s)"
    if ($errors.Count -gt 0) { $message += "; errors $($errors.Count)" }
    return @{success=$errors.Count-eq0;message=$message;changes=$changes;errors=$errors}
}
