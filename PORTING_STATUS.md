# ZPD1203 Linux 6.6 移植进度追踪 (PORTING_STATUS.md)

- **当前阶段**：**已完成第 #2 轮实机 `fbcon` 屏幕栈取证修复与全量重编校验**（`full` 新版 `6.6.144-zpd1203-g92c716870252` + `device_modules` `0d43534325ef` 达 **`已编译通过` / `已静态验证`**）；待用户将平板进入 Fastboot 并确认后刷入 `boot_a` 继续实机测试。
- **目标内核**：**`6.6.144-zpd1203-g92c716870252`**（零 `-dirty` 后缀；`AOSP android15-6.6` `92c716870252` + `Addster09` BSP `0d43534325ef` + Moto GPU `2d3b928b88ce` + Moto Connsys 5 仓）
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
> 已完成两轮实机测试取证：第 #1 轮通过 `pstore` 证实推进至 `t=0.590s` 并修复 `bq2589x`/`usb_prepare_clock`；第 #2 轮实机 `fbcon` + `panic=8` 屏幕栈证实推进至 `t=5.85s` (`late_initcall`) 并定位 `dramc.c` 空指针（详见 [DEBUGGING.md](file:///d:/P3066/DEBUGGING.md)）。新版 `dramc.c` 修复版尚未再次实机启动，各硬件子系统严格维持 **`已编译通过`** / **`已静态验证`** / **`尚未验证`** / **`已知故障`** 标注。

## 构建历史记录（`dramc` 崩溃修复 + 早期屏幕日志终版 `6.6.144-zpd1203-g92c716870252`）

> 全部 8 个 WSL2 Git 仓库均已清洁提交（`clean=True`）；以下全量产物大小与 SHA256 均取自本次重编后 [out/full/SHA256SUMS.txt](file:///d:/P3066/out/full/SHA256SUMS.txt) 与 `scripts/verify_build.sh --mode full` 实测输出；最小诊断模式尚停留在 `g79934f29bfe5` 构建。

### 1. 全量模式 (`mode=full`, `zpd1203_defconfig`, `6.6.144-zpd1203-g92c716870252`)

| 目标产物 | 大小 (Bytes) | SHA256 | 验证状态 |
|---|---|---|---|
| `out/full/Image` | 39,553,536 | `5c619be57ba0836598ca0595704781a98f215336f88f323ca401687134e389d5` | 已编译通过 (`ARM\x64` 有效) |
| `out/full/Image.gz` | 15,795,420 | `e4b916d4a675dac29a66f530a5f2e8d61a07173cf4a465c43f5c48be6b9b46a6` | 已编译通过 (Banner 无 `-dirty`, 含 `FB_SIMPLE` + `fbcon` + `U_SERIAL_CONSOLE`) |
| `out/full/mt6768-zpd1203.dtb` | 172,706 | `f2f36e351558e61e8b5a73ee56eed923b530f00ff3fae01e20509f4992b7545e` | 已静态验证 (`fdtoverlay` `dtbo_a_0.dtb` -> 202,917 B, `chosen/framebuffer0=okay`) |
| `out/full/dtb-full-6.6.dtimg` | 172,770 | `290fc69e289664f3cb800ccec3237c2bf84d0882272978e9640956a740848fca` | 已静态验证 (DT Table `0xd7b7ab1e`) |
| `out/full/initramfs-full-6.6.cpio.xz` | 12,355,772 | `bdc6e521fcf2781540023dbac798f5e2498dc678bea7e312a60b0bec26a5d0c0` | 已静态验证 (`xz --check=crc32`, 含 11 枚 `.ko` + 早期/守护 COM 包装器) |
| `out/full/boot-full-6.6.raw.img` | 28,329,984 | `14106e2bbe55d35035e988e1fd51949d24d9d2181c2ed4886b0ff29a9207f74c` | 已静态验证 (Boot v2, `< 32 MiB`, 含 `console=tty0 fbcon=rotate:3,font:TER16x32 panic=8`) |
| `out/full/boot-full-6.6.img` | 33,554,432 | `e6643dbe48d397870c2e453ebd8e0a9ef1773a7d3be2db53cfe57f05e3279957` | 已静态验证 (`avbtool` + `unpack_bootimg` + `verify_build.sh` PASS) |
| `out/full/modules/*.ko` (11 枚 Stripped) | 10,432,680 (总和) | 见 [out/full/SHA256SUMS.txt](file:///d:/P3066/out/full/SHA256SUMS.txt) | 已静态验证 (`vermagic=6.6.144-zpd1203-g92c716870252`, CRC `0x2933d34f`, 0 undef) |

#### 全量模式 11 枚内核模块明细 (`vermagic=6.6.144-zpd1203-g92c716870252`, CRC `0x2933d34f`)

| 模块 | Stripped 大小 (B) | Unstripped 大小 (B) | Stripped SHA256 | Unstripped SHA256 | 符号闭环 |
|---|---|---|---|---|---|
| `mali_mgm_mt6768.ko` | 24,696 | 211,592 | `5f976d10...` | `949aba83...` | 0 undef (PASS) |
| `mali_kbase_mt6768.ko` | 1,093,016 | 14,922,112 | `49574d42...` | `6a9e6f1e...` | 0 undef (PASS) |
| `rfkill.ko` | 51,400 | 266,016 | `0b747bd1...` | `5fba3f27...` | 0 undef (PASS) |
| `cfg80211.ko` | 1,649,040 | 7,500,112 | `fb40b327...` | `e4866c81...` | 0 undef (PASS) |
| `btif_drv.ko` | 198,872 | 806,560 | `ac00c28d...` | `d26809bc...` | 0 undef (PASS) |
| `conn_md_drv.ko` | 50,912 | 338,992 | `56212042...` | `17c13a66...` | 0 undef (PASS) |
| `connfem.ko` | 172,856 | 741,744 | `fb673c03...` | `a14e7e18...` | 0 undef (PASS) |
| `wmt_drv.ko` | 1,699,032 | 6,496,520 | `e2b70394...` | `6c9f26d5...` | 0 undef (PASS) |
| `wmt_chrdev_wifi.ko` | 52,312 | 318,728 | `d92707c9...` | `ffd5b9c4...` | 0 undef (PASS) |
| `bt_drv_connac1x.ko` | 96,208 | 658,800 | `20d072c4...` | `8e0e16bd...` | 0 undef (PASS) |
| `wlan_drv_gen4m.ko` | 5,344,336 | 49,593,112 | `b179e903...` | `3ead9da9...` | 0 undef (PASS) |

### 2. 最小诊断模式 (`mode=minimal`, `zpd1203_minimal_defconfig`, 前一基线 `6.6.144-zpd1203-g79934f29bfe5`)

| 目标产物 | 大小 (Bytes) | SHA256 | 验证状态 |
|---|---|---|---|
| `out/minimal/Image` | 28,723,712 | `8636ca36c34d37f41a0c71b178bcea101b184a03b8fc1c5417172c59e1a2d4aa` | 已编译通过 |
| `out/minimal/Image.gz` | 11,822,003 | `dc9feb02872e1d9899564c881b219bc66e7bb158963eebcf0002a009aff0026e` | 已编译通过 (含 `fbcon` + `U_SERIAL_CONSOLE`) |
| `out/minimal/mt6768-zpd1203-minimal.dtb` | 167,757 | `e51835447e6bc11d98f4ab444e1231fad2780745afe4fa54e9056dced790062d` | 已静态验证 (`fdtoverlay` -> 199,454 B, 0 错误) |
| `out/minimal/dtb-minimal-6.6.dtimg` | 167,821 | `3c5781ebbb6e41beae2ef26c4ba3b857af119c3a9c291b8f8b744ab3db1c4948` | 已静态验证 (`0xd7b7ab1e`) |
| `out/minimal/initramfs-minimal-6.6.cpio.gz` | 15,588,412 | `b8a07f009d1eb5b0cab2da9508b4eec145f11ba94804ce241d88a7caeeb37e89` | 已静态验证 (`gzip`, 更新版早期/守护 COM 包装器) |
| `out/minimal/boot-minimal-6.6.raw.img` | 27,582,464 | `218581ecc34caffb026772419883730a25dc5c760f532495f3d12501895f8ae3` | 已静态验证 (Boot v2, `< 32 MiB`, `console=tty0 fbcon=rotate:3,font:TER16x32`) |
| `out/minimal/boot-minimal-6.6.img` | 33,554,432 | `1a46703ac04fa6601263ceecded485aac7f4bec290bc71a3d78602da85ec19ae` | 已静态验证 (`avbtool` + `unpack_bootimg` + `verify_build.sh` PASS) |
