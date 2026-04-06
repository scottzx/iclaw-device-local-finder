#Requires -Version 5.1
#
# iClaw 设备发现脚本 (PowerShell 版本，无依赖)
# 扫描局域网发现 openclaw 设备
#
# 用法:
#   ./scan_shell_only.ps1              # 自动检测本机 IP 并扫描
#   ./scan_shell_only.ps1 10.100.70   # 指定网段扫描

param(
    [string]$Subnet
)

$ErrorActionPreference = "Stop"

# 获取本机 IP
function Get-LocalIp {
    $ipOutput = ipconfig 2>$null | Select-String "IPv4"
    foreach ($line in $ipOutput) {
        $match = [regex]::Match($line, "(:\s*)([\d.]+)")
        if ($match.Success) {
            $ip = $match.Groups[2].Value
            if ($ip -and -not $ip.StartsWith("169.254.")) {
                return $ip
            }
        }
    }
    throw "Error: Cannot determine local IP"
}

# 主扫描逻辑
function Main {
    if (-not $Subnet) {
        $localIp = Get-LocalIp
        Write-Host "Local IP: $localIp" -ForegroundColor Cyan
        $Subnet = ($localIp -split '\.')[0..2] -join '.'
    }

    Write-Host "Scanning subnet: $Subnet.x" -ForegroundColor Cyan

    $semaphore = [System.Threading.SemaphoreSlim]::new(50)
    $jobs = @()
    $allResults = @()

    foreach ($i in 1..254) {
        $ip = "$Subnet.$i"

        $null = $semaphore.Wait()
        $job = Start-Job -ScriptBlock {
            param($TargetIp, $ sem)

            try {
                $result = Invoke-RestMethod -Uri "http://${TargetIp}:8080/api/deviceinfo" `
                    -TimeoutSec 2 `
                    -ErrorAction SilentlyContinue

                if ($result -and $result.serial -and $result.serial -ne "null") {
                    [PSCustomObject]@{
                        Ip       = if ($result.ip) { $result.ip } else { $TargetIp }
                        Hostname = if ($result.hostname) { $result.hostname } else { "" }
                        Serial   = $result.serial
                    }
                }
            }
            catch { }
            finally {
                $semaphore.Release()
            }
        } -ArgumentList $ip, $semaphore

        $jobs += $job

        if ($jobs.Count -ge 50) {
            $completed = $jobs | Wait-Job -Any
            $jobs = $jobs | Where-Object { $_.State -eq 'Running' }
        }
    }

    $jobs | Wait-Job | Out-Null
    $allResults = $jobs | Receive-Job -AutoRemoveJob

    # 输出 JSON，与原脚本格式一致
    $devices = $allResults | Where-Object { $_ }
    $jsonItems = $devices | ForEach-Object {
        "{`"ip`":`"$($_.Ip)`",`"hostname`":`"$($_.Hostname)`",`"serial`":`"$($_.Serial)`"}"
    }

    $output = "[`n" + ($jsonItems -join ",`n") + "`n]"
    $output
}

Main
