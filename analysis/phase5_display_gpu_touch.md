# Phase 5 Step 5A 分析与移植报告：显示系统 / 背光 / Himax 触屏 / Mali-G52 GPU

- **阶段状态**：**`已编译通过` + `已静态验证`**（**尚未进行实机测试，绝不宣称 `已实机验证`**）
- **基线版本**：
  - `kernel-6.6`：`34be3f285fd5`（基于 Phase 3/4 `a0efcb376f2a`，AOSP `android15-6.6` **Linux `6.6.144`**）
  - `kernel_device_modules-6.6`：`e996acd6102c`（基于 Phase 3/4 `815405526aa3`，`Addster09/mtk-kernel-modules-bsp-6.6`）
  - `modules/gpu`：`2d3b928b88ce`（`MotorolaMobilityLLC/vendor-mediatek-kernel_modules-gpu` `mali-r32p1`）

---

## 1. 显示系统（MTK DRM v2 + `jt120wul005` + `aw37503` + PWM 背光）

### 1.1 面板驱动与电源架构
- 新增 `drivers/gpu/drm/panel/panel-himax-jt120wul005-vdo.c`（1200x2000 DSI Video 面板、`compatible = "himax,jt120wul005-vdo"`），接入 `Kconfig`（`CONFIG_DRM_PANEL_HIMAX_JT120WUL005_VDO=y`）与 `Makefile`。
- 上电与 GPIO 时序严格对齐原厂 DT：`vdd18-gpios` (GPIO 165)、`bias-pos-gpios` (GPIO 153)、`bias-neg-gpios` (GPIO 70)、`reset-gpios` (GPIO 45)，由 `vpos-supply` / `vneg-supply` 引用 I2C7 `aw37503@3e` 双路偏置稳压器。
- `kernel-6.6/drivers/regulator/aw37503-regulator.c` `aw37503_of_match[]` 新增 `{ .compatible = "aw,aw37503" }`，且 `aw37503@3e` DT 子节点不配置 `enable-gpios`，避免与面板驱动争抢 GPIO 153/70 引发 `-EBUSY`。
- 支持 LK Pre-initialized 交接（`mediatek,lk-handover` / `drm_panel_get_modes` 解析 1200x2000@60Hz `vrefresh=60` 时序）以及 72 条 DCS 初始化命令序列。

### 1.2 `mediatek_v2` DRM 与 MML / MMQoS / Thermal Built-in 适配
- 将 `mtk_drm_fbdev.c/.h` 迁移至 Linux 6.6 API（4 参数 `drm_fb_helper_prepare`、`drm_fb_helper_alloc_info`、`drm_fb_helper_unregister_info`、`drm_fb_helper_cfb_*` / `sys_*` 迁移、`drm_fb_helper_initial_config` 单参调用），清理与 `mtk_drm_drv.c` 重复定义的 `_parse_tag_videolfb` / `mtk_drm_lcm_is_connect` / `free_fb_buf`，并在 `struct mtk_drm_private` 补齐 `fb_helper` 与 `fbdev_bo`。
- 在 `drivers/gpu/drm/mediatek/mediatek_v2/Makefile` 中将 `mtk_aod_scp.o` 门控在 `CONFIG_MTK_TINYSYS_SCP_SUPPORT` 下。
- 修复 `drivers/gpu/drm/mediatek/mml/{mtk-mml-core.h,mtk-mml-pq-core.h}` clang-21 宏参数与非 AEE 桩；在 `mml/Makefile` 将仅面向新款 SoC（MT6886/MT6897/MT6899/MT6983/MT6985/MT6989/MT6991/MT6878）且内部互有重名全局符号的 `mtk-mml-tp-mt*.o` 限定为 `ifeq ($(CONFIG_MTK_MML),m)`，从而允许 `CONFIG_MTK_MML=y` 内置无链接符号冲突。
- 背光启用 `CONFIG_DEVICE_MODULES_PWM_MTK_DISP=y` + `CONFIG_LEDS_MTK=y` + `CONFIG_LEDS_MTK_PWM=y`（`mtk_leds` -> `/sys/class/leds/lcd-backlight`）。
- Built-in 启动链补齐：`CONFIG_MTK_MMPROFILE` -> `CONFIG_MMPROFILE=y`、`CONFIG_MMEVENT=y`、`CONFIG_MTK_IOMMU_MISC=y`、`CONFIG_MTK_PBM=y`、`CONFIG_MTK_PEAK_POWER_BUDGET=y`、`CONFIG_MTK_POWER_THROTTLING_COMMON=y`、`CONFIG_MTK_THERMAL_INTERFACE=y`、`CONFIG_INTERCONNECT_MTK_EXTENSION=y`、`CONFIG_INTERCONNECT_MTK_MMQOS_COMMON=y`、`CONFIG_INTERCONNECT_MTK_MMQOS_MT6768=y`。
- 修复 `drivers/dma-buf/heaps/mtk_dmabuf_events.h` 与 `mtk_dmabuf_monitor.c` 中 `tracing_mark_write` 同名 tracepoint 冲突（重命名为 `mtk_dmabuf_tracing_mark_write`），以及 40+ 个 `device_modules` 头文件中的 clang-21 `MIN`/`MAX` 重定义、未使用变量、`__maybe_unused` 与 `CREATE_TRACE_POINTS` 重复定义问题。

---

## 2. Himax HX83102-E/J SPI4 触摸屏（`hxchipset`）

- 将 5.10 已实机验证的 `drivers/input/touchscreen/hxchipset/` 前向移植至 Linux 6.6 API（`himax_mmi.o` 内置）：
  - 新增 `config TOUCHSCREEN_HIMAX_CHIPSET`（`HX83102` + `INCELL` + `DEBUG` + `INSPECT`）。
  - `strlcpy` -> `strscpy`；`spi_driver.remove` 迁移为 `void`；清理废弃 `mm_segment_t` / `get_fs()` / `set_fs()`；补充 `fallthrough;`。
  - 将 `HX_CONFIG_FB` 与 `CONFIG_DRM_MEDIATEK_V2` 的 `mtk_disp_notifier` 做互斥保护，避免休眠/唤醒通知重复注册。
  - DTS `spi4@11014000/zlt_ts@0` 覆盖原厂 DTBO 中的 `focaltech,fts`：优先 `"himax,hxcommon"`、启用 `himax,zpd1203-touch`、`himax,irq-gpio` = GPIO 6、`SPI_MODE_3`、`9.6 MHz`（继续跳过与屏幕共用的 GPIO 158 硬件复位防黑屏）。
  - 内建两份原厂固件：`Himax_firmware.bin` 与 `Himax_firmware_e.bin`（`CONFIG_EXTRA_FIRMWARE_DIR="/home/asus/zpd1203-6.6/extracted_stock/firmware"`）。

---

## 3. Mali-G52 MC2 GPU（DDK `r32p1-01eac0`）与 Platform DVFS

- 内核内置 MTK GPU 平台支持链：`ged`、`mtk_gpu_hal`、`gpufreq/v2_legacy`（`mtk_gpufreq_wrapper_legacy` + `mtk_gpufreq_mt6768`）、`gpu_bm/mtk_gpu_qos`、`mtk_gpu_power_throttling`。
- Out-of-Tree GPU 模块（`modules/gpu/gpu_mali/mali_valhall/mali-r32p1`）：
  - 在 `drivers/gpu/arm/midgard/mali_malisw.h` 的 `#ifndef MIN/MAX` 前引入 `#ifdef __KERNEL__ <linux/minmax.h>`，解决 clang-21 `-Wmacro-redefined`；
  - 修正 `platform/mt6768/Kbuild` 以适配 `OOT` 规则下 `$(M)/Kbuild-mtk-custom-env` 相对包含；
  - 编译出两个必须按依赖加载的 `.ko` 模块：
    1. `mali_mgm_mt6768.ko`（`drivers/base/arm/memory_group_manager`，`alias: of:N*T*Carm,physical-memory-group-manager`，若缺此模块 `mali_kbase_mem.c` 会一直 `-EPROBE_DEFER`）
    2. `mali_kbase_mt6768.ko`（`version: r32p1-01eac0 (UK version 11.31)`，`softdep: pre: memory_group_manager`，精确匹配原厂 `/vendor/lib64/egl/libGLES_mali.so` DDK 版本）。

---

## 4. 本阶段编译与静态校验实测结果

| 检查项 | 命令 / 工具 | 实测结果 |
|---|---|---|
| Step 5A 内核与内置模块编译 | `/tmp/build_5a.sh` (`Image.gz`, `modules`, `mt6768-zpd1203-display.dtb`) | **通过 (`exit 0`)**：`Image.gz` (`15M`)、`Module.symvers` (`1.1M`)、`mt6768-zpd1203-display.dtb` (`167K`) |
| Step 5A 关键配置项内置核验 | `grep -E "^CONFIG_...=y" .config` | **10/10 全部为 `=y`**（DRM v2、MMSYS、CMDQ、Panel、AW37503、PWM/LEDs、Himax Touch、MT6768 GPU） |
| 原厂 DTBO 叠加静态校验 | `fdtoverlay` (`mt6768-zpd1203-display.dtb` + `dtbo_a_0.dtb` -> `/tmp/test-5a-merged.dtb`) | **通过 (`exit 0`, `198K`)**；`dtc` 反编译确认 `aw37503@3e`、`panel@0`、`zlt_ts@0`、`dispsys_config@14000000`、`mtk_leds`、`mali@13040000`、`sysirq` 均存在且 `status = "okay"` |
| `mali_mgm_mt6768.ko` OOT 编译与校验 | `make M=.../memory_group_manager modules` + `modinfo` | **通过 (`207K`)**，0 未定义符号 |
| `mali_kbase_mt6768.ko` OOT 编译与校验 | `make M=.../midgard ... modules` + `modinfo` | **通过 (`15M` 未 strip)**，`version: r32p1-01eac0 (UK version 11.31)`，0 未定义符号，`vermagic` 与 `kernel.release` 完全一致 |
| 导出补丁集 | `d:\P3066\patches\phase5_display_gpu_touch\` | 共 4 份 `format-patch` 文件（`kernel-6.6` 1 份、`kernel_device_modules-6.6` 2 份、`modules-gpu` 1 份），各源码仓库均无未提交改动 |

> **诚实标注**：以上成果当前全部处于 **`已编译通过`** / **`已静态验证`** 状态；DSI 显示输出、背光亮度调节、Himax 触屏中断与横屏坐标、Mali GPU 硬件渲染与 `libGLES_mali.so` 运行时握手均 **尚未在 ZPD1203 实机上运行验证（`尚未验证`）**。
