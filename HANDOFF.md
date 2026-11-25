# 当前工作现场交接文档 (HANDOFF.md)

- **最后更新**：2026-11-25
- **当前状态**：已完成第 #3 轮实机测试（`dramc.c` 修复后内核通过全部 initcall、挂载 `super`、完成 SwitchRoot 并启动 Android `init` 加载 SELinux 策略，稳定跑码至 **`t=227s+`** 未重启；屏幕日志定位因 `CMDLINE` 缺少 `androidboot.selinux=permissive` 触发 `u:r:kernel:s0` `avc: denied ... permissive=0` 死循环）。**已补齐 `androidboot.mode=normal androidboot.selinux=permissive` 启动参数、`verify_build.sh` 校验及 `a12_init_wrapper.c` 2s/15 次退避节流，并重打包静态验证通过新版 `boot-full-6.6.img`**；等待用户重启平板进入 Fastboot 后刷入 `boot_a`。

## 1. 洁净源码仓库基线（全部 8 个 WSL2 仓库均已提交且 `clean=True`，零 `-dirty`）

| 仓库路径 (`/home/asus/zpd1203-6.6/...`) | 分支 | Clean HEAD | 说明 |
|---|---|---|---|
| `kernel/kernel-6.6` | `zpd1203-6.6` | `92c716870252` | Linux 6.6.144 (`android15-6.6`) + KernelSU v3.3.1 + `sysirq` + `force_slot_a=1` + `simplefb` + `aw37503` + `zpd1203{_minimal}_defconfig`（`full` 已启用 `CONFIG_FB_SIMPLE=y` + `fbcon`/`TER16x32`/`DEVTMPFS`/`U_SERIAL_CONSOLE`） |
| `kernel/kernel_device_modules-6.6` | `zpd1203-6.6` | `0d43534325ef` | `Addster09` BSP + DRM v2 (`drm_aperture` 交接) / `jt120wul005` / `hxchipset` / `sgm41510` / `musb` 空指针防护 / **`dramc.c` 延后设置 `dramc_pdev` 与空指针防护** / DTS |
| `modules/gpu` | `zpd1203-6.6` | `2d3b928b88ce` | Moto GPU `mali-r32p1` (`r32p1-01eac0`, `platform/mt6768` + `minmax.h` clang-21 fix) |
| `modules/connectivity/common` | `android-15-release-vvta35.58-77-1` | `0fd4f365ead4` | Moto `wmt_drv.ko`（0 修改 clean） |
| `modules/connectivity/connfem` | `android-15-release-vvta35.58-77-1` | `8a665a04c769` | Moto `connfem.ko`（0 修改 clean） |
| `modules/connectivity/bt/mt66xx` | `android-15-release-vvta35.58-77-1` | `95859aaae7f4` | Moto `bt_drv_connac1x.ko`（0 修改 clean） |
| `modules/connectivity/wlan/adaptor` | `android-15-release-vvta35.58-77-1` | `48e9f37a18b7` | Moto `wmt_chrdev_wifi.ko`（0 修改 clean） |
| `modules/connectivity/wlan/core/gen4m` | `android-15-release-v1tl35.73-60-3` | `0eb4c16595f3` | Moto `wlan_drv_gen4m.ko`（0 修改 clean） |

- 输出内核版本标识：**`6.6.144-zpd1203-g92c716870252`**。
- 全套 `git format-patch`（22 份补丁，含 `patches/phase7_pstore_fixes/`）、DTS/DTSI、config、分析报告（5 份）与脚本已完整保存至 `d:\P3066\`。

## 2. 已静态验证交付产物（新版 `full` 含 `dramc.c` + `androidboot.selinux=permissive` + 包装器退避节流；`minimal` 仍为前版 `g79934f29bfe5`）

- **全量产物**（`d:\P3066\out\full\`，校验详见 `out\full\SHA256SUMS.txt`）：
  - `boot-full-6.6.img`：`33,554,432 B`（SHA256 `c40aa239b74a8f76c540f772c9f9197f78db0e5332553d302da3ab18546f2813`，raw `28,334,080 B`，命令行含 `console=tty0 fbcon=rotate:3,font:TER16x32 panic=8 androidboot.mode=normal androidboot.selinux=permissive`）
  - `Image` (`39,553,536 B`), `Image.gz` (`15,795,420 B`), `mt6768-zpd1203.dtb` (`172,706 B`, `fdtoverlay` `202,917 B` PASS), `initramfs-full-6.6.cpio.xz` (`12,360,852 B`)
  - 11 枚 stripped `.ko`（`modules/*.ko`）与对应 11 枚调试 unstripped `.ko`（`unstripped/*.ko`），全部通过 `vermagic=6.6.144-zpd1203-g92c716870252` / `module_layout` CRC `0x2933d34f` / `llvm-nm` 0 未定义符号闭环。
- **最小诊断保底产物**（`d:\P3066\out\minimal\`，前一构建 `g79934f29bfe5`）：
  - `boot-minimal-6.6.img`：`33,554,432 B`（SHA256 `1a46703ac04fa6601263ceecded485aac7f4bec290bc71a3d78602da85ec19ae`）

## 3. 只读保护与测试约束
- 原厂分区备份 `D:\备份\p\GeekFlashTool_Readback_20260820162108246` 及 `/home/asus/{zpd1203-5.10.240,zpd1203,mt6768_build}` 全程未被修改。
- 实机 `expdb` 已证实原厂 `lk_a.img` 执行 `fastboot boot` 会因 `boot image is NULL` 触发 LK Panic；**实机测试需经用户明确确认后刷入 `boot_a`**（并可随时用 [restore_stock.ps1](file:///d:/P3066/scripts/restore_stock.ps1) 还原）。

## 4. 下一步实机验证建议流程（带早期 `simplefb` 屏幕日志 + USB COM 口监听）
1. 在 Windows 开一个窗口持续监听 COM 口（`.\scripts\watch_com.ps1`），并由用户确认重启至 Fastboot 后将新版 `d:\P3066\out\full\boot-full-6.6.img` 刷入 `boot_a`。
2. 设备重启后观察屏幕 `fbcon`（从 `simplefb` 到 `mtk_drm_bind` 交接）、捕获 `vid 1d6b/0104` / `0e8d/2006` COM 日志并等待 ADB 上线后运行 `.\scripts\collect_logs.ps1`。
