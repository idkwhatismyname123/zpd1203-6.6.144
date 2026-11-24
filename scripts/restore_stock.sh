#!/usr/bin/env bash
# Interactive safety-gated restore script from read-only ZPD1203 stock readback backup.
set -euo pipefail

STOCK_DIR="${STOCK_DIR:-/mnt/d/备份/p/GeekFlashTool_Readback_20260820162108246}"
ALL_PARTS=0
if [ "${1:-}" = "--all" ]; then ALL_PARTS=1; fi

declare -A EXPECTED=(
  [boot_a.img]="23db8b5325826d95a46d83806c4b27cf8a79861d621da98a29ae9a76edaae9b5"
  [dtbo_a.img]="0e2116106f575454eef5c374155443e9332cec67e2563c648528b0a2683a96dc"
  [vendor_boot_a.img]="5245a4627a3c1cb1f3ac0d6c85a6333cd273c1d32817ebff01c3828a614a1318"
  [vbmeta_a.img]="2f3fb6474d7ff35ac4c48ab2bef71247ba50de4a94de2474b7d1b60cd6654f51"
)

CHECK_LIST=("boot_a.img")
if [ "$ALL_PARTS" = "1" ]; then
  CHECK_LIST=("boot_a.img" "dtbo_a.img" "vendor_boot_a.img" "vbmeta_a.img")
fi

for f in "${CHECK_LIST[@]}"; do
  p="$STOCK_DIR/$f"
  [ -f "$p" ] || { echo "ERROR: missing stock backup file: $p" >&2; exit 1; }
  h=$(sha256sum "$p" | awk '{print $1}')
  [ "$h" = "${EXPECTED[$f]}" ] || { echo "ERROR: SHA256 mismatch on $f ($h != ${EXPECTED[$f]})" >&2; exit 1; }
  echo "[PASS] Verified read-only $f (SHA256=$h)"
done

DEVS=$(fastboot devices)
[ -n "$DEVS" ] || { echo "ERROR: no fastboot device detected" >&2; exit 1; }

SLOT_OUT=$(fastboot getvar current-slot 2>&1 || true)
echo "$SLOT_OUT"
if ! echo "$SLOT_OUT" | grep -Eq 'current-slot:[[:space:]]*a\b'; then
  echo "ERROR: refusing restore because current-slot is NOT 'a'." >&2
  exit 1
fi

read -r -p "Type exactly 'RESTORE ZPD1203 STOCK' to proceed: " CONFIRM
if [ "$CONFIRM" != "RESTORE ZPD1203 STOCK" ]; then
  echo "Aborted."
  exit 1
fi

fastboot flash boot_a "$STOCK_DIR/boot_a.img"
if [ "$ALL_PARTS" = "1" ]; then
  fastboot flash dtbo_a "$STOCK_DIR/dtbo_a.img"
  fastboot flash vendor_boot_a "$STOCK_DIR/vendor_boot_a.img"
  fastboot flash vbmeta_a "$STOCK_DIR/vbmeta_a.img"
fi
echo "[DONE] Stock restore complete. Run: fastboot reboot"
