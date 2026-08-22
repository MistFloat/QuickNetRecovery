function Invoke-RepairResetDns {
    param([switch]$Quiet)
    if (-not $Quiet) { Write-Host "  [Repair] Resetting DNS to auto..." -ForegroundColor Yellow }
    $changes = @()
    $errors = @()
    & ipconfig.exe /flushdns 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $changes += "DNS cache flushed" } else { $errors += "DNS cache flush failed with exit code $LASTEXITCODE" }

    $activeIndexes = @(Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.HardwareInterface -eq $true -and $_.Status -eq "Up" } |
        ForEach-Object { $_.ifIndex })
    $ifaces = @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $activeIndexes -contains $_.InterfaceIndex })
    foreach ($if in $ifaces) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $if.InterfaceIndex -ResetServerAddresses -ErrorAction Stop
            $changes += "DNS reset: $($if.InterfaceAlias)"
        }
        catch { $errors += "$($if.InterfaceAlias): $($_.Exception.Message)" }
    }

    if ($ifaces.Count -eq 0) { $errors += "No active physical adapter was found" }
    $message = if ($errors.Count -eq 0) { "DNS reset to automatic" } else { "DNS reset completed with errors" }
    return @{success=$errors.Count-eq0;message=$message;changes=$changes;errors=$errors}
}
