# ZPD1203 Linux 6.6 移植进度追踪 (PORTING_STATUS.md)

- **当前阶段**：**已实机验证第 #7 轮（`6.6.144-zpd1203-@idkwhatismyname123` + `fbcon=map:9` + Wi-Fi/BT 时序修复 + 内核态 MT6358 电量算法）**：成功进入桌面（`sys.boot_completed=1`）、**Wi-Fi 已实机上线并扫到 2.4G/5G AP**、**蓝牙已开启 `state: ON`（零 crash）**、**电池百分比已实机上报 `89%`（`Charge counter: 2621940`, `algo:1`）**，加上此前已实机验证的 `Mali-G52 MC2` GLES 3.2、Himax 触屏/手写笔、音频、`sgm41510` USB 充电及 `ADB + COM`。
- **目标内核**：**`6.6.144-zpd1203-@idkwhatismyname123`**（零 `-g<sha>` / `+` / `-dirty` 后缀；`AOSP android15-6.6` `abae8068d6e7` + `Addster09` BSP `8f118e0bd30b` + Moto GPU `2d3b928b88ce` + Moto Connsys 5 仓）
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
> - **第 #7 轮（当前平板实机运行版本：`6.6.144-zpd1203-@idkwhatismyname123` `#7`，`boot_a`）**：已通过 Fastboot 刷入 [boot-full-6.6.img](file:///d:/P3066/out/full/boot-full-6.6.img)（`4ff3be3bdf82e4125aae862a7c2c58324697053e86a73bf549cad8c5651bda58`）并**`已实机验证`**：
>   - **系统与模块**：`uname -a` 为 `Linux localhost 6.6.144-zpd1203-@idkwhatismyname123 #7 SMP PREEMPT Wed Nov 25 15:51:49 AEST 2026 aarch64 Toybox`、`sys.boot_completed=1`、`lsmod` 全部 11 枚 `.ko` 加载（`bt_drv_connac1x` `Used by 1`、`mali_kbase_mt6768` `Used by 15`）。
>   - **Wi-Fi**：`emi_mem_init` 获取 `pa=0xbf000000 size=0x400000`；开启 Wi-Fi 后 `wlanProbe` / `FW_START EVT success!!` / `WMT turn on WIFI success!`，`wlan0`（`<wlan-mac>`）`<UP>`，`cmd wifi list-scan-results` 实测扫出 多个 2.4 GHz 与 5 GHz 周边热点；关联 Wi-Fi 上网尚待实际连接测试。
>   - **蓝牙**：`OPID(3) type(0) ok`、`WMT turn on BT OK!`、`STP is ready!`，`dumpsys bluetooth_manager` 显示 `enabled: true`、`state: ON`、`address: <bt-mac>`、`Bluetooth crashed 0 times`，A2DP/AVRCP/HFP/HID Profile 已就绪；实际配对音频传输尚待实机测试。
>   - **电池电量百分比**：`fgauge` 运行 `algo:1`（`soc:89 uisoc:89 vbat:4313 baton:695`），`dumpsys battery` 与 `/sys/class/power_supply/battery/uevent` 均显示 `level: 89` / `POWER_SUPPLY_CAPACITY=89`、`Charge counter: 2621940`、`CHARGE_FULL=2946000`、`TIME_TO_FULL_NOW=98865`、`status: Charging`。
> - **第 #5 / #6 轮既有实机确认项**：`COM20` + `ADB+COM`（`0x0e8d:0x2006`）[logs_20261125_140716](file:///d:/P3066/out/logs_20261125_140716)、`Mali-G52 MC2` OpenGL ES 3.2 `v1.r32p1-01eac0`、Himax `HX83102J` 触屏/手写笔、`mt6768-mt6358` + `aw87xxx@59/5A`、`lcd-backlight`、`sgm41510` USB 充电在线、`fbcon=map:9` 永久禁用屏幕跑码（`vtconsole` 仅存 `vtcon0`）。待进一步打磨项：`disp_ovl0@1400b000` 缺 phandle `262144` 导致的原生 `mediatek-drm` 回退（当前走 `fb0_bridge`），以及 Wi-Fi 联网、蓝牙配对、扬声器外放的端到端实机使用测试。

## 构建历史记录（当前实机版本 `full` `6.6.144-zpd1203-@idkwhatismyname123`，含 Wi-Fi/BT/电量修复 + `fbcon=map:9`）

> 全部 8 个 WSL2 Git 仓库均已清洁提交（`clean=True`）；以下全量产物大小与 SHA256 均取自本次实机验证版本 [out/full/SHA256SUMS.txt](file:///d:/P3066/out/full/SHA256SUMS.txt) 与 `scripts/verify_build.sh --mode full` 实测输出；最小诊断模式配置已同步更新至 `@idkwhatismyname123`（尚未重编，仍保留 `g79934f29bfe5` 构建产物）。

### 1. 全量模式 (`mode=full`, `zpd1203_defconfig`, `6.6.144-zpd1203-@idkwhatismyname123`)

| 目标产物 | 大小 (Bytes) | SHA256 | 验证状态 |
|---|---|---|---|
| `out/full/Image` | 42,764,800 | `e7ea2d2b4d46d6e27aab41d295e7064303ed2b0a0c0ec9f3bbf6d70b1d6b09f7` | 已实机验证 (`6.6.144-zpd1203-@idkwhatismyname123`, 内核态电量 `89%`) |
| `out/full/Image.gz` | 15,799,522 | `30e60d77e853e1fea053cc3b26b0293ef4aa67a0cc270f32500c803238e300ba` | 已实机验证 (Banner 含 `6.6.144-zpd1203-@idkwhatismyname123`, 无 `-dirty`) |
| `out/full/mt6768-zpd1203.dtb` | 172,925 | `882c53f7de489df845f83c3bd482be058ee5e369c800c07e5c7b0eac95aadf2e` | 已实机验证 (`fdtoverlay` `dtbo_a_0.dtb` -> 203,136 B, 含 `mediatek,kernel-fuel-gauge`) |
| `out/full/dtb-full-6.6.dtimg` | 172,989 | `f35dffb2eb982b89e6169fe1482bb6afa5a250f0f82bb0081649187073985126` | 已实机验证 (DT Table `0xd7b7ab1e`) |
| `out/full/initramfs-full-6.6.cpio.xz` | 12,359,368 | `46707071b04761a7f62e6ea61e69a78d75503f43a503457455cd688a1d40c365` | 已实机验证 (`xz --check=crc32`, `a12_init_wrapper` 延迟无线加载 + 11 `.ko`) |
| `out/full/boot-full-6.6.raw.img` | 28,336,128 | `5ca3f842dc282c2f1d42281a087d74b501b76d0a588c05fce4e4068850b24630` | 已实机验证 (Boot v2, `< 32 MiB`, `fbcon=map:9 loglevel=4 panic=8 androidboot.selinux=permissive`) |
| `out/full/boot-full-6.6.img` | 33,554,432 | `4ff3be3bdf82e4125aae862a7c2c58324697053e86a73bf549cad8c5651bda58` | 已实机验证 (已刷 `boot_a`, 桌面 + Wi-Fi + BT + 电量全通, `verify_build.sh` PASS) |
| `out/full/modules/*.ko` (11 枚 Stripped) | 10,432,144 (总和) | 见 [out/full/SHA256SUMS.txt](file:///d:/P3066/out/full/SHA256SUMS.txt) | 已实机验证 (`vermagic=6.6.144-zpd1203-@idkwhatismyname123`, `lsmod` 11/11 已加载) |

#### 全量模式 11 枚内核模块明细 (`vermagic=6.6.144-zpd1203-@idkwhatismyname123`, CRC `0x2933d34f`)

| 模块 | Stripped 大小 (B) | Unstripped 大小 (B) | Stripped SHA256 | Unstripped SHA256 | 符号闭环 |
|---|---|---|---|---|---|
| `mali_mgm_mt6768.ko` | 24,696 | 211,592 | `0117d32e...` | `94549d31...` | 0 undef (PASS) |
| `mali_kbase_mt6768.ko` | 1,093,016 | 14,922,112 | `aad8690e...` | `b293da6b...` | 0 undef (PASS) |
| `rfkill.ko` | 51,344 | 265,896 | `dd33e73b...` | `c119e88b...` | 0 undef (PASS) |
| `cfg80211.ko` | 1,648,992 | 7,499,992 | `c100a575...` | `d43d2bd9...` | 0 undef (PASS) |
| `btif_drv.ko` | 198,752 | 806,376 | `8e770eef...` | `577fb5d3...` | 0 undef (PASS) |
| `conn_md_drv.ko` | 50,800 | 338,808 | `76804765...` | `774b0683...` | 0 undef (PASS) |
| `connfem.ko` | 172,808 | 741,640 | `5ca8d556...` | `925dd1f0...` | 0 undef (PASS) |
| `wmt_drv.ko` | 1,698,976 | 6,496,400 | `4555b252...` | `e143ba45...` | 0 undef (PASS) |
| `wmt_chrdev_wifi.ko` | 52,264 | 318,616 | `182c2b8e...` | `3b186e98...` | 0 undef (PASS) |
| `bt_drv_connac1x.ko` | 96,208 | 658,800 | `774137ac...` | `79b1d1cf...` | 0 undef (PASS) |
| `wlan_drv_gen4m.ko` | 5,344,288 | 49,592,976 | `c066e806...` | `79e30427...` | 0 undef (PASS) |

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
