function Invoke-RepairRestartServices {
    param([switch]$Quiet)
    if (-not $Quiet) { Write-Host "  [Repair] Restarting services..." -ForegroundColor Yellow }
    $svcs = @{Dhcp="DHCP Client";Dnscache="DNS Client";NlaSvc="NLA Service";LanmanWorkstation="Workstation";LanmanServer="Server"}
    $changes = @()
    $errors = @()
    foreach ($s in $svcs.Keys) {
        try {
            $sv = Get-Service $s -ErrorAction Stop
            if ($sv.Status -eq "Running") {
                Restart-Service -Name $s -Force -ErrorAction Stop
                $changes += "Restarted: $($svcs[$s])"
            }
            else {
                Start-Service -Name $s -ErrorAction Stop
                $changes += "Started: $($svcs[$s])"
            }
        }
        catch { $errors += "$($svcs[$s]): $($_.Exception.Message)" }
    }
    $message = "Processed $($changes.Count) service(s)"
    if ($errors.Count -gt 0) { $message += "; failed $($errors.Count)" }
    return @{success=$errors.Count-eq0;message=$message;changes=$changes;errors=$errors}
}
