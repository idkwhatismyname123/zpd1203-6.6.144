# ZPD1203 Linux 6.6 移植任务清单 (TASKS.md)

状态图例：`[ ]` 待处理 | `[/]` 进行中 | `[x]` 已完成 | `[!]` 阻塞/已知故障

## Phase 0：工程初始化与环境准备
- [x] 初始化 `d:\P3066` Git 仓库与 `.gitignore`
- [x] 创建 8 份核心项目管理文档（`AGENTS.md` 等）
- [/] 检查并补全 WSL2 构建与镜像解包依赖
- [ ] 提交初始工程脚手架 Git commit

## Phase 1：现有资源全面分析
- [ ] **Agent 3**：克隆并分析 `idkwhatismyname123/zpd1203-5.10.240`（提交记录、README、`zpd1203/`、DTS、defconfig、内核补丁、外置无线模块）
- [ ] **Agent 2**：只读分析原厂分区备份（`boot_a`、`vendor_boot_a`、`dtbo_a`、`vbmeta*`、`lk_a`、`expdb`、`super`）
- [ ] **Agent 2**：提取原厂 DTB、DTBO、ikconfig、cmdline、ramdisk、`vendor/firmware`、`vendor/lib/modules`
- [ ] **Agent 2**：提取原厂 Mali GPU DDK 版本、HWC/Gralloc 接口、音频/无线/电源/传感器/相机 HAL 与设备节点/ioctl 清单
- [ ] 汇总生成完整硬件资源与驱动映射表并回填 `AGENTS.md`

## Phase 2：六系内核源码调查与基底选择
- [ ] **Agent 1**：验证并对比候选 6.6 / 6.1 仓库（`mt6768-mainline/android_kernel_samsung_mt6768`、`Theman-Fromfar/a05m-kernel-6.6`、`MotorolaMobilityLLC/kernel-kernel_device_modules-6.6`、AOSP `android15-6.6`、`Mayuri-Chan/MTK_kernel_device_modules_6.6`、`MotorolaMobilityLLC/kernel-kernel_device_modules-6.1`、`mt6768-mainline/linux`）
- [ ] 建立候选源码覆盖率与构建方式对比矩阵
- [ ] 在 `DECISIONS.md` 正式确定移植基底并建立洁净 Git 工作树

## Phase 3：核心板级支持移植（Linux 6.6）
- [ ] **Agent 4**：移植 ZPD1203 DTS/DTSI 与 Reserved Memory
- [ ] **Agent 4**：适配 PSCI/SMP、GIC、MT6768 CCF 时钟、Pinctrl/GPIO、MT6358 PMIC/Regulator
- [ ] **Agent 4**：适配 MSDC0 eMMC、RPMB、USB PHY + MTU3 + Gadget ADB
- [ ] **Agent 4**：适配 IOMMU/SMI、Watchdog、Thermal、CPUFreq
- [ ] **Agent 4**：确认 Android Binder (`binderfs`)、DMA-BUF/DMA Heap、SELinux、KernelSU 集成

## Phase 4：无 UART 调试与首次最小启动准备
- [ ] **Agent 4**：配置 `ramoops`/`pstore` 保留内存与内核配置
- [ ] **Agent 4**：适配 Initramfs 调试脚本（阶段标记、dmesg/pstore 转储、早期 ADB）与可选屏幕早期输出
- [ ] **Agent 4**：编译最小可启动内核，校验 DTB 与打包最小 `boot.img`（`< 32 MiB`）

## Phase 5：完整硬件驱动移植
- [ ] **Agent 5**：移植 LCD Panel、DSI、MTK DRM/KMS、背光及显示时钟（含 5.10 横屏显示桥接兼容评估/迁移）
- [ ] **Agent 5**：迁移 Himax 触摸屏驱动至 6.6 API（固件加载、I2C、GPIO/IRQ、横屏坐标、休眠唤醒）
- [ ] **Agent 5**：适配 Mali-G52 GPU（`mali_kbase` + `ged` + `gpufreq`），匹配原厂用户态 DDK ABI
- [ ] **Agent 6**：从 6.6 上游重新适配并编译 Wi-Fi / BT Connsys 模块
- [ ] **Agent 6**：适配音频（MT6768 ASoC + MT6358 Codec + 外放）
- [ ] **Agent 6**：适配电池/电量检测/充电，**重点定位并修复 5.10 USB 充电状态上报问题**
- [ ] **Agent 6**：验证 CPUFreq、休眠唤醒、Thermal、传感器，并排查 5.10 相机失败原因与 6.6 可行性

## Phase 6：Android Vendor 兼容性
- [ ] **Agent 7**：对照原厂 Vendor HAL 逐项验证 Binder、DMA Heap/ION、GPU ioctl、MTK 私有 ioctl、procfs/sysfs、SELinux、init 服务与挂载点
- [ ] **Agent 7**：按需实现真实内核兼容层（无空函数/假状态）

## Phase 7：自动化构建、测试与最终交付
- [ ] **Agent 7**：编写一键可复现构建、打包与静态校验脚本（`scripts/`）
- [ ] **Agent 7**：编写非破坏性测试、交互式安全刷机、原厂备份恢复与日志收集脚本
- [ ] **Coordinator**：全量分支合并、洁净从头编译、校验所有产出并更新全部交付文档
- [ ] 等待用户实机测试并收集真实日志进行迭代验证
