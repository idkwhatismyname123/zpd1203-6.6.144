#!/usr/bin/env bash
# Interactive safety-gated flash script for boot_a (NEVER flashes without slot, size, SHA256 & typed confirmation).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="full"
IMG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --image) IMG="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--mode full|minimal] [--image path/to/boot.img]"
      exit 0
      ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$IMG" ]; then
  IMG="$REPO_ROOT/out/$MODE/boot-$MODE-6.6.img"
fi
[ -f "$IMG" ] || { echo "ERROR: missing image: $IMG" >&2; exit 1; }

SZ=$(stat -c %s "$IMG")
[ "$SZ" -le 33554432 ] || { echo "ERROR: image $SZ B > 33554432 B" >&2; exit 1; }

SUMS="$(dirname "$IMG")/SHA256SUMS.txt"
[ -f "$SUMS" ] || { echo "ERROR: missing $SUMS" >&2; exit 1; }
ACTUAL=$(sha256sum "$IMG" | awk '{print $1}')
EXPECTED=$(awk -v f="$(basename "$IMG")" '$2 == f {print $1}' "$SUMS")
[ -n "$EXPECTED" ] && [ "$ACTUAL" = "$EXPECTED" ] || { echo "ERROR: SHA256 mismatch" >&2; exit 1; }
echo "[PASS] Verified $(basename "$IMG") ($SZ B, SHA256=$ACTUAL)"

DEVS=$(fastboot devices)
[ -n "$DEVS" ] || { echo "ERROR: no fastboot device detected" >&2; exit 1; }

SLOT_OUT=$(fastboot getvar current-slot 2>&1 || true)
echo "$SLOT_OUT"
if ! echo "$SLOT_OUT" | grep -Eq 'current-slot:[[:space:]]*a\b'; then
  echo "ERROR: refusing to flash because current-slot is NOT 'a' (super only has slot _a)." >&2
  exit 1
fi

echo ""
echo "WARNING: This will overwrite boot_a on the connected ZPD1203 device."
echo "Recommended: test non-destructively first using scripts/test_fastboot_boot.sh"
read -r -p "Type exactly 'FLASH ZPD1203 BOOT_A' to proceed: " CONFIRM
if [ "$CONFIRM" != "FLASH ZPD1203 BOOT_A" ]; then
  echo "Aborted."
  exit 1
fi

fastboot flash boot_a "$IMG"
echo "[DONE] Flashed $IMG to boot_a. Reboot manually with: fastboot reboot"
