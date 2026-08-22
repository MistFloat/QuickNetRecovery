function Invoke-RepairEnableAdapter {
    param([switch]$Quiet)
    if (-not $Quiet) { Write-Host "  [Repair] Enabling disabled adapters..." -ForegroundColor Yellow }
    $disabled = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.HardwareInterface -eq $true -and $_.Status -eq "Disabled" -and $_.Name -notmatch "Bluetooth|Loopback"
    }
    if (-not $disabled) { if (-not $Quiet) { Write-Host "    Nothing to enable" -ForegroundColor Green }; return @{success=$true;message="No disabled adapters";changes=@()} }
    $changes = @()
    $errors = @()
    foreach ($a in $disabled) {
        try {
            Enable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction Stop
            $changes += "Enabled: $($a.Name)"
        }
        catch { $errors += "$($a.Name): $($_.Exception.Message)" }
    }
    $message = "Enabled $($changes.Count) adapter(s)"
    if ($errors.Count -gt 0) { $message += "; failed $($errors.Count)" }
    return @{success=$errors.Count-eq0;message=$message;changes=$changes;errors=$errors}
}
