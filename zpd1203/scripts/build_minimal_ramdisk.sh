#!/usr/bin/env bash
# Build clean Linux 6.6 minimal diagnostic ramdisk for ZPD1203 from stock vendor_boot_a ramdisk (NO Magisk).
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BASE="${BASE:-$(cd "$ROOT/.." && pwd)}"
STOCK_RD="${STOCK_RD:-$BASE/extracted_stock/vendor_boot/ramdisk}"
OUT_RD="${OUT_RD:-$BASE/out/initramfs-minimal-6.6.cpio.gz}"
WORK="/tmp/zpd66_ramdisk_work"
FAKEROUT_ENV="/tmp/zpd66_ramdisk.fakeroot"
MAX_RD_BYTES="${MAX_RD_BYTES:-19922944}"

if [ ! -f "$STOCK_RD" ]; then
  echo "ERROR: clean stock ramdisk not found: $STOCK_RD" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_RD")"
rm -rf "$WORK" "$FAKEROUT_ENV"
mkdir -p "$WORK"

echo "=== 1. Unpacking clean stock vendor_boot ramdisk via fakeroot ==="
fakeroot -s "$FAKEROUT_ENV" bash -c "cd '$WORK' && gzip -dc '$STOCK_RD' | cpio -idmu --no-absolute-filenames"

echo "=== 2. Removing any overlay/Magisk artifacts & building STAGE wrapper + gralloc_fb0_bridge.so ==="
[ -d "$WORK/.backup" ] && chmod -R u+rwX "$WORK/.backup" || true
rm -rf "$WORK/.backup" "$WORK/overlay.d" "$WORK/init"

aarch64-linux-gnu-gcc -static -O2 -s -Wall -Wextra -Werror \
  -o "$WORK/init" "$ROOT/tools/a12_init_wrapper.c"
chmod 0750 "$WORK/init"

aarch64-linux-gnu-gcc -shared -fPIC -nostdlib -ffreestanding -fno-builtin -fno-stack-protector \
  -O2 -s -Wall -Wextra -Werror -Wl,-soname,gralloc.default.so -Wl,--hash-style=both \
  -o "$WORK/gralloc.fb0_bridge.so" "$ROOT/tools/gralloc_fb0_bridge.c"
chmod 0755 "$WORK/gralloc.fb0_bridge.so"

if aarch64-linux-gnu-readelf -d "$WORK/gralloc.fb0_bridge.so" | grep -q "NEEDED"; then
  echo "ERROR: gralloc.fb0_bridge.so must have zero NEEDED dependencies" >&2
  exit 1
fi
if ! aarch64-linux-gnu-readelf --dyn-syms "$WORK/gralloc.fb0_bridge.so" | grep -Eq "[[:space:]]HMI([[:space:]]|$)"; then
  echo "ERROR: gralloc.fb0_bridge.so missing exported HMI symbol" >&2
  exit 1
fi

echo "=== 3. Verifying stock first_stage_ramdisk/fstab.mt6768 ==="
FSTAB="$WORK/first_stage_ramdisk/fstab.mt6768"
if [ ! -f "$FSTAB" ]; then
  echo "ERROR: missing $FSTAB" >&2
  exit 1
fi
grep -E "^(system|vendor|product)" "$FSTAB" || true

echo "=== 4. Patching prop.default for early root ADB & permissive bring-up ==="
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
print("Patched prop.default keys:", sorted(overrides))
PY

pack_ramdisk() {
  fakeroot -i "$FAKEROUT_ENV" bash -c "cd '$WORK' && find . | LC_ALL=C sort | cpio -o -H newc --reproducible 2>/dev/null | gzip -9 > '$OUT_RD'"
}

echo "=== 5. Packing compressed minimal diagnostic ramdisk ==="
pack_ramdisk
RD_SIZE=$(stat -c %s "$OUT_RD")
echo "Packed ramdisk size: $RD_SIZE bytes"

if [ "$RD_SIZE" -gt "$MAX_RD_BYTES" ]; then
  echo "Ramdisk ($RD_SIZE B) > budget ($MAX_RD_BYTES B); stripping res/images/*.png..."
  rm -f "$WORK"/res/images/*.png || true
  pack_ramdisk
  RD_SIZE=$(stat -c %s "$OUT_RD")
  echo "Stripped packed ramdisk size: $RD_SIZE bytes"
  if [ "$RD_SIZE" -gt "$MAX_RD_BYTES" ]; then
    echo "ERROR: ramdisk still exceeds budget ($RD_SIZE > $MAX_RD_BYTES)" >&2
    exit 1
  fi
fi

chmod -R u+rwX "$WORK" 2>/dev/null || true
rm -rf "$WORK" "$FAKEROUT_ENV"
ls -lh "$OUT_RD"
sha256sum "$OUT_RD"
