#!/usr/bin/env bash
# Reproducible Linux 6.6.144 kernel, in-tree modules & DTB builder for ZPD1203 (MT6768).
set -euo pipefail

MODE="full"
CLEAN_CFG=0
JOBS="${JOBS:-$(nproc)}"
BASE="${ZPD_WSL_BASE:-/home/asus/zpd1203-6.6}"

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --clean) CLEAN_CFG=1; shift ;;
    -j|--jobs) JOBS="${2:-$(nproc)}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--mode full|minimal] [--clean] [-j N]"
      exit 0
      ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

KDIR="$BASE/kernel/kernel-6.6"
DDIR="$BASE/kernel/kernel_device_modules-6.6"

case "$MODE" in
  full)
    OUT="$BASE/out/kernel-6.6-full"
    DEFCONFIG="zpd1203_defconfig"
    DTB_TARGET="mediatek/mt6768-zpd1203.dtb"
    MAKE_TARGETS="Image.gz modules"
    ;;
  minimal)
    OUT="$BASE/out/kernel-6.6"
    DEFCONFIG="zpd1203_minimal_defconfig"
    DTB_TARGET="mediatek/mt6768-zpd1203-minimal.dtb"
    MAKE_TARGETS="Image.gz"
    ;;
  *)
    echo "ERROR: --mode must be full or minimal (got: $MODE)" >&2
    exit 2
    ;;
esac

if [ "$CLEAN_CFG" = "1" ]; then
  rm -rf "$OUT" "$(dirname "$OUT")/kernel_device_modules-6.6"
fi
mkdir -p "$OUT"

COMMON_FLAGS=(
  ARCH=arm64
  LLVM=1
  LLVM_IAS=1
  CROSS_COMPILE=aarch64-linux-gnu-
  KCONFIG_EXT_PREFIX=../kernel_device_modules-6.6/
  DEVICE_MODULES_REL_DIR=../kernel_device_modules-6.6
  "DEVICE_MODULES_PATH=$DDIR"
  "DEVCIE_MODULES_INCLUDE=-I$DDIR/include -I$DDIR/include/uapi"
)

echo "=== [build_kernel:$MODE] Configuring ($DEFCONFIG) in $OUT ==="
make -C "$KDIR" O="$OUT" "${COMMON_FLAGS[@]}" "$DEFCONFIG"
make -C "$KDIR" O="$OUT" "${COMMON_FLAGS[@]}" olddefconfig

# Remove stale build outputs generated from earlier dirty commits so Image/modules reflect clean HEAD.
rm -f "$OUT/include/generated/compile.h" "$OUT/include/generated/utsrelease.h" "$OUT/include/config/kernel.release" "$OUT/init/version-timestamp.o"

echo "=== [build_kernel:$MODE] Building $MAKE_TARGETS (-j$JOBS) ==="
make -C "$KDIR" O="$OUT" -j"$JOBS" "${COMMON_FLAGS[@]}" $MAKE_TARGETS

echo "=== [build_kernel:$MODE] Building DTB ($DTB_TARGET) ==="
make -C "$KDIR" O="$OUT" -j"$JOBS" "${COMMON_FLAGS[@]}" \
  dtstree=../kernel_device_modules-6.6/arch/arm64/boot/dts \
  "DTC_INCLUDE=$KDIR/scripts/dtc/include-prefixes $DDIR/include $DDIR/arch/arm64/boot/dts $DDIR/arch/arm64/boot/dts/mediatek" \
  DTC_FLAGS=-@ \
  "$DTB_TARGET"

BUILT_DTB="$(dirname "$OUT")/kernel_device_modules-6.6/arch/arm64/boot/dts/$DTB_TARGET"
cp -f "$BUILT_DTB" "$OUT/zpd1203.dtb"
cp -f "$OUT/.config" "$OUT/zpd1203.config"

KREL="$(cat "$OUT/include/config/kernel.release")"
echo "[OK] kernel.release=$KREL"
ls -lh "$OUT/arch/arm64/boot/Image" "$OUT/arch/arm64/boot/Image.gz" "$OUT/zpd1203.dtb"
