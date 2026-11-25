# 当前工作现场交接文档 (HANDOFF.md)

- **最后更新**：2026-11-25
- **当前状态**：已完成 **Wi-Fi / 蓝牙时序修复**（`a12_init_wrapper` 推迟 `wmt_chrdev_wifi.ko` / `bt_drv_connac1x.ko` / `wlan_drv_gen4m.ko` 加载至 vendor `vendor.connsys.driver.ready=yes`）与 **MT6358 内核态电量算法启用**（`mediatek,kernel-fuel-gauge` + `mtk_battery.c` + `mtk-battery-manager.c`）的全量重编与静态校验（**`已编译通过 / 已静态验证`，尚未刷机**）。上一版（#6 `6.6.144-zpd1203-@idkwhatismyname123` + `fbcon=map:9`）已刷入 `boot_a` 并`已实机验证`进入桌面（`sys.boot_completed=1`、`vtconsole` 仅存 `vtcon0`）；待用户确认后重启至 fastboot 并刷入本新版 [boot-full-6.6.img](file:///d:/P3066/out/full/boot-full-6.6.img) 验证 Wi-Fi、蓝牙与电池电量。

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

## 2. 已静态验证最新交付产物（`full`: `6.6.144-zpd1203-@idkwhatismyname123` + Wi-Fi/BT/电量修复 + `fbcon=map:9`，待刷入 `boot_a` 实测；`minimal` 仍为 `g79934f29bfe5`）

- **全量产物**（`d:\P3066\out\full\`，校验详见 `out\full\SHA256SUMS.txt`）：
  - `boot-full-6.6.img`：`33,554,432 B`（SHA256 `4ff3be3bdf82e4125aae862a7c2c58324697053e86a73bf549cad8c5651bda58`，raw `5ca3f842dc282c2f1d42281a087d74b501b76d0a588c05fce4e4068850b24630` / `28,336,128 B`，命令行含 `console=ttyS0,921600n1 fbcon=map:9 panic=8 printk.devkmsg=on loglevel=4 ... androidboot.mode=normal androidboot.selinux=permissive`）
  - `Image` (`42,764,800 B`), `Image.gz` (`15,799,522 B`), `mt6768-zpd1203.dtb` (`172,925 B`, `fdtoverlay` `203,136 B` PASS), `initramfs-full-6.6.cpio.xz` (`12,359,368 B`)
  - 11 枚 stripped `.ko`（`modules/*.ko`）与对应 11 枚调试 unstripped `.ko`（`unstripped/*.ko`），全部通过 `vermagic=6.6.144-zpd1203-@idkwhatismyname123` / `module_layout` CRC `0x2933d34f` / `llvm-nm` 0 未定义符号闭环。
- **最小诊断保底产物**（`d:\P3066\out\minimal\`，前一构建 `g79934f29bfe5`）：
  - `boot-minimal-6.6.img`：`33,554,432 B`（SHA256 `1a46703ac04fa6601263ceecded485aac7f4bec290bc71a3d78602da85ec19ae`）

## 3. 只读保护与测试约束
- 原厂分区备份 `D:\备份\p\GeekFlashTool_Readback_20260820162108246` 及 `/home/asus/{zpd1203-5.10.240,zpd1203,mt6768_build}` 全程未被修改。
- 实机 `expdb` 已证实原厂 `lk_a.img` 执行 `fastboot boot` 会因 `boot image is NULL` 触发 LK Panic；**实机测试需经用户明确确认后刷入 `boot_a`**（并可随时用 [restore_stock.ps1](file:///d:/P3066/scripts/restore_stock.ps1) 还原）。

## 4. 下一步实机验证与后续优化
1. 经用户确认后执行 `adb reboot bootloader` 并将新版 [boot-full-6.6.img](file:///d:/P3066/out/full/boot-full-6.6.img)（`4ff3be3bdf82e4125aae862a7c2c58324697053e86a73bf549cad8c5651bda58`）刷入 `boot_a` 验证 Wi-Fi（`wlan0`）、蓝牙（`/dev/stpbt`）及电池百分比（`battery/capacity`、`dumpsys battery`）。
2. 后续视需要继续排查原生 `mediatek-drm`（`disp_ovl0@1400b000: could not find phandle 262144`）及音频/日常外设体验。
