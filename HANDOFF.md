# 当前工作现场交接文档 (HANDOFF.md)

- **最后更新**：2026-11-25
- **当前状态**：**第 #6 轮新版 `6.6.144-zpd1203-@idkwhatismyname123`（含 `fbcon=map:9` 永久禁用屏幕跑码）已刷入 `boot_a` 并`已实机验证`进入 Android 桌面**：
  - `uname -a`: `Linux localhost 6.6.144-zpd1203-@idkwhatismyname123 #6 SMP PREEMPT Wed Nov 25 14:20:37 AEST 2026 aarch64 Toybox`
  - `sys.boot_completed=1`、`getenforce=Permissive`、`/sys/class/vtconsole/` 仅存在 `vtcon0 ((S) dummy device)`（无 `vtcon1`/`fbcon` 屏幕跑码）、11 枚 `.ko` 全加载（`mali_kbase_mt6768` `Used by 12`）。
  - 前一轮（#5）已实机验证硬件项：`ADB + COM` (`0x0e8d:0x2006`)、`Mali-G52 MC2` OpenGL ES 3.2、Himax 触屏与手写笔、`mt6768-mt6358` + `aw87xxx@59/5A`、`lcd-backlight`、`sgm41510` 充电在线（11 枚 `.ko` 同源码，本次重编仅更新 `CONFIG_LOCALVERSION` 与 `fbcon=map:9`）。

## 1. 洁净源码仓库基线（全部 8 个 WSL2 仓库均已提交且 `clean=True`，零 `-dirty`）

| 仓库路径 (`/home/asus/zpd1203-6.6/...`) | 分支 | Clean HEAD | 说明 |
|---|---|---|---|
| `kernel/kernel-6.6` | `zpd1203-6.6` | `abae8068d6e7` | Linux 6.6.144 (`android15-6.6`) + KernelSU v3.3.1 + `sysirq` + `force_slot_a=1` + `simplefb` + `aw37503` + `CONFIG_LOG_BUF_SHIFT=20` + `CONFIG_LOCALVERSION="-zpd1203-@idkwhatismyname123"` (`LOCALVERSION_AUTO=n`) |
| `kernel/kernel_device_modules-6.6` | `zpd1203-6.6` | `4779d25e29f7` | `Addster09` BSP + DRM v2 / `jt120wul005` / `hxchipset` / `sgm41510` / `musb` 空指针防护 / `dramc.c` 空指针防护 / **GED 18/22-region ABI 兼容** / **`i2c2-4 ch-offset-i2c=0x100` & `aw87xxx -ETIMEDOUT` 退出** |
| `modules/gpu` | `zpd1203-6.6` | `2d3b928b88ce` | Moto GPU `mali-r32p1` (`r32p1-01eac0`, `platform/mt6768` + `minmax.h` clang-21 fix) |
| `modules/connectivity/common` | `android-15-release-vvta35.58-77-1` | `0fd4f365ead4` | Moto `wmt_drv.ko`（0 修改 clean） |
| `modules/connectivity/connfem` | `android-15-release-vvta35.58-77-1` | `8a665a04c769` | Moto `connfem.ko`（0 修改 clean） |
| `modules/connectivity/bt/mt66xx` | `android-15-release-vvta35.58-77-1` | `95859aaae7f4` | Moto `bt_drv_connac1x.ko`（0 修改 clean） |
| `modules/connectivity/wlan/adaptor` | `android-15-release-vvta35.58-77-1` | `48e9f37a18b7` | Moto `wmt_chrdev_wifi.ko`（0 修改 clean） |
| `modules/connectivity/wlan/core/gen4m` | `android-15-release-v1tl35.73-60-3` | `0eb4c16595f3` | Moto `wlan_drv_gen4m.ko`（0 修改 clean） |

- 输出内核版本标识：**`6.6.144-zpd1203-@idkwhatismyname123`**（`CONFIG_LOCALVERSION="-zpd1203-@idkwhatismyname123"` + `# CONFIG_LOCALVERSION_AUTO is not set` + `build_kernel.sh` `LOCALVERSION=""` 抑制 `+`）。
- 全套 `git format-patch`（26 份补丁，含 `patches/phase7_pstore_fixes/` `device_modules` `0003`/`0004` 与 `kernel-6.6` `0002`/`0003`）、DTS/DTSI、config、分析报告（5 份）与脚本已完整保存至 `d:\P3066\`。

## 2. 已实机验证交付产物（`full`: `6.6.144-zpd1203-@idkwhatismyname123` + `fbcon=map:9`，已刷入 `boot_a` 并进入桌面；`minimal` 仍为 `g79934f29bfe5`）

- **全量产物**（`d:\P3066\out\full\`，校验详见 `out\full\SHA256SUMS.txt`）：
  - `boot-full-6.6.img`：`33,554,432 B`（SHA256 `d1f0eabfd77cc7d73d6a0fb81fd00d62cdbe6b6200449dd88a29d4ab38491e12`，raw `31b185332d18bdbfd6abb8710422405a58c6e4763fcf6fcd152795de8d93f82a` / `28,334,080 B`，命令行含 `console=ttyS0,921600n1 fbcon=map:9 panic=8 printk.devkmsg=on loglevel=4 ... androidboot.mode=normal androidboot.selinux=permissive`）
  - `Image` (`42,764,800 B`), `Image.gz` (`15,798,010 B`), `mt6768-zpd1203.dtb` (`172,886 B`, `fdtoverlay` `203,097 B` PASS), `initramfs-full-6.6.cpio.xz` (`12,357,860 B`)
  - 11 枚 stripped `.ko`（`modules/*.ko`）与对应 11 枚调试 unstripped `.ko`（`unstripped/*.ko`），全部通过 `vermagic=6.6.144-zpd1203-@idkwhatismyname123` / `module_layout` CRC `0x2933d34f` / `llvm-nm` 0 未定义符号闭环。
- **最小诊断保底产物**（`d:\P3066\out\minimal\`，前一构建 `g79934f29bfe5`）：
  - `boot-minimal-6.6.img`：`33,554,432 B`（SHA256 `1a46703ac04fa6601263ceecded485aac7f4bec290bc71a3d78602da85ec19ae`）

## 3. 只读保护与测试约束
- 原厂分区备份 `D:\备份\p\GeekFlashTool_Readback_20260820162108246` 及 `/home/asus/{zpd1203-5.10.240,zpd1203,mt6768_build}` 全程未被修改。
- 实机 `expdb` 已证实原厂 `lk_a.img` 执行 `fastboot boot` 会因 `boot image is NULL` 触发 LK Panic；**实机测试需经用户明确确认后刷入 `boot_a`**（并可随时用 [restore_stock.ps1](file:///d:/P3066/scripts/restore_stock.ps1) 还原）。

## 4. 下一步实机打磨建议（功能排查与优化）
1. **电池电量上报**：排查 `battery/capacity=-1` / `mtk-gauge/present=0`（对比 `mt6358-gauge` DT 与 `fuelgauged` 通信日志）。
2. **原生 `mediatek-drm`**：排查 `disp_ovl0@1400b000: could not find phandle 262144`（及 `262145`/`262146`）导致当前走 `fb0_bridge` 回退的问题。
3. **日常外设体验实测**：在桌面下验证 Wi-Fi 扫描连接、蓝牙配对、扬声器播放、横屏触摸/手写笔及待机唤醒，必要时运行 `.\scripts\collect_logs.ps1` 抓包。
