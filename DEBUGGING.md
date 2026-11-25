# ZPD1203 无物理 UART 多级调试方案与真实日志 (DEBUGGING.md)

## 1. 约束条件
- ZPD1203 设备**没有物理 UART**，**严禁要求拆机焊接调试串口**。
- 所有内核带板调试依赖重启保留内存、`expdb` 分区转储、屏幕输出与 USB Composite Gadget (ADB + ACM) 通道。

## 2. 多级调试机制设计与实现（`已编译通过` / `已静态验证`）

### Level 1：内核早期异常与重启后日志留存 (`ramoops` / `pstore`)
- **原理**：Preloader 通过 `mblock` 在 **`0x4d010000`** (`0xe0000` = 896 KiB) 预留非清零物理区间，LK 注入 `ramoops.mem_address=0x4d010000 ramoops.mem_size=0xe0000 ramoops.pmsg_size=0x10000 ramoops.console_size=0x40000` 与 `debug-kinfo @ 0x4d000000`。全量与最小构建均使用 `CONFIG_CMDLINE_EXTEND=y` 保留 LK 参数。
- **内核配置**：`CONFIG_PSTORE=y`、`CONFIG_PSTORE_CONSOLE=y`、`CONFIG_PSTORE_PMSG=y`、`CONFIG_PSTORE_RAM=y`、`CONFIG_PSTORE_COMPRESS=y`。
- **自动取证**：`a12_init_wrapper`（`STAGE 2`）首先挂载 `/sys/fs/pstore`，归档所有转储至 `/dev/.pstore_dump.log` 并将尾部 1024 B 写入 `/dev/kmsg`。

### Level 2：MTK `EXPDB` 分区离线取证
- 设备存在独立 `expdb` 分区（`0x1400000` = 20 MiB，`linear_start_addr: 0x108000`）。
- 当系统在 ADB 与 ACM 枚举前崩溃且 `pstore` 无信息时，可通过 SP Flash Tool / GeekFlashTool / mtkclient 回读 `expdb` 解析 PL/LK/GZ/AEE 日志。

### Level 3：屏幕内核日志 (`fbcon`)、双模显示输出与回退保障（DRM v2 + `simplefb` 门控）
- **实机屏幕滚动内核日志 (`fbcon`)**：`full` 与 `minimal` 两种镜像均已启用 `CONFIG_VT=y`、`CONFIG_VT_CONSOLE=y`、`CONFIG_FRAMEBUFFER_CONSOLE=y`、`CONFIG_FRAMEBUFFER_CONSOLE_ROTATION=y` 与 `CONFIG_FONT_TER16x32=y`（高分屏 16x32 大字体），并在启动命令行注入 `console=tty0 fbcon=rotate:3,font:TER16x32 printk.devkmsg=on ignore_loglevel loglevel=8`，内核一起即可按横屏方向直接在屏幕实时滚动打印内核与 `[ZPD1203-6.6] STAGE 1..7` 日志（无需等到 Android 图形栈就绪）。
- **`full` 模式**：启用 `mediatek_v2` DRM (`CONFIG_DRM_FBDEV_EMULATION=y`)、`panel-himax-jt120wul005-vdo`、`aw37503` 与 `mtk_leds` 背光，提供原生 `/dev/dri/card0` 及支持 `fbcon` 的 `mtk_fbdev_ops`。
- **`minimal` 模式（或 `full` 模式 DRM 未就绪自动降级）**：使用 LK 帧缓冲 `0x7d350000`（`1200x2000`, `simplefb` 清除 OVL0-L3 DAL 覆盖层 + `/sys/kernel/debug/zpd_disp_regs` 快照）与零依赖 `gralloc.fb0_bridge.so`。
- `a12_init_wrapper` 在 `SwitchRoot` 后检测 `/dev/dri/card0`：若 `/dev/dri/card0` 存在则跳过 HWC 空桩、启用原生 DRM；若不存在（`minimal` 或异常降级）则挂载 `gralloc.fb0_bridge.so` + `/dev/.empty_hwc` 保底输出画面。

### Level 4：Initramfs 阶段标记 (`STAGE 1..7`)、早期/守护双阶段 USB COM 口 (`ttyGS*`) 与复合 Gadget
- 源码位于 [a12_init_wrapper.c](file:///d:/P3066/zpd1203/tools/a12_init_wrapper.c)（交叉编译为 `729,040 B` 静态 aarch64 二进制 `/init`）：
  - `STAGE 1`：挂载临时 `devtmpfs`/`sysfs`/`proc`，写入 `/dev/kmsg`。
  - `STAGE 2`：检查并归档 `/sys/fs/pstore/*` 至 `/dev/.pstore_dump.log`。
  - `mod (pre-init)`：在进入 `/system/bin/init` 前按拓扑顺序加载 `/zpd_modules/` 内全部 11 枚 6.6 `.ko`，`minimal` 模式下静默跳过。
  - `STAGE 3`：扫描 `/sys/class/udc` 检测 `musb-hdrc` 并 fork 后台 512 KiB `kmsg` 环形缓冲区 + 串口与状态守护子进程。
  - `STAGE 4`：卸载临时挂载，`execv("/system/bin/init")`。
  - `STAGE 5`：在 `SwitchRoot` 后重试未完成模块加载，将匹配 6.6 `.ko` 复制至 `/dev/.zpd_modules/` 并 `MS_BIND` 覆盖 `/vendor/lib/modules/<name>`，随后依据 `/dev/dri/card0` 执行 DRM / `simplefb` 门控分流，并对 `/dev/mali0`、`/dev/ion`、`/dev/graphics/fb0` 授权 `0666`。
  - **早期独立 COM 口回退 (`STAGE 7-early`, `zpd_com`)**：启用 `CONFIG_DEVTMPFS=y` 与 `CONFIG_U_SERIAL_CONSOLE=y`。若启动约 `15s` 后尚无 `/config/usb_gadget/g1/configs/b.1`（例如 Android init 卡死），守护进程主动写入 `/sys/module/musb_hdrc/parameters/kernel_init_done=1`、挂载临时 `configfs` 创建 `zpd_com` (`VID 0x1d6b / PID 0x0104`, CDC-ACM `acm.gs0`)，并主动读取 `/sys/class/tty/ttyGS0/dev` 执行 `mknod` 打开 `/dev/ttyGS0`，立即吐出完整历史内核日志并响应交互指令。
  - **`g1` 复合交接与防覆盖守护 (`STAGE 7`)**：待 Android `g1` 与 `/dev/usb-ffs/adb/ep1` 就绪后优雅释放 `zpd_com`，按需要先行解绑再绑定复合配置 (`ffs.adb + acm.gs1`, VID `0x0e8d` PID `0x2006`, `adb_acm`)；若 `SwitchRoot` 后 ~`25s` 仍未见 `ep1` 则回退为纯 `acm.gs1` (`VID 0x1d6b / PID 0x0104`)。同时内置看门狗每 ~`2s` 检查 `/config/usb_gadget/g1/configs/b.1/f2` 是否被 `init.mt6768.usb.rc` 清掉并在最多 6 次内自动恢复 `adb+acm`。
- **ACM 串口交互命令**（`/dev/ttyGS*`，Windows 端推荐使用 [watch_com.ps1](file:///d:/P3066/scripts/watch_com.ps1)）：支持输入 `status`、`pstore`、`help`、`unbind`、`reboot-fb`。

### Level 5：非破坏性测试、安全刷写、原厂恢复与一键日志收集
- 内存临时测试：[test_fastboot_boot.ps1](file:///d:/P3066/scripts/test_fastboot_boot.ps1) / [test_fastboot_boot.sh](file:///d:/P3066/scripts/test_fastboot_boot.sh)
- 一键日志采集（ADB `dmesg`/`pstore`/`lsmod`/`power_supply`/`dev_nodes`/`SurfaceFlinger`/`logcat` 或 TTY/`expdb` 离线指引）：[collect_logs.ps1](file:///d:/P3066/scripts/collect_logs.ps1) / [collect_logs.sh](file:///d:/P3066/scripts/collect_logs.sh)
- 交互式门禁刷写/原厂恢复：[flash_boot_safe.ps1](file:///d:/P3066/scripts/flash_boot_safe.ps1) / [restore_stock.ps1](file:///d:/P3066/scripts/restore_stock.ps1)（含 `.sh` 对应版）

---

## 3. 真实设备日志档案

> **当前尚无 Linux 6.6 实机测试日志（`尚未验证`）**。用户实机运行后可通过 `scripts\collect_logs.ps1` 拉取并回填本节，作为后续真机调优与实机状态晋级依据。
