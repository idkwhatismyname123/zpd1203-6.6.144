# ZPD1203 硬件驱动适配与验证状态 (HARDWARE_STATUS.md)

> **状态分类严格定义**：
> - **已编译通过**：已在目标 6.6 内核树成功编译为内置或 `.ko` 模块，无错误。
> - **已静态验证**：已核对 DTB 节点/phandle、模块 `vermagic`、导出符号、节点/ioctl ABI 或原厂 HAL 绑定关系。
> - **已实机验证**：**仅在收到用户真实 ZPD1203 实机运行日志并确认功能正常后使用**。
> - **尚未验证**：尚未移植、尚未编译或尚未实机确认。
> - **已知故障**：在调查、编译或测试中明确发现存在缺陷或阻塞项。

| 子系统 | 具体硬件 / 驱动 | 5.10 参考状态 | 6.6 目标方案 | 当前状态 | 备注 / 已知问题 |
|---|---|---|---|---|---|
| 启动与核心架构 | MT6769V/CB (MT6768), GICv3, PSCI, `sysirq @ 0x0c53a650` | 已静态验证（5.10 声明可进桌面） | `aosp-6.6` (`6.6.144`) + ZPD1203 DTS + `sysirq` 97 INTPOL + `force_slot_a` | **已静态验证** | `mtk_sysirq_of_init` / `init/main.c` `mt6768.force_slot_a=1` 已编译入 `vmlinux`；DTB 通过 `dtc` 与 `fdtoverlay` `dtbo_a_0.dtb` 校验；待实机验证 |
| 时钟与电源域 | MT6768 CCF, SSPM, MT6358 PMIC (`0x5820`) | 已静态验证 | `addster-bsp-6.6` `clk-mt6768*` + `mt6358` + `mtk-scpsys` + `clkbuf-pmif` | **已编译通过** | `clk_mt6768_scpsys_probe` / `mt6358_regulator_probe` / `pwrap_probe` / `mt6397_probe` 已内置 (`=y`)；修 `clkbuf-pmif.c` SPMI 弱符号 PLT 问题 |
| 引脚控制与 GPIO | `pinctrl-mt6768` | 已静态验证 | `addster-bsp-6.6` `pinctrl-mt6768` (`=y`) | **已编译通过** | `mt6768_pinctrl_init` / `mt6768_pinctrl_of_match` 已内置；SPI4/I2C/触控/显示/充电 GPIO 待 Phase 5 扩展 |
| 内部存储与加密 | MSDC0 eMMC (`11230000`) + CQHCI + `inlinecrypt` + RPMB | eMMC 已静态验证；RPMB 未打包 | `mtk-mmc.c` (`DEVICE_MODULES_MMC_MTK_PRO=y`) + `cqhci` + `inlinecrypt` + `rpmb-mtk` (`=y`) | **已静态验证** | 核实 6.6 `mtk-sd.c` 无 `"mediatek,mt6768-mmc"`，必须用 `mtk-mmc.c`；已修复非 UFS 下 `rpmb-mtk.c` 编译；`msdc_drv_probe` / `cqhci_init` / `rpmb_init` 已内置 |
| USB 与 ADB | `usb0@11200000` (**`musb-hdrc`**) + TPHY + ConfigFS | 已静态验证（强设 `peripheral`） | `usb/usb20` (`musb-hdrc`) + `phy-mtk-tphy` + `NOP_USB_XCEIV=y` + FFS/ACM | **已静态验证** | 最小 DTS 设 `dr_mode="peripheral"` 删 `usb-role-switch`（已核实匹配 `musb_dr.c`）；`musb_probe`/`mtk_tphy_probe` 已内置；角色切换留 Phase 5/6 |
| 显示系统 / 背光 | **`jt120wul005_a01_dsi_vdo`** (`HX83102-E/J` `1200x2000`) + **I2C7 `aw37503@3e`** + PWM | 已静态验证（`simplefb` + NEON 桥接） | Phase 4: `simplefb` (OVL0 L3 clear + `zpd_disp_regs`) + `gralloc.fb0_bridge.so`; Phase 5: MTK DRM v2 | **已静态验证（Phase 4 最小显示路径）** | `simplefb_probe` / `zpd_capture_regs` 已内置，ramdisk 含零依赖 `gralloc.fb0_bridge.so` (`HMI`)；Phase 5 DRM/DSI/背光尚未移植 |
| 触摸屏 | **SPI4 (`11014000`)** `zlt_ts@0` (`himax,hxcommon`), INT GPIO 6, RST GPIO 158 | 已静态验证（跳过共享 GPIO 158） | 前向移植 5.10 `hxchipset` (`HX83102-E/J`) 至 6.6 SPI API + 6 份固件 | 尚未验证 | 最小 DTS 仅留 `status="disabled"` 占位节点；待 Agent 5 移植 |
| GPU 硬件加速 | **Mali-G52 MC2 (`13040000`)** | 尚未验证（5.10 缺 IOMMU/SMI） | Moto 6.6 GPU **`mali-r32p1` (`r32p1-01eac0`)** + `ged` + `gpufreq` + IOMMU/SMI | **已编译通过（仅 IOMMU/SMI 底座）** | `mtk_iommu_probe` / `mtk_smi_common_probe` / `mtk_smi_larb_probe` 已内置；Mali 模块留待 Agent 5 |
| Wi-Fi | `consys@18002000` (`wlan_drv_gen4m` CONNAC 1.0) | 已静态验证（5.10 重编 `.ko`） | Moto `vvta35` (`common/connfem/adaptor`) + `v1tl35` (`gen4m` `Kbuild.6768`) | 尚未验证 | Phase 2 已单编验证；待 Agent 6 集成至全树与打包模块 |
| 蓝牙 | `bt_drv_connac1x` + `btif@1100c000` | 已静态验证 | Moto `vvta35` `bt-mt66xx/wmt` + 树内 `btif` | 尚未验证 | 待 Agent 6 集成 |
| 电池与电量计 | `mt6358_gauge` (`bat_gm30`) + 原厂电池曲线 | 已静态验证（仅读百分比） | `addster-bsp-6.6` `mt6358-gauge` + 洁净 `mtk_battery.c` + 电池曲线 DTSI | 尚未验证 | `zpd1203-stock-battery-profile.dtsi` 已迁入 DTS 目录；待 Agent 6 启用驱动 |
| USB 充电状态上报 | **I2C5 `sgm41510@6b`** + **I2C6 `aw35615@22` / `wusb3801@60` / `z350@35`** + I2C7 `slave@4b` | **已知故障（5.10 缺失 DT 与驱动）** | `addster` `sgm415xx.c` + `tcpc_aw/aw35615` + `aosp-6.6` `wusb3801.c` + `extcon_usb` | 已知故障 | Phase 4 故意禁用，留待 Agent 6 在 Phase 5 重点修复打通完整 `power_supply` 上报 |
| 音频 | `afe@11220000` + `mt6358` + **I2C3 SmartPA (`fs15xx@35/36`, `aw87xxx@59/5a`)** | 尚未验证（5.10 禁用） | `addster-bsp-6.6` `mt6768-mt6358` ASoC + ACCDET + SmartPA | 尚未验证 | 待 Agent 6 适配 |
| 温控、WDT 与调频 | `mtk_wdt`, `devapc-mt6768`, Thermal, CPUFreq, `cpuidle`, `dvfsrc` | 尚未验证（5.10 关 cpuidle） | `mtk_wdt` + `devapc` + Thermal + Phase 5 CPUFreq/DVFSRC | **已编译通过（WDT/DevAPC/Thermal）** | `mtk_wdt_probe` / `mt6768_devapc_probe` / `DEVICE_MODULES_MTK_THERMAL` 已内置；`cpufreq_v2`/`ppm_v3`/`eem_v2` 因依赖 `mtk_disp_notify`/`pbm`/`mcdi` 暂不在最小镜像启用，留 Phase 5 |
| 传感器 / 霍尔 | I2C1 `sc7a20`/`mc3416`/`ucs14266`/`ls9801i`; `hall` EINT 9/32 | 尚未验证 | 评估 SCP/IIO/Misc 传感器与霍尔接口 | 尚未验证 | — |
| 摄像头 | 主/副 `sc800cs`/`hi849`, 前 `sc800cssub`/`s5k4h7`, `aw36515@63` | **已知故障（5.10 全禁用）** | 评估 `addster` `isp4_t` (`sc800cs`/`s5k4h7`) + `/dev/gz_kree` EL2 接口 | 已知故障 | 缺 `hi849` 驱动且原厂 HAL 依赖 GenieZone EL2 `[ISP_HA]`/`[MTEE_SENINF]` |
| Android ABI & SELinux | BinderFS, `/dev/dma_heap/mtk_mm*`, `/dev/ion` (`BIT(10)`), SELinux | 已静态验证（5.10 ION 补丁） | `aosp-6.6` BinderFS + DMA-BUF Heaps + `/dev/ion` `BIT(10)` 兼容层 | **已编译通过（BinderFS/SELinux/DMA-Heap）** | `init_binderfs` / `mtk_system_heap_create` / SELinux / `ext4`/`f2fs`/`erofs`/`dm-verity` 已内置；`/dev/ion` `BIT(10)` 兼容层留 Agent 7 Phase 6 |
| 无 UART 调试体系 | `pstore/ramoops @ 0x4d010000`, `a12_init_wrapper` STAGE 1..7, `ttyGS*` ACM | 已静态验证 | 内置 `pstore_ram` + 静态 `a12_init_wrapper`（含早期 pstore 转储与 ACM+ADB） | **已静态验证** | `ramoops_probe` 已内置，ramdisk 与 `boot-minimal-6.6.img` 全部通过静态校验 |
| Root 支持 | KernelSU | 已静态验证 (v3.3.1) | KernelSU v3.3.1 (`0c0fdb96`, `KSU=y`, `KPROBES=y`) | **已编译通过** | `kernelsu_init` / `ksu_*` 全部符号已编译入 `vmlinux` |
