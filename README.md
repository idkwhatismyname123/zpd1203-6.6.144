# ZPD1203 (MediaTek MT6768) Linux 6.6.144 Android 内核移植

适用于 **ZYB ZPD1203（MediaTek MT6769V/CB / MT6768）** 平板的 **Linux 6.6.144（`android15-6.6`）** Android 内核移植仓库。目标是在保留原厂 Android 12 Vendor HAL（VNDK 31，兼容 `super` 中的 LineageOS 21 Android 14 GSI）的前提下，将板级支持、硬件驱动、Android ABI 兼容层与无 UART 调试工具链完整迁移至 Linux 6.6 LTS。

实机实测内核版本标识：**`6.6.144-zpd1203-@idkwhatismyname123`**（集成 KernelSU v3.3.1，已在实机进入 Android 桌面）。

> **仓库范围说明**：本仓库仅提供移植源码、补丁集（28 份 `git format-patch`）、DTS/DTSI、defconfig、Ramdisk 工具（`a12_init_wrapper` / `gralloc_fb0_bridge`）、构建校验脚本与移植文档；**不包含任何原厂固件备份、原厂 ramdisk、刷机镜像（`boot.img`）、`.ko`/`.bin` 二进制产物或设备私人日志**。构建启动镜像前请先从自己设备的原厂分区备份中提取纯净的 `vendor_boot_a` ramdisk 与 `dtbo_a`。

---

## 实机硬件适配与验证状态

状态严格按以下标准标注：**已实机验证**（真机日志/操作已确认）、**已静态验证 / 已编译通过**（宿主机编译与 ABI/DTB 检查通过，待端到端实测）、**尚未验证**、**已知故障**。

| 子系统 | Linux 6.6 实现方案 | 当前状态 | 说明 |
|---|---|---|---|
| 启动、桌面与核心架构 | `android15-6.6` + `mtk-sysirq` 97 INTPOL + `mt6768.force_slot_a=1` + `dramc` 防护 + SELinux permissive | **已实机验证** | 成功进入 Android 桌面（`sys.boot_completed=1`），无重启循环 |
| 显示与背光 | `simplefb` + NEON `gralloc.fb0_bridge.so`、`aw37503@3e` 偏压、`mtk_leds` 背光、`fbcon=map:9` | **已实机验证** | 横屏桌面与背光调光正常；`full` 模式关闭开机屏幕跑码（`vtcon0`）；原生 `mediatek-drm` 因 `disp_ovl0` 缺 phandle 自动回退至 `fb0_bridge` |
| 触摸屏与手写笔 | SPI4 `hxchipset`（6.6 API，跳过共用 `GPIO 158` 复位，加载设备 `/vendor/firmware/Himax_firmware*.bin`） | **已实机验证** | `mtk-tpd` 与 `himax-stylus` 触控/手写笔正常 |
| GPU 硬件加速 | Motorola `mali-r32p1`（`mali_mgm_mt6768.ko` + `mali_kbase_mt6768.ko` `r32p1-01eac0`）+ `ged` 18-region ABI 修复 | **已实机验证** | 匹配原厂 `libGLES_mali.so` DDK，OpenGL ES 3.2 真实硬件渲染（`Used by 15`） |
| Wi-Fi | 6.6 重编 `rfkill` / `cfg80211` / `connfem` / `wmt_drv` / `wmt_chrdev_wifi` / `wlan_drv_gen4m` + 延迟按需加载 | **已实机验证（扫描）** | `wlan0` 正常拉起并扫出 2.4 GHz / 5 GHz AP；实际联网吞吐尚待端到端实测 |
| 蓝牙 | 6.6 重编 `btif_drv` / `conn_md_drv` / `bt_drv_connac1x`（配合原厂 `wmt_loader` 初始化 EMI `0xbf000000`） | **已实机验证（开启）** | `state: ON`、零 crash、A2DP/AVRCP/HFP/HID Profile 就绪；蓝牙外设配对音频传输待测 |
| 电池电量与 USB 充电 | I2C5 `sgm41510@6b`（`bq2589x` 扩展 `usb`/`ac`/`primary_chg`）+ I2C6 `aw35615@22` + `mt6358-gauge` 内核态电量算法 | **已实机验证** | 相比 5.10 修复了 USB 充电状态上报与百分比显示（`algo:1` 内核态电量计、`Charge counter` 与 `Charging` 状态正常） |
| 物理三按键 | 内建 `CONFIG_KEYBOARD_MTK_KPD=y`（`10010000.kp`, `KEY_VOLUMEDOWN=114`）+ `CONFIG_DEVICE_MODULES_KEYBOARD_MTK_PMIC=y`（`KEY_POWER=116`, `KEY_VOLUMEUP=115`） | **已实机验证** | `event0` (`mtk-kpd`) 与 `event1` (`mtk-pmic-keys`) 中断触发与键值响应均正常 |
| 音频 | `afe@11220000` + `mt6358` + `accdet` + I2C3 `aw87xxx_pa@59/5A`（修复 `i2c2-4 ch-offset-i2c = <0x100>`） | **已实机验证（初始化/节点）** | 耳机插孔与 `mt6768-mt6358` 声卡初始化正常；外放端到端实测待补；二供 `fs15xx` 暂无 6.6 驱动 |
| 存储、USB 与无 UART 调试 | `mtk-mmc` + `cqhci` + `inlinecrypt` + `rpmb-mtk`；`musb-hdrc` `ffs.adb+acm.gs1`；`pstore/ramoops` + `a12_init_wrapper` | **已实机验证** | eMMC、`ADB + USB COM` 双接口、日志看门狗工作正常 |
| Android ABI 与 Root | BinderFS、`/dev/dma_heap/mtk_mm*`、`/dev/ion` -> DMA-BUF Heap 兼容驱动（`mtk_ion_compat.c`）、KernelSU v3.3.1 | **已实机验证** | 原厂 Android 12 Vendor HAL 无修改运行，KernelSU 符号已编入 `vmlinux` |
| 传感器 / 霍尔 | I2C1 `sc7a20` / `mc3416` / `ucs14266` / `ls9801i`、Hall EINT | **尚未验证** | 缺少 6.6 开源驱动 |
| 摄像头 | `mtkcam` / `sc800cs` / `hi849` / `s5k4h7` / `aw36515` | **已知故障** | 缺 `hi849`/`aw36515` 驱动，且原厂 `camerahalserver` 强依赖 GenieZone EL2 闭源 `/dev/gz_kree` 服务 |

---

## 上游源码基底与 8 个构建仓库组合

本移植基于以下 8 个独立仓库组合构建（主控仓记录了全部改动补丁与编排脚本）：

| 局部工作路径（`$ZPD_WSL_BASE/...`） | 上游仓库 | 基底 Commit | ZPD1203 改动补丁 |
|---|---|---|---|
| `kernel/kernel-6.6` | [AOSP kernel/common (`android15-6.6`)](https://android.googlesource.com/kernel/common) + [KernelSU v3.3.1](https://github.com/tiann/KernelSU) (`0c0fdb96`) | `329f9ae918a9` | **12 份补丁**（`sysirq`、`force_slot_a=1`、`simplefb`、`aw37503`、`zpd1203_defconfig` 等） |
| `kernel/kernel_device_modules-6.6` | [Addster09/mtk-kernel-modules-bsp-6.6](https://github.com/Addster09/mtk-kernel-modules-bsp-6.6) | `1561b421959f` | **15 份补丁**（ZPD1203 DTS、`hxchipset`、`sgm41510`、`mtk_ion_compat`、`ged` ABI、`dramc`/`usb` 防护、内核态电量计等） |
| `modules/gpu` | [MotorolaMobilityLLC/vendor-mediatek-kernel_modules-gpu](https://github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-gpu) (`mali-r32p1`) | `3b81cf6d7c0a` | **1 份补丁**（Clang 21 `minmax.h` 与 MT6768 OOT Kbuild 适配） |
| `modules/connectivity/common` | [MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-common](https://github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-common) | `0fd4f365ead4` | 零修改原样编译 (`wmt_drv.ko`) |
| `modules/connectivity/connfem` | [MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-connfem](https://github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-connfem) | `8a665a04c769` | 零修改原样编译 (`connfem.ko`) |
| `modules/connectivity/bt/mt66xx` | [MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-bt-mt66xx](https://github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-bt-mt66xx) | `95859aaae7f4` | 零修改原样编译 (`bt_drv_connac1x.ko`) |
| `modules/connectivity/wlan/adaptor` | [MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-wlan-adaptor](https://github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-wlan-adaptor) | `48e9f37a18b7` | 零修改原样编译 (`wmt_chrdev_wifi.ko`) |
| `modules/connectivity/wlan/core/gen4m` | [MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-wlan-core-gen4m](https://github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-wlan-core-gen4m) | `0eb4c16595f3` | 零修改原样编译 (`wlan_drv_gen4m.ko`) |

---

## 仓库目录结构与补丁顺序

```text
.
├── AGENTS.md                  # 移植总规范与红线约定
├── BUILD.md                   # 工具链清单与流水线脚本详细说明
├── DEBUGGING.md               # 无 UART 多级调试与早期崩溃排查记录
├── DECISIONS.md               # 关键架构决策记录 (ADR-001..004)
├── HANDOFF.md                 # 当前基线、产物校验与实机状态交接
├── HARDWARE_STATUS.md         # 硬件子系统详细适配矩阵
├── PORTING_STATUS.md          # 阶段里程碑与历次实机验证/构建记录
├── TASKS.md                   # Phase 0-7 完整任务清单
├── analysis/                  # 5.10 移植解析、原厂备份只读提取、6.x BSP 调研及 ABI/DRM 专题报告
├── patches/                   # 全套 28 份 git format-patch 补丁集
├── scripts/                   # 全自动化编译、打包、静态校验、安全刷写与日志脚本
└── zpd1203/
    ├── configs/               # zpd1203_defconfig、zpd1203_minimal_defconfig 及各子系统片段
    ├── data/                  # boot_structure.json (Boot Header v2 布局参数)
    ├── dts/                   # mt6768-zpd1203*.dts 与功能模块 .dtsi
    └── tools/                 # a12_init_wrapper.c、gralloc_fb0_bridge.c、wrap_dt_table.py
```

### 28 份补丁按仓库应用顺序

1. **应用于 `kernel/kernel-6.6`**（在 `329f9ae918a9` 上依次 `git am`，并集成 KernelSU `v3.3.1` 至 `drivers/kernelsu`）：
   - `patches/phase3_4/kernel-6.6/0001..0005-*.patch`
   - `patches/phase5_display_gpu_touch/kernel-6.6/0001-*.patch`
   - `patches/phase7_defconfig/kernel-6.6-0001-add-zpd1203_defconfig.patch`
   - `patches/phase7_console_com/kernel-6.6-0001-*.patch`
   - `patches/phase7_pstore_fixes/kernel-6.6-0001..0004-*.patch`
2. **应用于 `kernel/kernel_device_modules-6.6`**（在 `1561b421959f` 上依次 `git am`）：
   - `patches/phase3_4/kernel_device_modules-6.6/0001..0003-*.patch`
   - `patches/phase5_display_gpu_touch/kernel_device_modules-6.6/0001..0002-*.patch`
   - `patches/phase5_wireless_audio_power/0001..0002-*.patch`
   - `patches/phase6_abi/0001-*.patch`
   - `patches/phase7_defconfig/device_modules-6.6-0001-*.patch`
   - `patches/phase7_console_com/device_modules-6.6-0001-*.patch`
   - `patches/phase7_pstore_fixes/device_modules-6.6-0001..0005-*.patch`
3. **应用于 `modules/gpu`**（在 `3b81cf6d7c0a` 上 `git am`）：
   - `patches/phase5_display_gpu_touch/modules-gpu/0001-*.patch`

---

## 环境准备与可复现构建（Linux / WSL2 ext4）

> **重要**：Linux 内核编译必须在大小写敏感且支持符号链接的 **ext4 文件系统**（如 WSL2 `/home/<user>/zpd1203-6.6`）下进行，切勿在 NTFS 分区编译源码树。

### 1. 工具链依赖

实测使用 **Ubuntu + Clang 21.1.8 (`LLVM=1 LLVM_IAS=1`) + `lld`** 与 **`aarch64-linux-gnu-gcc`**，并安装：
`dtc`、`fdtoverlay`、`pahole`、`mkbootimg`、`unpack_bootimg`、`avbtool`、`fakeroot`、`cpio`、`xz`、`gzip`、`kmod`。

### 2. 准备原厂前置文件（用户自备提取）

从你自己的 ZPD1203 原厂固件备份提取：
- 纯净 `vendor_boot_a.img` 内的 `ramdisk`（ZPD1203 原厂 4.19 ramdisk 存放在 `vendor_boot_a`，无 Magisk） -> 默认读取 `$ZPD_WSL_BASE/extracted_stock/vendor_boot/ramdisk`（或通过环境变量 `STOCK_RD` 指定）
- 原厂 `dtbo_a` 解出的 `dtbo_a_0.dtb`（用于 `verify_build.sh` 执行 `fdtoverlay` 静态叠加验证） -> `$ZPD_WSL_BASE/extracted_stock/dtbo/dtbo_a_0.dtb`

### 3. 一键编译与校验

```bash
export ZPD_WSL_BASE=/home/asus/zpd1203-6.6   # 替换为你的 ext4 工作区路径
./scripts/build_all.sh --mode full --clean
```

- 如需同时生成**最小诊断镜像**（启用 `fbcon` 屏幕大字跑码与早期 USB COM 日志），使用 `--mode both --clean`。
- 完整产物与 `SHA256SUMS.txt` 将发布到 `out/full/`（及 `out/minimal/`），[scripts/verify_build.sh](scripts/verify_build.sh) 会自动校验 Boot Header v2、`kernel.release` 无 `-dirty`、`avbtool`、`fdtoverlay` 以及全部 11 枚 `.ko` 的 `vermagic` / `module_layout` CRC / 零未定义符号闭环。更多构建细节见 [BUILD.md](BUILD.md)。

---

## 实机刷写与安全恢复

> **重要警告**：实机 `expdb` 已证实 ZPD1203 原厂 `lk_a.img` 执行 `fastboot boot` 会触发 **`boot image is NULL` LK Panic**。因此**不要直接使用 `fastboot boot` 临时引导**，实机测试前请务必先完整备份原厂 `boot_a.img`，并**仅刷写 `boot_a`**（原厂动态分区仅位于 `_a` 槽位，切勿刷入 `boot_b` / `super` / `dtbo_a`）。

```powershell
# 1. 安全校验（核对 <= 32 MiB、SHA256SUMS.txt、current-slot=a 与二次确认口令）后刷入 boot_a：
.\scripts\flash_boot_safe.ps1 -Mode full

# 2. 需要回退原厂内核时（校验原厂只读备份 SHA256 后还原 boot_a）：
.\scripts\restore_stock.ps1 -StockDir "你的原厂只读备份目录"

# 3. 无物理 UART 时在 Windows 监听 USB COM 串口诊断通道（支持 status / pstore / help / reboot-fb）：
.\scripts\watch_com.ps1
```

---

## 致谢与许可证

- 参考前置工作：[idkwhatismyname123/zpd1203-5.10.240](https://github.com/idkwhatismyname123/zpd1203-5.10.240)
- 上游项目：[AOSP `kernel/common`](https://android.googlesource.com/kernel/common)、[Addster09/mtk-kernel-modules-bsp-6.6](https://github.com/Addster09/mtk-kernel-modules-bsp-6.6)、Motorola Mobility MT6768 GPU / Connsys 开源驱动、[KernelSU](https://github.com/tiann/KernelSU)
- **许可证**：内核补丁、DTS 与驱动修改遵循 **GPL-2.0**（详见对应补丁与源码头部 `SPDX-License-Identifier` 声明）。
