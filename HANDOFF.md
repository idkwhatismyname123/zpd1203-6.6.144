# 当前工作现场交接文档 (HANDOFF.md)

- **最后更新**：2026-11-24
- **当前状态**：Phase 1 与 Phase 2 全部完成并已拍板 6.6.144 移植基底；正在启动 **Phase 3 & 4（Agent 4：核心板级支持移植与最小可启动内核）**。

## 已确认的关键现场与硬件事实
1. **已选定 Linux 6.6.144 移植工作树**（位于 WSL2 `/home/asus/zpd1203-6.6/`）：
   - `/home/asus/zpd1203-6.6/kernel/kernel-6.6` (`AOSP android15-6.6`, `329f9ae918a9`, Linux `6.6.144`) + `external/KernelSU` (`0c0fdb96` v3.3.1)
   - `/home/asus/zpd1203-6.6/kernel/kernel_device_modules-6.6` (`Addster09/mtk-kernel-modules-bsp-6.6`, `1561b421959f`, 已加 `moto` 远端交叉校验)
   - `/home/asus/zpd1203-6.6/modules/gpu` (`MotorolaMobilityLLC/vendor-mediatek-kernel_modules-gpu`, `3b81cf6d7c0a`, 含 `mali-r32p1`)
   - `/home/asus/zpd1203-6.6/modules/connectivity/{common,bt/mt66xx,connfem,wlan/adaptor,wlan/core/gen4m}` (Motorola `vvta35` / `v1tl35`)
2. **关键硬件与 Boot 基线（详见 `analysis/phase1_stock_analysis.md` & `phase1_510_port_analysis.md`）**：
   - Boot 格式：**Android Boot Header v2** (`page_size=2048`, `kernel=0x40080000`, `ramdisk=0x47c80000`, `dtb=0x4bc80000`, `max=32 MiB`)；纯净原厂 ramdisk 位于 `/home/asus/zpd1203-6.6/extracted_stock/vendor_boot/ramdisk_unpacked/`。`lk_a.img` 支持 `fastboot boot`。
   - 内存：`6 GiB` 双 Rank（`0x40000000` + `0x100000000` 各 3 GiB），实机 `ramoops/pstore @ 0x4d010000 (0xe0000)`，BL framebuffer `0x7d350000 (0x20b0000)`。
   - 关键板级需求：`sysirq @ 0x0c53a650` 97 位 `INTPOL`、`mt6768.force_slot_a=1`（因 `super` 仅 slot A 有逻辑分区）、USB `musb-hdrc`（匹配原厂 HAL）、SPI4 Himax (`GPIO6` IRQ, 禁用 `GPIO158`)、`jt120wul005` (`aw37503@3e`)、Mali `r32p1-01eac0`、`sgm41510@6b` + `aw35615@22` + `wusb3801@60`、`/dev/ion` `BIT(10)` 兼容。
3. **只读保护**：`D:\备份\p\GeekFlashTool_Readback_20260820162108246` 及宿主机已有 `/home/asus/zpd1203-5.10.240` 等目录绝对只读不可修改。

## 下一步行动
1. **Agent 4 (`core-boot-storage`)**：执行 Phase 3 & 4——打通 `Makefile.ext` `CONFIG_DEVICE_MODULES_ALLOW_BUILTIN=y` 编译链、移植 `mt6768-zpd1203.dts` 与 `zpd1203_defconfig`、迁入 `sysirq`/`8250_mtk`/`force_slot_a`/KernelSU、`ramoops`/`pstore` 与 `simplefb` OVL0-L3 无串口调试，产出并静态校验首版可启动最小 6.6 内核与 `boot-minimal-6.6.img`。
2. 最小内核编译成功后，并行启动 **Agent 5 (`display-gpu-touch`)**、**Agent 6 (`wireless-audio-power`)** 与 **Agent 7 (`android-abi-build-test`)** 完成 Phase 5–7。
