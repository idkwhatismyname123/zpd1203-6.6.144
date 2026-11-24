# 当前工作现场交接文档 (HANDOFF.md)

- **最后更新**：2026-11-24
- **当前状态**：**Phase 0–7 宿主机开发、洁净集成构建、静态校验与项目文档已全部完成**；等待用户在 ZPD1203 实机上使用非破坏性 `fastboot boot` 启动并返回真实日志。

## 1. 洁净源码仓库基线（全部 8 个 WSL2 仓库均已提交且 `clean=True`，零 `-dirty`）

| 仓库路径 (`/home/asus/zpd1203-6.6/...`) | 分支 | Clean HEAD | 说明 |
|---|---|---|---|
| `kernel/kernel-6.6` | `zpd1203-6.6` | `91af1aa18e1a` | Linux 6.6.144 (`android15-6.6`) + KernelSU v3.3.1 + `sysirq` + `force_slot_a=1` + `simplefb` + `aw37503` + `zpd1203_defconfig` |
| `kernel/kernel_device_modules-6.6` | `zpd1203-6.6` | `8ed4bf689504` | `Addster09` BSP + DRM v2 / `jt120wul005` / `hxchipset` / `sgm41510` / `tcpc_aw` / `mtk_ion_compat` / DTS / `zpd1203_defconfig` |
| `modules/gpu` | `zpd1203-6.6` | `2d3b928b88ce` | Moto GPU `mali-r32p1` (`r32p1-01eac0`, `platform/mt6768` + `minmax.h` clang-21 fix) |
| `modules/connectivity/common` | `android-15-release-vvta35.58-77-1` | `0fd4f365ead4` | Moto `wmt_drv.ko`（0 修改 clean） |
| `modules/connectivity/connfem` | `android-15-release-vvta35.58-77-1` | `8a665a04c769` | Moto `connfem.ko`（0 修改 clean） |
| `modules/connectivity/bt/mt66xx` | `android-15-release-vvta35.58-77-1` | `95859aaae7f4` | Moto `bt_drv_connac1x.ko`（0 修改 clean） |
| `modules/connectivity/wlan/adaptor` | `android-15-release-vvta35.58-77-1` | `48e9f37a18b7` | Moto `wmt_chrdev_wifi.ko`（0 修改 clean） |
| `modules/connectivity/wlan/core/gen4m` | `android-15-release-v1tl35.73-60-3` | `0eb4c16595f3` | Moto `wlan_drv_gen4m.ko`（0 修改 clean） |

- 输出内核版本标识：**`6.6.144-zpd1203-g91af1aa18e1a`**。
- 全套 `git format-patch`（17 份补丁）、DTS/DTSI、config、分析报告（5 份）与脚本已完整保存至 `d:\P3066\`。

## 2. 已静态验证交付产物（非实机验证）

- **全量产物**（`d:\P3066\out\full\`，校验详见 `out\full\SHA256SUMS.txt`）：
  - `boot-full-6.6.img`：`33,554,432 B`（SHA256 `81df1add2b4f225ad7bdf3bc5219da961aa04a3c54915ad06ac234c642842fc5`，raw `28,213,248 B`）
  - `Image` (`39,406,080 B`), `Image.gz` (`15,691,027 B`), `mt6768-zpd1203.dtb` (`172,563 B`, `fdtoverlay` `202,774 B` PASS), `initramfs-full-6.6.cpio.xz` (`12,343,696 B`)
  - 11 枚 stripped `.ko`（`modules/*.ko`）与对应 11 枚调试 unstripped `.ko`（`unstripped/*.ko`），全部通过 `vermagic` / `module_layout` CRC `0x2933d34f` / `llvm-nm` 0 未定义符号闭环。
- **最小诊断保底产物**（`d:\P3066\out\minimal\`，校验详见 `out\minimal\SHA256SUMS.txt`）：
  - `boot-minimal-6.6.img`：`33,554,432 B`（SHA256 `72c92725458ac735d29401ed3c196d1080ed6429dd10efb2b10bfa707e5b76e4`，raw `27,457,536 B`）
  - `Image` (`28,510,720 B`), `Image.gz` (`11,731,820 B`), `mt6768-zpd1203-minimal.dtb` (`167,757 B`, `fdtoverlay` `199,454 B` PASS), `initramfs-minimal-6.6.cpio.gz` (`15,553,088 B`)

## 3. 只读保护约束
- 原厂分区备份 `D:\备份\p\GeekFlashTool_Readback_20260820162108246` 及 `/home/asus/{zpd1203-5.10.240,zpd1203,mt6768_build}` 全程未被修改。
- 严禁未经用户确认执行 `fastboot flash`。

## 4. 下一步实机验证建议流程
1. 设备进入 Fastboot 后先用最小诊断包验证内核早起与 ADB/ACM/显示基线：
   `.\scripts\test_fastboot_boot.ps1 -Mode minimal`
2. 确认正常启动后，再用全量包验证 DRM/Himax/Mali GPU/Wi-Fi+BT/`sgm41510+aw35615` 充电上报与 `/dev/ion` ABI：
   `.\scripts\test_fastboot_boot.ps1 -Mode full`
3. 收集实时与崩溃后日志反馈调优（见 `DEBUGGING.md`）：
   `.\scripts\collect_logs.ps1`
