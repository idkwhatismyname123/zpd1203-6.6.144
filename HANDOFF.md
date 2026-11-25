# 当前工作现场交接文档 (HANDOFF.md)

- **最后更新**：2026-11-25
- **当前状态**：**第 #7 轮（`6.6.144-zpd1203-@idkwhatismyname123` `#7` + Wi-Fi/BT 时序修复 + 内核态 MT6358 电量算法 + `fbcon=map:9`）已刷入 `boot_a` 并`已实机验证`进入 Android 桌面**：
  - `uname -a`: `Linux localhost 6.6.144-zpd1203-@idkwhatismyname123 #7 SMP PREEMPT Wed Nov 25 15:51:49 AEST 2026 aarch64 Toybox`
  - `sys.boot_completed=1`、`lsmod` 全部 11 枚 `.ko` 已加载（`bt_drv_connac1x` `Used by 1`、`mali_kbase_mt6768` `Used by 15`）
  - **Wi-Fi**：`emi_mem_init` 获取 `pa=0xbf000000 size=0x400000`，`FW_START EVT success!!` / `WMT turn on WIFI success!`，`wlan0`（`<wlan-mac>`）启用并扫到 2.4G/5G AP；
  - **蓝牙**：`WMT turn on BT OK!`、`STP is ready!`，`dumpsys bluetooth_manager` 显示 `enabled: true` / `state: ON`（`<bt-mac>`、0 crash）；
  - **电池电量**：`fgauge` 运行 `algo:1`（`soc:89 uisoc:89 vbat:4313`），`dumpsys battery` 与 `battery/uevent` 上报 `89%`（`Charge counter: 2621940`）。
  - 既有已实机验证项：`Mali-G52 MC2` OpenGL ES 3.2、Himax `HX83102J` 触屏/手写笔、`mt6768-mt6358` + `aw87xxx@59/5A`、`lcd-backlight`、`sgm41510` 充电、`ADB+COM`、`fbcon=map:9`（`vtconsole` 仅存 `vtcon0`）。

## 1. 洁净源码仓库基线（全部 8 个 WSL2 仓库均已提交且 `clean=True`，零 `-dirty`）

| 仓库路径 (`/home/asus/zpd1203-6.6/...`) | 分支 | Clean HEAD | 说明 |
|---|---|---|---|
| `kernel/kernel-6.6` | `zpd1203-6.6` | `abae8068d6e7` | Linux 6.6.144 (`android15-6.6`) + KernelSU v3.3.1 + `sysirq` + `force_slot_a=1` + `simplefb` + `aw37503` + `CONFIG_LOG_BUF_SHIFT=20` + `CONFIG_LOCALVERSION="-zpd1203-@idkwhatismyname123"` (`LOCALVERSION_AUTO=n`) |
| `kernel/kernel_device_modules-6.6` | `zpd1203-6.6` | `8f118e0bd30b` | `Addster09` BSP + DRM v2 / `jt120wul005` / `hxchipset` / `sgm41510` / `musb`/`dramc` 防护 / GED 18/22-region 兼容 / `i2c2-4 ch-offset-i2c=0x100` & `aw87xxx` / **`mediatek,kernel-fuel-gauge` 内核态 MT6358 电量算法** |
| `modules/gpu` | `zpd1203-6.6` | `2d3b928b88ce` | Moto GPU `mali-r32p1` (`r32p1-01eac0`, `platform/mt6768` + `minmax.h` clang-21 fix) |
| `modules/connectivity/common` | `android-15-release-vvta35.58-77-1` | `0fd4f365ead4` | Moto `wmt_drv.ko`（0 修改 clean） |
| `modules/connectivity/connfem` | `android-15-release-vvta35.58-77-1` | `8a665a04c769` | Moto `connfem.ko`（0 修改 clean） |
| `modules/connectivity/bt/mt66xx` | `android-15-release-vvta35.58-77-1` | `95859aaae7f4` | Moto `bt_drv_connac1x.ko`（0 修改 clean） |
| `modules/connectivity/wlan/adaptor` | `android-15-release-vvta35.58-77-1` | `48e9f37a18b7` | Moto `wmt_chrdev_wifi.ko`（0 修改 clean） |
| `modules/connectivity/wlan/core/gen4m` | `android-15-release-v1tl35.73-60-3` | `0eb4c16595f3` | Moto `wlan_drv_gen4m.ko`（0 修改 clean） |

- 输出内核版本标识：**`6.6.144-zpd1203-@idkwhatismyname123`**（`CONFIG_LOCALVERSION="-zpd1203-@idkwhatismyname123"` + `# CONFIG_LOCALVERSION_AUTO is not set` + `build_kernel.sh` `LOCALVERSION=""` 抑制 `+`）。
- 全套 `git format-patch`（27 份补丁，含 `patches/phase7_pstore_fixes/` `device_modules` `0003`/`0004`/`0005` 与 `kernel-6.6` `0002`/`0003`）、DTS/DTSI、config、分析报告（5 份）与脚本已完整保存至 `d:\P3066\`。

## 2. 已实机验证当前交付产物（`full`: `6.6.144-zpd1203-@idkwhatismyname123` + Wi-Fi/BT/电量修复 + `fbcon=map:9`，已刷入 `boot_a`；`minimal` 仍为 `g79934f29bfe5`）

- **全量产物**（`d:\P3066\out\full\`，校验详见 `out\full\SHA256SUMS.txt`）：
  - `boot-full-6.6.img`：`33,554,432 B`（SHA256 `4ff3be3bdf82e4125aae862a7c2c58324697053e86a73bf549cad8c5651bda58`，raw `5ca3f842dc282c2f1d42281a087d74b501b76d0a588c05fce4e4068850b24630` / `28,336,128 B`，命令行含 `console=ttyS0,921600n1 fbcon=map:9 panic=8 printk.devkmsg=on loglevel=4 ... androidboot.mode=normal androidboot.selinux=permissive`）
  - `Image` (`42,764,800 B`), `Image.gz` (`15,799,522 B`), `mt6768-zpd1203.dtb` (`172,925 B`, `fdtoverlay` `203,136 B` PASS), `initramfs-full-6.6.cpio.xz` (`12,359,368 B`)
  - 11 枚 stripped `.ko`（`modules/*.ko`）与对应 11 枚调试 unstripped `.ko`（`unstripped/*.ko`），全部通过 `vermagic=6.6.144-zpd1203-@idkwhatismyname123` / `module_layout` CRC `0x2933d34f` / `llvm-nm` 0 未定义符号闭环。
- **最小诊断保底产物**（`d:\P3066\out\minimal\`，前一构建 `g79934f29bfe5`）：
  - `boot-minimal-6.6.img`：`33,554,432 B`（SHA256 `1a46703ac04fa6601263ceecded485aac7f4bec290bc71a3d78602da85ec19ae`）

## 3. 只读保护与测试约束
- 原厂分区备份 `D:\备份\p\GeekFlashTool_Readback_20260820162108246` 及 `/home/asus/{zpd1203-5.10.240,zpd1203,mt6768_build}` 全程未被修改。
- 实机 `expdb` 已证实原厂 `lk_a.img` 执行 `fastboot boot` 会因 `boot image is NULL` 触发 LK Panic；**实机测试需经用户明确确认后刷入 `boot_a`**（并可随时用 [restore_stock.ps1](file:///d:/P3066/scripts/restore_stock.ps1) 还原）。

## 4. 下一步实机体验与可选优化建议
1. **端到端体验测试**：在桌面实测连接 Wi-Fi 上网、蓝牙耳机/HID 配对与媒体外放、横屏触摸/手写笔与休眠唤醒。
2. **原生 `mediatek-drm`（可选）**：排查 `disp_ovl0@1400b000: could not find phandle 262144`（及 `262145`/`262146`）导致当前走 `fb0_bridge` 回退的问题。
3. **充电细节（可选）**：核对拔插充电器与持续充电期间电流符号/充满状态联动。
