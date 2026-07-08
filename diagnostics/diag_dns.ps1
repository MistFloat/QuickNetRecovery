function Verify-DnsResolution {
    <#
    .SYNOPSIS
        第 3 层 —— DNS 域名解析验证
    .DESCRIPTION
        确认各接口的 DNS 服务器配置是否正确，并通过实际解析测试验证域名能否被正常解析
    #>
    $problems = @()
    $snap    = @{}

    Write-Host "  [DNS验证] 排查 DNS 服务器与解析能力..." -ForegroundColor Cyan

    # 1. 遍历各网卡的 DNS 服务器列表
    $dnsClients = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceAlias -notmatch "Loopback|Bluetooth" }
    $snap.ServersPerNIC = @()
    foreach ($client in $dnsClients) {
        if ($client.ServerAddresses -and $client.ServerAddresses.Count -gt 0) {
            $snap.ServersPerNIC += @{
                Interface = $client.InterfaceAlias
                Servers   = $client.ServerAddresses
            }
            Write-Host "    $($client.InterfaceAlias) → $($client.ServerAddresses -join ', ')" -ForegroundColor Gray

            if ($client.ServerAddresses -contains "0.0.0.0" -or -not $client.ServerAddresses) {
                $problems += @{
                    Code      = "sdns_no_server"
                    Severity  = "error"
                    Message   = "网卡 '$($client.InterfaceAlias)' 未分配 DNS 解析服务器"
                    Treatments = @("repair_reset_dns", "repair_renew_dhcp")
                }
            }
        }
    }

    # 2. 对知名域名进行实际解析测试
    $testDomains = @("baidu.com", "sina.com", "bilibili.com")
    $snap.Results = @()
    $atLeastOnePass = $false

    foreach ($domain in $testDomains) {
        try {
            $answer = [System.Net.Dns]::GetHostAddresses($domain)
            if ($answer.Count -gt 0) {
                $atLeastOnePass = $true
                $snap.Results += @{
                    Domain   = $domain
                    Success  = $true
                    IPs      = $answer.IPAddressToString
                }
                Write-Host "    [OK] $domain → $($answer.IPAddressToString -join ', ')" -ForegroundColor Green
            }
        } catch {
            $snap.Results += @{
                Domain  = $domain
                Success = $false
            }
            Write-Host "    [FAIL] $domain 解析失败" -ForegroundColor Red
        }
    }

    if (-not $atLeastOnePass) {
        $problems += @{
            Code       = "sdns_resolve_all_fail"
            Severity   = "error"
            Message    = "全部测试域名的 DNS 解析均失败，疑似 DNS 服务不可用"
            Treatments = @("repair_reset_dns", "repair_renew_dhcp", "repair_clear_proxy")
        }
    }

    return @{
        Healthy  = $atLeastOnePass
        Problems = $problems
        Raw      = $snap
        Brief    = if ($atLeastOnePass) { "DNS 解析功能正常" } else { "DNS 解析功能异常" }
    }
}
