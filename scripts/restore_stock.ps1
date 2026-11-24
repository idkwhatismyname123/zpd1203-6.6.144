param(
    [string]$StockDir = "D:\备份\p\GeekFlashTool_Readback_20260820162108246",
    [switch]$IncludeVendorAndDtbo
)

$ErrorActionPreference = "Stop"

$Expected = @{
    "boot_a.img"        = "23db8b5325826d95a46d83806c4b27cf8a79861d621da98a29ae9a76edaae9b5"
    "dtbo_a.img"        = "0e2116106f575454eef5c374155443e9332cec67e2563c648528b0a2683a96dc"
    "vendor_boot_a.img" = "5245a4627a3c1cb1f3ac0d6c85a6333cd273c1d32817ebff01c3828a614a1318"
    "vbmeta_a.img"      = "2f3fb6474d7ff35ac4c48ab2bef71247ba50de4a94de2474b7d1b60cd6654f51"
}

$Targets = @(@{ Part = "boot_a"; File = "boot_a.img" })
if ($IncludeVendorAndDtbo) {
    $Targets += @{ Part = "dtbo_a"; File = "dtbo_a.img" }
    $Targets += @{ Part = "vendor_boot_a"; File = "vendor_boot_a.img" }
    $Targets += @{ Part = "vbmeta_a"; File = "vbmeta_a.img" }
}

foreach ($t in $Targets) {
    $p = Join-Path $StockDir $t.File
    if (-not (Test-Path $p)) {
        throw "Missing stock backup file (read-only): $p"
    }
    $h = (Get-FileHash -Algorithm SHA256 $p).Hash.ToLower()
    if ($h -ne $Expected[$t.File]) {
        throw "Stock backup SHA256 mismatch on $($t.File)! Expected $($Expected[$t.File]), got $h"
    }
    Write-Host "[PASS] Verified read-only stock $($t.File): $h"
}

$Devs = & fastboot devices
if (-not $Devs) {
    throw "No fastboot device detected."
}

$SlotOut = (& fastboot getvar current-slot 2>&1) -join "`n"
Write-Host $SlotOut
if ($SlotOut -notmatch "current-slot:\s*a\b") {
    throw "Refusing to restore: current-slot is NOT 'a'."
}

Write-Host ""
Write-Host "WARNING: Read-only restore from $StockDir" -ForegroundColor Yellow
$Confirm = Read-Host "Type exactly 'RESTORE ZPD1203 STOCK' to proceed"
if ($Confirm -cne "RESTORE ZPD1203 STOCK") {
    Write-Host "Aborted."
    exit 1
}

foreach ($t in $Targets) {
    $p = Join-Path $StockDir $t.File
    Write-Host "[INFO] Restoring $($t.Part) <- $p"
    & fastboot flash $t.Part $p
}
Write-Host "[DONE] Stock restore complete. Run: fastboot reboot"
