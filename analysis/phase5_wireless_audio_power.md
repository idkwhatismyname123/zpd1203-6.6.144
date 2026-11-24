# Phase 5 Step 5B 分析与交付报告：充电 / Type-C / 音频 / 温控与调频 / 无线 Connsys（Linux 6.6.144）

> **状态声明**：Step 5B 相关内核驱动、设备树与全部外置模块均达到 **已编译通过 / 已静态验证** 状态；**尚未进行实机验证**。所有已知缺失芯片（`fs15xx`、`wusb3801`、传感器、部分摄像头模组及 GenieZone EL2 依赖）均据实标注，严禁使用虚假桩代码冒充。

---

## 1. 提交与补丁清单

- **`kernel_device_modules-6.6` (分支 `zpd1203-6.6`)**：
  1. `f0ee0c1` — `zpd1203: charger/typec: add SGM41510 support and fix tcpc_aw include selection`
  2. `c168a29` — `zpd1203: dts/config: add Step 5B power, Type-C, audio, thermal and wireless support`
- **已导出补丁集**：
  - [0001-zpd1203-charger-typec-add-SGM41510-support-and-fix-t.patch](file:///d:/P3066/patches/phase5_wireless_audio_power/0001-zpd1203-charger-typec-add-SGM41510-support-and-fix-t.patch)
  - [0002-zpd1203-dts-config-add-Step-5B-power-Type-C-audio-th.patch](file:///d:/P3066/patches/phase5_wireless_audio_power/0002-zpd1203-dts-config-add-Step-5B-power-Type-C-audio-th.patch)
- **核心与无线外置仓库状态**：
  - `kernel-6.6` (`34be3f285fd5`)、`modules/gpu` (`2d3b928b88ce`) 与 5 个 Motorola Connsys 仓库（`common`: `0fd4f365ead4`、`connfem`: `8a665a04c769`、`bt/mt66xx`: `95859aaae7f4`、`wlan/adaptor`: `48e9f37a18b7`、`wlan/core/gen4m`: `0eb4c16595f3`）均保持 `clean=True`（Connsys 6.6 C 源码零修改即可编译通过）。

---

## 2. 充电、电量计与 Type-C 子系统（修复 5.10 已知缺失）

5.10.240 版本缺少 I2C5 主充电芯片与 I2C6 Type-C 驱动及 DT 描述。Step 5B 已在 Linux 6.6.144 完成完整适配：

1. **SGM41510 主充电 IC（I2C5 `@0x6b`）**：
   - SGM41510 寄存器映射（`REG_00..REG_14`）与 TI BQ25890/BQ25892 兼容；实机读回确认部件号 `PN_SGM41510 = 0x00`。
   - 适配 `drivers/power/supply/bq2589x_charger.c` 与 `bq2589x_reg.h`：
     - 新增 `PN_SGM41510`（`0x00`）与 `{ .compatible = "sgm,sgm41510", .data = &pn_data[PN_SGM41510] }`。
     - 兼容原厂 DTS 的 `sgm,*` 微安/微伏属性（转换 `/ 1000`），解析 `sgm,chg-en-gpio`（GPIO 166）与 `sgm,irq-gpio`（GPIO 26 `gpio_to_irq`）。
     - 修复 `bq->irq` 在 `enable_irq_wake()` 前未赋值、`ti,otg-*` GPIO 缺乏 `gpio_is_valid()` 防护等上游缺陷。
     - 修复 `!mt_usb_is_device()` 在 MUSB 处于 `USB_ROLE_NONE` 时引起的互斥死锁：改为使用 `bq2589x_is_otg_enable(bq) > 0` 判断 OTG 状态。
     - 为 `otg_rdev` 正确挂载 `usb_otg_vbus` 子节点，并在注册 `"primary_chg"` 的同时导出独立的 `"usb"`（`POWER_SUPPLY_TYPE_USB`）与 `"ac"`（`POWER_SUPPLY_TYPE_MAINS`）`power_supply` 实例以匹配 Android `health@2.1`。
2. **`tcpc_aw` 头文件路径修复（5 处 `Makefile`）**：
   - `drivers/misc/mediatek/typec/tcpc/inc` 与 `tcpc_aw/inc` 的头文件定义全部存在差异；此前 5 个调用方 `Makefile`（`drivers/power/supply/Makefile`、`drivers/misc/mediatek/typec/mux/Makefile`、`drivers/misc/mediatek/extcon/Makefile`、`drivers/misc/mediatek/usb/usb20/Makefile`、`drivers/misc/mediatek/usb/usb20/musb_main/Makefile`）硬编码引用 `tcpc/inc`。已统一增加 `ifeq ($(CONFIG_AW_USBPD),y)` 条件切换至 `tcpc_aw/inc`。
   - 启用 `CONFIG_AW_USBPD=y`、`CONFIG_TCPC_CLASS=y`、`CONFIG_USB_POWER_DELIVERY=y`、`CONFIG_AW35615_PD=y`，并配置 I2C6 `aw35615@22`（`awinic,int_n` GPIO 8，`aw35615-id-gpio` GPIO 159）与 `&mtk_ctd` / `&extcon_usb`（ID GPIO 41）。
3. **MT6358 电量计与 Master Charger**：
   - 启用 `CONFIG_MTK_CHARGER=y`、`CONFIG_BATTERY_MT6358=y`、`CONFIG_MTK_CHARGER_TYPE_DETECT=y`。
   - **DTB + 原厂 DTBO 叠加静态验证**：`mt6768-zpd1203.dtb` 与原厂 `dtbo_a_0.dtb` 通过 `fdtoverlay` 合并（产出 `202,774` 字节 `/tmp/test-5b-merged.dtb`，退出码 `0`）；`dtc -I dtb -O dts` 反编译证实根节点 `/charger`（`compatible = "mediatek,charger"`）成功维持 `charger = <0x3b>` 指向 `/i2c@11016000/sgm41510@6b`（`compatible = "sgm,sgm41510"`），I2C3/I2C5/I2C6 已补齐 `#address-cells = <1>; #size-cells = <0>;` 消除 `reg_format` 告警。

---

## 3. 音频、温控、CPUFreq 与电源管理

- **音频**：启用 `CONFIG_DEVICE_MODULES_SND_SOC_MEDIATEK=y`、`CONFIG_SND_SOC_MT6768=y`、`CONFIG_SND_SOC_MT6768_MT6358=y`、`CONFIG_DEVICE_MODULES_SND_SOC_MT6358=y`、`CONFIG_SND_SOC_MT6358_ACCDET=y`、`CONFIG_SND_SOC_AW87XXX=y`、`CONFIG_DEVICE_MODULES_SND_SOC_MTK_BTCVSD=y`；在 `zpd1203-power-audio-wireless.dtsi` 启用 `&sound`、`&accdet` 及 I2C3 `aw87xxx_pa@59` / `aw87xxx_pa@5A`（保持与原厂 `dtbo_a_0.dtb` 一致的大小写以防节点重复）。
- **温控 / DVFS / 低功耗**：启用 `CONFIG_MTK_LEGACY_THERMAL=y`（`MTK_LEGACY_THERMAL_PLATFORM="mt6768"`）、`CONFIG_MEDIATEK_CPU_DVFS=y`、`CONFIG_MTK_DVFS_MT6768=y`、`CONFIG_MTK_PPM_V3=y`、`CONFIG_MTK_PTPOD_LEGACY=y`、`CONFIG_MTK_SPM=y`、`CONFIG_MEDIATEK_MCDI=y`、`CONFIG_MTK_CPUHOTPLUG=y`、`CONFIG_MTK_UNIFIED_POWER=y`、`CONFIG_MEDIATEK_CPUIDLE=y`、`CONFIG_MTK_POWER_GS_LEGACY=y`。关闭 `CONFIG_MTK_THERMAL_PA_VIA_ATCMD`。

---

## 4. 无线 Connsys 模块编译与符号闭环静态验证

针对 `6.6.144-zpd1203-g34be3f285fd5`（`Module.symvers` `module_layout` CRC = `0x2933d34f`）重新编译全部内核内/外置无线及 GPU `.ko` 模块，已全部通过 `modinfo`、`modprobe --show-modversions` 与全集 `llvm-nm` 符号闭环检查（**0 个未解析符号**）：

| 模块文件名 | 原始大小 (B) | Stripped (B) | `gzip -9` (B) | `xz` (B) | `module_layout` CRC 匹配 | 依赖关系 (`depends`) | 状态 |
|---|---:|---:|---:|---:|---|---|---|
| `mali_mgm_mt6768.ko` | 211,592 | 24,696 | 5,239 | 4,320 | `0x2933d34f` (匹配) | 无 | 已静态验证 |
| `mali_kbase_mt6768.ko` | 14,922,112 | 1,093,016 | 299,043 | 217,032 | `0x2933d34f` (匹配) | `softdep: pre: memory_group_manager` | 已静态验证 |
| `rfkill.ko` | 266,016 | 51,400 | 13,064 | 10,468 | `0x2933d34f` (匹配) | 无 | 已静态验证 |
| `cfg80211.ko` | 7,500,112 | 1,649,040 | 380,872 | 259,848 | `0x2933d34f` (匹配) | `rfkill` | 已静态验证 |
| `btif_drv.ko` | 806,560 | 198,872 | 47,694 | 34,104 | `0x2933d34f` (匹配) | 无 | 已静态验证 |
| `conn_md_drv.ko` | 338,992 | 50,912 | 12,992 | 10,404 | `0x2933d34f` (匹配) | 无 | 已静态验证 |
| `connfem.ko` | 741,744 | 172,856 | 40,028 | 30,040 | `0x2933d34f` (匹配) | 无 | 已静态验证 |
| `wmt_drv.ko` | 6,496,520 | 1,699,032 | 396,384 | 261,608 | `0x2933d34f` (匹配) | `conn_md_drv,btif_drv` | 已静态验证 |
| `bt_drv_connac1x.ko` | 663,192 | 98,792 | 25,817 | 19,284 | `0x2933d34f` (匹配) | `wmt_drv` | 已静态验证 |
| `wmt_chrdev_wifi.ko` | 318,728 | 52,312 | 12,104 | 9,532 | `0x2933d34f` (匹配) | `wmt_drv` | 已静态验证 |
| `wlan_drv_gen4m.ko` | 49,593,112 | 5,344,336 | 1,459,449 | 974,712 | `0x2933d34f` (匹配) | `wmt_chrdev_wifi,cfg80211,wmt_drv` | 已静态验证 |
| **合计（11 个模块）** | **78.07 MiB** | **9.95 MiB** | **2.57 MiB** | **1.75 MiB** | **11/11 通过** | — | — |

> 注：`wlan_drv_gen4m` 内 `os/linux/gl_kal.c` 原生已用 `#if IS_ENABLED(CONFIG_DRM_MEDIATEK_V2)` 保护 `mtk_disp_notifier_register`，无需额外裁剪即可在仅启用或切换显示栈时编译通过。全部产物已归档至 `out/kernel-6.6-full/staging_modules/{unstripped,stripped}/`。

---

## 5. 二供器件、传感器与摄像头诚实审计（不做虚假兼容）

依据 `AGENTS.md` 红线（禁止空函数/虚假返回值欺骗），以下二供或缺失子系统据实记录现状：

1. **Foursemi 音频功放 `fs15xx`（`foursemi,fs15xx`）**：
   - `kernel_device_modules-6.6/sound/soc/codecs/fs18xx/fsm_core.c` 仅支持检测 `FS1601S/FS1603/FS1818/FS1896/FS1860` ID，不支持 `fs15xx`；当前主用同硬件配置的 `AW87XXX`（I2C3 `0x59`/`0x5A`），若整机批次焊装 `fs15xx` 功放，标为 **尚未验证 / 缺失驱动**。
2. **Willsemi Type-C CC `wusb3801`（`I2C6 @0x60`）**：
   - AOSP 6.6 内核 `drivers/usb/typec/wusb3801.c` 使用 `"willsemi,wusb3801"` 且以独占方式申请中断，与原厂 DT 中共享的 `GPIO 8`（和主 PD 芯片 `aw35615@22` 共用）存在冲突；当前默认启用 `AW35615_PD`，禁用 `CONFIG_TYPEC_WUSB3801`。
3. **传感器（I2C1 `sc7a20`/`mc3416`/`ucs14266`/`ls9801i`）**：
   - `kernel_device_modules-6.6` 与主线 6.6 均未内置上述 Sensor 驱动，目前 **尚未验证**（需另行从 4.19/5.10 参考实现或厂商源码迁移并适配 Android `sensors` HAL `/dev/m_*_misc` 接口）。
4. **摄像头与 GenieZone EL2（`known limitation` -> 已知故障）**：
   - `imgsensor/src/isp4_t` 仅存在 `s5k4h7sub` 及 `common/v1_1/sc800cs_mipi_raw`，缺少副摄 `hi849` 与闪光灯 `aw36515`。
   - 原厂 `camerahalserver` 硬编码依赖 EL2 GenieZone 接口 `/dev/gz_kree`（`[ISP_HA]` / `[MTEE_SENINF]`）；此前实机/5.10 已确认摄像头处于 **已知故障** 状态。
