# ZPD1203 (MediaTek MT6768) Linux 6.6 LTS Android 内核移植

为 **ZYB ZPD1203（MediaTek MT6769V/CB / MT6768）** 平板移植 **Linux 6.6.144 (`android15-6.6`)** Android 内核，兼顾原厂 Android 12 Vendor HAL 无修改兼容（含 LineageOS Android 14 GSI `system_a`）、KernelSU v3.3.1 与全自动化无 UART 调试/校验体系。

> **重要状态声明**：截至目前，全部内核镜像、`dtb`、模块与 `boot.img` 均在宿主机完成 **`已编译通过` / `已静态验证`**（零 `-dirty` 后缀、32 MiB 限制内、`fdtoverlay` + `avbtool` + `.ko` CRC/符号闭环 0 错误）；**尚未在真机执行实机运行（所有真机待测项目严格标注为 `尚未验证` 或 `已知故障`，绝不虚标 `已实机验证`）**。

---

## 内核基底与仓库结构

- **核心内核**：`android15-6.6` (**Linux 6.6.144**，`kernel-6.6` commit `91af1aa18e1a`)，集成 KernelSU v3.3.1 (`0c0fdb96`)
- **MTK BSP 模块树**：`Addster09/mtk-kernel-modules-bsp-6.6`（`kernel_device_modules-6.6` commit `8ed4bf689504`）
- **Mali-G52 GPU DDK**：`MotorolaMobilityLLC/vendor-mediatek-kernel_modules-gpu` `mali-r32p1`（`r32p1-01eac0`，`modules/gpu` commit `2d3b928b88ce`，匹配原厂 `libGLES_mali.so`）
- **Wi-Fi / BT Connsys**：Motorola `vvta35` + `v1tl35.73-60-3`（`connfem` / `common` / `bt-mt66xx` / `wlan-adaptor` / `wlan-core-gen4m`，C 源码零修改编译通过）

```text
d:\P3066\
├── AGENTS.md / TASKS.md / PORTING_STATUS.md / HARDWARE_STATUS.md
├── BUILD.md / DEBUGGING.md / DECISIONS.md / HANDOFF.md
├── analysis/                  # Phase 1-6 源码调查、原厂备份与子系统移植报告
├── patches/                   # 按阶段导出的全部 git format-patch 补丁集 (17 份)
├── scripts/                   # 全自动化构建、校验、无损伤快启、安全刷写、恢复与日志收集脚本
├── zpd1203/
│   ├── configs/               # zpd1203_defconfig、zpd1203_minimal_defconfig 及各子系统片段
│   ├── data/                  # boot_structure.json (Boot v2 布局参数)
│   ├── dts/                   # mt6768-zpd1203*.dts 及各硬件模块 .dtsi
│   └── tools/                 # a12_init_wrapper.c、gralloc_fb0_bridge.c、wrap_dt_table.py
└── out/                       # (不入库) 已打包并校验的 full/ 与 minimal/ 交付产物
```

---

## 硬件驱动适配状态摘要

| 子系统 | 6.6 方案 | 当前状态 |
|---|---|---|
| 核心启动 / GIC / `sysirq` / eMMC / RPMB | `mtk-sysirq` 97 INTPOL、`force_slot_a=1`、`mtk-mmc` + `cqhci` + `inlinecrypt` + `rpmb-mtk` | **已静态验证** |
| USB / ADB / Gadget | `usb/usb20` (`musb-hdrc`) + `phy-mtk-tphy` + `extcon-mtk-usb` + `ffs.adb+acm.gs1` | **已静态验证** |
| LCD 显示与背光 | MTK DRM v2 + `panel-himax-jt120wul005-vdo` + `aw37503` + `mtk_leds`；`minimal` 与降级回退使用 `simplefb` + NEON `gralloc.fb0_bridge.so` | **已静态验证** |
| Himax 触摸屏 | SPI4 `hxchipset`（6.6 API，跳过共用 GPIO 158，内建双固件） | **已编译通过** |
| Mali-G52 GPU | `mali_mgm_mt6768.ko` + `mali_kbase_mt6768.ko` (`r32p1-01eac0`) + `ged` + `gpufreq` + IOMMU/SMI | **已静态验证** |
| 电池 / 充电 / Type-C（修复 5.10 缺失） | `bq2589x_charger.c` 适配 `sgm,sgm41510`（导出 `usb`/`ac`/`primary_chg`）+ `aw35615` (`tcpc_aw`) + `mt6358-gauge` | **已静态验证** |
| Wi-Fi / 蓝牙 | `rfkill`、`cfg80211`、`btif_drv`、`conn_md_drv`、`connfem`、`wmt_drv`、`wmt_chrdev_wifi`、`bt_drv_connac1x`、`wlan_drv_gen4m` | **已静态验证** |
| 音频 / Thermal / CPUFreq / SPM | `mt6768-mt6358` ASoC + ACCDET + `aw87xxx`；MT6768 Thermal / DVFS / PPM / EEM / SPM / MCDI | **已编译通过**（`fs15xx` 二供暂缺驱动） |
| Android ABI & KernelSU | BinderFS、SELinux、`mtk_system_heap` + `/dev/ion` -> DMA-BUF Heap 真实转发 (`mtk_ion_compat.c`, `BIT(10)`)、KernelSU v3.3.1 | **已静态验证** |
| 传感器 / 霍尔 (`sc7a20` 等) | 无内置/开源 6.6 对应驱动 | **尚未验证** |
| 摄像头 (`mtkcam` / `gz_kree`) | 缺 `hi849`/`aw36515`，且原厂 `camerahalserver` 强依赖 EL2 `/dev/gz_kree` | **已知故障** |

---

## 快速构建与校验（WSL2 Ubuntu）

```bash
# 同时执行洁净全量模式 (full) 与最小诊断模式 (minimal) 构建与静态验证：
/mnt/d/P3066/scripts/build_all.sh --mode both --clean
```

产物输出至 `d:\P3066\out\full\` 与 `d:\P3066\out\minimal\`，均自动通过 `scripts/verify_build.sh` 与 `SHA256SUMS.txt` 校验（详情见 [BUILD.md](file:///d:/P3066/BUILD.md) 与 [PORTING_STATUS.md](file:///d:/P3066/PORTING_STATUS.md)）。

---

## 非破坏性实机测试、恢复与日志收集

> 严禁未经确认刷写分区；优先使用内存临时引导 `fastboot boot` 测试。

```powershell
# 1. 非破坏性内存临时测试（强烈建议先测试 minimal，再测试 full）：
.\scripts\test_fastboot_boot.ps1 -Mode minimal
.\scripts\test_fastboot_boot.ps1 -Mode full

# 2. 收集内核 dmesg / pstore / Android logcat / 电源与设备节点状态（无 ADB 时自动提示 TTY/expdb 步骤）：
.\scripts\collect_logs.ps1

# 3. 确认需要持久刷写 boot_a 或回退原厂只读备份时（带槽位、SHA256 与二次口令确认门禁）：
.\scripts\flash_boot_safe.ps1 -Mode full
.\scripts\restore_stock.ps1
```
