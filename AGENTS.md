# ZPD1203 (MT6768) Linux 6.6 Android 内核移植全局开发规范 (AGENTS.md)

> **强制准则**：任何新会话、子代理（Subagent）、上下文恢复或继续执行任务之前，必须首先完整阅读 `AGENTS.md`、`TASKS.md` 和 `HANDOFF.md`。

---

## 1. 项目总目标

为 **ZPD1203（ZYB ZPD1203 平板，MediaTek MT6768 / Helio P65-G85 家族）** 设备完成 **Linux 6.6 LTS Android 内核**完整移植，并最终实现完整 Android 实机正常运行（当前优先目标 Linux 6.6；仅当源码调查证明 Linux 6.1 具有压倒性更完整的 MT6768 BSP 支持时才可切换 6.1，且必须在 `DECISIONS.md` 记录完整技术依据）。

### 最终功能与体验目标
- Android 正常进入桌面（兼容原厂 Android 12 Vendor）
- LCD 显示及背光（横屏显示 / DRM-KMS 或真硬件流水线）
- Himax 触摸屏（I2C、GPIO、中断、固件加载、横屏坐标映射、休眠唤醒）
- GPU 硬件加速（Mali-G52 真实硬件渲染与原厂 `libGLES_mali.so` DDK ABI 兼容；严禁使用软件渲染冒充硬件加速）
- Wi-Fi、蓝牙（适配并重新编译 6.6 Connsys 模块，禁止直接加载 5.10 二进制 `.ko`）
- USB、ADB（MTU3/MUSB + ConfigFS + FunctionFS）
- 内部存储（MSDC0 eMMC、RPMB、`super` 动态分区、dm-verity/ext4/f2fs/erofs）
- 电池、电量检测、充电（**重点修复 5.10 版本 USB 充电状态上报未完成问题**）
- 音频（MT6768 ASoC、MT6358 Codec、外置功放如适用）
- SELinux、Binder（binderfs）、Android IPC、DMA-BUF / DMA Heap（及必要的真实兼容层）
- CPU 调频（CPUFreq）、休眠唤醒（SPM/CPUIDLE）及温控（Thermal）
- 尽可能兼容原厂 Vendor HAL，避免不必要的用户空间修改
- KernelSU 集成支持
- 尽可能排查并修复 5.10 版本尚未解决的硬件问题（如相机 `mtkcam`/MIPI CSI 与充电状态上报）

---

## 2. 核心参考资源与路径约定

| 资源类型 | 路径 / 地址 | 访问规则 |
|---|---|---|
| 项目控制仓库（Windows） | `d:\P3066` | 文档、脚本、DTS/DTSI、defconfig、补丁集、分析报告与最终交付物 |
| 独立 Linux 构建工作区（WSL2 ext4） | `/home/asus/zpd1203-6.6/` | 所有内核源码克隆、提取与编译在此执行（严禁在 NTFS `/mnt/d` 编译内核，避免大小写敏感与符号链接问题） |
| 原厂完整分区备份 | `D:\备份\p\GeekFlashTool_Readback_20260820162108246` (`/mnt/d/备份/p/GeekFlashTool_Readback_20260820162108246`) | **只读！严禁修改、覆盖或删除任何原厂备份文件** |
| 已完成实机运行的 5.10.240 仓库 | `https://github.com/idkwhatismyname123/zpd1203-5.10.240` | 在 `/home/asus/zpd1203-6.6/ref-5.10.240` 独立克隆分析；不破坏现有本地目录 |

---

## 3. 设备硬件信息与驱动映射（持续维护）

### 已确认基础设备条件
- **SoC**：MediaTek **MT6769V/CB (`hw_code=0x707`) / MT6768** 平台（Scatter 标识 `MT6768`，存储 `EMMC` / `MSDC_0`，Preloader `preloader_k69v1_64_k419.bin` `zpd_mt8788_android12`，双 Rank **6 GiB DRAM**: `0x40000000` + `0x100000000` 各 3 GiB）
- **Bootloader & 分区现状**：已解锁（`[AVB20] lock_state=0x3`, `verifiedbootstate=orange`），`lk_a.img` **支持 `fastboot boot`**；使用 **Boot Header v2**（`page_size=2048`, `kernel=0x40080000`, `ramdisk=0x47c80000`, `dtb=0x4bc80000`）。`vendor_boot_a/b` 实际存放**未修改原厂 4.19.191 `boot.img`**（纯净基线），`boot_a` 含 Magisk ramdisk，`super` 仅 slot `_a` 存在逻辑分区（原厂 Android 12 `vendor_a`/`product_a` VNDK 31 + LineageOS 21 Android 14 GSI `system_a`）
- **无物理 UART**：不允许要求拆机，已从 `expdb.img` 实测提取 `ramoops/pstore` 地址 **`0x4d010000` (`0xe0000`)**、BL FB **`0x7d350000` (`0x20b0000`)** 及完整 PL/LK/GZ 日志
- **5.10 参考状态**：基于 Motorola `kernel-mtk` (`f83ca9e95d59`)，KernelSU v3.3.1，已验证 Android 12 横屏显示（`simplefb` + NEON `gralloc_fb0_bridge`）、SPI4 Himax 触屏、ADB (`musb-hdrc`)、Wi-Fi/BT（9 个无线模块）、电量百分比；已知问题：相机失效（未移植 + EL2 GenieZone 依赖）、USB 充电状态上报未完成（缺 `sgm41510`/`aw35615`/`wusb3801` 节点与驱动）

### 硬件资源与驱动映射表（Phase 1 实证定稿）

| 子系统 | 硬件芯片 / 总线 / GPIO / IRQ (实测提取) | 原厂 4.19 / HAL 接口 | 5.10.240 实现 | 6.6 目标驱动方案 | 状态 |
|---|---|---|---|---|---|
| 核心 SoC / 启动 | MT6768 ARMv8 + GICv3 + PSCI; `sysirq @ 0x0c53a650` (97 INTPOL); GenieZone EL2 | LK boot v2 + `vendor_boot_a` 纯净 ramdisk | `mt6768-zpd1203-minimal.dts` + `sysirq` 平台驱动补丁 + `mt6768.force_slot_a=1` | `aosp-6.6` (`6.6.144`) + ZPD1203 DTS + `sysirq` / `force_slot_a` 补丁 | 待移植 |
| 时钟 / Pinctrl / PMIC | MT6768 CCF / Pinctrl / `pwrap` / MT6358 PMIC (`0x5820`) | `clk-mt6768`, `pinctrl-mt6768`, `mt6358` | Motorola 5.10 原生驱动 + `8250_mtk` 时钟修复 | `addster-bsp-6.6` + `aosp-6.6` 原生 MT6768 clk/pinctrl/mt6358 | 待移植 |
| 内部存储 / 加密 | eMMC `mmc@11230000` (HS400 + CQHCI) + `inlinecrypt` (`aes-256-xts:v2`) + RPMB | `fstab.mt6768` + `super` 动态分区 (`_a`) | `mtk-sd.c` (`=y`); `RPMB=m` 未打包 | 6.6 `mtk-sd` + `cqhci` + `inlinecrypt` + `rpmb-mtk` (`=y`) | 待移植 |
| USB / ADB | `usb0@11200000` (**`musb-hdrc`**) + `extcon_usb` (ID GPIO 41) + TPHY | `usb@1.2` HAL 与 `init.mt6768.usb.rc` 硬编码 **`musb-hdrc`** | `usb20/musb_core.c` (`dr_mode="peripheral"`, 删 `usb-role-switch`) + FFS ADB | 6.6 `usb/usb20` (`musb-hdrc`) + TPHY + ConfigFS/FFS（打通角色切换） | 待移植 |
| 显示系统 / 背光 | **实机面板 `jt120wul005_a01_dsi_vdo`** (`HX83102-E/J`, `1200x2000`, `FB @ 0x7d350000`), **I2C7 `aw37503@3e`**, GPIO 153/70/165/45, `disp_pwm` | `hwcomposer.mt6768` 用 `/dev/mtk_disp_mgr` + `fb0`; `pq@2.15`/`mapper@4.0` 用 `/dev/dri/card0` | `DRM_MEDIATEK=n`; `simplefb.c` 关 OVL0 L3 + `a12_init_wrapper` + NEON `gralloc_fb0_bridge.so` | Phase 4 先行 `simplefb` + NEON 桥接保证点亮；Phase 5 迁移 6.6 MTK DRM v2 + `jt120wul005` + `aw37503` + 背光/HWC 兼容评估 | 待移植 |
| 触摸屏 | **SPI4 (`spi4@11014000`)** `zlt_ts@0` (`"himax,hxcommon"`, CS/CLK/MO/MI=GPIO 17..20, INT=**GPIO 6**, 共享复位 **GPIO 158**) | `Himax_firmware*.bin` (`HX83102-J` / `HX83102-E` 6 份) | 5.10 `hxchipset`（active pinctrl, `SPI_MODE_3`, 跳过 `GPIO158`, 内建固件） | 前向移植 `hxchipset` 至 6.6 API（参考 Samsung `hx83112f`） | 待移植 |
| GPU | **Mali-G52 MC2 (`mali@13040000`)** | `libGLES_mali.so` DDK **`1.4 Bifrost-"r32p1-01eac0"`** + `/dev/mali0` + `/proc/ged` | 5.10 `mali-r32p1` + `ged` + `gpufreq_mt6768` (`IOMMU`/`SMI` 未打包) | Moto 6.6 GPU `mali-r32p1` (`r32p1-01eac0`, `platform/mt6768`) + `ged` + `gpufreq` + `IOMMU`/`SMI` | 待移植 |
| 无线网络 | `consys@18002000`, `btif@1100c000`, `wifi_ant_swap`=GPIO 108, `gps_lna`=GPIO 94 | 11 `.ko` (`connfem`->`wmt_drv`->`wmt_chrdev_wifi`/`bt_drv_connac1x`/`gps`/`fm`->`wlan_drv_gen4m`) + `soc1_0_*` 固件 | 9 个 5.10 `.ko` (`wireless.cpio.xz` + `MS_BIND` + `fb` notifier 补丁) | 重编 Moto `vvta35`/`v1tl35` 6.6 Connsys `.ko`（严禁复用 5.10 `.ko`） | 待移植 |
| 电池 / 充电 / Type-C | `mt6358_gauge`; **I2C5 `sgm41510@6b`** (IRQ GPIO 26, EN GPIO 166), `subpmic@34`, `usb_type_c@4e`; **I2C6 `aw35615@22`** (PD, GPIO 8/159), `wusb3801@60` (CC), `z350@35` (QC); **I2C7 `slave_charger@4b`** | `health@2.1`, `/sys/class/power_supply/{battery,ac,usb}`, `fuelgauged` | 电量百分比可用；无充电 IC/Type-C DT 与驱动 (`CHARGER_SGM415XX=n`) | `addster-bsp-6.6` **`sgm415xx.c`** + **`tcpc_aw/aw35615`** + `aosp-6.6` **`wusb3801.c`** + `mt6358-gauge` + 完整 `power_supply` 上报 | 待修复 |
| 音频 | `afe@11220000` + `mt6358` + **I2C3 SmartPA (`fs15xx@35/36`, `aw87xxx_pa@59/5a`)** + `accdet` | `audio.primary.mt6768` (`mt6768mt6358`), `awinic.audio.effect.so`, `fs15xx.fsm`/`aw87xxx_acf.bin` | 5.10 Defconfig 关闭 (`SND_SOC_MT6768=n`) | `addster-bsp-6.6` `mt6768-mt6358` ASoC + SmartPA/ACCDET 适配 | 待移植 |
| 传感器 / 霍尔 / 按键 | I2C1 `sc7a20@18`, `mc3416@36`, `ucs14266@38`/`ls9801i@54` (EINT 7); `hall` (EINT 9/32); `kp` GPIO 93 | `/dev/m_*_misc`, `/dev/sensorlist` | 5.10 未移植（DTS 空桩） | 评估 IIO/Input 或 SCP 传感器接口对齐 | 待评估 |
| 摄像头 | `sc800cs`/`hi849` (主/副 I2C2/I2C3), `sc800cssub`/`s5k4h7` (前 I2C4), 闪光灯 I2C7 `aw36515@63` | `camerahalserver` 依赖 `/dev/gz_kree` (EL2 `[ISP_HA]`/`[MTEE_SENINF]`) + ISP4 | 5.10 全禁用 (`dvfsrc` 禁用) | 评估 `addster-bsp-6.6` `isp4_t` (`sc800cs`/`s5k4h7`) + `gz_kree` EL2 接口 | 已知故障 |
| Android ABI / 特权 | BinderFS, `/dev/dma_heap/mtk_mm*`, `/dev/ion` (`BIT(10)` Codec2), 软件 Keymaster, KernelSU | `allocator@4.0`/`mapper@4.0` 同时链接 `libdmabufheap.so` 与 `libion_mtk.so` | `MTK_ION_MM_HEAP_CODEC_ABI=y`, SELinux permissive, KernelSU v3.3.1 | 6.6 BinderFS/SELinux + DMA-BUF Heaps + `/dev/ion` `BIT(10)` 真实兼容转发 + KernelSU v3.3.1+ | 待移植 |

---

## 4. 六系内核基底选择及技术依据（Phase 2 已拍板，详见 `DECISIONS.md` ADR-002）

- **已选定唯一主基底（Linux 6.6.144）**：
  1. **核心内核**：AOSP `https://android.googlesource.com/kernel/common` 分支 `android15-6.6`（Commit `329f9ae918a9e18da3c488e531adf9b7995e2aae`，**Linux 6.6.144**）——零 Samsung DEFEX/FIVE/AFDO 污染，宿主机 `clang-21.1.8` + `ld.lld` 纯 Kbuild 一次通过。
  2. **MT6768 `device_modules`**：**`Addster09/mtk-kernel-modules-bsp-6.6`**（`android15-6.6`, `1561b421959f`）为主，辅以 **`MotorolaMobilityLLC/kernel-kernel_device_modules-6.6`**（`android-15-release-v1tl35.73-60-3`, `9b049a46b9fc`）做 OEM 编译修复交叉校验。关键决定因素：`Addster09` 去除 Moto 机型强绑定且原生自带 ZPD1203 硬件所需的 `sgm415xx.c` 与 `tcpc_aw/aw35615`（AOSP 自带 `wusb3801.c` 与 `aw37503-regulator.c`）。
  3. **Mali GPU 模块**：`MotorolaMobilityLLC/vendor-mediatek-kernel_modules-gpu`（`android-15-release-v1tl35.73-60-3`, `3b81cf6d7c0a`）中的 **`mali-r32p1` (`r32p1-01eac0`, `platform/mt6768/`)**，精确匹配原厂 `libGLES_mali.so` DDK 版本。
  4. **Connsys 无线模块**：Motorola `vvta35` (`common`, `bt-mt66xx`, `connfem`, `wlan-adaptor`) + `v1tl35.73-60-3` (`wlan-core-gen4m`)，实测 5 大组件在 `6.6.144` 上 C 源码零修改编译通过。
- **Linux 6.1 排除依据**：实测 `MotorolaMobilityLLC/kernel-kernel_device_modules-6.1` 完全不含 MT6768 源码（`find *6768*` 为空），而 Linux 6.6 拥有完整且维护至 2026 年的 MT6768 BSP，故坚持 Linux 6.6。

---

## 5. Phase 1–7 完整任务规范

- **Phase 1 — 现有资源全面分析**：分析 `zpd1203-5.10.240` 全部提交、README、脚本、`zpd1203/` 源码、DTS、defconfig、外置无线模块；只读分析原厂备份各分区、提取 DTB/DTBO/ikconfig/cmdline/ramdisk/固件/HAL/`vendor/lib/modules`、Mali DDK 版本、ioctl 与设备节点，建立硬件-驱动映射表。
- **Phase 2 — 六系内核源码调查**：检索并验证真实 6.6/6.1 MT6768 仓库与分支、版本、完整度，建立对比表选定移植基底（记录于 `DECISIONS.md`）。
- **Phase 3 — 板级支持移植**：迁移 DTS/DTSI、Reserved memory、PSCI/SMP、GIC、CCF、Pinctrl/GPIO、PMIC/Regulator、MSDC/eMMC、USB PHY/MTU3、IOMMU/SMI、Watchdog、Thermal、CPUFreq、RPMB、Binder、DMA-BUF/DMA Heap。**严禁直接将 5.10 `drivers/` 整目录覆盖到 6.6 内核**，必须逐项适配 6.6 API，优先使用 6.6 原生驱动。
- **Phase 4 — 实现首次启动（最小可启动内核）**：构建最小内核，建立无 UART 多级调试体系（`ramoops/pstore`、`expdb`、initramfs 阶段脚本、USB Gadget/ADB、Framebuffer 屏幕状态输出），生成支持 `fastboot boot`（及安全回退机制）的最小 `boot.img`。
- **Phase 5 — 完整硬件驱动移植**：显示系统（LCD/DSI/DRM/背光/显示桥接兼容）、Himax 触摸屏、Mali GPU（匹配用户态 DDK ABI，严禁软件渲染伪装）、Wi-Fi/蓝牙（重编 6.6 模块）、音频、充电与电量（重点修复 USB 充电状态上报）、温控、休眠唤醒、传感器、摄像头分析与尝试修复。
- **Phase 6 — Android Vendor 兼容性**：系统解决 Linux 4.19/5.10 与 6.6 的 Binder、DMA Heap/ION、DMA-BUF、GPU ioctl、MTK 私有 ioctl、procfs/sysfs、SELinux、模块符号、HAL、init 服务和挂载点差异；保留真实硬件功能，禁止空函数/假返回值欺骗；尽量不动用户态 vendor。
- **Phase 7 — 构建、测试与最终交付**：自动化可复现编译脚本、验证门禁、安全刷写与恢复脚本、完整产物（`Image`、`Image.gz`、DTB/DTBO、`boot.img`、`vendor_boot.img` 如需、`.ko` 模块源码及产物、补丁集、完整文档）。

---

## 6. 多 Agent 协作与职责规范

所有子代理必须遵守本 `AGENTS.md`，工作于各自隔离分支/目录，产出写入指定分析文件或分支，由主 Agent 协调合并与冲突解决。

| Agent 标识 | 职责分工 | 核心产出 |
|---|---|---|
| **Coordinator (主 Agent)** | 统筹 Phase 1-7、规范维护、基线决策、分支合并、冲突处理、最终洁净构建与交付 | 根目录文档、最终集成构建与 SHA256 清单 |
| **Agent 1 (`bsp-survey`)** | Phase 2：六系源码调查、仓库验证、构建系统与驱动覆盖率对比及基底推荐 | `analysis/phase2_bsp_survey.md` |
| **Agent 2 (`stock-backup-analyzer`)** | Phase 1：原厂备份只读解析（DTB/DTBO/ikconfig/super/HAL/GPU DDK/固件/ioctl） | `analysis/phase1_stock_analysis.md` |
| **Agent 3 (`kernel510-analyzer`)** | Phase 1：5.10.240 全部板级修改、DTS、无线构建、`zpd1203/` 工具与已知问题分析 | `analysis/phase1_510_port_analysis.md` |
| **Agent 4 (`core-boot-storage`)** | Phase 3 & 4：DTS/defconfig 迁移、核心启动/存储/USB/KernelSU、无 UART 调试与最小内核 | 核心板级补丁 + 最小可启动 `boot.img` |
| **Agent 5 (`display-gpu-touch`)** | Phase 5：LCD/DSI/DRM、显示桥接兼容、Himax 触屏、Mali-G52 GPU DDK 驱动适配 | 显示/触控/GPU 驱动补丁与模块 |
| **Agent 6 (`wireless-audio-power`)** | Phase 5：Wi-Fi/BT 6.6 模块、音频、电池/USB 充电修复、温控/PM、传感器/相机排查 | 无线/音频/电源/温控驱动与模块 |
| **Agent 7 (`android-abi-build-test`)** | Phase 6 & 7：Android Vendor ABI 兼容层、全自动化构建/打包/校验/安全测试与恢复脚本 | `scripts/*` + ABI 兼容补丁 |

---

## 7. 编译环境、工具链与构建规范

- **编译宿主机**：Windows 11 + WSL2 Ubuntu (`x86_64`, 10 CPU cores, 15 GiB RAM)
- **已验证工具链**：`clang-21`, `ld.lld`, `llvm-ar`, `dtc`, `aarch64-linux-gnu-gcc`, `pahole`, `mkbootimg`, `avbtool`, `lpunpack`, `simg2img`, `fsck.erofs`, `fakeroot`, `cpio`, `lz4`, `xz`, `zstd`, `fastboot`
- **构建命令约定**：所有编译均应记录至 `BUILD.md` 并可通过 `scripts/build_all.sh` 一键无交互复现。每次成功构建必须把 Git commit、内核版本、配置文件与产物 SHA256 记录到 `PORTING_STATUS.md`。

---

## 8. 内核移植技术红线与 Vendor ABI 规则

1. **禁止整目录覆盖**：严禁从 5.10 直接复制整个 `drivers/` 目录到 6.6。
2. **禁止加载旧二进制模块**：严禁直接塞入 5.10 `.ko` 模块；所有模块必须针对目标 6.6 内核树重新编译且 `vermagic` 完全一致。
3. **禁止伪造功能**：绝不允许用空函数、固定假返回值或软件渲染冒充 GPU/相机/充电硬件正常工作。
4. **严格状态诚实**：所有功能只能标注以下五种状态之一：
   - `已编译通过`
   - `已静态验证`
   - `已实机验证`（**仅当用户提供真实设备启动日志/输出后方可使用**）
   - `尚未验证`
   - `已知故障`
5. **不擅自降低验收标准**：任何编译错误、ABI 差异或硬件问题必须记录真实错误与分析过程，尝试上游驱动或编写真实兼容层。

---

## 9. 无物理 UART 调试方案

- **一级（Bootloader / 早期启动）**：启用 `ramoops`/`pstore`（`console`, `dmesg`, `pmsg` 保留内存，跨热重启留存）；支持时启用 `simple-framebuffer`/屏幕早期输出阶段标记。
- **二级（Initramfs 调试外壳）**：分阶段标记（`STAGE 1..N`），在 `init` 启动前转储 `dmesg`、`/sys/fs/pstore/*`、模块加载结果，并尽早拉起 USB Gadget FunctionFS ADB / 串口日志通道。
- **三级（系统级 / 崩溃取证）**：ADB `dmesg`/`logcat`/`pstore` 拉取脚本，以及无法启动 ADB 时的 `EXPDB` 分区回读解析流程。详情见 `DEBUGGING.md`。

---

## 10. 实机测试、刷写安全与恢复规范

1. **严禁未经用户明确确认执行任何 `fastboot flash` 或写分区操作**。
2. 优先使用 `fastboot boot <boot.img>` 进行非破坏性内存临时引导测试。
3. 若 ZPD1203 LK 不支持 `fastboot boot`，只允许生成镜像和提供带确认门禁的刷写脚本（核对当前活动槽位 `_a`/`_b`、校验 SHA256、要求显式输入确认），并同时提供一键恢复原厂 `boot_a.img`/`dtbo_a.img`/`vendor_boot_a.img` 的恢复脚本。
4. 原厂备份目录 `D:\备份\p\GeekFlashTool_Readback_20260820162108246` 永久只读。

---

## 11. 持续执行与上下文恢复机制

以下核心文件必须随项目持续更新：
- `AGENTS.md`：全局开发规范与任务目标
- `TASKS.md`：全部任务清单与实时状态
- `PORTING_STATUS.md`：当前阶段、里程碑与构建记录（commit / 版本 / config / SHA256）
- `HARDWARE_STATUS.md`：各硬件子系统驱动适配与验证状态
- `DEBUGGING.md`：无 UART 调试方案、取证步骤与真实日志记录
- `DECISIONS.md`：关键技术决策及验证依据
- `BUILD.md`：依赖安装与完整可复现编译命令
- `HANDOFF.md`：当前工作现场、路径、阻塞项与下一步行动
