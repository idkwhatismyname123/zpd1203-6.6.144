# ZPD1203 硬件驱动适配与验证状态 (HARDWARE_STATUS.md)

> **状态分类严格定义**：
> - **已编译通过**：已在目标 6.6 内核树成功编译为内置或 `.ko` 模块，无错误。
> - **已静态验证**：已核对 DTB 节点/phandle、模块 `vermagic`、导出符号、节点/ioctl ABI 或原厂 HAL 绑定关系。
> - **已实机验证**：**仅在收到用户真实 ZPD1203 实机运行日志并确认功能正常后使用**。
> - **尚未验证**：尚未移植、尚未编译或尚未实机确认。
> - **已知故障**：在调查、编译或测试中明确发现存在缺陷或阻塞项。

| 子系统 | 具体硬件 / 驱动 | 5.10 参考状态 | 6.6 目标方案 | 当前状态 | 备注 / 已知问题 |
|---|---|---|---|---|---|
| 启动与核心架构 | MT6769V/CB (MT6768), GICv3, PSCI, `sysirq @ 0x0c53a650` | 已静态验证 | `aosp-6.6` (`6.6.144`) + ZPD1203 DTS + `sysirq` 97 INTPOL + `force_slot_a=1` | **已静态验证** | `mtk_sysirq_of_init` / `init/main.c` `force_slot_a` 内置；`full` 与 `minimal` DTB 均通过 `fdtoverlay` `dtbo_a_0.dtb` 校验 |
| 时钟与电源域 | MT6768 CCF, SSPM, MT6358 PMIC (`0x5820`) | 已静态验证 | `addster-bsp-6.6` `clk-mt6768*` + `mt6358` + `mtk-scpsys` + `clkbuf-pmif` | **已编译通过** | 内置 `=y`；修复 `clkbuf-pmif.c` SPMI 弱符号 PLT 与 clang-21 宏 |
| 引脚控制与 GPIO | `pinctrl-mt6768` | 已静态验证 | `addster-bsp-6.6` `pinctrl-mt6768` (`=y`) | **已编译通过** | 含显示/触控/SPI4/I2C3/5/6/7/充电/Type-C/Wi-Fi 天线完整引脚定义 |
| 内部存储与加密 | MSDC0 eMMC (`11230000`) + CQHCI + `inlinecrypt` + RPMB | eMMC 已静态验证；RPMB 未打包 | `mtk-mmc.c` (`DEVICE_MODULES_MMC_MTK_PRO=y`) + `cqhci` + `inlinecrypt` + `rpmb-mtk` (`=y`) | **已静态验证** | 修复非 UFS 下 `rpmb-mtk.c` 编译并将 `rpmb-mtk` 内置 |
| USB 与 ADB | `usb0@11200000` (**`musb-hdrc`**) + `extcon_usb` (GPIO 41) + TPHY + ConfigFS | 已静态验证（强制 `peripheral`） | `usb/usb20` (`musb-hdrc`) + `phy-mtk-tphy` + `extcon-mtk-usb` + `dr_mode="otg"` (`full`) / `peripheral` (`minimal`) | **已静态验证** | 修复 `tcpc_aw` 头文件路径选择与 `bq2589x` OTG 互斥死锁，支持 `ffs.adb+acm.gs1` |
| 显示系统 / 背光 | **`jt120wul005_a01_dsi_vdo`** (`HX83102-E/J` `1200x2000`) + **I2C7 `aw37503@3e`** + `disp_pwm` | 已静态验证（`simplefb` + NEON 桥接） | `full`: `mediatek_v2` DRM + `panel-himax-jt120wul005-vdo` + `aw37503` + `mtk_leds`; `minimal`/降级: `simplefb` + `gralloc.fb0_bridge.so` | **已静态验证** | `a12_init_wrapper` 根据 `/dev/dri/card0` 存在性动态分流原生 DRM 与 `simplefb` 桥接 |
| 触摸屏 | **SPI4 (`11014000`)** `zlt_ts@0` (`himax,hxcommon`), INT GPIO 6, RST GPIO 158 | 已静态验证（跳过共享 GPIO 158） | 前向移植 5.10 `hxchipset` (`HX83102-E/J`) 至 6.6 SPI API + 内建 `Himax_firmware*.bin` | **已编译通过** | 保留 active pinctrl、`SPI_MODE_3` 与跳过 `GPIO 158` 复位逻辑防黑屏 |
| GPU 硬件加速 | **Mali-G52 MC2 (`13040000`)** | 尚未验证（5.10 缺 IOMMU/SMI） | Moto `mali-r32p1` (`mali_mgm_mt6768.ko` + `mali_kbase_mt6768.ko` **`r32p1-01eac0`**) + `ged` + `gpufreq` + IOMMU/SMI | **已静态验证** | 真实硬件 DDK `r32p1-01eac0` (`UK 11.31`) 匹配原厂 `libGLES_mali.so`；`vermagic`/CRC/0 undef 通过 |
| Wi-Fi | `consys@18002000` (`wlan_drv_gen4m` CONNAC 1.0) + `wifi_ant_swap` GPIO 108 | 已静态验证（5.10 `.ko`） | 重编 6.6 `rfkill.ko` + `cfg80211.ko` + `connfem.ko` + `wmt_drv.ko` + `wmt_chrdev_wifi.ko` + `wlan_drv_gen4m.ko` | **已静态验证** | 全部 `.ko` 针对 `6.6.144-zpd1203-g91af1aa18e1a` 编出，CRC 与符号闭环 0 错误，`a12_init_wrapper` 自动替换 `/vendor/lib/modules` |
| 蓝牙 | `bt_drv_connac1x.ko` + `btif@1100c000` | 已静态验证 | `btif_drv.ko` + `conn_md_drv.ko` + `wmt_drv.ko` + Moto 6.6 `bt_drv_connac1x.ko` | **已静态验证** | 同上，严格拓扑加载与 `MS_BIND` 替换 |
| 电池、电量计与 USB 充电上报 | **I2C5 `sgm41510@6b`** + **I2C6 `aw35615@22`** + `mt6358_gauge` | **已知故障（5.10 缺失充电状态上报）** | `bq2589x_charger.c` 扩展 `sgm41510` + `tcpc_aw/aw35615` + `mt6358-gauge` + `mtk-master-charger` | **已静态验证** | 修复 `sgm,*` 解析、`/vendor/lib` 电源属性需求（注册 `usb`/`ac`/`primary_chg` PSY）、`fdtoverlay` 确认 `charger = <&sgm41510>` |
| Type-C 二供 `wusb3801` | I2C6 `wusb3801@60`（与 `aw35615@22` 共用 GPIO 8） | 已知故障 | 禁用冲突 `CONFIG_TYPEC_WUSB3801`；优先主器件 `AW35615` | **尚未验证（二供硬件若存在共享中断待测）** | AOSP `wusb3801.c` 独占 IRQ 会与 `aw35615` 冲突 |
| 音频 | `afe@11220000` + `mt6358` + **I2C3 SmartPA (`aw87xxx_pa@59/5A`)** + `accdet` | 尚未验证（5.10 禁用） | `addster-bsp-6.6` `mt6768-mt6358` ASoC + `mt6358-accdet` + `aw87xxx` | **已编译通过** | 若出货批次焊装 `foursemi,fs15xx` 二供功放，6.6 树内 `fs18xx` 仅认 FS16xx/FS18xx（`fs15xx` 标为 `尚未验证`） |
| 温控、WDT 与调频 | `mtk_wdt`, `devapc-mt6768`, Thermal, CPUFreq, `ppm_v3`, `ptpod`, `spm`, `mcdi`, `cpuidle` | 尚未验证（5.10 关 cpuidle） | `mtk_wdt` + `devapc` + MT6768 Legacy Thermal + CPU DVFS/PPM/EEM + SPM + MCDI | **已编译通过** | 全部已在 `full` 配置内置（`=y`），`full` cmdline 不加 `cpuidle.off=1` |
| 传感器 / 霍尔 | I2C1 `sc7a20`/`mc3416`/`ucs14266`/`ls9801i`; `hall` EINT 9/32 | 尚未验证 | 无内置/开源 6.6 对应传感器驱动 | **尚未验证** | 缺失开源驱动源码，未生成虚假节点 |
| 摄像头 | 主/副 `sc800cs`/`hi849`, 前 `sc800cssub`/`s5k4h7`, `aw36515@63` | **已知故障（5.10 全禁用）** | `addster` `isp4_t` 缺 `hi849` / `aw36515`，且 HAL 强依赖 `/dev/gz_kree` EL2 | **已知故障** | 受限于 GenieZone EL2 `[ISP_HA]`/`[MTEE_SENINF]` 闭源依赖与缺参传感器驱动 |
| Android ABI & SELinux | BinderFS, `/dev/dma_heap/mtk_mm*`, `/dev/ion` (`BIT(10)`), SELinux | 已静态验证 | BinderFS + `mtk_system_heap` + `mtk_ion_compat.c` (`/dev/ion` -> `dma_heap`) + SELinux | **已静态验证** | `# CONFIG_DMABUF_HEAPS_SYSTEM is not set` 规避重名冲突；`/dev/ion` 真实转发分配，未知 ioctl 返回 `-ENOTTY` |
| 无 UART 调试体系 | `pstore/ramoops @ 0x4d010000`, `a12_init_wrapper` STAGE 1..7, `ttyGS*` ACM | 已静态验证 | 内置 `pstore_ram` + 静态 `a12_init_wrapper`（含 `.ko` 挂载、DRM/FB 门控与 ACM+ADB） | **已静态验证** | `ramoops_probe` 内置；静态交叉编译 `a12_init_wrapper`（0 动态段）已打包校验 |
| Root 支持 | KernelSU | 已静态验证 (v3.3.1) | KernelSU v3.3.1 (`0c0fdb96`, `KSU=y`, `KPROBES=y`) | **已编译通过** | `kernelsu_init` / `ksu_*` 全部符号已编译入 `vmlinux` |
