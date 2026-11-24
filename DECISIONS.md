# ZPD1203 Linux 6.6 技术决策记录 (DECISIONS.md)

## ADR-001：工作目录隔离策略（Windows 控制仓 + WSL2 ext4 构建区）
- **日期**：2026-11-24
- **决策**：项目管理文档、分析报告、DTS/DTSI、defconfig、补丁集、自动化脚本及最终发布产物存放在 Windows `d:\P3066` 并纳入 Git 管理；内核源码克隆、原厂镜像解包及内核编译全部在 WSL2 ext4 文件系统 `/home/asus/zpd1203-6.6/` 中执行。
- **原因**：Linux 内核源码依赖大小写敏感与符号链接；`/home/asus/zpd1203-5.10.240` 与原厂备份 `D:\备份\p\GeekFlashTool_Readback_20260820162108246` 必须绝对保持只读与完整。

## ADR-002：选定 Linux 6.6.144 (`android15-6.6`) + `Addster09` BSP + Moto GPU/Connsys 为移植基底
- **日期**：2026-11-24
- **状态**：已定案（Phase 1–7 全程实证）
- **决策**：
  - **Core Kernel**：`https://android.googlesource.com/kernel/common` 分支 `android15-6.6`（基线 `329f9ae918a9` **Linux 6.6.144** -> `91af1aa18e1a`）。
  - **MT6768 `device_modules`**：`https://github.com/Addster09/mtk-kernel-modules-bsp-6.6`（基线 `1561b421959f` -> `8ed4bf689504`）为主，交叉比对 Moto `v1tl35.73-60-3`。
  - **GPU**：`https://github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-gpu`（`3b81cf6d7c0a` -> `2d3b928b88ce`）中的 **`mali_valhall/mali-r32p1`** (`r32p1-01eac0`)。
  - **Connsys 无线**：Motorola `vvta35` (`common` `0fd4f365ead4`, `connfem` `8a665a04c769`, `bt-mt66xx` `95859aaae7f4`, `wlan-adaptor` `48e9f37a18b7`) + `v1tl35.73-60-3` (`wlan-core-gen4m` `0eb4c16595f3`)。
- **依据**：Linux 6.1 Moto 仓库不含 MT6768；Samsung 树带 DEFEX/AFDO 且缺失 `mali-r32p1`；本组合在宿主机 `clang-21.1.8` + `ld.lld` 下 0 错误编译，且精准匹配原厂 `libGLES_mali.so` (`r32p1-01eac0`)、SGM41510 与 AW35615。

## ADR-003：Android Boot v2 打包基线、纯净 Ramdisk 与 `ALLOW_BUILTIN` 策略
- **日期**：2026-11-24
- **决策**：
  1. 采用 Android Boot Header v2（`page_size=2048`, `kernel=0x40080000`, `ramdisk=0x47c80000`, `dtb=0x4bc80000`），从纯净原厂 `vendor_boot_a.img` 提取 Ramdisk（剔除 `.backup`/`overlay.d` Magisk 残留）。
  2. 集成 `DEVICE_MODULES_ALLOW_BUILTIN=y`，核心 SoC/显示/触控/音频/充电/存储驱动全部内置；OOT Mali 与无线驱动编译为 `.ko` 并经 `vermagic`/CRC/符号闭环校验。
  3. 固化 `KBUILD` 强制传参规则：所有 `make -C $KDIR O=$OUT` 调用均须显式传递 `KCONFIG_EXT_PREFIX=../kernel_device_modules-6.6/`，防止 `syncconfig` 误删外部配置符号。

## ADR-004：显示/GPU/充电多器件真实驱动路线（拒绝虚假桩）
- **日期**：2026-11-24
- **决策**：
  1. `usb20` (`musb-hdrc`) + `bq2589x_charger.c` 扩展 `sgm,sgm41510`（同时修复 `!mt_usb_is_device()` OTG 互斥死锁与 `usb`/`ac` PSY 导出）+ 5 处 `Makefile` 适配 `tcpc_aw/inc` + `aw35615`。
  2. 诚实标注二供 `fs15xx`（6.6 `fs18xx` 不支持）、`wusb3801`（与 `aw35615` 共用 GPIO 8 冲突）、I2C1 传感器（无开源 6.6 驱动）及摄像头（EL2 `/dev/gz_kree` + 缺 `hi849`/`aw36515`）现状，严禁用虚假桩函数欺骗状态。

## ADR-005：`/dev/ion` -> DMA-BUF Heap 真实转发兼容层（Phase 6）
- **日期**：2026-11-24
- **决策**：在 `kernel_device_modules-6.6/drivers/dma-buf/heaps/` 实现 `mtk_ion_compat.c`（`CONFIG_ZPD1203_ION_DMABUF_COMPAT=y`），启用 `CONFIG_DEVICE_MODULES_DMABUF_HEAPS_SYSTEM=y` 并显式禁用上游 `# CONFIG_DMABUF_HEAPS_SYSTEM is not set` 防止 `"system"` 堆重名冲突；`/dev/ion` 接收 ABI v2 ioctl 并通过内核 `dma_heap_find()` + `dma_heap_bufferfd_alloc()` 真实分配与返回 `dma_buf` fd（`BIT(10)` -> `mtk_mm`/`mtk_mm-uncached`，`BIT(0)` -> `system`/`system-uncached`，未定义 ioctl 返回 `-ENOTTY`）。

## ADR-006：全量 Ramdisk `xz` 压缩与 `a12_init_wrapper` DRM/FB 动态分流（Phase 6–7）
- **日期**：2026-11-24
- **决策**：
  1. 在 `zpd1203_defconfig` 启用 `CONFIG_RD_XZ=y`，使含 11 枚 stripped `.ko` 的 `initramfs-full-6.6.cpio.xz` 控制在 `12,343,696 B`（`boot-full-6.6.raw.img` = `28,213,248 B`，在 32 MiB 上限下保留 5+ MiB 冗余），无需删除恢复界面资源。
  2. `a12_init_wrapper.c` 在预启动和 `SwitchRoot` 后通过保持只读 fd 跨根切换加载并 `MS_BIND` 替换 `/vendor/lib/modules`；依据 `/dev/dri/card0` 存在性动态决定启用原生 DRM 链路或自动挂载 `simplefb` + `gralloc.fb0_bridge.so` 桥接。
  3. 同步保存 standalone `zpd1203_defconfig` 至 `kernel-6.6` 与 `kernel_device_modules-6.6` 两仓 `arch/arm64/configs/`（兼容 Kbuild `%_defconfig` `srctree` 查找规则），并实现 14 份自动化构建/校验/测试/恢复/日志脚本。
