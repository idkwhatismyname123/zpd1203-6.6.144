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

$SumsFile = Join-Path (Split-Path -Parent $BootImg) "SHA256SUMS.txt"
$ImgName = Split-Path -Leaf $BootImg
if (Test-Path $SumsFile) {
    $Actual = (Get-FileHash -Algorithm SHA256 $BootImg).Hash.ToLower()
    $Line = Select-String -Path $SumsFile -Pattern ([regex]::Escape($ImgName) + "$") | Select-Object -First 1
    if ($Line) {
        $Expected = ($Line.Line -split "\s+")[0].ToLower()
        if ($Actual -ne $Expected) {
            throw "SHA256 mismatch for $ImgName! Expected $Expected, got $Actual"
        }
        Write-Host "[PASS] SHA256 verified: $Actual"
    }
}

$Size = (Get-Item $BootImg).Length
if ($Size -gt 33554432) {
    throw "Boot image exceeds 32 MiB limit: $Size bytes"
}

Write-Host "[INFO] Checking fastboot devices..."
$Devs = & fastboot devices
if (-not $Devs) {
    throw "No device detected in fastboot mode."
}
Write-Host $Devs
Write-Host "[INFO] Performing non-destructive RAM boot (no partition write): fastboot boot $BootImg"
& fastboot boot $BootImg
