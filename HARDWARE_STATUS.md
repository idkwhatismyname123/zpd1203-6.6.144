# ZPD1203 硬件驱动适配与验证状态 (HARDWARE_STATUS.md)

> **状态分类严格定义**：
> - **已编译通过**：已在目标 6.6 内核树成功编译为内置或 `.ko` 模块，无错误。
> - **已静态验证**：已核对 DTB 节点/phandle、模块 `vermagic`、导出符号、节点/ioctl ABI 或原厂 HAL 绑定关系。
> - **已实机验证**：**仅在收到用户真实 ZPD1203 实机运行日志并确认功能正常后使用**。
> - **尚未验证**：尚未移植、尚未编译或尚未实机确认。
> - **已知故障**：在调查、编译或测试中明确发现存在缺陷或阻塞项。

| 子系统 | 具体硬件 / 驱动 | 5.10 参考状态 | 6.6 目标方案 | 当前状态 | 备注 / 已知问题 |
|---|---|---|---|---|---|
| 启动与核心架构 | MT6769V/CB (MT6768), GICv3, PSCI, `sysirq @ 0x0c53a650` | 已静态验证（5.10 声明可进桌面） | `aosp-6.6` (`6.6.144`) + ZPD1203 DTS + `sysirq` 97 INTPOL + `force_slot_a` | 尚未验证 | 内存双 Rank 6 GiB；`ramoops @ 0x4d010000 (0xe0000)`；需保护 BL FB `0x7d350000` |
| 时钟与电源域 | MT6768 CCF, SCP/SSPM/SPM, MT6358 PMIC (`0x5820`) | 已静态验证 | `addster-bsp-6.6` `clk-mt6768*` + `mt6358` + `mtk-scpsys` | 尚未验证 | 阶段一 `clk/pinctrl/mt6358` 已单编通过校验 |
| 引脚控制与 GPIO | `pinctrl-mt6768` | 已静态验证 | `addster-bsp-6.6` `pinctrl-mt6768` | 尚未验证 | 需迁移 SPI4/I2C1-7/触摸/显示/充电 GPIO |
| 内部存储与加密 | MSDC0 eMMC (`11230000`) + CQHCI + `inlinecrypt` + RPMB | eMMC 已静态验证；RPMB 未打包 | `mtk-sd` + `cqhci` + `inlinecrypt` + `rpmb-mtk` (`=y`) | 尚未验证 | `/data` 使用 `aes-256-xts:v2` + `inlinecrypt` |
| USB 与 ADB | `usb0@11200000` (**`musb-hdrc`**) + ID GPIO 41 + TPHY | 已静态验证（强设 `peripheral`） | `usb/usb20` (`musb-hdrc`) + `phy-mtk-tphy` + ConfigFS/FFS | 尚未验证 | 原厂 `usb@1.2` HAL 硬编码 `"musb-hdrc"` |
| 显示系统 / 背光 | **`jt120wul005_a01_dsi_vdo`** (`HX83102-E/J` `1200x2000`) + **I2C7 `aw37503@3e`** + PWM | 已静态验证（`simplefb` + NEON 桥接） | Phase 4: `simplefb` + NEON 桥接；Phase 5: MTK DRM v2 + `jt120wul005` + `aw37503` + HWC 适配 | 尚未验证 | 原厂 `hwcomposer` 用 `/dev/mtk_disp_mgr` + `fb0`，而 6.6 无 `MTK_FB` |
| 触摸屏 | **SPI4 (`11014000`)** `zlt_ts@0` (`himax,hxcommon`), INT GPIO 6, RST GPIO 158 | 已静态验证（跳过共享 GPIO 158） | 前向移植 5.10 `hxchipset` (`HX83102-E/J`) 至 6.6 SPI API + 6 份固件 | 尚未验证 | 绝不能拉动共享复位 `GPIO158` |
| GPU 硬件加速 | **Mali-G52 MC2 (`13040000`)** | 尚未验证（5.10 缺 IOMMU/SMI） | Moto 6.6 GPU **`mali-r32p1` (`r32p1-01eac0`)** + `ged` + `gpufreq` + IOMMU/SMI | 尚未验证 | 严格匹配原厂 `libGLES_mali.so` (`1.4 Bifrost-r32p1-01eac0`)，需修 `MIN/MAX` 宏冲突 |
| Wi-Fi | `consys@18002000` (`wlan_drv_gen4m` CONNAC 1.0) | 已静态验证（5.10 重编 `.ko`） | Moto `vvta35` (`common/connfem/adaptor`) + `v1tl35` (`gen4m` `Kbuild.6768`) | 尚未验证 | 已于 `6.6.144` 初步编译通过，待集成全树校验 `vermagic` |
| 蓝牙 | `bt_drv_connac1x` + `btif@1100c000` | 已静态验证 | Moto `vvta35` `bt-mt66xx/wmt` + 树内 `btif` | 尚未验证 | 依赖 `wmt_drv.ko` 与 `/vendor/firmware/soc1_0_*` |
| 电池与电量计 | `mt6358_gauge` (`bat_gm30`) + 原厂电池曲线 | 已静态验证（仅读百分比） | `addster-bsp-6.6` `mt6358-gauge` + 洁净 `mtk_battery.c` + 电池曲线 DTSI | 尚未验证 | `addster` 去除了 Moto `mmi,battid` 耦合 |
| USB 充电状态上报 | **I2C5 `sgm41510@6b`** + **I2C6 `aw35615@22` / `wusb3801@60` / `z350@35`** + I2C7 `slave@4b` | **已知故障（5.10 缺失 DT 与驱动）** | `addster` `sgm415xx.c` + `tcpc_aw/aw35615` + `aosp-6.6` `wusb3801.c` + `extcon_usb` | 已知故障 | Phase 5 重点打通完整 `power_supply` (`online`/`status`/`type`) 上报 |
| 音频 | `afe@11220000` + `mt6358` + **I2C3 SmartPA (`fs15xx@35/36`, `aw87xxx@59/5a`)** | 尚未验证（5.10 禁用） | `addster-bsp-6.6` `mt6768-mt6358` ASoC + ACCDET + SmartPA | 尚未验证 | 原厂卡名 `mt6768mt6358` |
| 温控与调频 | Thermal, CPUFreq, `cpuidle`, `dvfsrc` | 尚未验证（5.10 关 cpuidle） | `addster-bsp-6.6` Thermal + CPUFreq + DVFSRC（安全验证 cpuidle） | 尚未验证 | 待检查原厂 ATF PSCI idle state 稳定性 |
| 传感器 / 霍尔 | I2C1 `sc7a20`/`mc3416`/`ucs14266`/`ls9801i`; `hall` EINT 9/32 | 尚未验证 | 评估 SCP/IIO/Misc 传感器与霍尔接口 | 尚未验证 | — |
| 摄像头 | 主/副 `sc800cs`/`hi849`, 前 `sc800cssub`/`s5k4h7`, `aw36515@63` | **已知故障（5.10 全禁用）** | 评估 `addster` `isp4_t` (`sc800cs`/`s5k4h7`) + `/dev/gz_kree` EL2 接口 | 已知故障 | 缺 `hi849` 驱动且原厂 HAL 依赖 GenieZone EL2 `[ISP_HA]`/`[MTEE_SENINF]` |
| Android ABI & SELinux | BinderFS, `/dev/dma_heap/mtk_mm*`, `/dev/ion` (`BIT(10)`), SELinux | 已静态验证（5.10 ION 补丁） | `aosp-6.6` BinderFS + DMA-BUF Heaps + `/dev/ion` `BIT(10)` 兼容层 | 尚未验证 | 6.6 已移去 ION，但原厂 `libion_mtk`/`Codec2`/`libGLES_mali` 仍引用 `/dev/ion` |
| Root 支持 | KernelSU | 已静态验证 (v3.3.1) | KernelSU v3.3.1+ (`KPROBES=y`) | 尚未验证 | `aosp-6.6` 原生已启用 `CONFIG_KPROBES=y` |
