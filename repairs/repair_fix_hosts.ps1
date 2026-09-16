function Invoke-RepairFixHosts {
    param(
        [switch]$Quiet,
        [string[]]$Targets = @("baidu.com", "sina.com", "bilibili.com"),
        [string]$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    )
    $hp = $HostsPath
    if (-not (Test-Path $hp)) { return @{success=$true;message="hosts not found";changes=@()} }
    if (-not $Quiet) { Write-Host "  [Repair] Checking hosts file..." -ForegroundColor Yellow }
    $changes = @()
    $errors = @()
    try {
        $content = @(Get-Content -LiteralPath $hp -ErrorAction Stop)
        $targetNames = @($Targets | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
        if ($targetNames.Count -eq 0) {
            return @{success=$true;message="No hosts targets configured";changes=@();errors=@()}
        }

        $removed = 0
        $filtered = @(foreach ($line in $content) {
            $segments = $line -split '#', 2
            $body = $segments[0].Trim()
            $comment = if ($segments.Count -gt 1) { $segments[1] } else { $null }
            $parts = @($body -split '\s+' | Where-Object { $_ })
            if ($parts.Count -lt 2 -or $parts[0] -notin @("0.0.0.0", "127.0.0.1", "::", "::1")) {
                $line
                continue
            }

            $remainingNames = @($parts[1..($parts.Count - 1)] | Where-Object {
                if ($targetNames -contains $_.ToLowerInvariant()) { $removed++; return $false }
                return $true
            })
            if ($remainingNames.Count -gt 0) {
                $newLine = "$($parts[0])`t$($remainingNames -join ' ')"
                if ($comment -ne $null) { $newLine += " #$comment" }
                $newLine
            }
            elseif ($comment -ne $null) {
                "#$comment"
            }
        })
        if ($removed -eq 0) {
            return @{success=$true;message="No matching hosts entries";changes=@();errors=@()}
        }

        $backup = "$hp.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -LiteralPath $hp -Destination $backup -Force -ErrorAction Stop
        $changes += "Backup: $backup"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllLines($hp, [string[]]$filtered, $utf8NoBom)
        $changes += "Removed $removed blocked hostname mapping(s)"
    }
    catch { $errors += $_.Exception.Message }

    $message = if ($errors.Count -eq 0) { "hosts file cleaned" } else { "hosts cleanup failed" }
    return @{success=$errors.Count-eq0;message=$message;changes=$changes;errors=$errors}
}
