param(
    [string]$OutDir = ""
)

$ErrorActionPreference = "Continue"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutDir = Join-Path $RepoRoot ("out\logs_" + $Stamp)
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$AdbDevs = & adb devices
$Connected = ($AdbDevs | Select-String -Pattern "\sdevice$").Count -gt 0

if (-not $Connected) {
    Write-Host "No active ADB device found." -ForegroundColor Yellow
    Write-Host "=== No-UART Offline Crash Forensics ==="
    Write-Host "1. Check Windows Device Manager / COM port for ZPD1203 ACM serial logger (ttyGS1)."
    Write-Host "   Send 'status', 'pstore', or 'reboot-fb' on the COM terminal."
    Write-Host "2. Or readback pstore/expdb via SP Flash Tool / mtkclient from partition 'expdb':"
    Write-Host "   ramoops/pstore DRAM physical base = 0x4d010000 (size 0xe0000)"
    Write-Host "   expdb PL/LK/GZ/AEE forensic parser reference: DEBUGGING.md"
    exit 1
}

Write-Host "[INFO] Collecting ADB kernel, pstore, hardware & Android logs into $OutDir ..."
& adb shell "cat /proc/version" | Out-File (Join-Path $OutDir "proc_version.txt") -Encoding utf8
& adb shell "dmesg" | Out-File (Join-Path $OutDir "dmesg.txt") -Encoding utf8
& adb shell "lsmod" | Out-File (Join-Path $OutDir "lsmod.txt") -Encoding utf8
& adb shell "cat /dev/.pstore_dump.log 2>/dev/null || ls -la /sys/fs/pstore 2>/dev/null" | Out-File (Join-Path $OutDir "pstore.txt") -Encoding utf8
& adb shell "cat /dev/.fb0_bridge.log 2>/dev/null" | Out-File (Join-Path $OutDir "fb0_bridge.log") -Encoding utf8
& adb shell "ls -la /dev/dri /dev/mali0 /dev/ion /dev/stpwmt /dev/wmtWifi /dev/stpbt /dev/input 2>/dev/null" | Out-File (Join-Path $OutDir "dev_nodes.txt") -Encoding utf8
& adb shell "grep -H . /sys/class/power_supply/*/{type,online,status,capacity,voltage_now,current_now,present} 2>/dev/null" | Out-File (Join-Path $OutDir "power_supply.txt") -Encoding utf8
& adb shell "dumpsys battery" | Out-File (Join-Path $OutDir "dumpsys_battery.txt") -Encoding utf8
& adb shell "dumpsys SurfaceFlinger" | Out-File (Join-Path $OutDir "dumpsys_surfaceflinger.txt") -Encoding utf8
& adb logcat -b all -d | Out-File (Join-Path $OutDir "logcat_all.txt") -Encoding utf8
Write-Host "[DONE] Logs saved to $OutDir"
