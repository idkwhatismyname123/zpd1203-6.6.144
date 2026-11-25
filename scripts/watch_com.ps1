param(
    [string]$Port = "",
    [int]$BaudRate = 115200,
    [string]$LogFile = "",
    [int]$WaitSeconds = 120
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($LogFile)) {
    $OutDir = Join-Path $RepoRoot "out"
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $LogFile = Join-Path $OutDir ("com_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
}

function Find-ZpdComPort {
    $candidates = @()
    try {
        $pnp = Get-CimInstance Win32_PnPEntity -Filter "Name LIKE '%(COM%'" -ErrorAction SilentlyContinue
        foreach ($dev in $pnp) {
            if ($dev.Name -match '\((COM\d+)\)') {
                $com = $matches[1]
                $score = 0
                if ($dev.Name -match 'ZPD1203|CDC|Gadget|Serial Device|USB Serial|MediaTek') { $score += 10 }
                if ($dev.PNPDeviceID -match 'VID_1D6B&PID_0104|VID_0E8D&PID_2006|VID_0E8D&PID_2000') { $score += 50 }
                $candidates += [PSCustomObject]@{ Port = $com; Name = $dev.Name; Score = $score }
            }
        }
    } catch {
        # Fallback if WMI/CIM unavailable
    }
    if ($candidates.Count -gt 0) {
        return ($candidates | Sort-Object Score -Descending | Select-Object -First 1)
    }
    $rawPorts = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
    if ($rawPorts.Count -gt 0) {
        return [PSCustomObject]@{ Port = $rawPorts[-1]; Name = $rawPorts[-1]; Score = 0 }
    }
    return $null
}

$targetPort = $Port
if ([string]::IsNullOrWhiteSpace($targetPort)) {
    Write-Host "[INFO] Waiting up to $WaitSeconds s for ZPD1203 USB CDC-ACM COM port (VID 1D6B/0104 or 0E8D/2006)..."
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        $found = Find-ZpdComPort
        if ($found -and $found.Score -ge 10) {
            $targetPort = $found.Port
            Write-Host "[INFO] Auto-detected ZPD1203 COM port: $($found.Port) ($($found.Name))"
            break
        }
        Start-Sleep -Milliseconds 1000
    }
    if ([string]::IsNullOrWhiteSpace($targetPort)) {
        $fallback = Find-ZpdComPort
        if ($fallback) {
            $targetPort = $fallback.Port
            Write-Host "[WARN] ZPD1203 VID not matched; trying available port: $($fallback.Port) ($($fallback.Name))" -ForegroundColor Yellow
        } else {
            throw "No COM port detected within $WaitSeconds seconds. Check USB cable / Device Manager."
        }
    }
}

$sp = New-Object System.IO.Ports.SerialPort($targetPort, $BaudRate, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$sp.DtrEnable = $true
$sp.RtsEnable = $true
$sp.ReadTimeout = 100
$sp.WriteTimeout = 1000
$sp.Encoding = [System.Text.Encoding]::UTF8

$writer = New-Object System.IO.StreamWriter($LogFile, $true, [System.Text.Encoding]::UTF8)
$writer.AutoFlush = $true

Write-Host "[INFO] Connected to $targetPort @ $BaudRate bps. Logging to $LogFile"
Write-Host "[INFO] Interactive commands on ZPD1203 COM: status | pstore | help | unbind | reboot-fb  (Press Ctrl+C to exit)"
Write-Host "--------------------------------------------------------------------------------"

try {
    $sp.Open()
    $sp.WriteLine("status")
    $inputBuf = ""
    while ($true) {
        try {
            $avail = $sp.BytesToRead
            if ($avail -gt 0) {
                $chunk = $sp.ReadExisting()
                Write-Host -NoNewline $chunk
                $writer.Write($chunk)
            }
        } catch [System.TimeoutException] {
            # ignore read timeouts
        }

        $hasKey = $false
        try { $hasKey = [Console]::KeyAvailable } catch { $hasKey = $false }
        if ($hasKey) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq [ConsoleKey]::Enter) {
                Write-Host ""
                $sp.Write($inputBuf + "`n")
                $inputBuf = ""
            } elseif ($k.Key -eq [ConsoleKey]::Backspace) {
                if ($inputBuf.Length -gt 0) {
                    $inputBuf = $inputBuf.Substring(0, $inputBuf.Length - 1)
                    Write-Host -NoNewline "`b `b"
                }
            } elseif ($k.KeyChar -ne "`0") {
                $inputBuf += $k.KeyChar
                Write-Host -NoNewline $k.KeyChar
            }
        }
        Start-Sleep -Milliseconds 30
    }
} finally {
    if ($sp -and $sp.IsOpen) { $sp.Close() }
    if ($writer) { $writer.Dispose() }
    Write-Host ""
    Write-Host "[INFO] Closed $targetPort. Saved log: $LogFile"
}
