function Invoke-RepairFixHosts {
    param([switch]$Quiet)
    $hp = "$env:SystemRoot\System32\drivers\etc\hosts"
    if (-not (Test-Path $hp)) { return @{success=$true;message="hosts not found";changes=@()} }
    if (-not $Quiet) { Write-Host "  [Repair] Checking hosts file..." -ForegroundColor Yellow }
    $changes = @()
    $errors = @()
    try {
        $content = @(Get-Content -LiteralPath $hp -ErrorAction Stop)
        $filtered = @($content | Where-Object { $_ -notmatch "^\s*(0\.0\.0\.0|127\.0\.0\.1|::)\s+(baidu|sina|bilibili|huorong)(\.|\s|$)" })
        $removed = $content.Count - $filtered.Count
        if ($removed -eq 0) {
            return @{success=$true;message="No matching hosts entries";changes=@();errors=@()}
        }

        $backup = "$hp.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -LiteralPath $hp -Destination $backup -Force -ErrorAction Stop
        $changes += "Backup: $backup"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllLines($hp, [string[]]$filtered, $utf8NoBom)
        $changes += "Removed $removed entries"
    }
    catch { $errors += $_.Exception.Message }

    $message = if ($errors.Count -eq 0) { "hosts file cleaned" } else { "hosts cleanup failed" }
    return @{success=$errors.Count-eq0;message=$message;changes=$changes;errors=$errors}
}
