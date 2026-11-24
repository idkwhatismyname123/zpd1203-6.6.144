# ZPD1203 Linux 6.6 技术决策记录 (DECISIONS.md)

## ADR-001：工作目录隔离策略（Windows 控制仓 + WSL2 ext4 构建区）
- **日期**：2026-11-24
- **决策**：项目管理文档、分析报告、DTS/DTSI、defconfig、补丁集、自动化脚本及最终发布产物存放在 Windows `d:\P3066` 并纳入 Git 管理；内核源码克隆、原厂镜像解包及内核编译全部在 WSL2 ext4 文件系统 `/home/asus/zpd1203-6.6/` 中执行。
- **原因**：
  1. Linux 内核源码包含仅大小写不同的文件（如 `net/netfilter/xt_DSCP.c` 与 `xt_dscp.c`）以及大量符号链接，NTFS (`/mnt/d`) 默认大小写不敏感且跨 9P IO 性能极差。
  2. 现有 WSL2 目录 `/home/asus/zpd1203-5.10.240` 与原厂备份 `D:\备份\p\GeekFlashTool_Readback_20260820162108246` 必须绝对保持不受破坏/只读。

## ADR-002：六系内核版本与移植基底选择（待 Phase 1 & Phase 2 完成定案）
- **状态**：待定（正在进行 Phase 1 与 Phase 2 并行调查）
- **候选**：
  - Linux 6.6 LTS：`mt6768-mainline/android_kernel_samsung_mt6768` (6.6.50) / `Theman-Fromfar/a05m-kernel-6.6` (6.6.50) / `MotorolaMobilityLLC/kernel-kernel_device_modules-6.6` + AOSP `android15-6.6` / `Mayuri-Chan/MTK_kernel_device_modules_6.6`
  - Linux 6.1 LTS（仅当 6.6 均存在严重缺口时备选）：`MotorolaMobilityLLC/kernel-kernel_device_modules-6.1`
- **评估维度**：Kbuild 可直接构建性、MT6768 核心与外设驱动完整度、GPU DDK 与原厂 Android 12 兼容性、无线驱动 6.6 适配度、代码整洁度。
