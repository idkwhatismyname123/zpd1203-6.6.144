# ZPD1203 无物理 UART 多级调试方案与真实日志 (DEBUGGING.md)

## 1. 约束条件
- ZPD1203 设备**没有物理 UART**，**严禁要求拆机焊接调试串口**。
- 所有内核带板调试必须依赖重启保留内存、分区转储、屏幕早期输出与 USB/ADB 通道。

## 2. 多级调试机制设计与 Phase 4 实现（已静态验证）

### Level 1：内核早期异常与重启后日志留存 (`ramoops` / `pstore`)
- **原理**：Preloader 通过 `mblock` 在 `0x4d010000` (`0xe0000` = 896 KiB) 预留非清零物理区间，LK 启动时动态注入 `ramoops.mem_address=0x4d010000 ramoops.mem_size=0xe0000 ramoops.pmsg_size=0x10000 ramoops.console_size=0x40000` 及 `debug-kinfo @ 0x4d000000 (0x10000)`。`mt6768-zpd1203-minimal.dts` 使用 `CONFIG_CMDLINE_EXTEND=y` 保留 LK 注入参数，严禁 `CMDLINE_FORCE`。
- **内核配置（`zpd1203_minimal_defconfig` 已启用）**：
  - `CONFIG_PSTORE=y`
  - `CONFIG_PSTORE_CONSOLE=y`
  - `CONFIG_PSTORE_PMSG=y`
  - `CONFIG_PSTORE_RAM=y`
  - `CONFIG_PSTORE_COMPRESS=y`
- **取证方式**：`a12_init_wrapper`（PID 1 接管阶段）会先行挂载 `/sys/fs/pstore`，检索 `console-ramoops*` / `dmesg-ramoops*` / `pmsg-ramoops*`，将文件名与大小输出到 `/dev/kmsg`，将完整内容归档至 `/dev/.pstore_dump.log`，并把最后 1024 B tail 写入 `/dev/kmsg` 供当前启动的串口/ADB 立即读取。

### Level 2：MTK `EXPDB` 分区转储分析
- 设备存在独立 `expdb` 分区（`0x1400000` = 20 MiB，`linear_start_addr: 0x108000`）。
- 只读原厂备份 `expdb.img` 已用于确认实机 `ramoops`/`framebuffer`/`mblock` 布局；若实机出现无 ADB 崩溃且 `pstore` 无输出，可通过 MTKClient/Fastboot/Recovery 回读 `expdb` 解码 PL/LK/GZ/AEE 日志。

### Level 3：早期屏幕输出与 `simplefb` / `zpd_disp_regs` 调试
- 在 Phase 4 最小启动配置中启用 `CONFIG_FB=y` + `CONFIG_FB_SIMPLE=y`（`CONFIG_DRM=n`，`&dispsys_config` 与 `&dsi0` 禁用，命令行加 `clk_ignore_unused pd_ignore_unused regulator_ignore_unused` 保持 LK 面板电源与时钟），使用 LK 活态帧缓冲 `0x7d350000` (`1200x2000`, stride `4864`, `a8r8g8b8`)。
- `drivers/video/fbdev/simplefb.c` 移植了 `mediatek,zpd1203-lk-display` 钩子：探测时清除 OVL0 Layer 3 DAL 覆盖层（`0x1400b000 + 0x02c` 写 0，防止 LK 启动文字层遮挡）并提供 `/sys/kernel/debug/zpd_disp_regs` 寄存器快照。
- `gralloc.fb0_bridge.so`（零动态库依赖、静态断言校验 `HMI`/`framebuffer_device_t` ABI 偏移）由 `a12_init_wrapper` 在 SwitchRoot 后覆盖 `/vendor/lib64/hw/gralloc.default.so`（同时用空文件屏蔽 `/vendor/lib64/hw/hwcomposer.mt6768.so`），允许 Android SurfaceFlinger 通过 `HWC2OnFbAdapter` + NEON DMA-BUF 搬运输出画面至 `fb0`。

### Level 4：Initramfs 阶段标记 (`STAGE 1..7`) 与复合 USB Gadget (ADB + ACM)
- 源码位于 `zpd1203/tools/a12_init_wrapper.c`（由 `zpd1203/scripts/build_minimal_ramdisk.sh` 静态编译为 `/init`）：
  - `STAGE 1`：挂载临时 `devtmpfs`/`sysfs`/`proc`，写入 `/dev/kmsg`。
  - `STAGE 2`：检查并归档 `/sys/fs/pstore/*` 至 `/dev/.pstore_dump.log`。
  - `STAGE 3`：扫描 `/sys/class/udc` 检测 `musb-hdrc` 并 fork 后台日志守护进程（单次绑定策略，避免 ConfigFS UDC 重绑触发 MUSB DMA/QMU 卡死）。
  - `STAGE 4`：卸载临时挂载并 `execv("/system/bin/init")`。
  - `STAGE 5`：检测到 `/proc/1/root/vendor/lib64/hw/hwcomposer.mt6768.so` 后 chroot 至 Android 活态根文件系统，挂载 `gralloc.fb0_bridge.so` 与空 HWC 桩。
  - `STAGE 6`：`/dev/graphics/fb0` 就绪后授权 `0666`。
  - `STAGE 7`：待 `/dev/usb-ffs/adb/ep1` 就绪后将 `g1` 复合配置 (`ffs.adb + acm.gs1`, VID `0x0e8d` PID `0x2006`) 绑定至 `musb-hdrc`（若 ~175s 超时则自动退化绑定 `acm.gs1` 保留调试串口）。
- **ACM 串口交互命令**（`/dev/ttyGS*`）：支持输入 `status`、`pstore`、 `unbind`、`reboot-fb`。

### Level 5：非破坏性测试与安全回退
- 优先使用 `fastboot boot out/minimal/boot-minimal-6.6.img`（仅驻留内存，不擦写 eMMC）。
- 因 `super` 仅 slot `_a` 存在逻辑分区，最小镜像命令行注入 `mt6768.force_slot_a=1`，即便从 `_b` 槽启动测试亦可正确挂载 `_a` 动态分区而不修改 `fstab.mt6768`。

---

## 3. 真实设备日志档案

> **当前尚无 Linux 6.6 实机测试日志**。实机测试后将在此追加真实 `dmesg`、`pstore`、`logcat` 摘要与排查结论。
