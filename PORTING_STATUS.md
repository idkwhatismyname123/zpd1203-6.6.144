# ZPD1203 Linux 6.6 移植进度追踪 (PORTING_STATUS.md)

- **当前阶段**：Phase 3 与 Phase 4 已完成编译与静态验证（准备进入 Phase 5 完整硬件驱动移植与 Phase 6–7）
- **目标内核**：Linux **6.6.144** (`AOSP android15-6.6` + `Addster09/mtk-kernel-modules-bsp-6.6` + Moto GPU `r32p1` + Moto Connsys `vvta35`/`v1tl35`)
- **原厂基线**：ZYB Android 12 (`vendor_boot_a.img` 4.19.191 / VNDK 31，`super` 含 LineageOS 21 Android 14 GSI `system_a`)
- **参考移植**：`idkwhatismyname123/zpd1203-5.10.240` (`test25` / `8a74a527`)

## 阶段里程碑状态

| 阶段 | 描述 | 状态 | 备注 |
|---|---|---|---|
| Phase 0 | 工程文档、Git 仓库与 WSL2 工具链检查 | 已完成 | 已生成 8 份核心规范文档并验证 WSL2 工具链 |
| Phase 1 | 5.10 仓库深度解析 + 原厂备份只读提取分析 | 已完成 | `analysis/phase1_510_port_analysis.md` & `analysis/phase1_stock_analysis.md` |
| Phase 2 | 六系内核源码调查与基底选型 | 已完成 | `analysis/phase2_bsp_survey.md`，定案 Linux 6.6.144 组合架构 |
| Phase 3 | 核心板级支持迁移（DTS/时钟/PMIC/存储/USB/Android核心） | 已编译通过 / 已静态验证 | `kernel-6.6` (`a0efcb376f2a`), `devmod-6.6` (`815405526aa3`); 补丁归档于 `patches/phase3_4/` |
| Phase 4 | 无 UART 调试体系与最小可启动内核构建 | 已编译通过 / 已静态验证 | 产出 `out/minimal/boot-minimal-6.6.img` (32 MiB, Boot v2, DTB + DTBO `fdtoverlay` 0 错误) |
| Phase 5 | 完整硬件驱动（显示/触屏/GPU/无线/音频/电源/相机分析） | 未开始 | 待 Agent 5 & Agent 6 并行执行 |
| Phase 6 | Android Vendor ABI 兼容性验证与适配 | 未开始 | 待 Agent 7 执行 |
| Phase 7 | 自动化构建、安全测试脚本与最终交付 | 未开始 | 待集成与校验 |

## 实机测试说明
> 当前尚未进行任何实机刷机或测试。所有主机端编译与静态校验产出，在收到用户真实设备运行日志前，严格标注为 `已编译通过` / `已静态验证`，绝不标注为 `已实机验证`。

## 构建历史记录

| 日期 | Git Commit | 内核版本 | 配置文件 | 目标产物 | 大小 (Bytes) | SHA256 | 构建结果 |
|---|---|---|---|---|---|---|---|
| 2026-11-24 | `kernel-6.6`: `a0efcb376f2a`<br>`devmod-6.6`: `815405526aa3` | `6.6.144-zpd1203-ga0efcb376f2a` | `zpd1203_minimal_defconfig`<br>(`zpd1203_minimal.config`) | `Image` | 28,510,720 | `2498ea1869039c32f049c37e068f6e0d88d3fbf3f0b778869c802c63f86455d5` | 已编译通过 |
| 2026-11-24 | `kernel-6.6`: `a0efcb376f2a`<br>`devmod-6.6`: `815405526aa3` | `6.6.144-zpd1203-ga0efcb376f2a` | `zpd1203_minimal_defconfig` | `Image.gz` | 11,731,770 | `67cf07df245db5c44b4ac505870e7ee7646ef51a71fc3b67a1c0bd0d547b18d8` | 已编译通过 |
| 2026-11-24 | `devmod-6.6`: `815405526aa3` | `6.6.144` | `mt6768-zpd1203-minimal.dts` (`-@`) | `mt6768-zpd1203-minimal.dtb` | 167,757 | `e51835447e6bc11d98f4ab444e1231fad2780745afe4fa54e9056dced790062d` | 已静态验证 (`fdtoverlay` `dtbo_a_0.dtb` 0 错误) |
| 2026-11-24 | `zpd1203/` (`vendor_boot_a` 基线) | - | `build_minimal_ramdisk.sh` | `initramfs-minimal-6.6.cpio.gz` | 15,549,025 | `b36167e843933c6fb1ec8006ac1c25425670f3bce54b45bb939b49a335bfa663` | 已静态验证 (无 Magisk, `HMI` OK, `0` NEEDED) |
| 2026-11-24 | `kernel-6.6`: `a0efcb376f2a`<br>`devmod-6.6`: `815405526aa3` | `6.6.144-zpd1203-ga0efcb376f2a` | `package_boot_minimal.sh` | `boot-minimal-6.6.raw.img` | 27,453,440 | `2ddf9c5d3e5a3d56d8576f3c9540876a0aa74104892e484662526aa4472c1105` | 已静态验证 (Boot v2, DT Table `0xd7b7ab1e`) |
| 2026-11-24 | `kernel-6.6`: `a0efcb376f2a`<br>`devmod-6.6`: `815405526aa3` | `6.6.144-zpd1203-ga0efcb376f2a` | `package_boot_minimal.sh` | `boot-minimal-6.6.img` | 33,554,432 | `387c0d2aa6c794e097cf216d267a7e052a2b7f6eda917917497e663012619cca` | 已静态验证 (`unpack_bootimg` / `avbtool` PASS) |
