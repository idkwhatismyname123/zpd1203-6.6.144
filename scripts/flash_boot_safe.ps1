param(
    [ValidateSet("full", "minimal")]
    [string]$Mode = "full",
    [string]$BootImg = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BootImg)) {
    $BootImg = Join-Path $RepoRoot ("out\" + $Mode + "\boot-" + $Mode + "-6.6.img")
}

if (-not (Test-Path $BootImg)) {
    throw "Boot image not found: $BootImg"
}

$Size = (Get-Item $BootImg).Length
if ($Size -gt 33554432) {
    throw "Refusing to flash: $BootImg is $Size bytes (> 33554432 bytes)."
}

$SumsFile = Join-Path (Split-Path -Parent $BootImg) "SHA256SUMS.txt"
$ImgName = Split-Path -Leaf $BootImg
$Actual = (Get-FileHash -Algorithm SHA256 $BootImg).Hash.ToLower()
if (-not (Test-Path $SumsFile)) {
    throw "Missing SHA256SUMS.txt next to $BootImg"
}
$Line = Select-String -Path $SumsFile -Pattern ([regex]::Escape($ImgName) + "$") | Select-Object -First 1
if (-not $Line) {
    throw "$ImgName not listed in $SumsFile"
}
$Expected = ($Line.Line -split "\s+")[0].ToLower()
if ($Actual -ne $Expected) {
    throw "SHA256 mismatch! Expected $Expected, got $Actual"
}
Write-Host "[PASS] Verified $ImgName ($Size bytes, SHA256=$Actual)"

$Devs = & fastboot devices
if (-not $Devs) {
    throw "No fastboot device detected."
}

$SlotOut = (& fastboot getvar current-slot 2>&1) -join "`n"
Write-Host $SlotOut
if ($SlotOut -notmatch "current-slot:\s*a\b") {
    throw "Refusing to flash: current-slot is NOT 'a'. Stock super dynamic partitions only exist on slot _a!"
}

Write-Host ""
Write-Host "WARNING: This will overwrite partition boot_a on the connected ZPD1203 device." -ForegroundColor Yellow
Write-Host "Recommended first step: test non-destructively using scripts\test_fastboot_boot.ps1" -ForegroundColor Cyan
$Confirm = Read-Host "Type exactly 'FLASH ZPD1203 BOOT_A' to proceed"
if ($Confirm -cne "FLASH ZPD1203 BOOT_A") {
    Write-Host "Aborted by user."
    exit 1
}

& fastboot flash boot_a $BootImg
Write-Host "[DONE] Flashed $BootImg to boot_a. Reboot manually with: fastboot reboot"
