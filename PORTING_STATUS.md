# ZPD1203 Linux 6.6 移植进度追踪 (PORTING_STATUS.md)

- **当前阶段**：**Phase 0–7 宿主机开发、屏幕日志 (`fbcon`) + 早/晚全链路 USB COM 口改造、洁净集成构建与静态校验已全部完成**（`full` + `minimal` 双模式均达 **`已编译通过` / `已静态验证`**）；待用户在真机执行非破坏性测试并返回实机日志。
- **目标内核**：**`6.6.144-zpd1203-g79934f29bfe5`**（零 `-dirty` 后缀；`AOSP android15-6.6` `79934f29bfe5` + `Addster09` BSP `398a4dd27ef0` + Moto GPU `2d3b928b88ce` + Moto Connsys 5 仓）
- **原厂基线**：ZYB Android 12 (`vendor_boot_a.img` 4.19.191 / VNDK 31，`super` 含 LineageOS 21 Android 14 GSI `system_a`)
- **参考移植**：`idkwhatismyname123/zpd1203-5.10.240` (`test25` / `8a74a527`)

## 阶段里程碑状态

| 阶段 | 描述 | 状态 | 备注 |
|---|---|---|---|
| Phase 0 | 工程文档、Git 仓库与 WSL2 工具链检查 | 已完成 | 8 份规范文档 + WSL2 工具链校验通过 |
| Phase 1 | 5.10 仓库深度解析 + 原厂备份只读提取分析 | 已完成 | `analysis/phase1_510_port_analysis.md` & `analysis/phase1_stock_analysis.md` |
| Phase 2 | 六系内核源码调查与基底选型 | 已完成 | `analysis/phase2_bsp_survey.md`，定案 Linux 6.6.144 组合架构 |
| Phase 3 | 核心板级支持迁移（DTS/时钟/PMIC/存储/USB/Android核心） | 已编译通过 / 已静态验证 | 补丁归档 `patches/phase3_4/` |
| Phase 4 | 无 UART 调试体系与最小可启动内核构建 | 已编译通过 / 已静态验证 | 更新版 `out/minimal/boot-minimal-6.6.img` (Boot v2, `< 32 MiB`) |
| Phase 5 | 完整硬件驱动（DRM 显示/触屏/GPU/无线/音频/SGM41510+AW35615充电/Thermal） | 已编译通过 / 已静态验证 | 补丁 `patches/phase5_display_gpu_touch/` + `patches/phase5_wireless_audio_power/`；摄像头 EL2 依赖标为 `已知故障` |
| Phase 6 | Android 12 Vendor ABI 兼容（`/dev/ion` -> DMA-BUF Heap `mtk_mm` + `a12_init_wrapper`） | 已编译通过 / 已静态验证 | 补丁 `patches/phase6_abi/`；见 `analysis/phase6_7_abi_tooling.md` |
| Phase 7 | 主配置固化、全自动化构建/校验/安全测试与恢复脚本 + 屏幕日志 (`fbcon`) & COM 口增强 | 已编译通过 / 已静态验证 | 补丁 `patches/phase7_defconfig/` + `patches/phase7_console_com/`；新增 `scripts/watch_com.ps1`；`full` + `minimal` 均 PASS |

## 实机测试说明
> 当前尚未进行任何实机刷机或启动测试。所有主机端编译与静态校验产出均严格标注为 **`已编译通过`** 或 **`已静态验证`**，绝不使用 `已实机验证`。

## 构建历史记录（屏幕日志 + USB COM 增强终版 `6.6.144-zpd1203-g79934f29bfe5`）

> 全部 8 个 WSL2 Git 仓库均已清洁提交（`clean=True`）；以下全部大小与 SHA256 均取自本次重构后 `d:\P3066\out\{full,minimal}\SHA256SUMS.txt` 与 `scripts/verify_build.sh` 实测输出。

### 1. 全量模式 (`mode=full`, `zpd1203_defconfig`)

| 目标产物 | 大小 (Bytes) | SHA256 | 验证状态 |
|---|---|---|---|
| `out/full/Image` | 39,553,536 | `bab87b275b04d6a06571aa8e3e18d672e914fe011585d5e365a97c3a9b2944da` | 已编译通过 (`ARM\x64` 有效) |
| `out/full/Image.gz` | 15,780,023 | `ac555aa4e5df716ad37fc55bf9c2819c01317c29f4365f32c0989350d61ca3c4` | 已编译通过 (Banner 无 `-dirty`, 含 `fbcon` + `U_SERIAL_CONSOLE`) |
| `out/full/mt6768-zpd1203.dtb` | 172,563 | `435b65dd9cd1af5f60aec83aa4ee34520a6bfb5c07299d4f1e9a929ade3a2e83` | 已静态验证 (`fdtoverlay` `dtbo_a_0.dtb` -> 202,774 B, 0 错误) |
| `out/full/dtb-full-6.6.dtimg` | 172,627 | `6f5e3777816f1b29ee5ef5d992c47a71d311a160bc775ff95c7eec5311e86840` | 已静态验证 (DT Table `0xd7b7ab1e`) |
| `out/full/initramfs-full-6.6.cpio.xz` | 12,361,976 | `83116c95e1f3c8c2a2aa14b586412c2f64bb9f885bf9ab7fb3a60821e3dc9708` | 已静态验证 (`xz --check=crc32`, 含 11 枚 `.ko` + 早期/守护 COM 包装器) |
| `out/full/boot-full-6.6.raw.img` | 28,321,792 | `fbe0fc7c10e95e99f7674faa12f13b409d5edd313c850b841beab3b4ec0f082c` | 已静态验证 (Boot v2, `< 32 MiB`, `console=tty0 fbcon=rotate:3,font:TER16x32`) |
| `out/full/boot-full-6.6.img` | 33,554,432 | `7bd488a642eab7220d9f8cc9b00df6e7be61e216e25652c9bbf4e2e41709bc49` | 已静态验证 (`avbtool` + `unpack_bootimg` + `verify_build.sh` PASS) |
| `out/full/modules/*.ko` (11 枚 Stripped) | 10,432,680 (总和) | 见 [out/full/SHA256SUMS.txt](file:///d:/P3066/out/full/SHA256SUMS.txt) | 已静态验证 (`vermagic=6.6.144-zpd1203-g79934f29bfe5`, CRC `0x2933d34f`, 0 undef) |

#### 全量模式 11 枚内核模块明细 (`vermagic=6.6.144-zpd1203-g79934f29bfe5`, CRC `0x2933d34f`)

| 模块 | Stripped 大小 (B) | Unstripped 大小 (B) | Stripped SHA256 | Unstripped SHA256 | 符号闭环 |
|---|---|---|---|---|---|
| `mali_mgm_mt6768.ko` | 24,696 | 211,592 | `b9dd36e6...` | `ab2e8553...` | 0 undef (PASS) |
| `mali_kbase_mt6768.ko` | 1,093,016 | 14,922,112 | `6bd1ba54...` | `7c7a118b...` | 0 undef (PASS) |
| `rfkill.ko` | 51,400 | 266,016 | `2c47dda4...` | `18fd3211...` | 0 undef (PASS) |
| `cfg80211.ko` | 1,649,040 | 7,500,112 | `b52cca87...` | `0ebf7e42...` | 0 undef (PASS) |
| `btif_drv.ko` | 198,872 | 806,560 | `e69a08d4...` | `630fe0bc...` | 0 undef (PASS) |
| `conn_md_drv.ko` | 50,912 | 338,992 | `2adbb1a0...` | `457e219a...` | 0 undef (PASS) |
| `connfem.ko` | 172,856 | 741,744 | `d9cfac55...` | `a3a404fa...` | 0 undef (PASS) |
| `wmt_drv.ko` | 1,699,032 | 6,496,520 | `b68524f3...` | `64ea4e6a...` | 0 undef (PASS) |
| `wmt_chrdev_wifi.ko` | 52,312 | 318,728 | `cc9a0a04...` | `afc45321...` | 0 undef (PASS) |
| `bt_drv_connac1x.ko` | 96,208 | 658,800 | `ccf1ec48...` | `26a50666...` | 0 undef (PASS) |
| `wlan_drv_gen4m.ko` | 5,344,336 | 49,593,112 | `c89f6151...` | `7c8ba0df...` | 0 undef (PASS) |

### 2. 最小诊断模式 (`mode=minimal`, `zpd1203_minimal_defconfig`)

| 目标产物 | 大小 (Bytes) | SHA256 | 验证状态 |
|---|---|---|---|
| `out/minimal/Image` | 28,723,712 | `8636ca36c34d37f41a0c71b178bcea101b184a03b8fc1c5417172c59e1a2d4aa` | 已编译通过 |
| `out/minimal/Image.gz` | 11,822,003 | `dc9feb02872e1d9899564c881b219bc66e7bb158963eebcf0002a009aff0026e` | 已编译通过 (含 `fbcon` + `U_SERIAL_CONSOLE`) |
| `out/minimal/mt6768-zpd1203-minimal.dtb` | 167,757 | `e51835447e6bc11d98f4ab444e1231fad2780745afe4fa54e9056dced790062d` | 已静态验证 (`fdtoverlay` -> 199,454 B, 0 错误) |
| `out/minimal/dtb-minimal-6.6.dtimg` | 167,821 | `3c5781ebbb6e41beae2ef26c4ba3b857af119c3a9c291b8f8b744ab3db1c4948` | 已静态验证 (`0xd7b7ab1e`) |
| `out/minimal/initramfs-minimal-6.6.cpio.gz` | 15,588,412 | `b8a07f009d1eb5b0cab2da9508b4eec145f11ba94804ce241d88a7caeeb37e89` | 已静态验证 (`gzip`, 更新版早期/守护 COM 包装器) |
| `out/minimal/boot-minimal-6.6.raw.img` | 27,582,464 | `218581ecc34caffb026772419883730a25dc5c760f532495f3d12501895f8ae3` | 已静态验证 (Boot v2, `< 32 MiB`, `console=tty0 fbcon=rotate:3,font:TER16x32`) |
| `out/minimal/boot-minimal-6.6.img` | 33,554,432 | `1a46703ac04fa6601263ceecded485aac7f4bec290bc71a3d78602da85ec19ae` | 已静态验证 (`avbtool` + `unpack_bootimg` + `verify_build.sh` PASS) |
