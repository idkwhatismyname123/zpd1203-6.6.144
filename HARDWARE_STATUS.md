# ZPD1203 硬件驱动适配与验证状态 (HARDWARE_STATUS.md)

> **状态分类严格定义**：
> - **已编译通过**：已在目标 6.6 内核树成功编译为内置或 `.ko` 模块，无错误。
> - **已静态验证**：已核对 DTB 节点/phandle、模块 `vermagic`、导出符号、节点/ioctl ABI 或原厂 HAL 绑定关系。
> - **已实机验证**：**仅在收到用户真实 ZPD1203 实机运行日志并确认功能正常后使用**。
> - **尚未验证**：尚未移植、尚未编译或尚未实机确认。
> - **已知故障**：在调查、编译或测试中明确发现存在缺陷或阻塞项。

| 子系统 | 具体硬件 / 驱动 | 5.10 参考状态 | 6.6 目标方案 | 当前状态 | 备注 / 已知问题 |
|---|---|---|---|---|---|
| 启动与核心架构 | MT6768 ARM64, GICv3, PSCI, SMP | 已实机运行 | 6.6 原生 + ZPD1203 DTS | 尚未验证 | 待 Phase 1 提取原厂内存图与保留区 |
| 时钟与电源域 | MT6768 CCF, SCP/SSPM/SPM, Regulator | 已实机运行 | 6.6 MT6768 clk + MT6358 | 尚未验证 | 待核对 6.6 clk/power-domain 绑定 |
| 引脚控制与 GPIO | pinctrl-mt6768 | 已实机运行 | 6.6 `pinctrl-mt6768` | 尚未验证 | 待迁移 DTS pinmux |
| 内部存储与加密 | MSDC0 eMMC, RPMB, dm-verity/linear | 已实机运行 | 6.6 `mtk-sd` + RPMB | 尚未验证 | 待核对 `super` 动态分区挂载 |
| USB 与 ADB | MTU3/MUSB, PHY, ConfigFS, FunctionFS | 已实机运行 | 6.6 `mtu3` + Gadget ADB | 尚未验证 | 待确认 5.10 USB 角色切换与充电状态关联 |
| 显示系统 | LCD Panel + DSI + DRM + 背光 | 已实机运行（横屏 NEON 桥接） | 6.6 MTK DRM/DSI + 桥接评估 | 尚未验证 | 待 Phase 1 确认 Panel IC 与 HWC ABI |
| 触摸屏 | Himax (`Himax_firmware*.bin`) | 已实机运行 | 6.6 API 适配 Himax 驱动 | 尚未验证 | 需适配 6.6 I2C/DRM notifier/proc_ops |
| GPU 硬件加速 | Mali-G52（DDK 版本待确认） | 待核实 5.10 实现 | 匹配 DDK 的 6.6 `mali_kbase` + `ged` | 尚未验证 | **严禁软件渲染伪装** |
| Wi-Fi | Connsys `wlan_drv_gen4m` + WMT | 已实机运行（9 `.ko`） | 6.6 Connsys 重编译适配 | 尚未验证 | 禁止复用 5.10 二进制 `.ko` |
| 蓝牙 | Connsys `bt_drv` / `mt66xx` | 已实机运行 | 6.6 Connsys 重编译适配 | 尚未验证 | 依赖 WMT / connfem |
| 电池与电量计 | MT6358 Gauge / Fuel Gauge | 已实机运行（电量百分比） | 6.6 `mt6358` / `mtk_battery` | 尚未验证 | 需核对 `power_supply` sysfs 属性 |
| USB 充电状态上报 | Charger IC / Type-C / Extcon | **已知故障（5.10 未完成）** | 6.6 Charger + Extcon/TCPC | 已知故障 | 需在 6.6 重点定位并修复上报链路 |
| 音频 | MT6768 ASoC + MT6358 Codec | 待核实 5.10 状态 | 6.6 ASoC 适配 | 尚未验证 | 待分析原厂 Audio HAL 与 DTS |
| 温控与调频 | Thermal, CPUFreq, SPM/CPUIDLE | 5.10 传递 `cpuidle.off=1` | 6.6 Thermal + CPUFreq | 尚未验证 | 需核实 `cpuidle.off=1` 原因 |
| 传感器 | 待 Phase 1 提取列表 | 待核实 | 6.6 传感器驱动 / SCP 评估 | 尚未验证 | 待原厂 HAL 与 DTS 分析 |
| 摄像头 | 待 Phase 1 提取 Sensor 型号 | **已知故障（5.10 相机已爆炸）** | 评估 6.6 `mtkcam`/`imgsensor` | 已知故障 | 将做根因分析并尝试适配 |
| Android ABI & SELinux | Binder, DMA-BUF/Heap, ION, SELinux | 5.10 宽容模式启动 | 6.6 原生 + 必要兼容层 | 尚未验证 | 待核对原厂 `libion`/mtk ioctl |
| Root 支持 | KernelSU | 已集成 v3.3.1 | KernelSU 6.6 适配版 | 尚未验证 | 需确认 6.6 hooks/kprobe 支持 |
