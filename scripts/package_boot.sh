#!/usr/bin/env bash
# Package Boot Header v2 image for ZPD1203 (MT6768) and publish verified artifacts to d:\P3066\out\<mode>.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE="${ZPD_WSL_BASE:-/home/asus/zpd1203-6.6}"
MODE="full"
PARTITION_SIZE=33554432

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

case "$MODE" in
  full)
    KOUT="$BASE/out/kernel-6.6-full"
    DTB_NAME="mt6768-zpd1203.dtb"
    RAMDISK_IMG="$BASE/out/initramfs-full-6.6.cpio.xz"
    DTB_WRAPPED="$BASE/out/dtb-full-6.6.dtimg"
    OUT_BOOT="$BASE/out/boot-full-6.6.img"
    CMDLINE="bootopt=64S3,32N2,64N2 buildvariant=user console=tty0 8250.nr_uarts=2 printk.devkmsg=on loglevel=7 clk_ignore_unused pd_ignore_unused regulator_ignore_unused mt6768.force_slot_a=1"
    ;;
  minimal)
    KOUT="$BASE/out/kernel-6.6"
    DTB_NAME="mt6768-zpd1203-minimal.dtb"
    RAMDISK_IMG="$BASE/out/initramfs-minimal-6.6.cpio.gz"
    DTB_WRAPPED="$BASE/out/dtb-minimal-6.6.dtimg"
    OUT_BOOT="$BASE/out/boot-minimal-6.6.img"
    CMDLINE="bootopt=64S3,32N2,64N2 buildvariant=user console=tty0 8250.nr_uarts=2 cpuidle.off=1 printk.devkmsg=on ignore_loglevel loglevel=8 clk_ignore_unused pd_ignore_unused regulator_ignore_unused mt6768.force_slot_a=1"
    ;;
  *)
    echo "ERROR: --mode must be full or minimal (got: $MODE)" >&2
    exit 2
    ;;
esac

KERNEL_RAW="$KOUT/arch/arm64/boot/Image"
KERNEL_IMG="$KOUT/arch/arm64/boot/Image.gz"
DTB_RAW="$KOUT/zpd1203.dtb"

for f in "$KERNEL_RAW" "$KERNEL_IMG" "$DTB_RAW" "$RAMDISK_IMG"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: missing input artifact: $f" >&2
    exit 1
  fi
done

python3 "$REPO_ROOT/zpd1203/tools/wrap_dt_table.py" "$DTB_RAW" "$DTB_WRAPPED" --page-size 2048 --id 0 --rev 0

RAW_BOOT="${OUT_BOOT%.img}.raw.img"
mkbootimg \
  --header_version 2 \
  --pagesize 2048 \
  --base 0x40000000 \
  --kernel_offset 0x00080000 \
  --ramdisk_offset 0x07c80000 \
  --second_offset 0x00000000 \
  --tags_offset 0x0bc80000 \
  --dtb_offset 0x0bc80000 \
  --os_version 12.0.0 \
  --os_patch_level 2024-07 \
  --cmdline "$CMDLINE" \
  --kernel "$KERNEL_IMG" \
  --ramdisk "$RAMDISK_IMG" \
  --dtb "$DTB_WRAPPED" \
  -o "$RAW_BOOT"

RAW_SZ=$(stat -c %s "$RAW_BOOT")
echo "[$MODE] Raw boot image size: $RAW_SZ bytes (limit $PARTITION_SIZE)"
if [ "$RAW_SZ" -gt "$PARTITION_SIZE" ]; then
  echo "ERROR: raw boot image exceeds 32 MiB partition limit!" >&2
  exit 1
fi

cp -f "$RAW_BOOT" "$OUT_BOOT"
avbtool add_hash_footer \
  --image "$OUT_BOOT" \
  --partition_name boot \
  --partition_size "$PARTITION_SIZE" \
  --hash_algorithm sha256

PUB_DIR="$REPO_ROOT/out/$MODE"
rm -rf "$PUB_DIR"
mkdir -p "$PUB_DIR"

cp -f "$KERNEL_RAW" "$PUB_DIR/Image"
cp -f "$KERNEL_IMG" "$PUB_DIR/Image.gz"
cp -f "$DTB_RAW" "$PUB_DIR/$DTB_NAME"
cp -f "$DTB_WRAPPED" "$PUB_DIR/$(basename "$DTB_WRAPPED")"
cp -f "$RAMDISK_IMG" "$PUB_DIR/$(basename "$RAMDISK_IMG")"
cp -f "$RAW_BOOT" "$PUB_DIR/$(basename "$RAW_BOOT")"
cp -f "$OUT_BOOT" "$PUB_DIR/$(basename "$OUT_BOOT")"
cp -f "$KOUT/zpd1203.config" "$PUB_DIR/config-$MODE"

if [ "$MODE" = "full" ]; then
  mkdir -p "$PUB_DIR/modules" "$PUB_DIR/unstripped"
  cp -f "$KOUT/staging_modules/stripped"/*.ko "$PUB_DIR/modules/"
  cp -f "$KOUT/staging_modules/unstripped"/*.ko "$PUB_DIR/unstripped/"
  cp -f "$KOUT/Module.symvers" "$PUB_DIR/Module.symvers"
fi

(
  cd "$PUB_DIR"
  find . -type f ! -name 'SHA256SUMS.txt' | LC_ALL=C sort | sed 's|^\./||' | xargs sha256sum > SHA256SUMS.txt
)

echo "[OK] Published $MODE artifacts to $PUB_DIR"
ls -lh "$PUB_DIR"
