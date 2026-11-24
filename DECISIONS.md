# ZPD1203 Linux 6.6 技术决策记录 (DECISIONS.md)

## ADR-001：工作目录隔离策略（Windows 控制仓 + WSL2 ext4 构建区）
- **日期**：2026-11-24
- **决策**：项目管理文档、分析报告、DTS/DTSI、defconfig、补丁集、自动化脚本及最终发布产物存放在 Windows `d:\P3066` 并纳入 Git 管理；内核源码克隆、原厂镜像解包及内核编译全部在 WSL2 ext4 文件系统 `/home/asus/zpd1203-6.6/` 中执行。
- **原因**：
  1. Linux 内核源码包含仅大小写不同的文件（如 `net/netfilter/xt_DSCP.c` 与 `xt_dscp.c`）以及大量符号链接，NTFS (`/mnt/d`) 默认大小写不敏感且跨 9P IO 性能极差。
  2. 现有 WSL2 目录 `/home/asus/zpd1203-5.10.240` 与原厂备份 `D:\备份\p\GeekFlashTool_Readback_20260820162108246` 必须绝对保持不受破坏/只读。

## ADR-002：选定 Linux 6.6.144 (`android15-6.6`) + `Addster09` BSP + Moto GPU/Connsys 为移植基底
- **日期**：2026-11-24
- **状态**：已定案（Phase 1 + Phase 2 实证完毕）
- **决策**：
  - **Core Kernel**：`https://android.googlesource.com/kernel/common` 分支 `android15-6.6`（`329f9ae918a9e18da3c488e531adf9b7995e2aae` = **Linux 6.6.144**）。
  - **MT6768 `device_modules`**：`https://github.com/Addster09/mtk-kernel-modules-bsp-6.6`（`android15-6.6`, `1561b421959f`）为主，交叉比对 `https://github.com/MotorolaMobilityLLC/kernel-kernel_device_modules-6.6`（`android-15-release-v1tl35.73-60-3`, `9b049a46b9fc`）。
  - **GPU**：`https://github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-gpu`（`v1tl35.73-60-3`, `3b81cf6d7c0a`）中的 **`mali_valhall/mali-r32p1`** (`r32p1-01eac0`)。
  - **Connsys 无线**：Motorola `vvta35` (`common`, `bt-mt66xx`, `connfem`, `wlan-adaptor`) + `v1tl35.73-60-3` (`wlan-core-gen4m`)，辅以 `vvob35` (`fmradio`/`gps`)。
- **技术依据（详见 `analysis/phase2_bsp_survey.md`）**：
  1. **否决 Linux 6.1**：`MotorolaMobilityLLC/kernel-kernel_device_modules-6.1` 完全不含 MT6768 代码；Linux 6.6 拥有完整 MT6768 BSP。
  2. **否决 Samsung `android_kernel_samsung_mt6768` / `a05m-kernel-6.6` 整树**：包含 135 个 Samsung DEFEX/FIVE/PROCA 安全文件、42 个核心挂钩、强制 `CONFIG_AUTOFDO_CLANG=y` 阻塞无 profile 构建，且缺失 `mali-r32p1`（仅带 `r49p1`）；仅在局部参考其 `hx83112f` 6.6 触控 API 适配。
  3. **否决 `Mayuri-Chan` (`6.6.30`)**：核心 `6.6.30` 在宿主机 `clang-21` + glibc 2.43 下 `resolve_btfids/libbpf.c` 编译报错，且设备模块缺失 2024-09 至 2026-07 修复。
  4. **选定组合决定性优势**：宿主机 `clang-21.1.8` 纯 Kbuild 一次编过 `modules_prepare`、`mt6768.dtb`、核心 MT6768 驱动及全部 5 大 Connsys 无线模块；`Addster09` 原生自带 ZPD1203 硬件所需的 `sgm415xx.c` + `aw35615` + 干净 `mtk_battery.c`，`aosp-6.6` 原生自带 `wusb3801.c` + `aw37503-regulator.c`，Motorola GPU 仓唯一保留与原厂 `libGLES_mali.so` 完全一致的 **`r32p1-01eac0`**。

## ADR-003：Android Boot v2 打包基线、纯净 Ramdisk 来源与内建模块 (`ALLOW_BUILTIN`) 策略
- **日期**：2026-11-24
- **决策**：
  1. 使用 **Android Boot Image Header v2**（`page_size=2048`, `kernel=0x40080000`, `ramdisk=0x47c80000`, `dtb=0x4bc80000`, `os_version=12.0.0`），并从 **`vendor_boot_a.img`**（字节级纯净原厂 4.19 `boot.img`）提取基础 ramdisk（避免 `boot_a.img` 中的 Magisk 残留）。
  2. 在 `kernel-6.6/drivers/Makefile` 末尾接入 1 行 `include $(srctree)/$(KCONFIG_EXT_PREFIX)Makefile.ext` 并启用 `CONFIG_DEVICE_MODULES_ALLOW_BUILTIN=y`，使核心启动/时钟/PMIC/存储/USB/触控/电源驱动直接编译进 `Image.gz`（控制 `boot.img < 32 MiB` 限制内，同时避免 5.10 中 115 个 `=m` 未打包陷阱）；Connsys 无线等仍编为与 `Image.gz` 严格同版本 `vermagic` 的 `.ko` 模块。
  3. `ramoops/pstore` 固定映射与 LK 实机日志一致的物理区间 **`0x4d010000` (`0xe0000`)**。

## ADR-004：USB 控制器选型 (`musb-hdrc` vs `mtu3`) 与显示 / GPU / ION 兼容路线
- **日期**：2026-11-24
- **决策**：
  1. **USB 优先对接 `musb-hdrc` (`drivers/misc/mediatek/usb/usb20/`)**：原厂 `init.mt6768.usb.rc` 与 `android.hardware.usb@1.2` HAL 硬编码 `"musb-hdrc"` 且 6.6 `Addster09`/`Moto` 树完整保留 `usb20`；同时打通 `sgm41510@6b` + `aw35615@22` + `wusb3801@60` + `extcon_usb` + `mt6358_gauge` 完整充电状态上报链。
  2. **显示双阶段推进**：Phase 4 最小启动使用 `simplefb`（`0x7d350000`，继承 5.10 清除 OVL0 L3 `0x1400b000+0x02c` 修复）+ `gralloc_fb0_bridge` 确保第一时间无串口进入可视/ADB 环境；Phase 5 推进 6.6 MTK DRM v2 + `jt120wul005_a01_dsi_vdo` (`HX83102-E/J`) + `aw37503` + 背光与 Android HWC 兼容方案。
  3. **GPU & ION 严守真硬件原则**：启用 `mali-r32p1` + `ged` + `gpufreq` + `mtk_iommu` + `mtk-smi` 对齐原厂 `libGLES_mali.so` (`r32p1-01eac0`)；针对 6.6 移除 `staging/ion` 但原厂 `Codec2`/`libion_mtk` 依赖 `/dev/ion` `BIT(10)` 的问题，Phase 6 实现由真实 `dma_heap` (`mtk_mm`) 支撑的 `/dev/ion` 兼容层（绝不伪造桩函数）。
