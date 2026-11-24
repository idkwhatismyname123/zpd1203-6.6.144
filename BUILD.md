# ZPD1203 Linux 6.6 编译与打包说明 (BUILD.md)

## 1. 环境要求
- **宿主机**：Windows 11 + WSL2 Ubuntu（已检测：10 核心，15 GiB RAM，764 GiB 可用 ext4 空间）
- **已验证宿主机工具**（2026-11-24 检测）：
  - Clang / LLD：`clang-21` (`/usr/bin/clang -> clang-21`, Ubuntu 21.1.8), `ld.lld`, `llvm-ar`, `llvm-nm`, `llvm-objcopy`, `llvm-readelf`
  - 交叉编译：`aarch64-linux-gnu-gcc` (`gcc 15.2.0`, 用于用户态静态 wrapper 与 freestanding `.so` 编译)
  - 辅助构建：`make`, `git`, `python3`, `bc`, `bison`, `flex`, `dtc`, `pahole`, `libssl-dev`, `libelf-dev`, `kmod`, `fakeroot`
  - Android 镜像工具：`mkbootimg` (`1:34.0.5`), `unpack_bootimg`, `avbtool` (`1.3.0`), `fdtoverlay`, `lpunpack`, `simg2img`, `fsck.erofs`, `cpio`, `lz4`, `gzip`, `xz`, `zstd`, `fastboot`

## 2. 目录布局（WSL2）
- `/home/asus/zpd1203-6.6/kernel/kernel-6.6/` — Linux `6.6.144` 主内核树（`zpd1203-6.6` 分支，含 `external/KernelSU` v3.3.1 `0c0fdb96`）
- `/home/asus/zpd1203-6.6/kernel/kernel_device_modules-6.6/` — MTK `device_modules`（`Addster09` 基底，`zpd1203-6.6` 分支）
- `/home/asus/zpd1203-6.6/zpd1203/` — ZPD1203 ramdisk/boot 打包与校验工具集（同步至 `d:\P3066\zpd1203\`）
- `/home/asus/zpd1203-6.6/extracted_stock/` — 原厂分区备份只读解包产物（含纯净 `vendor_boot/ramdisk` 与 `dtbo/dtbo_a_0.dtb`）
- `/home/asus/zpd1203-6.6/modules/` — 外置模块（Connsys 无线 / Mali GPU）源码区（Phase 5 使用）
- `/home/asus/zpd1203-6.6/out/` — 编译及打包产物，校验后同步至 `d:\P3066\out\minimal\`

## 3. Phase 3 & Phase 4 最小内核构建命令（已在 WSL2 实测通过）

### 3.1 生成配置（两种等价方式）
方式 A（推荐，使用已定稿 `zpd1203_minimal_defconfig`）：
```bash
KDIR=/home/asus/zpd1203-6.6/kernel/kernel-6.6
DDIR=/home/asus/zpd1203-6.6/kernel/kernel_device_modules-6.6
OUT=/home/asus/zpd1203-6.6/out/kernel-6.6

make -C "$KDIR" O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- \
  KCONFIG_EXT_PREFIX=../kernel_device_modules-6.6/ zpd1203_minimal_defconfig
```

方式 B（从 GKI + MTK 碎片重新合并）：
```bash
make -C "$KDIR" O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- \
  KCONFIG_EXT_PREFIX=../kernel_device_modules-6.6/ gki_defconfig
(cd "$OUT" && "$KDIR/scripts/kconfig/merge_config.sh" -m .config \
  "$DDIR/arch/arm64/configs/mgk_64_k66_defconfig" \
  "$DDIR/kernel/configs/mt6768_overlay.config" \
  "$DDIR/arch/arm64/configs/zpd1203_minimal.config")
"$KDIR/scripts/config" --file "$OUT/.config" -d MODULE_SIG -d MODULE_SIG_FORCE -d TRIM_UNUSED_KSYMS
make -C "$KDIR" O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- \
  KCONFIG_EXT_PREFIX=../kernel_device_modules-6.6/ olddefconfig
```

### 3.2 编译 `Image`、`Image.gz` 与 ZPD1203 DTB
> 注意必须同时传入 `DEVICE_MODULES_PATH="$DDIR"` 与 `DEVCIE_MODULES_INCLUDE`（遵循 MTK `Makefile.ext` 变量名拼写）以及 `dtstree`/`DTC_INCLUDE`/`DTC_FLAGS=-@`。
```bash
make -C "$KDIR" O="$OUT" -j10 \
  ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- \
  KCONFIG_EXT_PREFIX=../kernel_device_modules-6.6/ \
  DEVICE_MODULES_REL_DIR=../kernel_device_modules-6.6 \
  DEVICE_MODULES_PATH="$DDIR" \
  DEVCIE_MODULES_INCLUDE="-I$DDIR/include -I$DDIR/include/uapi" \
  Image.gz

make -C "$KDIR" O="$OUT" -j10 \
  ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- \
  KCONFIG_EXT_PREFIX=../kernel_device_modules-6.6/ \
  dtstree=../kernel_device_modules-6.6/arch/arm64/boot/dts \
  DEVICE_MODULES_PATH="$DDIR" \
  DTC_INCLUDE="$KDIR/scripts/dtc/include-prefixes $DDIR/include $DDIR/arch/arm64/boot/dts $DDIR/arch/arm64/boot/dts/mediatek" \
  DTC_FLAGS=-@ \
  mediatek/mt6768-zpd1203-minimal.dtb
```

### 3.3 构建诊断 Ramdisk、打包与静态校验 `boot-minimal-6.6.img`
```bash
/home/asus/zpd1203-6.6/zpd1203/scripts/build_minimal_ramdisk.sh
/home/asus/zpd1203-6.6/zpd1203/scripts/package_boot_minimal.sh
/home/asus/zpd1203-6.6/zpd1203/scripts/verify_boot_minimal.sh
```
- 构建产出位于 `/home/asus/zpd1203-6.6/out/` 并已同步至 `d:\P3066\out\minimal\`。
- Phase 7 将继续补充全量模块编译与一键交付脚本（`scripts/build_all.sh`）。
