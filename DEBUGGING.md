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

### Level 3：双模显示输出与回退保障（DRM v2 + `simplefb` 门控）
- **`full` 模式**：启用 `mediatek_v2` DRM、`panel-himax-jt120wul005-vdo`、`aw37503` 与 `mtk_leds` 背光，提供原生 `/dev/dri/card0`。
- **`minimal` 模式（或 `full` 模式 DRM 未就绪自动降级）**：使用 LK 帧缓冲 `0x7d350000`（`1200x2000`, `simplefb` 清除 OVL0-L3 DAL 覆盖层 + `/sys/kernel/debug/zpd_disp_regs` 快照）与零依赖 `gralloc.fb0_bridge.so`。
- `a12_init_wrapper` 在 `SwitchRoot` 后检测 `/dev/dri/card0`：若 `/dev/dri/card0` 存在则跳过 HWC 空桩、启用原生 DRM；若不存在（`minimal` 或异常降级）则挂载 `gralloc.fb0_bridge.so` + `/dev/.empty_hwc` 保底输出画面。

### Level 4：Initramfs 阶段标记 (`STAGE 1..7`)、模块加载与复合 USB Gadget
- 源码位于 [a12_init_wrapper.c](file:///d:/P3066/zpd1203/tools/a12_init_wrapper.c)（交叉编译为 `597,928 B` 静态 aarch64 二进制 `/init`）：
  - `STAGE 1`：挂载临时 `devtmpfs`/`sysfs`/`proc`，写入 `/dev/kmsg`。
  - `STAGE 2`：检查并归档 `/sys/fs/pstore/*` 至 `/dev/.pstore_dump.log`。
  - `mod (pre-init)`：在进入 `/system/bin/init` 前按拓扑顺序加载 `/zpd_modules/` 内全部 11 枚 6.6 `.ko`（`mali_mgm_mt6768` -> `mali_kbase_mt6768` -> `rfkill` -> `cfg80211` -> `btif_drv` -> `conn_md_drv` -> `connfem` -> `wmt_drv` -> `wmt_chrdev_wifi` -> `bt_drv_connac1x` -> `wlan_drv_gen4m`），`minimal` 模式下无此目录则静默跳过。
  - `STAGE 3`：扫描 `/sys/class/udc` 检测 `musb-hdrc` 并 fork 后台串口与状态守护子进程。
  - `STAGE 4`：卸载临时挂载，`execv("/system/bin/init")`。
  - `STAGE 5`：在 `SwitchRoot` 后重试未完成模块加载，将匹配 6.6 `.ko` 复制至 `/dev/.zpd_modules/` 并 `MS_BIND` 覆盖 `/vendor/lib/modules/<name>`，随后依据 `/dev/dri/card0` 执行 DRM / `simplefb` 门控分流，并对 `/dev/mali0`、`/dev/ion`、`/dev/graphics/fb0` 授权 `0666`。
  - `STAGE 7`：待 `/dev/usb-ffs/adb/ep1` 就绪后将 `g1` 复合配置 (`ffs.adb + acm.gs1`, VID `0x0e8d` PID `0x2006`) 绑定至 `musb-hdrc`（超时 ~175s 回退至纯 `acm.gs1`）。
- **ACM 串口交互命令**（`/dev/ttyGS*`）：支持输入 `status`（输出 `new_root/hwc_bound/g1_switched/ep1/dri/fb0/mali/ion/pstore/g1_UDC`）、`pstore`、`unbind`、`reboot-fb`。

### Level 5：非破坏性测试、安全刷写、原厂恢复与一键日志收集
- 内存临时测试：[test_fastboot_boot.ps1](file:///d:/P3066/scripts/test_fastboot_boot.ps1) / [test_fastboot_boot.sh](file:///d:/P3066/scripts/test_fastboot_boot.sh)
- 一键日志采集（ADB `dmesg`/`pstore`/`lsmod`/`power_supply`/`dev_nodes`/`SurfaceFlinger`/`logcat` 或 TTY/`expdb` 离线指引）：[collect_logs.ps1](file:///d:/P3066/scripts/collect_logs.ps1) / [collect_logs.sh](file:///d:/P3066/scripts/collect_logs.sh)
- 交互式门禁刷写/原厂恢复：[flash_boot_safe.ps1](file:///d:/P3066/scripts/flash_boot_safe.ps1) / [restore_stock.ps1](file:///d:/P3066/scripts/restore_stock.ps1)（含 `.sh` 对应版）

---

## 3. 真实设备日志档案

> **当前尚无 Linux 6.6 实机测试日志（`尚未验证`）**。用户实机运行后可通过 `scripts\collect_logs.ps1` 拉取并回填本节，作为后续真机调优与实机状态晋级依据。
