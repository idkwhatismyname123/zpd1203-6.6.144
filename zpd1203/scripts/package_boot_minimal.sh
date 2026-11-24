#!/usr/bin/env bash
# Package boot-minimal-6.6.img (Android Boot Header v2) compatible with ZYB ZPD1203 stock LK.
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BASE="${BASE:-$(cd "$ROOT/.." && pwd)}"
OUT_DIR="${OUT_DIR:-$BASE/out}"
KERNEL_IMG="${KERNEL_IMG:-$OUT_DIR/kernel-6.6/arch/arm64/boot/Image.gz}"
DTB_RAW="${DTB_RAW:-$OUT_DIR/kernel_device_modules-6.6/arch/arm64/boot/dts/mediatek/mt6768-zpd1203-minimal.dtb}"
RAMDISK_IMG="${RAMDISK_IMG:-$OUT_DIR/initramfs-minimal-6.6.cpio.gz}"
OUT_BOOT="${OUT_BOOT:-$OUT_DIR/boot-minimal-6.6.img}"
CMDLINE="${CMDLINE:-bootopt=64S3,32N2,64N2 buildvariant=user console=tty0 8250.nr_uarts=2 cpuidle.off=1 printk.devkmsg=on ignore_loglevel loglevel=8 clk_ignore_unused pd_ignore_unused regulator_ignore_unused mt6768.force_slot_a=1}"
ADD_AVB_FOOTER="${ADD_AVB_FOOTER:-1}"
PARTITION_SIZE="${PARTITION_SIZE:-33554432}"

for f in "$KERNEL_IMG" "$DTB_RAW" "$RAMDISK_IMG"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: missing input file: $f" >&2
    exit 1
  fi
done

mkdir -p "$OUT_DIR"

DTB_WRAPPED="$OUT_DIR/dtb-minimal-6.6.dtimg"
python3 "$ROOT/tools/wrap_dt_table.py" "$DTB_RAW" "$DTB_WRAPPED" --page-size 2048 --id 0 --rev 0

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
echo "Raw boot image size: $RAW_SZ bytes (limit $PARTITION_SIZE)"
if [ "$RAW_SZ" -gt "$PARTITION_SIZE" ]; then
  echo "ERROR: raw boot image exceeds 32 MiB limit!" >&2
  exit 1
fi

cp "$RAW_BOOT" "$OUT_BOOT"
if [ "$ADD_AVB_FOOTER" = "1" ] && command -v avbtool >/dev/null 2>&1; then
  avbtool add_hash_footer \
    --image "$OUT_BOOT" \
    --partition_name boot \
    --partition_size "$PARTITION_SIZE" \
    --hash_algorithm sha256
  echo "Added unsigned AVB hash footer (partition_size=$PARTITION_SIZE) to $OUT_BOOT"
fi

ls -lh "$RAW_BOOT" "$OUT_BOOT"
sha256sum "$RAW_BOOT" "$OUT_BOOT"
