# ZPD1203 Linux 6.6 移植任务清单 (TASKS.md)

状态图例：`[ ]` 待处理 | `[/]` 进行中 | `[x]` 已完成 | `[!]` 阻塞/已知故障

## Phase 0：工程初始化与环境准备
- [x] 初始化 `d:\P3066` Git 仓库与 `.gitignore`
- [x] 创建 8 份核心项目管理文档（`AGENTS.md` 等）
- [x] 检查并补全 WSL2 构建与镜像解包依赖（`clang-21`, `lld`, `aarch64-linux-gnu-gcc`, `mkbootimg`, `avbtool`, `fdtoverlay`, `xz` 等）
- [x] 提交初始工程脚手架 Git commit

## Phase 1：现有资源全面分析
- [x] **Agent 3**：克隆并分析 `idkwhatismyname123/zpd1203-5.10.240` -> 见 `analysis/phase1_510_port_analysis.md`
- [x] **Agent 2**：只读分析原厂分区备份 -> 见 `analysis/phase1_stock_analysis.md`
- [x] **Agent 2**：提取原厂 DTB、DTBO、ikconfig、cmdline、ramdisk、`vendor/firmware`、`vendor/lib/modules`
- [x] **Agent 2**：提取原厂 Mali GPU DDK 版本、HWC/Gralloc 接口、音频/无线/电源/传感器/相机 HAL 与设备节点/ioctl 清单
- [x] 汇总生成完整硬件资源与驱动映射表并回填 `AGENTS.md`

## Phase 2：六系内核源码调查与基底选择
- [x] **Agent 1**：验证并对比候选 6.6 / 6.1 仓库 -> 见 `analysis/phase2_bsp_survey.md`
- [x] 建立候选源码覆盖率与构建方式对比矩阵
- [x] 在 `DECISIONS.md` 正式确定移植基底并建立洁净 Git 工作树（`AOSP android15-6.6 6.6.144` + `Addster09` BSP + Moto GPU/Connsys）

## Phase 3：核心板级支持移植（Linux 6.6）
- [x] **Agent 4**：移植 ZPD1203 最小 DTS/DTSI（`mt6768-zpd1203-minimal.dts` + `zpd1203-stock-battery-profile.dtsi`）与 Reserved Memory
- [x] **Agent 4**：适配 PSCI/SMP、GIC、`irq-mtk-sysirq.c`（97 位 `INTPOL`）、`init/main.c` `force_slot_a`、MT6768 CCF 时钟、Pinctrl/GPIO、MT6358 PMIC/Regulator
- [x] **Agent 4**：适配 MSDC0 eMMC（`mtk-mmc.c` + `cqhci` + `inlinecrypt`）、`rpmb-mtk`（`=y`）、`usb/usb20` (`musb-hdrc`) + `phy-mtk-tphy` + ConfigFS FFS ADB
- [x] **Agent 4**：适配 IOMMU、SMI、Watchdog、DevAPC、BinderFS、DMA-BUF Heaps、SELinux、KernelSU v3.3.1（`KSU=y`）

## Phase 4：无 UART 调试与最小启动内核构建
- [x] **Agent 4**：启用 `ramoops`/`pstore` 保留内存参数与内核配置（`0x4d010000` / `0xe0000`）
- [x] **Agent 4**：实现 `a12_init_wrapper.c`（`STAGE 1..7`、`pstore` 归档、复合 ADB+ACM 控制台）与 `simplefb.c` OVL0-L3 清屏 / `gralloc_fb0_bridge.c`
- [x] **Agent 4**：编译并静态校验 `boot-minimal-6.6.img`（clean `6.6.144-zpd1203-g91af1aa18e1a`, `< 32 MiB`, Boot Header v2, `0xd7b7ab1e`, `fdtoverlay` PASS）

## Phase 5：完整硬件驱动移植
- [x] **Agent 5 (`Step 5A`)**：移植 `jt120wul005` DSI 面板、MTK DRM v2 (`fbdev` 6.6 API)、`aw37503`、`mtk_leds` 背光，并构建与校验 `zpd1203-display-touch-gpu.dtsi` -> 见 `analysis/phase5_display_gpu_touch.md`
- [x] **Agent 5 (`Step 5A`)**：前向移植 Himax SPI4 `hxchipset`（跳过共用 `GPIO 158`，内建双固件）
- [x] **Agent 5 (`Step 5A`)**：移植 Moto 6.6 `mali-r32p1`（`mali_mgm_mt6768.ko` + `mali_kbase_mt6768.ko` `r32p1-01eac0`）与 `ged`/`gpufreq`
- [x] **Agent 6 (`Step 5B`)**：从 Motorola 6.6 上游适配并编出全部 Wi-Fi/BT Connsys 模块与依赖链 `.ko` -> 见 `analysis/phase5_wireless_audio_power.md`
- [x] **Agent 6 (`Step 5B`)**：启用 MT6768+MT6358 ASoC + ACCDET + `aw87xxx` SmartPA（诚实标注 `fs15xx` 二供缺失）
- [x] **Agent 6 (`Step 5B`)**：适配 `bq2589x_charger.c` 支持 `sgm41510@6b`、修复 `tcpc_aw` 头文件路径选择、启用 `aw35615@22` PD / `extcon_usb` / `mt6358-gauge` / `mtk-master-charger`，并校验 `fdtoverlay` 保留 `charger = <&sgm41510>`
- [x] **Agent 6 (`Step 5B`)**：启用 Thermal (`mt6768`)、CPUFreq DVFS / PPM v3 / EEM、`MTK_SPM`、`MCDI`、`CPUIDLE`；诚实完成传感器与摄像头 EL2 `/dev/gz_kree` 审计（标记 `尚未验证` / `已知故障`）

## Phase 6：Android Vendor 兼容性
- [x] **Agent 7**：编写并编通真实 `/dev/ion` -> DMA-BUF Heap 兼容驱动 `mtk_ion_compat.c`（映射 `BIT(10)` -> `mtk_mm*` 与 `BIT(0)` -> `system*`，未知 ioctl 诚实返回 `-ENOTTY`）并启用 `mtk_system_heap`（禁用上游防重名 `# CONFIG_DMABUF_HEAPS_SYSTEM is not set`）
- [x] **Agent 7**：扩展 `a12_init_wrapper.c` 支持 11 模块严格拓扑加载、`/vendor/lib/modules` `MS_BIND` 替换、`/dev/mali0`+`/dev/ion` 权限守护，以及 `/dev/dri/card0` vs `simplefb` 门控切换 -> 见 `analysis/phase6_7_abi_tooling.md`

## Phase 7：自动化构建、测试与最终交付
- [x] **Coordinator / Agent 7**：整合并固化全量 `zpd1203_defconfig`（保留 `zpd1203_minimal_defconfig`），确保全部 8 个 WSL2 Git 仓洁净无 `-dirty`
- [x] **Agent 7**：编写完整可复现构建、模块打包、XZ/Gzip Ramdisk 与静态门禁校验脚本（`scripts/build_*.sh`, `verify_build.sh`）
- [x] **Agent 7**：编写非破坏性 `fastboot boot`、安全刷写、原厂恢复与无 UART 日志收集脚本（`.ps1` + `.sh`）
- [x] **Coordinator**：完成 `full` + `minimal` 双模式洁净重建并 0 错误通过全部静态校验，输出全部文档与 SHA256 清单
- [ ] 等待用户实机测试并收集真实日志进行迭代验证
