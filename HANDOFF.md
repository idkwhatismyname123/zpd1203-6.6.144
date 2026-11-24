# 当前工作现场交接文档 (HANDOFF.md)

- **最后更新**：2026-11-24
- **当前状态**：**Phase 3 与 Phase 4 已全部完成编译与静态验证**（Agent 4）；准备并行进入 **Phase 5（Agent 5 显示/触控/GPU、Agent 6 无线/音频/电源/温控）** 与 **Phase 6–7（Agent 7 ABI/自动化构建校验）**。

## 已完成工作与当前现场（WSL2 + `d:\P3066`）

1. **Git 提交记录（Linux 6.6.144 洁净构建，无 `-dirty`）**：
   - `/home/asus/zpd1203-6.6/kernel/kernel-6.6`（分支 `zpd1203-6.6`，基线 `329f9ae918a9`，HEAD **`a0efcb376f2a4f4dc08a0d3aebca9964b9375229`**）：
     - `cc554201aaf5` `kbuild: integrate device_modules Makefile.ext and KernelSU`（已忽略未跟踪 `external/`）
     - `c3fcb61c6fd2` `irqchip/mtk-sysirq: port platform driver and mediatek,intpol-init for MT6768`
     - `4b4293088ed5` `init: add mt6768.force_slot_a=1 cmdline slot_a override`
     - `21a8dc39ea0f` `video/fbdev/simplefb: port ZPD1203 OVL0 L3 clear and zpd_disp_regs debugfs`
     - `a0efcb376f2a` `arm64: configs: add zpd1203_minimal_defconfig for Linux 6.6.144 bring-up`
   - `/home/asus/zpd1203-6.6/kernel/kernel_device_modules-6.6`（分支 `zpd1203-6.6`，基线 `1561b421959f`，HEAD **`815405526aa37abc621a7c47e7eb5cbda4daeded`**）：
     - `4654b45c01a6` `devmod: fix Linux 6.6.144 builtin Kbuild guards, MIN/MAX, RPMB, IOMMU, PPM, clkbuf`
     - `02e25be96cdd` `arm64: dts: mediatek: add ZPD1203 minimal Linux 6.6 DTS and battery profile`
     - `815405526aa3` `arm64: configs: add zpd1203_minimal.config fragment for Phase 4 bring-up`
   - 全部 8 份 `git format-patch` 已导出至 `d:\P3066\patches\phase3_4\`。

2. **已验证的 Phase 3/4 关键技术发现（供 Agent 5/6/7 直接复用）**：
   - **`ALLOW_BUILTIN=y` 必须传入的变量**：`DEVICE_MODULES_REL_DIR=../kernel_device_modules-6.6`、`DEVICE_MODULES_PATH=/home/asus/zpd1203-6.6/kernel/kernel_device_modules-6.6`、`DEVCIE_MODULES_INCLUDE="-I.../include -I.../include/uapi"`。
   - **eMMC 驱动选择**：6.6 `device_modules` 中 `mtk-sd.c` (`DEVICE_MODULES_MMC_MTK`) **不包含 `"mediatek,mt6768-mmc"` 匹配项且无 RPMB 注册**；必须启用 **`CONFIG_DEVICE_MODULES_MMC_MTK_PRO=y`**（`mtk-mmc.c` + `cqhci` + `inlinecrypt`）与 `CONFIG_DEVICE_MODULES_MMC_DEBUG=y` + `CONFIG_MTK_IRQ_DBG=y`。
   - **MUSB + Gadget**：`usb0@11200000` 设为 `dr_mode="peripheral"` 并删除 `usb-role-switch`（已核实 `musb_dr.c` 原生按 `USB_DR_MODE_PERIPHERAL` 上电 PHY 并触发 `MUSB_VBUS_VALID`），需内置 `CONFIG_NOP_USB_XCEIV=y`。
   - **DTBO 兼容性**：6.6 `mt6358_6768.dtsi` 缺失 `mt_pmic_vsim1_ldo_reg` / `mt_pmic_vsim2_ldo_reg`，已在 `mt6768-zpd1203-minimal.dts` 补齐；`fdtoverlay` 将原厂 `dtbo_a_0.dtb` 叠加至 `mt6768-zpd1203-minimal.dtb` 实测 0 错误（全部 49 条 `__fixups__` 通过）。
   - **CPUFreq/PPM/EEM 注意事项**：`cpufreq_v2`/`ppm_v3`/`eem_v2` 依赖 `mtk_disp_notify`（DRM）与 `pbm`/`low_battery_throttling`/`mcdi`（Phase 5），故最小启动配置暂关闭之；Phase 5 启用完整显示/电源驱动后即可一并重新打开。
   - **静态验证产物（`d:\P3066\out\minimal\`，非实机验证）**：
     - `Image` (`28,510,720 B`), `Image.gz` (`11,731,770 B`), `mt6768-zpd1203-minimal.dtb` (`167,757 B`)
     - `initramfs-minimal-6.6.cpio.gz` (`15,549,025 B`, 无 Magisk, 含 `STAGE 1..7` + `pstore` 归档 + 零依赖 `gralloc.fb0_bridge.so`)
     - `boot-minimal-6.6.raw.img` (`27,453,440 B`), `boot-minimal-6.6.img` (`33,554,432 B`, Boot v2 + `0xd7b7ab1e` DT Table + unsigned AVB hash footer)

3. **只读保护**：`D:\备份\p\GeekFlashTool_Readback_20260820162108246` 及 `/home/asus/zpd1203-5.10.240` 等预存目录绝对只读不可修改。

## 下一步行动
1. **Agent 5 (`display-gpu-touch`)**：基于 `zpd1203-6.6` 分支移植完整显示（MTK DRM v2 + `jt120wul005` + `aw37503` + HWC 评估）、SPI4 Himax `hxchipset`（跳过 `GPIO158`）及 Moto GPU `mali-r32p1` + `ged` + `gpufreq`。
2. **Agent 6 (`wireless-audio-power`)**：重编 Moto `vvta35`/`v1tl35` 6.6 Connsys `.ko`（`vermagic` 匹配 `6.6.144-zpd1203`）、适配 MT6768+MT6358 音频 + SmartPA、移植 `sgm415xx` + `aw35615` + `wusb3801` + `mt6358-gauge` 修复 USB 充电状态上报、打通 Thermal/CPUFreq/传感器及排查相机。
3. **Agent 7 (`android-abi-build-test`)**：补全 `/dev/ion` `BIT(10)` 真实转发兼容层（Phase 6）与全自动化构建/校验/安全测试/原厂恢复脚本（Phase 7）。
