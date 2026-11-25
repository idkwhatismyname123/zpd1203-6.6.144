# ZPD1203 Linux 6.6 编译与打包说明 (BUILD.md)

## 1. 环境要求
- **宿主机**：Windows 11 + WSL2 Ubuntu (`x86_64`, 10 CPU cores, 15 GiB RAM)
- **已验证工具链**：
  - Clang / LLD：`clang-21` (`Ubuntu clang version 21.1.8`), `ld.lld`, `llvm-ar`, `llvm-nm`, `llvm-strip`, `llvm-objcopy`, `llvm-readelf`
  - 交叉编译：`aarch64-linux-gnu-gcc` (`gcc 15.2.0`, 用于静态 `a12_init_wrapper` 与 freestanding `gralloc.fb0_bridge.so`)
  - 镜像与校验工具：`mkbootimg`, `unpack_bootimg`, `avbtool` (`1.3.0`), `fdtoverlay`, `dtc`, `pahole`, `modinfo`, `modprobe`, `fakeroot`, `cpio`, `gzip`, `xz`, `zstd`, `sha256sum`, `fastboot`, `adb`

## 2. 目录布局（WSL2 + Windows 控制仓）
- `/home/asus/zpd1203-6.6/kernel/kernel-6.6/` — Linux `6.6.144` 主内核树（`zpd1203-6.6`, commit `79934f29bfe5`, clean）
- `/home/asus/zpd1203-6.6/kernel/kernel_device_modules-6.6/` — MTK BSP 模块树（`zpd1203-6.6`, commit `398a4dd27ef0`, clean）
- `/home/asus/zpd1203-6.6/modules/gpu/` — Mali-G52 `r32p1` GPU 模块源码（commit `2d3b928b88ce`, clean）
- `/home/asus/zpd1203-6.6/modules/connectivity/` — Connsys 无线模块源码（5 仓均 clean；构建脚本自动维护 `.connsys_top` 符号链接）
- `/home/asus/zpd1203-6.6/extracted_stock/` — 只读原厂解包（纯净 `vendor_boot/ramdisk` 与 `dtbo/dtbo_a_0.dtb`）
- `d:\P3066\` — 控制仓，含全部脚本 (`scripts/`)、工具源码 (`zpd1203/tools/`)、配置与 DTS (`zpd1203/{configs,dts}/`)、补丁集 (`patches/`) 及输出目录 (`out/{full,minimal}/`)

## 3. 一键全自动化可复现构建与静态校验

在 WSL2 Ubuntu 中运行以下单条命令即可从头完成**全量模式 (`full`)** 与**最小诊断模式 (`minimal`)** 构建、模块编译、Ramdisk/Boot v2/AVB 打包及静态门禁校验：

```bash
/mnt/d/P3066/scripts/build_all.sh --mode both --clean
```

单独构建某一模式或仅增量构建：

```bash
# 仅全量完整内核 + 11 模块 + XZ Ramdisk + boot-full-6.6.img：
/mnt/d/P3066/scripts/build_all.sh --mode full --clean

# 仅最小诊断内核 + simplefb/FB0 桥接 + Gzip Ramdisk + boot-minimal-6.6.img：
/mnt/d/P3066/scripts/build_all.sh --mode minimal --clean

# 仅重跑静态验证门禁：
/mnt/d/P3066/scripts/verify_build.sh --mode full
/mnt/d/P3066/scripts/verify_build.sh --mode minimal
```

## 4. 流水线脚本职责明细

1. **[build_kernel.sh](file:///d:/P3066/scripts/build_kernel.sh)** (`--mode full|minimal [--clean]`):
   - 强制传入 `KCONFIG_EXT_PREFIX=../kernel_device_modules-6.6/`、`DEVICE_MODULES_REL_DIR=../kernel_device_modules-6.6`、`DEVICE_MODULES_PATH="$DDIR"` 与 `DEVCIE_MODULES_INCLUDE`，防止 `syncconfig` 丢失外部配置。
   - 使用 `zpd1203_defconfig` (`full`) 或 `zpd1203_minimal_defconfig` (`minimal`) 编译 `Image.gz`、树内模块及 `mt6768-zpd1203.dtb` / `mt6768-zpd1203-minimal.dtb` (`DTC_FLAGS=-@`)。
2. **[build_modules.sh](file:///d:/P3066/scripts/build_modules.sh)** (`--mode full|minimal`):
   - `full` 模式构建 OOT Mali (`mali_mgm_mt6768.ko`、`mali_kbase_mt6768.ko`) 与 Connsys 5 模块（`connfem.ko`、`wmt_drv.ko`、`bt_drv_connac1x.ko`、`wmt_chrdev_wifi.ko`，以及携带 `MTK_ANDROID_WMT=y MTK_ANDROID_EMI=y` 的 `wlan_drv_gen4m.ko`），汇集树内 `rfkill.ko`、`cfg80211.ko`、`btif_drv.ko`、`conn_md_drv.ko`，分别保留 unstripped 与 `llvm-strip --strip-debug` 版本并清理 OOT 源码树。
3. **[build_ramdisk.sh](file:///d:/P3066/scripts/build_ramdisk.sh)** (`--mode full|minimal`):
   - 解包纯净 `vendor_boot_a` ramdisk，交叉编译静态 `a12_init_wrapper` 与零依赖 `gralloc.fb0_bridge.so`，修补 `prop.default` (`ro.debuggable=1`, `ro.adb.secure=0`, `ro.boot.selinux=permissive`)；`full` 模式打包全部 11 枚 stripped `.ko` 至 `/zpd_modules/` 并采用 `xz --check=crc32 -6` 压缩。
4. **[package_boot.sh](file:///d:/P3066/scripts/package_boot.sh)** (`--mode full|minimal`):
   - 调用 `wrap_dt_table.py` (`0xd7b7ab1e`) 与 `mkbootimg`（Boot Header v2, `console=tty0 fbcon=rotate:3,font:TER16x32 ... mt6768.force_slot_a=1`），强制检查 `<= 33,554,432` B 后加签未签名 AVB hash footer (`avbtool`)，将全部产物与 `SHA256SUMS.txt` 发布至 `d:\P3066\out\<mode>\`。
5. **[verify_build.sh](file:///d:/P3066/scripts/verify_build.sh)** (`--mode full|minimal`):
   - 核对 `SHA256SUMS.txt`、Boot v2 头字段与偏移、`console=tty0` / `fbcon=rotate:3,font:TER16x32` / `mt6768.force_slot_a=1`、解压 `ARM\x64` 内核 banner (`Linux version 6.6.144` 且无 `-dirty`)、`unpack_bootimg`、`avbtool info_image`、`fdtoverlay` 叠加原厂 `dtbo_a_0.dtb`（0 错误）、关键 `.config` 必选配置（含 `VT`/`FRAMEBUFFER_CONSOLE`/`FONT_TER16x32`/`DEVTMPFS`/`U_SERIAL_CONSOLE`）及全量 `.ko` 的 `vermagic` / `module_layout` CRC / `llvm-nm` 0 未定义符号闭环。
6. **[watch_com.ps1](file:///d:/P3066/scripts/watch_com.ps1)**（Windows USB COM 口终端监听助手）:
   - 自动检索 `VID_1D6B&PID_0104` 或 `VID_0E8D&PID_2006` 等 ZPD1203 USB 串口设备，并以 `115200 8N1` 打开、开启 `DtrEnable`/`RtsEnable`、实时回显与落盘日志并支持直接发送 `status` / `pstore` / `help` / `reboot-fb`。
