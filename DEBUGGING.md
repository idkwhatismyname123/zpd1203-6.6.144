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
- **实机屏幕滚动内核日志 (`fbcon`)**：`full` 与 `minimal` 两种镜像均已启用 `CONFIG_VT=y`、`CONFIG_VT_CONSOLE=y`、`CONFIG_FRAMEBUFFER_CONSOLE=y`、`CONFIG_FRAMEBUFFER_CONSOLE_ROTATION=y`、`CONFIG_FB_SIMPLE=y` 与 `CONFIG_FONT_TER16x32=y`（高分屏 16x32 大字体），并在启动命令行注入 `console=tty0 fbcon=rotate:3,font:TER16x32 panic=8 printk.devkmsg=on ignore_loglevel loglevel=8`（异常 Panic 停留 8 秒便于读屏）。
- **`full` 模式平滑交接**：DTS `&chosen/framebuffer@7d350000` 开启早期 `simple-framebuffer` 从 `t=0.45s` 起立即输出屏幕日志；随后 `mediatek_v2` DRM (`CONFIG_DRM_FBDEV_EMULATION=y`)、`panel-himax-jt120wul005-vdo`、`aw37503` 与 `mtk_leds` 在 `mtk_drm_bind()` 调用 `drm_aperture_remove_framebuffers(&mtk_drm_driver)` 平滑接管并注销 `simplefb`，提供原生 `/dev/dri/card0` 与支持 `fbcon` 的 `mtk_fbdev_ops`。
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

### 记录 #1：2026-11-25 首次 `boot-full-6.6.img` (`g79934f29bfe5`) 实机测试与 `pstore`/`expdb` 取证

- **取证路径**：[crash_forensics_20261125_125044](file:///d:/P3066/out/crash_forensics_20261125_125044)（恢复原厂 `boot_a.img` 后通过 `adb root` 完整导出 `console-ramoops-0` 168,499 B、`dmesg-ramoops-0/1`、`proc_pl_lk.txt` 及 20 MiB `expdb_live.img`）。
- **已由实机日志直接确认的事实**：
  1. `boot-full-6.6.img`（`6.6.144-zpd1203-g79934f29bfe5 #2`）成功由 LK 跳转并通过 Linux 6.6.144 极早期启动至 **`t=0.590s`**（`console-ramoops-0` 共 2,240 行）：双 Rank 6 GiB DRAM、8 核 CPU / PSCIv1.1 / GICv3、`ramoops` (`0xe0000@0x4d010000`)、`pwrap` / `mt6358-rtc`、`SSPM`、`mtk_sysirq`（10 字 `INTPOL` 写入完成）、`KernelSU v3.3.1`、`mtk-smi`、`mtk-wdt`、`mt6358-gauge`、`i2c0..5` 及真实充电 IC **`sgm41510@6b` (`Part Num: 0, Revision: 0`)** 均已正常探测。
  2. **崩溃根因（`dmesg-ramoops-0` L48–L90）**：`bq2589x_charger_probe()` 在 `0.589s` 注册完立即以 `0 ms` 调度 `bq2589x_read_byte_work`，检测到板端已连接 USB 后调用 `Charger_Detect_Init()` -> `usb_prepare_clock+0x38/0x30c`，此时 `usb20` (`musb-hdrc`) 尚未完成 `probe`、`glue` 仍为 `NULL`，访问 `glue->sys_clk`（虚拟地址 `0x0000000000000018`）触发 Kernel Panic 并立刻重启；且旧版 `full` 未开启 `simplefb` 导致 DRM 初始化前屏幕上无可见报错。
  3. **次生隐患定位**：`bq2589x_get_usb_type()` 中 `Charger_Detect_Release()` 仅在 `if (prev_pg)` 时执行，首次上电检测到 PC SDP/CDP 时不会释放 D+/D- 给 MUSB。
  4. **`fastboot boot` LK 限制实证（`expdb_live.img` 偏移 `0x12dca88`）**：尝试对 `boot-minimal-6.6.img` 执行 `fastboot boot` 时，LK 打印 `[fastboot: command buf]-[boot]` -> **`boot image is NULL`** -> `panic (caller 0x4c42941f)`，导致 USB 断连报 `usb_read failed (31)`；因此实机测试应刷写 `boot_a` 分区并保留原厂 `boot_a.img` 恢复路径。
- **修复措施（已合入 `92c716870252` / `3086c4b0af53` 并通过 `full` 重建）**：
  1. 在 [musb_core.c](/home/asus/zpd1203-6.6/kernel/kernel_device_modules-6.6/drivers/misc/mediatek/usb/usb20/musb_core.c) 的 `Charger_Detect_Init()`、`Charger_Detect_Release()`、`usb_prepare_clock()`、`usb_enable_clock()` 加入 `glue` / `glue->phy` 空指针保护。
  2. 在 `bq2589x_charger.c` 将 `INIT_DELAYED_WORK` 前移至中断注册前、初始 `read_byte_work` 延后至 `1500 ms`，并在初次探测为 `SDP`/`CDP`/`UNKNOWN` 时补齐 `Charger_Detect_Release()`。
  3. 为 `full` 模式开启 `CONFIG_FB_SIMPLE=y` 与 `&chosen/framebuffer@7d350000` 早期屏幕日志，在 `mtk_drm_bind()` 接入 `drm_aperture_remove_framebuffers(&mtk_drm_driver)`，并在命令行加入 `panic=8`。

### 记录 #2：2026-11-25 第二版 `boot-full-6.6.img` (`92c716870252` / `3086c4b0af53`) 实机屏幕日志验证与 `dramc` 崩溃定位

- **实机现象与截图证据**：
  1. 新开启的早期 `simplefb` + `fbcon=rotate:3,font:TER16x32` + `panic=8` 在平板屏幕横屏高清输出内核滚动日志并清晰驻留 8 秒，证明前期 `bq2589x`/`musb_core` 修复生效：内核已跳过 `0.590s` 崩溃并一路推进通过全部 `device_initcall`（level 6）直达 **`t=5.85s`**（`late_initcall` / level 7）。
  2. 实机 `com_full_fix1_20261125_130707.log` 记录到约每 29 秒重返 `PreLoader`（正常复位间隔加 `panic=8`）。
- **崩溃根因（实机屏幕栈轨迹）**：
  `mtk_sleep_init -> mtk_spm_init -> spm_module_init -> spm_get_spmfw_idx -> mtk_dramc_get_ddr_type+0x18/0x28` 解引用空指针导致 Kernel Panic。
  - 根因：`drivers/memory/mediatek/dramc.c` 的 `dramc_probe()` 在第 221 行先设置了全局 `dramc_pdev = pdev;`，随后在解析 DT `dram_type` 失败时直接 `return -EINVAL` 退出，此时 `platform_set_drvdata(pdev, dramc_dev_ptr)` 尚未执行；当 `spm_get_spmfw_idx()` 调用 `mtk_dramc_get_ddr_type()` 时，`dramc_pdev` 非空但 `platform_get_drvdata(dramc_pdev)` 返回 `NULL`，导致访问 `dramc_dev_ptr->dram_type` 崩溃。
- **修复措施（已合入 `0d43534325ef` 并重新构建验证 `full`）**：
  - 将 `dramc_pdev = pdev;` 移至 `platform_set_drvdata(pdev, dramc_dev_ptr);` 之后发布，并为 `dramc.c` 内全部 `platform_get_drvdata(dramc_pdev)` 调用点（`mr_show`、`mr4_show`、`mtk_dramc_get_steps_freq`、`mtk_dramc_get_data_rate`、`mtk_dramc_get_mr4`、`mtk_dramc_get_ddr_type`）补充 `NULL` 防护；已交叉核查 `emicen.c`/`emiisu.c`/`emimpu.c` 均已在探测成功后再赋 `*_pdev` 且 `spm_get_spmfw_idx()` 在无 DRAMC 时安全返回 `0`。

### 记录 #3：2026-11-25 第三版 `boot-full-6.6.img` (`0d43534325ef`, `e6643dbe...`) 实机跑码至 `t=227s+` 与 SELinux Enforcing 阻塞定位

- **重要实机突破（实机屏幕照片 `t=223s–227s`）**：
  1. `dramc.c` 修复完全生效，Linux `6.6.144-zpd1203-g92c716870252` 顺利通过全部内核 `initcall`（未再发生 Kernel Panic 或重启），挂载 `super` 动态分区，完成 `a12_init_wrapper` `SwitchRoot`，并拉起 Android `init` 与 SELinux 策略加载，设备稳定运行至 **`t=227s+`** 持续输出日志。
  2. 76 秒 USB 遥测（[com_full_fix2_20261125_131905.log](file:///d:/P3066/out/com_full_fix2_20261125_131905.log)）中未见 PreLoader 二次跳变，说明设备未处于重启循环，而是被 SELinux Enforcing 拦截后 USB Gadget 无法完成枚举。
- **阻塞根因（屏幕实拍日志）**：
  - 屏幕持续刷屏：`type=1400 audit(...): avc: denied { ... } for pid=... comm="init" scontext=u:r:kernel:s0 ... permissive=0`（涉及 `/dev/kmsg`、`graphics_device`、`configfs`、`tmpfs`）。
  1. **主因 (`permissive=0`)**：`scripts/package_boot.sh` 注入的 `CMDLINE` 缺少 `androidboot.mode=normal androidboot.selinux=permissive`（原 5.10 在 `CMDLINE` 显式传入该参数）。Android `init` 仅校验内核命令行中的 `androidboot.selinux=permissive` 而非 `prop.default`，导致虽然内核已启用 `CONFIG_SECURITY_SELINUX_DEVELOP=y`，仍被 Android `init` 强制切入 Enforcing。
  2. **次因（20 Hz 刷屏放大）**：[a12_init_wrapper.c](file:///d:/P3066/zpd1203/tools/a12_init_wrapper.c) 的 `run_logger_child()`（以 `u:r:kernel:s0` / `comm="init"` 运行）在权限受拒或设备未就绪时按 50 ms 循环无退避地重复调用 `ensure_dev_perms()`、`bind_early_acm()` 与 `bind_composite_g1()`，加速触发内核日志限速与 `fbcon` 刷屏。
- **修复措施（已重编并静态验证通过 `boot-full-6.6.img` SHA256 `c40aa239...`）**：
  1. 在 [package_boot.sh](file:///d:/P3066/scripts/package_boot.sh) 为 `full` 与 `minimal` 的 `CMDLINE` 均追加 `androidboot.mode=normal androidboot.selinux=permissive`。
  2. 在 [verify_build.sh](file:///d:/P3066/scripts/verify_build.sh) 增加 `androidboot.mode=normal` 与 `androidboot.selinux=permissive` 启动命令行校验断言。
  3. 在 [a12_init_wrapper.c](file:///d:/P3066/zpd1203/tools/a12_init_wrapper.c) 为 `ensure_dev_perms()`（限前 60s 内每秒一次）以及 `bind_early_acm()` / `bind_composite_g1()`（失败后按 2s / 最多 15 次退避重试）加入节流与上限控制。

### 记录 #4：2026-11-25 第四版实机跑码（`c40aa239...`）`COM20` 完整内核日志抓包与 4 项根因修复

- **抓包路径与实机成果**：[com20_live_6.6_20261125_134002.log](file:///d:/P3066/out/com20_live_6.6_20261125_134002.log)（从 `COM20` `USB\VID_1D6B&PID_0104\<device-serial>` 抓回 `723,919` 字节 / `4,221` 行，内核序列 `seq=3864..18500`、`t=93.5s..249.0s`），配合 [com_full_fix3_20261125_133552.log](file:///d:/P3066/out/com_full_fix3_20261125_133552.log) 实证：
  1. 设备零崩溃、零重启循环（`preloaderEdges=1`），所有 `avc: denied` 已切换为 `permissive=1`。
  2. Connsys Wi-Fi/BT 在实机完成补丁下载、RF 校准（`Backup success`）与 `mtk_wcn_wmt_func_ctrl:OPID(3) type(9) ok`（`t=139.4s` 屏幕照片）。
  3. `COM20` `[status]`（`L4085`）回报：`[status] new_root=1 early_acm=0 g1_switched=1 rebinds=0 hwc_bound=1 ep1=1 dri=0 fb0=1 mali=1 ion=1 pstore=0 UDC='musb-hdrc'`。
  4. `mt6768-afe-pcm`（`vendor.audio-hal`）、`bq2589x`/`sgm41510`（`usb online(1), pg(1), psy_usb_type:3, ichg=1500mA, Vbat=4257`）、`zygote`、`netd`、`wificond`、`mediaserver`、`adbd`（`T1059`, `ep1=1`）均已正常拉起。
- **定位的 4 项阻塞/关键根因**：
  1. **GED `GE_ALLOC` ABI 不兼容（致 `surfaceflinger` 反复 SIGABRT）**：原厂 Android 12 `allocator@4.0`（`PID 921`）传入 18 个 region（`76 B`），而 6.6 `ged_main.c` 硬性要求 `GE_ALLOC_STRUCT_NUM=22`（`92 B`）报 `Failed to region_num, it must be 22`，且 `ged_ge.c` 将负数 `ge_fd=-1` 误判为 `GED_OK`，引发 `binder: 921:921 got transaction with invalid fd, -1` 与 `surfaceflinger`（`PID 2668`）`signal 6` 连环重启。
  2. **MT6768 `i2c2`/`i2c3`/`i2c4` 多通道缺少 `ch-offset-i2c = <0x100>`（致 `aw87xxx` 阻塞 104 秒）**：6.6 `i2c-mt65xx.c` 依赖 DTS 属性 `ch-offset-i2c`，缺失导致 `i2c3` (`1100f000`) 对 `aw87xxx_pa@59/5A` 访问错误偏移并超时 `104,083,011 usecs`。
  3. **`a12_init_wrapper.c` ACM 锁死阻断 ADB**：因前述 104 秒延迟导致 `SwitchRoot` 后 25 秒内未见 `ep1`，`g1` 回退为纯 `acm.gs1` (`VID 0x1d6b / PID 0x0104`) 后看门狗不再将其升级为 `ffs.adb+acm.gs1`，致后续 `init.mt6768.usb.rc` 报 `File exists` / `Device or resource busy`。
  4. **早期日志被覆盖（`dri=0` 原因未保留）**：默认 `CONFIG_LOG_BUF_SHIFT=17` (128 KiB) 加 `ignore_loglevel loglevel=8` 刷屏导致 `t=0..93.5s` 早期启动与 DRM 初始化日志被挤出环形缓冲区。
- **修复与验证（`6.6.144-zpd1203-ga8f0da857734` + `device_modules` `4779d25e29f7`）**：
  1. 修改 `ged_main.c` / `ged_ge.c` 兼容 1..22 个 region（18 与 22 region 均按真实 `i32InBufferSize` 解析与分配）并修正 `ge_fd >= 0` 判错（见 `device_modules-6.6-0003-*.patch`）。
  2. 在 [zpd1203-power-audio-wireless.dtsi](file:///d:/P3066/zpd1203/dts/zpd1203-power-audio-wireless.dtsi) 为 `i2c2`/`i2c3`/`i2c4` 补全 `ch-offset-i2c = <0x100>;` / `ch-offset-ccu = <0x200>;`（`i2c3` 另配 `scl/sda-gpio-id`），并在 `aw87xxx_device.c` 遇到 `-ETIMEDOUT` 时立即跳出（见 `device_modules-6.6-0004-*.patch`）。
  3. 在 `zpd1203_defconfig` / `zpd1203_console_com.config` 提高 `CONFIG_LOG_BUF_SHIFT=20` (1 MiB)（见 `kernel-6.6-0002-*.patch`）。
  4. 在 [a12_init_wrapper.c](file:///d:/P3066/zpd1203/tools/a12_init_wrapper.c) 增加 `ep1` 就绪后从纯 ACM 自动升级至 `ffs.adb+acm.gs1` 分支（`g1_tries < 20`），并在 [package_boot.sh](file:///d:/P3066/scripts/package_boot.sh) 将 `full` 命令行调为 `loglevel=4`。已完成 `./scripts/build_all.sh --mode full` 全量重编校验 PASS。
