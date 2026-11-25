# 当前工作现场交接文档 (HANDOFF.md)

- **最后更新**：2026-11-25
- **当前状态**：已完成首版 `boot-full-6.6.img` 实机 `pstore`/`expdb` 崩溃取证（定位为 `bq2589x` -> `Charger_Detect_Init` -> `usb_prepare_clock` 空 `glue` 指针 Panic，且 `expdb` 确认原厂 LK `fastboot boot` 报 `boot image is NULL`），**已完成内核/DTS/DRM aperture/`panic=8` 修复并清洁重编通过新版 `full` (`6.6.144-zpd1203-g92c716870252`)**；平板当前安全处于原厂 Android 4.19 (`boot_a` 已恢复)，等待用户确认再次进入 Fastboot 刷入新版 `boot-full-6.6.img` 测试。

## 1. 洁净源码仓库基线（全部 8 个 WSL2 仓库均已提交且 `clean=True`，零 `-dirty`）

| 仓库路径 (`/home/asus/zpd1203-6.6/...`) | 分支 | Clean HEAD | 说明 |
|---|---|---|---|
| `kernel/kernel-6.6` | `zpd1203-6.6` | `92c716870252` | Linux 6.6.144 (`android15-6.6`) + KernelSU v3.3.1 + `sysirq` + `force_slot_a=1` + `simplefb` + `aw37503` + `zpd1203{_minimal}_defconfig`（`full` 已启用 `CONFIG_FB_SIMPLE=y` + `fbcon`/`TER16x32`/`DEVTMPFS`/`U_SERIAL_CONSOLE`） |
| `kernel/kernel_device_modules-6.6` | `zpd1203-6.6` | `3086c4b0af53` | `Addster09` BSP + DRM v2 (`drm_aperture` 交接) / `jt120wul005` / `hxchipset` / `sgm41510`（1.5s 延时+DPDM释放） / `musb` (`glue` 空指针防呆) / `tcpc_aw` / `mtk_ion_compat` / DTS（`full` 开启早期 `simplefb`） |
| `modules/gpu` | `zpd1203-6.6` | `2d3b928b88ce` | Moto GPU `mali-r32p1` (`r32p1-01eac0`, `platform/mt6768` + `minmax.h` clang-21 fix) |
| `modules/connectivity/common` | `android-15-release-vvta35.58-77-1` | `0fd4f365ead4` | Moto `wmt_drv.ko`（0 修改 clean） |
| `modules/connectivity/connfem` | `android-15-release-vvta35.58-77-1` | `8a665a04c769` | Moto `connfem.ko`（0 修改 clean） |
| `modules/connectivity/bt/mt66xx` | `android-15-release-vvta35.58-77-1` | `95859aaae7f4` | Moto `bt_drv_connac1x.ko`（0 修改 clean） |
| `modules/connectivity/wlan/adaptor` | `android-15-release-vvta35.58-77-1` | `48e9f37a18b7` | Moto `wmt_chrdev_wifi.ko`（0 修改 clean） |
| `modules/connectivity/wlan/core/gen4m` | `android-15-release-v1tl35.73-60-3` | `0eb4c16595f3` | Moto `wlan_drv_gen4m.ko`（0 修改 clean） |

- 输出内核版本标识：**`6.6.144-zpd1203-g92c716870252`**。
- 全套 `git format-patch`（21 份补丁，含 `patches/phase7_pstore_fixes/`）、DTS/DTSI、config、分析报告（5 份）与脚本已完整保存至 `d:\P3066\`。

## 2. 已静态验证交付产物（新版 `full` 为 `g92c716870252`；`minimal` 仍为前版 `g79934f29bfe5`）

- **全量产物**（`d:\P3066\out\full\`，校验详见 `out\full\SHA256SUMS.txt`）：
  - `boot-full-6.6.img`：`33,554,432 B`（SHA256 `330bc03a9250f4980d51d2ffa14e7c8b6668b92366c2ff9bf0421a2c385ad179`，raw `28,336,128 B`，命令行含 `console=tty0 fbcon=rotate:3,font:TER16x32 panic=8`）
  - `Image` (`39,553,536 B`), `Image.gz` (`15,794,204 B`), `mt6768-zpd1203.dtb` (`172,706 B`, `fdtoverlay` `202,917 B` PASS), `initramfs-full-6.6.cpio.xz` (`12,362,484 B`)
  - 11 枚 stripped `.ko`（`modules/*.ko`）与对应 11 枚调试 unstripped `.ko`（`unstripped/*.ko`），全部通过 `vermagic=6.6.144-zpd1203-g92c716870252` / `module_layout` CRC `0x2933d34f` / `llvm-nm` 0 未定义符号闭环。
- **最小诊断保底产物**（`d:\P3066\out\minimal\`，前一构建 `g79934f29bfe5`）：
  - `boot-minimal-6.6.img`：`33,554,432 B`（SHA256 `1a46703ac04fa6601263ceecded485aac7f4bec290bc71a3d78602da85ec19ae`）

## 3. 只读保护与测试约束
- 原厂分区备份 `D:\备份\p\GeekFlashTool_Readback_20260820162108246` 及 `/home/asus/{zpd1203-5.10.240,zpd1203,mt6768_build}` 全程未被修改。
- 实机 `expdb` 已证实原厂 `lk_a.img` 执行 `fastboot boot` 会因 `boot image is NULL` 触发 LK Panic；**实机测试需经用户明确确认后刷入 `boot_a`**（并可随时用 [restore_stock.ps1](file:///d:/P3066/scripts/restore_stock.ps1) 还原）。

## 4. 下一步实机验证建议流程（带早期 `simplefb` 屏幕日志 + USB COM 口监听）
1. 在 Windows 开一个窗口持续监听 COM 口（`.\scripts\watch_com.ps1`），并由用户确认重启至 Fastboot 后将新版 `d:\P3066\out\full\boot-full-6.6.img` 刷入 `boot_a`。
2. 设备重启后观察屏幕 `fbcon`（从 `simplefb` 到 `mtk_drm_bind` 交接）、捕获 `vid 1d6b/0104` / `0e8d/2006` COM 日志并等待 ADB 上线后运行 `.\scripts\collect_logs.ps1`。
