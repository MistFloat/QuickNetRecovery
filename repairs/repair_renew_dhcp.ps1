function Invoke-RepairRenewDhcp {
    param([switch]$Quiet)
    if (-not $Quiet) { Write-Host "  [Repair] Renewing DHCP..." -ForegroundColor Yellow }
    $changes = @()
    $errors = @()
    $activeIndexes = @(Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.HardwareInterface -eq $true -and $_.Status -eq "Up" } |
        ForEach-Object { $_.ifIndex })
    $dhcpInterfaces = @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $activeIndexes -contains $_.InterfaceIndex -and $_.Dhcp -eq "Enabled" })
    if ($dhcpInterfaces.Count -eq 0) {
        return @{success=$false;message="No active DHCP-enabled physical adapter";changes=@();errors=@()}
    }

    & ipconfig.exe /release 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $changes += "DHCP released" } else { $errors += "ipconfig /release failed with exit code $LASTEXITCODE" }
    Start-Sleep -Milliseconds 500
    & ipconfig.exe /renew 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $changes += "DHCP renewed" } else { $errors += "ipconfig /renew failed with exit code $LASTEXITCODE" }

    $message = if ($errors.Count -eq 0) { "DHCP lease renewed" } else { "DHCP renewal completed with errors" }
    return @{success=$errors.Count-eq0;message=$message;changes=$changes;errors=$errors}
}
