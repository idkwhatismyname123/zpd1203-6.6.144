#!/usr/bin/env bash
# Reproducible OOT Mali-G52 GPU + Connsys Wi-Fi/BT module builder & staging script for ZPD1203.
set -euo pipefail

MODE="full"
JOBS="${JOBS:-$(nproc)}"
BASE="${ZPD_WSL_BASE:-/home/asus/zpd1203-6.6}"

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    -j|--jobs) JOBS="${2:-$(nproc)}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--mode full|minimal] [-j N]"
      exit 0
      ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ "$MODE" = "minimal" ]; then
  echo "=== [build_modules:minimal] Minimal diagnostic mode skips OOT/wireless .ko staging ==="
  exit 0
elif [ "$MODE" != "full" ]; then
  echo "ERROR: --mode must be full or minimal (got: $MODE)" >&2
  exit 2
fi

KDIR="$BASE/kernel/kernel-6.6"
DDIR="$BASE/kernel/kernel_device_modules-6.6"
OUT="$BASE/out/kernel-6.6-full"
CONN="$BASE/modules/connectivity"
CONNSYS_TOP="$BASE/modules/.connsys_top"
GPU_R32="$BASE/modules/gpu/gpu_mali/mali_valhall/mali-r32p1"
STAGE_UNSTRIP="$OUT/staging_modules/unstripped"
STAGE_STRIP="$OUT/staging_modules/stripped"

if [ ! -f "$OUT/Module.symvers" ]; then
  echo "ERROR: $OUT/Module.symvers missing; run build_kernel.sh --mode full first." >&2
  exit 1
fi

mkdir -p "$CONNSYS_TOP/vendor/mediatek/kernel_modules"
ln -sfn "$CONN" "$CONNSYS_TOP/vendor/mediatek/kernel_modules/connectivity"
mkdir -p "$STAGE_UNSTRIP" "$STAGE_STRIP"
rm -f "$STAGE_UNSTRIP"/*.ko "$STAGE_STRIP"/*.ko

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

clean_oot_trees() {
  for repo in "$BASE/modules/gpu" "$CONN/common" "$CONN/connfem" "$CONN/bt/mt66xx" "$CONN/wlan/adaptor" "$CONN/wlan/core/gen4m"; do
    if [ -d "$repo/.git" ]; then
      git -C "$repo" clean -fdq >/dev/null 2>&1 || true
    fi
  done
}
trap clean_oot_trees EXIT
clean_oot_trees

echo "=== [build_modules:full] Building Mali Memory Group Manager (mali_mgm_mt6768.ko) ==="
make -C "$KDIR" O="$OUT" -j"$JOBS" "${COMMON_FLAGS[@]}" \
  "M=../../modules/gpu/gpu_mali/mali_valhall/mali-r32p1/drivers/base/arm/memory_group_manager" \
  MTK_PLATFORM_VERSION=mt6768 \
  CONFIG_MALI_MEMORY_GROUP_MANAGER=y \
  modules
cp -f "$GPU_R32/drivers/base/arm/memory_group_manager/mali_mgm_mt6768.ko" "$STAGE_UNSTRIP/"

echo "=== [build_modules:full] Building Mali-G52 Midgard/Valhall r32p1 DDK (mali_kbase_mt6768.ko) ==="
make -C "$KDIR" O="$OUT" -j"$JOBS" "${COMMON_FLAGS[@]}" \
  "M=../../modules/gpu/gpu_mali/mali_valhall/mali-r32p1/drivers/gpu/arm/midgard" \
  MTK_PLATFORM_VERSION=mt6768 \
  LOCAL_MTK_GPU_VERSION=mali_valhall_r32p1_mt6768 \
  BUILD_RULE=OOT \
  modules
cp -f "$GPU_R32/drivers/gpu/arm/midgard/mali_kbase_mt6768.ko" "$STAGE_UNSTRIP/"

echo "=== [build_modules:full] Building Connsys 1/5: connfem.ko ==="
make -C "$KDIR" O="$OUT" -j"$JOBS" "${COMMON_FLAGS[@]}" \
  "M=../../modules/connectivity/connfem" \
  "TOP=$CONNSYS_TOP" "KERNEL_OUT=$OUT" MTK_PLATFORM=mt6768 \
  modules
cp -f "$CONN/connfem/connfem.ko" "$STAGE_UNSTRIP/"

echo "=== [build_modules:full] Building Connsys 2/5: wmt_drv.ko ==="
make -C "$KDIR" O="$OUT" -j"$JOBS" "${COMMON_FLAGS[@]}" \
  "M=../../modules/connectivity/common" \
  "TOP=$CONNSYS_TOP" "KERNEL_OUT=$OUT" MTK_PLATFORM=mt6768 \
  modules
cp -f "$CONN/common/wmt_drv.ko" "$STAGE_UNSTRIP/"

echo "=== [build_modules:full] Building Connsys 3/5: bt_drv_connac1x.ko ==="
make -C "$KDIR" O="$OUT" -j"$JOBS" "${COMMON_FLAGS[@]}" \
  "M=../../modules/connectivity/bt/mt66xx/wmt" \
  "TOP=$CONNSYS_TOP" "KERNEL_OUT=$OUT" MTK_PLATFORM=mt6768 \
  BT_PLATFORM=connac1x "LOG_TAG=[BT_Drv][wmt]" \
  "KBUILD_EXTRA_SYMBOLS=$CONN/common/Module.symvers" \
  modules
cp -f "$CONN/bt/mt66xx/wmt/bt_drv_connac1x.ko" "$STAGE_UNSTRIP/"

echo "=== [build_modules:full] Building Connsys 4/5: wmt_chrdev_wifi.ko ==="
make -C "$KDIR" O="$OUT" -j"$JOBS" "${COMMON_FLAGS[@]}" \
  "M=../../modules/connectivity/wlan/adaptor" \
  "TOP=$CONNSYS_TOP" "KERNEL_OUT=$OUT" MTK_PLATFORM=mt6768 \
  CONNAC_VER=1_0 MODULE_NAME=wmt_chrdev_wifi WLAN_BUILD_COMMON=1 \
  "KBUILD_EXTRA_SYMBOLS=$CONN/common/Module.symvers" \
  modules
cp -f "$CONN/wlan/adaptor/wmt_chrdev_wifi.ko" "$STAGE_UNSTRIP/"

echo "=== [build_modules:full] Building Connsys 5/5: wlan_drv_gen4m.ko ==="
make -C "$KDIR" O="$OUT" -j"$JOBS" "${COMMON_FLAGS[@]}" \
  "M=../../modules/connectivity/wlan/core/gen4m" \
  "TOP=$CONNSYS_TOP" "KERNEL_OUT=$OUT" MTK_PLATFORM=mt6768 \
  CONFIG_MTK_COMBO_WIFI_HIF=axi WLAN_CHIP_ID=6768 MTK_COMBO_CHIP=CONNAC \
  MODULE_NAME=wlan_drv_gen4m CONFIG_MTK_WIFI_PRODUCT=y MTK_ANDROID_WMT=y MTK_ANDROID_EMI=y \
  "KBUILD_EXTRA_SYMBOLS=$CONN/common/Module.symvers $CONN/wlan/adaptor/Module.symvers" \
  modules
cp -f "$CONN/wlan/core/gen4m/wlan_drv_gen4m.ko" "$STAGE_UNSTRIP/"

echo "=== [build_modules:full] Collecting in-tree dependency modules & stripping ==="
cp -f "$OUT/net/rfkill/rfkill.ko" "$STAGE_UNSTRIP/"
cp -f "$OUT/net/wireless/cfg80211.ko" "$STAGE_UNSTRIP/"
DM_OUT="$(dirname "$OUT")/kernel_device_modules-6.6"
cp -f "$DM_OUT/drivers/misc/mediatek/btif/common/btif_drv.ko" "$STAGE_UNSTRIP/"
cp -f "$DM_OUT/drivers/misc/mediatek/conn_md/conn_md_drv.ko" "$STAGE_UNSTRIP/"

for ko in "$STAGE_UNSTRIP"/*.ko; do
  base_ko="$(basename "$ko")"
  llvm-strip --strip-debug -o "$STAGE_STRIP/$base_ko" "$ko"
done

ls -lh "$STAGE_STRIP"
