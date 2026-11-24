#!/usr/bin/env bash
# Build Linux 6.6 Android 12 ramdisk for ZPD1203 from read-only stock vendor_boot_a ramdisk (NO Magisk).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE="${ZPD_WSL_BASE:-/home/asus/zpd1203-6.6}"
MODE="full"

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--mode full|minimal]"
      exit 0
      ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

STOCK_RD="${STOCK_RD:-$BASE/extracted_stock/vendor_boot/ramdisk}"
if [ ! -f "$STOCK_RD" ]; then
  echo "ERROR: clean stock ramdisk not found: $STOCK_RD" >&2
  exit 1
fi

case "$MODE" in
  full)
    OUT_RD="$BASE/out/initramfs-full-6.6.cpio.xz"
    STAGE_STRIP="$BASE/out/kernel-6.6-full/staging_modules/stripped"
    MAX_RD_BYTES=16777216
    ;;
  minimal)
    OUT_RD="$BASE/out/initramfs-minimal-6.6.cpio.gz"
    STAGE_STRIP=""
    MAX_RD_BYTES=19922944
    ;;
  *)
    echo "ERROR: --mode must be full or minimal (got: $MODE)" >&2
    exit 2
    ;;
esac

WORK="/tmp/zpd66_ramdisk_${MODE}"
FAKEROOT_ENV="/tmp/zpd66_ramdisk_${MODE}.fakeroot"
mkdir -p "$(dirname "$OUT_RD")" "$BASE/out/tools"
rm -rf "$WORK" "$FAKEROOT_ENV"
mkdir -p "$WORK"

echo "=== [build_ramdisk:$MODE] 1. Unpacking clean stock vendor_boot_a ramdisk ==="
fakeroot -s "$FAKEROOT_ENV" bash -c "cd '$WORK' && gzip -dc '$STOCK_RD' | cpio -idmu --no-absolute-filenames"

[ -d "$WORK/.backup" ] && chmod -R u+rwX "$WORK/.backup" || true
rm -rf "$WORK/.backup" "$WORK/overlay.d" "$WORK/init"

echo "=== [build_ramdisk:$MODE] 2. Cross-compiling a12_init_wrapper & gralloc.fb0_bridge.so ==="
aarch64-linux-gnu-gcc -static -O2 -s -Wall -Wextra -Werror \
  -o "$WORK/init" "$REPO_ROOT/zpd1203/tools/a12_init_wrapper.c"
chmod 0750 "$WORK/init"
cp -f "$WORK/init" "$BASE/out/tools/a12_init_wrapper"

aarch64-linux-gnu-gcc -shared -fPIC -nostdlib -ffreestanding -fno-builtin -fno-stack-protector \
  -O2 -s -Wall -Wextra -Werror -Wl,-soname,gralloc.default.so -Wl,--hash-style=both \
  -o "$WORK/gralloc.fb0_bridge.so" "$REPO_ROOT/zpd1203/tools/gralloc_fb0_bridge.c"
chmod 0755 "$WORK/gralloc.fb0_bridge.so"
cp -f "$WORK/gralloc.fb0_bridge.so" "$BASE/out/tools/gralloc.fb0_bridge.so"

if aarch64-linux-gnu-readelf -d "$WORK/gralloc.fb0_bridge.so" | grep -q "NEEDED"; then
  echo "ERROR: gralloc.fb0_bridge.so must have zero NEEDED dependencies" >&2
  exit 1
fi
if ! aarch64-linux-gnu-readelf --dyn-syms "$WORK/gralloc.fb0_bridge.so" | grep -Eq "[[:space:]]HMI([[:space:]]|$)"; then
  echo "ERROR: gralloc.fb0_bridge.so missing exported HMI symbol" >&2
  exit 1
fi

echo "=== [build_ramdisk:$MODE] 3. Verifying first_stage_ramdisk/fstab.mt6768 ==="
FSTAB="$WORK/first_stage_ramdisk/fstab.mt6768"
if [ ! -f "$FSTAB" ]; then
  echo "ERROR: missing $FSTAB" >&2
  exit 1
fi

if [ "$MODE" = "full" ]; then
  echo "=== [build_ramdisk:full] 4. Staging 11 stripped 6.6 .ko modules into /zpd_modules ==="
  REQUIRED_MODS=(
    mali_mgm_mt6768.ko
    mali_kbase_mt6768.ko
    rfkill.ko
    cfg80211.ko
    btif_drv.ko
    conn_md_drv.ko
    connfem.ko
    wmt_drv.ko
    wmt_chrdev_wifi.ko
    bt_drv_connac1x.ko
    wlan_drv_gen4m.ko
  )
  mkdir -p "$WORK/zpd_modules"
  chmod 0755 "$WORK/zpd_modules"
  for m in "${REQUIRED_MODS[@]}"; do
    if [ ! -f "$STAGE_STRIP/$m" ]; then
      echo "ERROR: missing staged stripped module: $STAGE_STRIP/$m" >&2
      exit 1
    fi
    cp -f "$STAGE_STRIP/$m" "$WORK/zpd_modules/$m"
    chmod 0644 "$WORK/zpd_modules/$m"
  done
fi

echo "=== [build_ramdisk:$MODE] 5. Patching prop.default (permissive ADB debuggable) ==="
PROP="$WORK/prop.default"
if [ ! -f "$PROP" ]; then
  echo "ERROR: missing $PROP" >&2
  exit 1
fi

python3 - "$PROP" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
lines = p.read_text(encoding="utf-8").splitlines()
overrides = {
    "ro.debuggable": "1",
    "ro.adb.secure": "0",
    "persist.sys.usb.config": "adb",
    "ro.vendor.usb.kpoc_adb": "1",
    "service.adb.root": "1",
    "ro.boot.selinux": "permissive",
}
seen = set()
out = []
for ln in lines:
    if ln.startswith("#") or "=" not in ln:
        out.append(ln)
        continue
    k, _ = ln.split("=", 1)
    k = k.strip()
    if k in overrides:
        if k not in seen:
            out.append(f"{k}={overrides[k]}")
            seen.add(k)
        continue
    out.append(ln)
for k, v in overrides.items():
    if k not in seen:
        out.append(f"{k}={v}")
p.write_text("\n".join(out) + "\n", encoding="utf-8")
PY

pack_ramdisk() {
  if [ "$MODE" = "full" ]; then
    fakeroot -i "$FAKEROOT_ENV" bash -c "cd '$WORK' && find . | LC_ALL=C sort | cpio -o -H newc --reproducible 2>/dev/null | xz --check=crc32 -6 -T0 > '$OUT_RD'"
  else
    fakeroot -i "$FAKEROOT_ENV" bash -c "cd '$WORK' && find . | LC_ALL=C sort | cpio -o -H newc --reproducible 2>/dev/null | gzip -9 > '$OUT_RD'"
  fi
}

echo "=== [build_ramdisk:$MODE] 6. Compressing ramdisk -> $OUT_RD ==="
pack_ramdisk
RD_SIZE=$(stat -c %s "$OUT_RD")
echo "Packed ramdisk size: $RD_SIZE bytes (limit $MAX_RD_BYTES)"

if [ "$RD_SIZE" -gt "$MAX_RD_BYTES" ]; then
  echo "Ramdisk exceeds budget; stripping recovery PNGs..."
  rm -f "$WORK"/res/images/*.png || true
  pack_ramdisk
  RD_SIZE=$(stat -c %s "$OUT_RD")
  echo "Stripped ramdisk size: $RD_SIZE bytes"
  if [ "$RD_SIZE" -gt "$MAX_RD_BYTES" ]; then
    echo "ERROR: ramdisk still exceeds budget ($RD_SIZE > $MAX_RD_BYTES)" >&2
    exit 1
  fi
fi

chmod -R u+rwX "$WORK" 2>/dev/null || true
rm -rf "$WORK" "$FAKEROOT_ENV"
ls -lh "$OUT_RD"
