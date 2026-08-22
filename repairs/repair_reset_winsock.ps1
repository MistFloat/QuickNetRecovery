function Invoke-RepairResetWinsock {
    param([switch]$Quiet)
    if (-not $Quiet) { Write-Host "  [Repair] Resetting Winsock and TCP/IP..." -ForegroundColor Yellow }
    $changes = @()
    $errors = @()
    & netsh.exe winsock reset 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $changes += "Winsock reset" } else { $errors += "Winsock reset failed with exit code $LASTEXITCODE" }
    & netsh.exe int ip reset 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $changes += "TCP/IP reset" } else { $errors += "TCP/IP reset failed with exit code $LASTEXITCODE" }
    $message = if ($errors.Count -eq 0) { "Winsock and TCP/IP reset; restart recommended" } else { "Network stack reset completed with errors" }
    return @{success=$errors.Count-eq0;message=$message;changes=$changes;errors=$errors}
}
