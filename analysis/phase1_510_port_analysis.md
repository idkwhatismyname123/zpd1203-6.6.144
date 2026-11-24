# ZPD1203 (MT6768 / MT6769V) Linux 5.10.240 (`test25`) 移植深度分析报告

- **分析对象**：[`https://github.com/idkwhatismyname123/zpd1203-5.10.240`](https://github.com/idkwhatismyname123/zpd1203-5.10.240)（WSL2 独立分析路径：`/home/asus/zpd1203-6.6/ref-5.10.240/`）
- **分析基准**：分支 `main`、标签 `test25`（Commit `8a74a52734a0e168521b638c1794c6c92a2bccda`）
- **对比上游基线**：`https://github.com/MotorolaMobilityLLC/kernel-mtk` Commit `f83ca9e95d5944053603fe7f0663fb21467eb50f`（Linux 5.10.240）
- **责任人**：Agent 3 (`kernel510-analyzer`)
- **编写准则**：仅记录在源码文件、Git Diff/Log 与编译配置中直接观察到的事实；硬件实机状态严格区分为 `README.md` 声明的已测状态与静态代码核查结论。

---

## 1. 仓库总体架构与上游 Diff 全量盘点

### 1.1 Git 历史与子模块

`zpd1203-5.10.240` 在 Motorola `kernel-mtk` (`f83ca9e95d5944053603fe7f0663fb21467eb50f`) 基础上共包含 4 个提交（无额外分支，标签 `test25` 指向最新提交 `8a74a52734a0e168521b638c1794c6c92a2bccda`）：

1. `4b5652824` — Import Test #25 sources（核心内核移植源码、DTS、defconfig 与 `zpd1203/` 构建打包脚本）
2. `1e1fcc20f` — `.gitmodules` 配置
3. `658587d9f` — 中文 `README.md` 说明
4. `8a74a5273` — 精简 `README.md`

子模块与 Root 方案：
- `.gitmodules` 声明 `external/KernelSU` 子模块，锁死在提交 `0c0fdb960178fa12d80d6cbcfdcb6ad8be6a865d`（**KernelSU v3.3.1**）。
- 通过符号链接 `drivers/kernelsu -> ../external/KernelSU/kernel` 接入内核，在 `drivers/Kconfig` 与 `drivers/Makefile` 中各增加 2 行挂接 `Kconfig`/`Makefile`。
- 内核启用 `CONFIG_KPROBES=y`、`CONFIG_KRETPROBES=y` 与 `CONFIG_KSU=y`（`CONFIG_KSU_DEBUG=n`、`CONFIG_KSU_DISABLE_MANAGER=n`、`CONFIG_KSU_DISABLE_POLICY=n`），未对 VFS/execve 等核心路径做手动侵入式 hook 补丁。

### 1.2 `build.config*` 与顶级构建元数据

仓库继承 AOSP/MTK GKI 5.10 构建文件体系（`build.config.common`、`build.config.aarch64`、`build.config.mtk.aarch64`、`build.config.gki`、`build.config.gki.aarch64`、`defconfig.mk`、`kenv.mk`、`Android.mk`），实际构建由 `zpd1203/scripts/build-kernel.sh` 直接驱动 `make`，工具链配置为：
- `ARCH=arm64`、`LLVM=1`、`LLVM_IAS=1`（实测 `zpd1203_test25_defconfig` 记录宿主编译器为 `Ubuntu clang version 21.1.8 (6ubuntu1)`）
- `CROSS_COMPILE=aarch64-linux-gnu-`、`CROSS_COMPILE_COMPAT=arm-linux-gnueabi-`
- `build.config.aarch64` 默认 `MAKE_GOALS="Image modules"`，但 **`build-kernel.sh` 仅构建 `Image.gz mediatek/mt6768-zpd1203-minimal.dtb`，并未全局编译 `modules` 目标**（直接导致 `zpd1203_test25_defconfig` 中大量 `=m` 模块实际上未被编译或打包，见第 3.3 节）。

### 1.3 相对 Motorola 上游 (`f83ca9e95d59`) 的全量 35 个变更文件

`git diff --stat f83ca9e95d5944053603fe7f0663fb21467eb50f..HEAD` 共修改/新增 **35 个文件**（`10877 insertions(+), 177 deletions(-)`）：

| 分类 | 文件路径 | 变更规模 | 作用摘要 |
|---|---|---|---|
| 构建/文档/Git | `.gitignore` | +7 | 忽略构建产物与 `zpd1203` 临时产物 |
| 构建/文档/Git | `.gitmodules` | +3 | 引入 `external/KernelSU` |
| 构建/文档/Git | `README.md` | 168 +- | 说明 Test #25 现状、功能与 cmdline |
| DTS / Defconfig | `arch/arm64/boot/dts/mediatek/Makefile` | +3 | 编译 `mt6768-zpd1203-minimal.dtb` 并附加 `DTC_FLAGS := -@` |
| DTS / Defconfig | `arch/arm64/boot/dts/mediatek/mt6768-zpd1203-minimal.dts` | +196 | ZPD1203 板级最小 DTS（继承 `mt6768.dts`） |
| DTS / Defconfig | `arch/arm64/boot/dts/mediatek/zpd1203-stock-battery-profile.dtsi` | +366 | 从原厂提取的 MT6358 电池曲线与 ZCV 表 |
| DTS / Defconfig | `arch/arm64/configs/zpd1203_test25_defconfig` | +7983 | ZPD1203 Test #25 完整运行配置 |
| KernelSU | `external/KernelSU`、`drivers/kernelsu`、`drivers/Kconfig`、`drivers/Makefile` | +6 | 接入 KernelSU v3.3.1 |
| 显示 / GPU | `drivers/video/fbdev/simplefb.c` | +260 | 清除 LK OVL0 Layer 3 (DAL) 并暴露 `zpd_disp_regs` debugfs |
| 显示 / GPU | `drivers/gpu/mediatek/ged/src/ged_kpi.c` | -6 | 当 `CONFIG_DRM_MEDIATEK=n` 时移除 `disp_arr.h` 与 FPS 回调引用 |
| 触摸屏 (SPI4) | `drivers/input/touchscreen/hxchipset/himax_platform.c` | 72 +- | 修复 SPI4 active pinctrl/Mode 3、跳过 GPIO158 复位、支持 2 元 `display-coords` |
| 触摸屏 (SPI4) | `drivers/input/touchscreen/hxchipset/himax_common.c` | 44 +- | 修复 `ic_boot_done` 竞态与 `IRQF_NO_AUTOEN`、缺失 SRAM 固件时干净退出 |
| 触摸屏 (SPI4) | `drivers/input/touchscreen/hxchipset/himax_ic_HX83102.c` | +3 | HX83102 系列芯片板级兼容适配 |
| 触摸屏 (SPI4) | `drivers/input/touchscreen/hxchipset/himax_ic_incell_core.c` | 8 +- | 无物理复位 GPIO 时的软复位 (`fp_system_reset()`) 适配 |
| 电源 / 电池 | `drivers/power/supply/mtk_battery.c` | 18 +- | 当 `chg_psy` 为 NULL/ERR 及 `MTK_CHARGER=n` 时防止空指针崩溃 |
| 电源 / 电池 | `drivers/power/supply/mt6358-gauge.c` | 4 +- | 支持 `mediatek,kernel-fuel-gauge` 模式 |
| 电源 / 电池 | `drivers/power/supply/mtk_battery_daemon.c` | 5 +- | `mediatek,kernel-fuel-gauge` 时绕过用户态 netlink 守护进程 |
| 中断 / 串口 / 调试 | `drivers/irqchip/irq-mtk-sysirq.c` | 34 +- | 改为 `IRQCHIP_PLATFORM_DRIVER` 并写入 `0x0c53a650` 修复 97 个 INTPOL 极性位 |
| 中断 / 串口 / 调试 | `drivers/tty/serial/8250/8250_mtk.c` | 8 +- | 将 `MTK_UART_RATE_FIX` 寄存器写入移至 `mtk8250_runtime_resume()` 之后 |
| 中断 / 串口 / 调试 | `drivers/misc/mediatek/include/mt-plat/aee.h` | 2 +- | 当 `CONFIG_MTK_HANG_DETECT=n` 时补齐 `monitor_hang_regist_ldt()` 内联桩 |
| ION / 媒体 ABI | `drivers/staging/android/ion/heaps/Kconfig` | +7 | 新增 `CONFIG_MTK_ION_MM_HEAP_CODEC_ABI` |
| ION / 媒体 ABI | `drivers/staging/android/ion/heaps/mtk_ion_mm_heap.c` | +3 | 强制 MM heap `.id = BIT(10)` 以兼容 Android 12 Codec2 |
| 启动 / 分区槽位 | `init/main.c` | +19 | 解析 `mt6768.force_slot_a=1`，运行时覆写 `androidboot.slot(_suffix)` 为 `_a`/`a` |
| `zpd1203/` 工程目录 | `zpd1203/` 下全部 **9 个文件** | 新建 | 内核编译、无线编译、Ramdisk 重编、NEON 显示桥接、DTB/Boot 打包与校验工具 |

> **关键观察**：整个 5.10 移植对内核源码本身的修改极其克制（核心 C 代码 diff 仅约 500 行），核心难点大量通过 **`zpd1203/tools/gralloc_fb0_bridge.c`、pre-init C wrapper (`a12_init_wrapper.c`) 以及 `zpd1203/scripts/build_wireless.sh`** 解决。

---

## 2. `zpd1203/` 全部脚本、工具、Ramdisk 与显示桥接逐一分析

`zpd1203/` 目录共包含 9 个文件，构成从内核编译到可刷写 `boot.img` 的完整流水线：

### 2.1 `zpd1203/data/boot_structure.json`

记录从原厂 `boot_a` 提取的启动镜像布局参数（用于 `package_boot.sh` 与 `verify_boot.sh` 校验）：
- `header_version`: `2`、`page_size`: `2048`
- `kernel_addr`: `0x40080000`（相对 `base=0x40000000` 偏移 `0x00080000`）
- `ramdisk_addr`: `0x47c80000`（偏移 `0x07c80000`）
- `tags_addr`: `0x4bc80000`（偏移 `0x0bc80000`）
- `dtb_addr`: `0x4bc80000`（偏移 `0x0bc80000`）
- `os_version_raw`: `0x18000187`（对应 Android `12.0.0`，patch level `2024-07`）

### 2.2 `zpd1203/scripts/build-kernel.sh`

1. 检查 `$HIMAX_FIRMWARE_DIR` 下是否存在 `Himax_firmware.bin` 与 `Himax_firmware_e.bin`，以及 `drivers/kernelsu/Kconfig` 是否就位。
2. 使用 `ARCH=arm64 LLVM=1 LLVM_IAS=1 LOCALVERSION= CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-` 生成 `zpd1203_test25_defconfig`。
3. 在构建参数中覆盖 `EXTRA_FIRMWARE_DIR` 指向 `$HIMAX_FIRMWARE_DIR`，仅构建目标：
   `Image.gz mediatek/mt6768-zpd1203-minimal.dtb`。
4. **工程影响**：由于未传入 `modules` 编译目标，除 `build_wireless.sh` 单独编译的 4 个树内无线 `.ko` 外，**`zpd1203_test25_defconfig` 中其余 115 个 `=m` 选项实际上既未编译也未打包进镜像**。

### 2.3 `zpd1203/scripts/build_wireless.sh` 与 `0001-gen4m-select-available-display-notifier.patch`

这是使原厂 Android 12 Vendor Wi-Fi/BT 正常工作的关键模块构建脚本，使用 Motorola **MMI-UHAS34.29-3 (MT6768)** 的 5 个外部无线仓库，放置于 `$WIRELESS_DIR/connectivity/`：

| 仓库目录 | GitHub 仓库 / 模块性质 | 锁定 Commit Hash | 产物 `.ko` | 关键编译参数 / 补丁 |
|---|---|---|---|---|
| 树内 (`drivers/misc/mediatek/btif`) | `mtk_btif` | 同内核树 | `btif_drv.ko` | 树内单独编译 (`M=...`) |
| 树内 (`net/wireless`) | `cfg80211` | 同内核树 | `cfg80211.ko` | 树内单独编译 |
| 树内 (`drivers/misc/mediatek/conn_md`) | `conn_md` | 同内核树 | `conn_md_drv.ko` | 树内单独编译 |
| 树内 (`drivers/misc/mediatek/connectivity`) | `connadp` | 同内核树 | `connadp.ko` | `CONFIG_MTK_COMBO=m` |
| `common` | `MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-common` | `8c858eae50cbbb9b86008038f7b124761506baaf` | `wmt_drv.ko` | `CONFIG_MTK_COMBO=m MTK_PLATFORM_WMT=MT6768 TARGET_BOARD_PLATFORM_WMT=mt6768` |
| `bt/mt66xx/wmt` | `MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-bt-mt66xx` | `2a851b310d43afd104a0379e552c23a58eef69ab` | `bt_drv_connac1x.ko` | `BT_PLATFORM=connac1x BT_ENABLE_LOW_POWER_DEBUG=y 'LOG_TAG=[BT_Drv][wmt]'` |
| `connfem` | `MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-connfem` | `b40ab0fd746016c6a8d6f2d55ae9c98edc797981` | `connfem.ko` | 标准外部模块编译 |
| `wlan/adaptor` | `MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-wlan-adaptor` | `6c5a97726c86d1cf6da6d38387b2abe118a0ea` | `wmt_chrdev_wifi.ko` | `CONNAC_VER=1_0 MODULE_NAME=wmt_chrdev_wifi` |
| `wlan/core/gen4m` | `MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-wlan-core-gen4m` | `f72d1f101aae82da581add5e4cf87d52f5174c0f` | `wlan_drv_gen4m.ko` | 打入 `0001-gen4m-select-available-display-notifier.patch`；`CONFIG_MTK_COMBO_WIFI_HIF=axi MODULE_NAME=wlan_drv_gen4m MTK_COMBO_CHIP=CONNAC WLAN_CHIP_ID=6768 MTK_ANDROID_WMT=y WIFI_ENABLE_GCOV= WIFI_IP_SET=1 MTK_ANDROID_EMI=y MTK_WLAN_SERVICE=yes` |

- **`0001-gen4m-select-available-display-notifier.patch` 技术作用**：原厂 `gen4m` 在 `MTK_DRM` 未启用时仍强依赖 `mtk_disp_notifier` 获取亮灭屏状态。该补丁改为仅当 `IS_REACHABLE(CONFIG_DRM_MEDIATEK) && IS_ENABLED(CONFIG_DRM_MEDIATEK_V2)` 时使用 `mtk_disp_notifier`，否则回退到标准 Linux Framebuffer 通知链 `fb_register_client` / `FB_EVENT_BLANK`，使 `simplefb` 内核也能正确通知 Wi-Fi 驱动休眠/唤醒省电。
- **符号与版本门禁**：脚本最后强制将上述 **9 个 `.ko`** 的 `vermagic` 字符串与 `__versions` 中的 `module_layout` CRC 逐一比对内核 `vmlinux.symvers`，确保 100% 匹配。

### 2.4 `zpd1203/scripts/build_android12_ramdisk.sh` 与 Pre-Init Wrapper (`a12_init_wrapper.c`)

由于 ZPD1203 尽量不修改原厂 `vendor`/`system` 分区，5.10 通过重建 ramdisk 并在 Android `/init` 执行前注入静态 C 程序 `a12_init_wrapper.c` 来完成早期模块加载与 HAL 挂载替换：

1. 解包原厂 `ramdisk`，删除 Magisk 残留（`.backup`、`overlay.d`）。
2. 编译**静态链接 pre-init 包装器** `a12_init_wrapper.c` 为 `/init`（原厂 `/init` 被重命名/转存以链式 `execv` 拉起）。
3. 编译**零动态依赖共享库** `gralloc_fb0_bridge.c` 为 `/gralloc.fb0_bridge.so`。
4. 修正 `prop.default` 属性，限制总大小不超过 `MAX_RD_BYTES=16252928`（~15.5 MiB）。
5. 将 9 个 strip 后的 `.ko` 打成额外 CPIO 包 `wireless.cpio.xz`（位于 `zpd-wireless/*.ko`）**直接追加**到主 ramdisk 末尾（内核解压 initramfs 时自动合并）。
6. **`a12_init_wrapper.c` 运行时动作**：
   - 在 Android `init` 执行 `SwitchRoot` 清空 rootfs 前，先打开全部 9 个 `.ko` 文件描述符。
   - 对标记 `replace_vendor=1` 的 5 个外部模块（`connfem.ko`、`wmt_drv.ko`、`bt_drv_connac1x.ko`、`wmt_chrdev_wifi.ko`、`wlan_drv_gen4m.ko`），将内容复制到 tmpfs `/dev/.zpd-wireless/`，并在 `vendor` 挂载后将其 `MS_BIND` 覆盖挂载到 `/vendor/lib/modules/<name>.ko`（绕过原厂 4.19 `.ko` 版本不匹配，同时不写入实机分区）。
   - 直接通过 `finit_module` 在启动阶段加载 6 个 `load_at_boot=1` 模块：`btif_drv.ko`、`conn_md_drv.ko`、`connadp.ko`、`cfg80211.ko`、`connfem.ko`、`wmt_drv.ko`；其余 3 个（`bt_drv_connac1x.ko`、`wmt_chrdev_wifi.ko`、`wlan_drv_gen4m.ko`）留待原厂 vendor init 触发加载被 `MS_BIND` 替换后的 5.10 版本。
   - **显示 HAL 替换**：挂载空文件覆盖 `/vendor/lib64/hw/hwcomposer.mt6768.so`，并将 `/dev/.gralloc_fb0_bridge.so` `MS_BIND` 覆盖到 `/vendor/lib64/hw/gralloc.default.so`。

### 2.5 `zpd1203/tools/gralloc_fb0_bridge.c` — NEON 显示桥接完整机制

#### 为什么必须编写这个桥接器？
在 `zpd1203_test25_defconfig` 中：`CONFIG_DRM_MEDIATEK` **未设置**（虽然写了 `CONFIG_DRM_MEDIATEK_V2=y`，但 `drivers/gpu/drm/mediatek/Makefile` 以 `$(CONFIG_DRM_MEDIATEK)` 门控，因此 **DRM/DSI 驱动实际零编译**）；同时 DTS 将 `&dispsys_config` 与 `&dsi0` 设为 `disabled`，cmdline 传入 `clk_ignore_unused pd_ignore_unused regulator_ignore_unused`，从而**保活 LK 阶段已初始化好的 MMSYS/OVL0/RDMA0/DSI0/MIPI_TX0/PWM0 硬件扫描流水线**，内核侧仅注册 `simple-framebuffer` 暴露 `/dev/graphics/fb0`。

然而原厂 Android 12 用户态依赖 MTK HWC (`hwcomposer.mt6768.so`) 与 DRM/DISP2 ioctl，在没有 MTK DRM 驱动的情况下 HWC 直接失败黑屏：
1. `a12_init_wrapper` 用空文件 `MS_BIND` 遮蔽 `/vendor/lib64/hw/hwcomposer.mt6768.so`，迫使 SurfaceFlinger 回退到 AOSP 内置的 `HWC2OnFbAdapter`（基于 legacy framebuffer HAL `gralloc.default.so` 的 `framebuffer_device_t`）。
2. `HWC2OnFbAdapter` 调用 `fbdev->post(dev, buffer_handle_t)` 提交由 `vendor.gralloc-4-0`（Mali）分配的 `native_handle_t` DMA-BUF。原厂 `gralloc.default.so` 无法识别外部 gralloc-4-0 句柄结构并会拒绝。
3. **`gralloc_fb0_bridge.c`** 作为零依赖（`-nostdlib -ffreestanding`，无 `NEEDED` 段，可运行在任何 linker namespace 中）的 `gralloc.default.so` 替代品，精准接管并完成 DMA-BUF -> `fb0` 搬运：
   - **ABI 精确对齐**：导出 `HMI` 符号，将 `hw_module_t` 填充至 688 字节、将 `framebuffer_device_t` 字段按 Android 12 `0x120B` 布局对齐（含编译期 typedef/大小校验）。
   - **跨分配器 DMA-BUF 识别**：在 `fb_post()` 中扫描 `native_handle_t->data[]` 最多 `MAX_HANDLES_SCAN=8` 个 fd，通过 `lseek(fd, 0, SEEK_END)` 选取体积最大的像素 DMA-BUF fd（自动避开 fence fd 与 metadata buffer）。
   - **缓存一致性与 NEON 像素格式转换**：
     - 对源 DMA-BUF 执行 `DMA_BUF_IOCTL_SYNC` (`START | READ`) 后 `mmap()` 映射到用户态。
     - `blit_row()` 使用 ARM64 NEON 指令 `vld1q_u8` / `vst1q_u8` 逐行拷贝到 `mmap(/dev/graphics/fb0)`（宽度 `1200`，步长 `stride=4864` 字节 = `1216*4`，高度 `2000`）。
     - 当检测 `vinfo.red.offset != 0`（LK 将 OVL0 配置为 `eBGRA8888` 即 `"a8r8g8b8"`，而 Android 合成输出为 `RGBA8888`）时，在单条 NEON `vqtbl1q_u8` 指令内使用置换表 `{2,1,0,3, 6,5,4,7, 10,9,8,11, 14,13,12,15}` 完成每 4 像素 16 字节的 RGBA -> BGRA 红蓝通道互换，避免 CPU 标量逐字节搬运导致帧率崩溃。
     - 拷贝结束后发出 `DMA_BUF_IOCTL_SYNC` (`END | READ`) 并 `munmap`。

> **注**：`simplefb` 分辨率为竖屏 `1200x2000`，`gralloc_fb0_bridge.c` 本身**不做像素旋转**；横屏显示是由 Android 系统属性/SurfaceFlinger 图层合成逻辑完成，物理扫描仍按 `1200x2000` 写入 `fb0`。

### 2.6 `zpd1203/tools/wrap_dt_table.py`、`package_boot.sh` 与 `verify_boot.sh`

- `wrap_dt_table.py` 将编译得到的 `mt6768-zpd1203-minimal.dtb` 封装为带 Android DT Table 头（Magic `0xd7b7ab1e`）的镜像。
- `package_boot.sh` 读取 `boot_structure.json` 并调用 `mkbootimg` 生成 v2 `boot.img`（`base=0x40000000`、`pagesize=2048`、`os_version=12.0.0`、`os_patch_level=2024-07`），最后附加 `partition_size=33554432`（32 MiB）的未签名 AVB hash footer。
- `verify_boot.sh` 对生成的 `boot.img` 执行静态头部偏移、大小、AVB footer 与 ramdisk/DTB/Image 存在性校验。

---

## 3. 设备树 (`DTS/DTSI`) 与 `zpd1203_test25_defconfig` 完整分析

### 3.1 `mt6768-zpd1203-minimal.dts` 与 `mt6768.dts` 硬件拓扑

DTS 注释明确设备信息：**MediaTek MT6769V/CB (`hw_code=0x707`, MT6768 platform)**，主板代号 **ZYB ZPD1203 (`ZYBPAD` / `k69v1_64_k419`)**，LCM 型号 **`jt120wul005`**。

1. **原厂 DTBO 兼容桩机制**：
   - 编译参数附带 `DTC_FLAGS_mt6768-zpd1203-minimal := -@` 生成 `__symbols__` 表。
   - 在 DTS 根节点定义无 `compatible` 的空节点桩：`lcm`、`flashlights_aw36515`、`hall`、`hall_sensor`、`battery_swell_det`、`zlt_alsps`。目的在于让 LK 的 `ufdt_apply_overlay()` 合并原厂 `dtbo_a` 时所有 phandle 引用能正常解析而不报错，同时不触发尚未移植的驱动探测。
2. **完整内存映射与保留内存 (`reserved-memory`)**：
   - `debug-kinfo` (`google,debug-kinfo`): `0x4d000000`，大小 `0x10000`（64 KiB，对应 LK `aee_debug_kinfo`）。
   - `ramoops` / `pstore`：基址 `0x4d010000`，总大小 `0xe0000`（896 KiB，其中 `pmsg_size=0x10000`、`console_size=0x40000`），由 LK 通过内核 cmdline 动态注入参数（非 DTS 硬编码）。
   - **LK Framebuffer (`mblock[13]`)**：起始 `0x7d350000`，保留大小 `0x20b0000` (`no-map`)；`simple-framebuffer` (`framebuffer@7d350000`) 映射 `reg = <0 0x7d350000 0 0x0095a000>`（`1200x2000`, `stride = 4864`, `format = "a8r8g8b8"`）。紧随其后的 `0x7dcaa000`（`0x7d350000 + 0x95a000`）为 LK OVL0 Layer 3 (DAL 调试文字图层) 物理地址。
   - 继承自 `mt6768.dts` 的 SoC 保留区：`ssmr_cma_mem` (`0xc0000000..0xd0000000`, `0x10000000`)、`sspm_share` (`0x510000`)、`scp_share` (`0x300000`)、`ion-carveout-heap` (`0x9000`)、`consys_mem` (`0x400000`)、`wifi_mem` (`0x300000`)。
3. **关键板级节点覆写**：
   - 显示关闭：`&dispsys_config` 与 `&dsi0` 显式设为 `status = "disabled"`，交由 `framebuffer@7d350000` (`simple-framebuffer`) 接管。
   - 触摸屏：**SPI4 (`&spi4` @ `0x11014000`)** 挂载子节点 `zlt_ts@0`（原厂 `dtbo_0` `fragment@64` 匹配 `"himax,hxcommon"`、`himax,zpd1203-touch`、IRQ GPIO6），而非 I2C。
   - 电源/充电裁剪：禁用 Motorola 的 `&mt6370`，从 `&mtk_gauge` 删除 `charger = <&mt6370_chg>`，新增 `mediatek,kernel-fuel-gauge`，并 `#include "zpd1203-stock-battery-profile.dtsi"`（366 行原厂电池参数）。注释明确记录主充电 IC 为 `sgm41510 @ i2c5 0x6b`，Type-C IC 为 `wusb3801` 或 `aw35615`，但均未编写活跃 DT 节点。
   - USB 强制外设模式：`&usb { dr_mode = "peripheral"; /delete-property/ usb-role-switch; };`，绕过 Type-C 角色切换，保证 ADB 稳定拉起。
   - 禁用 `dvfsrc`。

### 3.2 内核命令行 (`cmdline`) 参数拆解

`zpd1203_test25_defconfig` 启用 `CONFIG_CMDLINE_EXTEND=y`（`CONFIG_CMDLINE="stack_depot_disable=on kasan.stacktrace=off kvm-arm.mode=protected cgroup_disable=pressure cgroup.memory=nokmem"`），结合 DTS `chosen/bootargs` 与 `README.md` 实测命令行：

- **实际合并生效关键参数**：
  `bootopt=64S3,32N2,64N2 buildvariant=user console=tty0 8250.nr_uarts=2 cpuidle.off=1 printk.devkmsg=on ignore_loglevel loglevel=8 clk_ignore_unused pd_ignore_unused regulator_ignore_unused mt6768.force_slot_a=1 androidboot.mode=normal androidboot.selinux=permissive`
  以及 DTS `chosen` 中 `console=ttyS0,921600n1 root=/dev/ram vmalloc=400M swiotlb=noforce cgroup.memory=nosocket,nokmem firmware_class.path=/vendor/firmware loop.max_part=7`。
- **关键参数原因分析**：
  - `clk_ignore_unused pd_ignore_unused regulator_ignore_unused`：防止内核 late_initcall 关断未被驱动认领的显示时钟、MTCMOS 电源域与 PMIC 供电，保障 `simplefb` 期间屏幕不黑屏。
  - `cpuidle.off=1`：`mt6768.dts` 定义了 `STANDBY`、`MCDI_CPU`、`MCDI_CLUSTER`、`idledram`、`idlesyspll` 5 个 PSCI `idle-states`，而 `CONFIG_MEDIATEK_CPUIDLE=m` / `CONFIG_MEDIATEK_MCDI=m` / `CONFIG_MTK_SPM=m` 均未打包，关闭 cpuidle 可防止因缺少 MTK MCDI/SPM 协调或 4.19 ATF PSCI 差异触发核死机。
  - `mt6768.force_slot_a=1`：触发 `init/main.c` 中的补丁，从 `boot_b` 测试引导时强行按 `_a` 槽位挂载 `super` 动态分区。
  - `androidboot.selinux=permissive`：Permissive 模式容忍缺少专有 HAL/node 或 4.19->5.10 SELinux 标签微差（Defconfig `CONFIG_SECURITY_SELINUX=y`, `CONFIG_SECURITY_SELINUX_DEVELOP=y`）。

### 3.3 `zpd1203_test25_defconfig` 关键子系统状态与 `=m` 陷阱

对照 `k69v1_64_k510_defconfig` 与 Motorola `ext_config`（`moto-mt6768.config`、`moto-k69v1_64_k510*.config`），`zpd1203_test25_defconfig` 中共有 **119 个 `=m` 配置项**。由于 `build-kernel.sh` **不编译 `modules` 目标**，除了被 `build_wireless.sh` 单独编译打包进 `wireless.cpio.xz` 的 **4 个树内无线模块**（`CFG80211`, `MTK_BTIF`, `MTK_CONN_MD`, `MTK_COMBO=n` 但用 `MTK_COMBO=m` 编译 `connadp.ko`）外，其余 **115 个 `=m` 模块在 Test #25 中实际处于“未随内核交付/未加载”状态**：

- **被正确内建 (`=y`) 的核心基础驱动**：
  - 存储与分区：`MMC_MTK=y` (`mtk-sd.c`)、`MMC_BLOCK=y`、`EXT4_FS=y`、`F2FS_FS=y` (含 LZ4/ZSTD 压缩与 `FS_ENCRYPTION_INLINE_CRYPT=y`)、`EROFS_FS=y` (`_ZIP=y`)、`OVERLAY_FS=y`、`DM_VERITY=y`
  - USB/ADB：`USB_MTK_HDRC=y`（注意：**5.10 使用 MTK `usb20/musb` 而非 `CONFIG_USB_MTU3=n` / `USB_MUSB_HDRC=n`**）、`PHY_MTK_TPHY=y`、`USB_CONFIGFS=y`、`USB_CONFIGFS_F_FS=y`
  - 基础 SoC/安全/IPC：`COMMON_CLK_MT6768=y`、`PINCTRL_MT6768=y`、`MTK_PMIC_WRAP=y`、`REGULATOR_MT6358=y`、`MEDIATEK_WATCHDOG=y`、`MTK_DEVAPC=y`、`MTK_SYSIRQ=y`、`SERIAL_8250_MT6577=y`、`ANDROID_BINDER_IPC=y`、`ANDROID_BINDERFS=y` (`"binder,hwbinder,vndbinder"`)、`SECURITY_SELINUX=y`
  - 触摸/电量/GPU/ION/Pstore/KSU：`TOUCHSCREEN_HIMAX_CHIPSET/COMMON/INCELL/IC_HX83102=y`、`EXTRA_FIRMWARE="Himax_firmware.bin Himax_firmware_e.bin"`、`BATTERY_MT6358=y`、`MTK_GPU_SUPPORT=y`、`MTK_GPUFREQ_V2=y`、`MTK_GPU_MT6768_SUPPORT=y`、`ION=y` + `DMABUF_HEAPS=y` + `MTK_ION_MM_HEAP=y` + `MTK_ION_MM_HEAP_CODEC_ABI=y`、`PSTORE=y` + `PSTORE_RAM/CONSOLE/PMSG=y`、`KSU=y` + `KPROBES=y` + `KRETPROBES=y`
- **被设为 `=m`（Test #25 未打包）的关键子系统**：
  - 电源/充电检测链路：`MTK_CHARGER_TYPE_DETECT=m`、`EXTCON_MTK_USB=m`、`TCPC_CLASS=m`、`MTK_USB_TYPEC=m`、`USB_POWER_DELIVERY=m`
  - 性能/调度/总线：`ARM_MEDIATEK_CPUFREQ_HW=m`（`ARM_MEDIATEK_CPUFREQ=n`）、`MEDIATEK_CPU_DVFS=m`、`MEDIATEK_CPUIDLE=m`、`MEDIATEK_MCDI=m`、`MTK_SPM=m`、`MTK_DVFSRC_DEVFREQ=m`、`MTK_DVFSRC_HELPER=m`、`MTK_IOMMU=m`、`MTK_SMI=m`、`MTK_MMSYS=m`、`MTK_MMDVFS=m`、`INTERCONNECT_MTK_MMQOS_*=m`
  - 其余安全/存储/音频/相机辅助：`RPMB=m`、`TEE=m`、`TRUSTONIC_TEE_SUPPORT=m`、`MICROTRUST_TEE_SUPPORT=m`、`SND_SOC_MT6358_ACCDET=m`、`SND_SOC_MT6660=m`、`SND_SOC_MTK_BTCVSD=m`、`MTK_CAM_CAL=m`、`MTK_V4L2_LENS=m`、`MTK_V4L2_FLASHLIGHT=m`
- **被彻底关闭 (`=n`) 的子系统**：
  - `DRM_MEDIATEK=n`（注：`DRM_MEDIATEK_V2=y` 但因主开关为 `n` 而完全不编译）
  - `MTK_CHARGER=n`、`CHARGER_SGM415XX=n`、`MOTO_CHARGER_SGM415XX=n`、`MTK_BQ2560x_SUPPORT=n`、`TCPC_WUSB3801=n`
  - `MTK_CAMERA_ISP_SUPPORT=n`、`MTK_IMGSENSOR=n`、`MTK_IMGSENSOR_ISP4=n`、`MTK_V4L2_IMGSENSOR=n`、`MTK_CCU=n`、`MTK_MDP=n`
  - `SND_SOC_MT6768=n`、`SND_SOC_MT6358=n`、`MTK_THERMAL=n`、`MTK_TINYSYS_SCP_SUPPORT=n`、`MTK_TINYSYS_SSPM_SUPPORT=n`

---

## 4. 驱动级改动深度解析与已知故障诊断

### 4.1 Himax 触摸屏驱动 (`drivers/input/touchscreen/hxchipset/`)

原厂 `dtbo` 与设备树实锤触摸屏走 **SPI4**（`&spi4` @ `0x11014000`，节点 `zlt_ts@0`，匹配 `"himax,hxcommon"`），IRQ 为 **GPIO6**，固件内建为 `Himax_firmware.bin`（HX83102J）与 `Himax_firmware_e.bin`（HX83102E）。ZPD1203 做了以下关键修复：
1. **SPI4 Pinctrl 与模式强制 (`himax_platform.c`)**：原厂 `dtbo_0` 默认 pinctrl 状态会将 SPI4 引脚拉低为 GPIO 模式。驱动修改后主动选择 `"active"` pinctrl，并强制设置 `SPI_MODE_3` 与 `8 bits_per_word`。
2. **跳过共享复位 GPIO158 (`himax_platform.c` & `himax_ic_incell_core.c`)**：`himax,rst-gpio` 对应的 `GPIO158` 在 ZPD1203 上与 LCD 上电时序共享，内核再次拉低复位 GPIO 会导致屏幕闪断/黑屏。5.10 选择不驱动硬件 `GPIO158`，而在 `himax_ic_incell_core.c` 中回退调用软件/总线复位 `fp_system_reset()`。
3. **2 元 `display-coords` 兼容 (`himax_platform.c`)**：适配原厂 DTBO 仅提供 2 个整数的 `himax,display-coords`，同时兼容标准 4 元属性。
4. **启动升级/中断竞态修复 (`himax_common.c`)**：使用 `WRITE_ONCE(ic_boot_done, ...)` 配合 `IRQF_NO_AUTOEN` 消除探测与升级期间的中断竞态；若 SRAM 固件缺失则干净失败退出而非死锁或崩溃；坐标上报通过 `input_report_abs(..., ABS_MT_POSITION_X/Y, ...)` 原始输出（驱动内无坐标旋转变换）。

### 4.2 显示、SimpleFB、GED 与 Mali GPU

1. **`drivers/video/fbdev/simplefb.c` (+260 行)**：在保持 LK 扫描流水线不掉电的基础上，向 `0x1400b000` (DISP_OVL0) 偏移 `0x02c` (`DISP_REG_OVL_SRC_CON`) 写入 `ovl_src_con & ~BIT(3)`，强行关闭 LK 留下的 DAL 调试文字叠层 (Layer 3，位于 `0x7dcaa000`)；并注册 debugfs `/sys/kernel/debug/zpd_disp_regs` 用于无 UART 现场排障。
2. **`drivers/gpu/mediatek/ged/src/ged_kpi.c` (-6 行)**：由于 `CONFIG_DRM_MEDIATEK=n`，去掉 `#include "disp_arr.h"` 及不存在的 `disp_register_fps_chg_callback` 等回调调用以保证编译通过。
3. **Mali GPU 与 GPUFreq 状态评估**：
   - 源码启用了 `CONFIG_MTK_GPU_SUPPORT=y`、`CONFIG_MTK_GPU_VERSION="mali valhall r32p1 mt6833"`、`CONFIG_MTK_GPUFREQ_V2=y`、`CONFIG_MTK_GPU_MT6768_SUPPORT=y`。`mali_kbase` (`r32p1`) 与 `mt6768.dts` 的 `mali@13040000` (`"mediatek,mali", "arm,mali-valhall"`) 对接。
   - `gpufreq_mt6768.c` 通过 `rootfs_initcall(__gpufreq_init)` 注册，探针依赖 `clk_mux`、`clk_main_parent`、`clk_sub_parent`、`subsys_mfg_cg`、`mtcmos_mfg_async`、`mtcmos_mfg`、`mtcmos_mfg_core0/1`、`vgpu`/`vsram_gpu` PMIC 调节器以及 `apmixed`/`devinfo` efuse。
   - **移植风险提示**：`mali_kbase_config_mt6833.c` 依赖 `ged` 与 `gpufreq_v2`，而 `CONFIG_MTK_IOMMU=m` / `CONFIG_MTK_SMI=m` / `CONFIG_MTK_MMSYS=m` 在 Test #25 中未随 ramdisk 加载，且用户态强制走 `HWC2OnFbAdapter` + `gralloc_fb0_bridge`（`README.md` 未列出 GPU 硬件加速实机验证通过）。Linux 6.6 必须结合 Agent 2 对 `/vendor/lib64/egl/libGLES_mali.so` DDK 版本的精确提取结果，确保 `mali_kbase` ioctl ABI 与时钟/电源域/SMI/IOMMU 完整打通。

### 4.3 【重点诊断】为何 5.10 版本 USB 充电状态上报未完成？

通过对 `mt6768-zpd1203-minimal.dts`、`zpd1203_test25_defconfig` 及 `drivers/power/supply/`、`drivers/misc/mediatek/{typec,extcon,usb20}/` 源码链路逐层排查，5.10 测试版**仅有电量百分比可读，USB 插拔与充电状态无法上报**由以下 **4 层断裂** 共同导致：

1. **硬件拓扑差异与 DT 节点缺失**：
   - Motorola MT6768 默认配置使用 `mt6370 @ i2c5 0x34` 与 `rt9471`；ZPD1203 minimal DTS 注释指出原机实际使用的是 **`sgm41510 @ i2c5 0x6b`** 与某款 Type-C 控制芯片（猜测为 **`wusb3801` 或 `aw35615`**）。
   - ZPD1203 5.10 直接禁用了 `&mt6370` 并从 `&mtk_gauge` 删除了 `charger = <&mt6370_chg>`，但**未编写任何 `sgm41510` 或 Type-C 控制器 (`wusb3801`/`aw35615`) 的 DTS 节点**。
2. **充电 IC 驱动未开启且缺失 `sgm41510` `of_match` 条目**：
   - `zpd1203_test25_defconfig` 中 `CONFIG_MTK_CHARGER=n`、`CONFIG_CHARGER_SGM415XX=n`、`CONFIG_MOTO_CHARGER_SGM415XX=n`、`CONFIG_MTK_BQ2560x_SUPPORT=n`。
   - 全树搜索证实：`drivers/power/supply/sgm415xx.c` 的 `sgm4154x_of_match[]` 仅包含 `sgm41541/41542/41543/41543D/41513/41513A/41513D/41516/41516D`；`bq2560x_charger.c` 仅匹配 `ti,bq25600/25600D/25601/25601D`（枚举注释含 `SGM41511/41542/41513`），**全仓库对 `"sgm41510"` 零命中**（需 Agent 2 从原厂 4.19 DTBO/内核符号确认 `i2c5@0x6b` 的准确兼容字符串与芯片 ID）。
3. **Type-C / BC1.2 / Extcon 事件链被切断**：
   - Minimal DTS 将 `&usb` 强制设为 `dr_mode = "peripheral"` 并删除 `usb-role-switch`，旁路了 `extcon-mtk-usb.c`。
   - `CONFIG_TCPC_WUSB3801=n`，且 `CONFIG_TCPC_CLASS=m`、`CONFIG_MTK_USB_TYPEC=m`、`CONFIG_EXTCON_MTK_USB=m`、`CONFIG_MTK_CHARGER_TYPE_DETECT=m` 均为 `=m` 且未编译进 ramdisk。
   - 在 MTK 5.10 电源链路中：`TCPC` 事件 -> `extcon-mtk-usb` / `mtk_chg_type_det.c` 触发 BC1.2 识别并通过 `POWER_SUPPLY_PROP_ONLINE` 更新 `bc12_psy`/charger 驱动 -> `sgm415xx`（或等价驱动）上报 `POWER_SUPPLY_PROP_ONLINE`、`POWER_SUPPLY_PROP_STATUS`、`POWER_SUPPLY_PROP_USB_TYPE` -> 注册 `"primary_chg"`/`charger` `power_supply` 并通知 `mtk_battery`。链路起点全部缺失。
4. **`mtk_battery.c` 采用了只保电量不报充电的“防崩溃旁路补丁”**：
   - ZPD1203 在 `mt6358-gauge.c` 与 `mtk_battery_daemon.c` 增加 `mediatek,kernel-fuel-gauge` 支持（脱离原厂 netlink 守护进程，由内核直接用原厂电池表读取电压/库仑计计算电量百分比）。
   - 同时修改 `mtk_battery.c`：当 `CONFIG_MTK_CHARGER` 不可达时跳过 `mmi_batt_health_check()`（返回 `HEALTH_UNKNOWN`）；当 `chg_psy`（`"primary_chg"`/`"charger_2nd"`）为 `IS_ERR_OR_NULL` 时直接在 `mtk_battery_external_power_changed()` 与 `battery_psy_init()` 提前返回以防内核 Oops。
   - **最终结果**：`mtk_battery` 永远收不到外部充电器的 `external_power_changed` 回调，也无 `usb`/`primary_chg` `power_supply` 暴露 `ONLINE`/`USB_TYPE`，导致 Android `HealthService` 仅能读到电池电量、电压、温度，无法获知 USB 插入与正在充电状态。

### 4.4 【重点诊断】为何 5.10 版本相机完全失效（“相机暂不支持”/“相机已爆炸”）？

静态核查证实 5.10 测试版根本**尚未移植任何相机组件**，原因包括：
1. **所有核心相机驱动均在 Defconfig 中被禁用或仅设为未打包的 `=m`**：
   - `CONFIG_MTK_CAMERA_ISP_SUPPORT=n`、`CONFIG_MTK_IMGSENSOR=n`、`CONFIG_MTK_IMGSENSOR_ISP4=n`、`CONFIG_MTK_V4L2_IMGSENSOR=n`、`CONFIG_MTK_CCU=n`、`CONFIG_MTK_CCU_RPROC=n`、`CONFIG_MTK_MDP=n`、`CONFIG_MTK_TINYSYS_SCP_SUPPORT=n`。
   - 辅助模块 `MTK_CAM_CAL=m`、`MTK_CAMERA_ISP_RAW_SUPPORT_ISP4_T=m`、`MTK_V4L2_LENS=m`、`MTK_V4L2_FLASHLIGHT=m` 以及相机高度依赖的多媒体基础设施 `MTK_IOMMU=m`、`MTK_SMI=m`、`MTK_MMSYS=m`、`MTK_MMDVFS=m`、`MTK_DVFSRC_DEVFREQ=m` 全部未编入 `Image.gz` 或 ramdisk。
2. **零板级 Sensor / 闪光灯 / 供电适配**：
   - `CONFIG_CUSTOM_KERNEL_IMGSENSOR` 仍保留 Motorola 通用型号列表（`"imx519_mipi_raw s5k2t7sp_mipi_raw ..."`），且 `CONFIG_MTK_SENSOR_PROJECT=""`、`CONFIG_MTK_CAMERA_ISP_PLATFORM=""`。
   - `mt6768-zpd1203-minimal.dts` 将 `flashlights_aw36515` 声明为空白无 `compatible` 占位节点，并直接**禁用了 `dvfsrc`**——而 `mt6768.dts` 中 `kd_camera_hw1@1a040000` 与 `ccu` 均强引用 `dvfsrc-vcore-supply = <&dvfsrc_vcore>;`！
3. **跨大版本 HAL/ISP4 兼容鸿沟**：原厂 Android 12 Vendor 内嵌的是针对 4.19 内核构建的 `mtkcam` / ISP4 用户态栈与私有 ioctl 接口。在未移植 ZPD1203 真实 Sensor ID/上电时序 (`kd_camera_hw`)、`cam_cal` EEPROM 驱动、V4L2/ISP4 设备节点、`SMI/IOMMU` 以及对齐 ioctl 结构体前，相机必然不可用。

### 4.5 其余关键系统级补丁（ION、Sysirq、UART、AEE、Force Slot A）

1. **`drivers/staging/android/ion/heaps/mtk_ion_mm_heap.c` (+3 行) 与 `Kconfig` (+7 行)**：
   - 新增 `CONFIG_MTK_ION_MM_HEAP_CODEC_ABI=y`，强制将 MTK Multimedia ION Heap 的 `.id` 设为 **`BIT(10)`**。
   - **原因**：原厂 Android 12 Codec2 硬件编解码客户端通过 `/dev/ion` 使用写死的 `heap_id_mask = BIT(10)` 申请媒体缓冲区；若不固定 ID，MediaCodec 视频硬解分配会失败。
2. **`drivers/irqchip/irq-mtk-sysirq.c` (34 +-)**：
   - 从早期 `IRQCHIP_DECLARE` 改为 **`IRQCHIP_PLATFORM_DRIVER`**，并在探针阶段向 `sysirq` 控制器寄存器基址 **`0x0c53a650`** 写入 **97 个低电平/下降沿有效 SPI 中断的 `INTPOL` 极性反转位**。
   - **原因**：ZPD1203 使用原厂 4.19 Preloader/ATF 启动后，`sysirq` 硬件 `INTPOL` 状态未按 5.10 `mt6768.dts` 直连 GIC 的模型初始化，导致大量边缘/低电平外设中断风暴或彻底不触发。
3. **`drivers/tty/serial/8250/8250_mtk.c` (8 +-)**：
   - 将 `MTK_UART_RATE_FIX` 寄存器写入移到 `mtk8250_runtime_resume()` 启用 `bus_clk` 之后执行，修复未开总线时钟直接写寄存器导致的挂死。
4. **`drivers/misc/mediatek/include/mt-plat/aee.h` (2 +-)**：
   - 当 `CONFIG_MTK_HANG_DETECT` 关闭时提供空内联 `monitor_hang_regist_ldt()` 修复编译错误。
5. **`init/main.c` (+19 行)**：
   - 识别 cmdline 中的 **`mt6768.force_slot_a=1`**，在内核早期解析时直接原地改写 `saved_command_line` 中的 `androidboot.slot_suffix=_b` -> `_a` 及 `androidboot.slot=b` -> `a`，实现在 `_b` 槽位安全测试新内核而仍加载原厂 `_a` 槽位 `super` 动态分区，无需修改原厂 `fstab`。

---

## 5. ZPD1203 硬件资源与驱动映射总表（5.10.240 参考基线 -> 6.6 目标方案）

> 注：本分析未获取实机引导串口/ADB 日志，依据 `AGENTS.md` 第 8 节状态诚实准则，6.6 移植目标前的所有条目仅按源码/Defconfig 静态核查结果标注为 `已静态验证`、`尚未验证` 或 `已知故障`，并辅注 `5.10 README` 所声明的状态。原厂具体外设 IC 型号（如 `sgm41510`、Type-C、Camera Sensor、音频 PA、传感器列表）须结合 Agent 2 原厂备份分析最终定锤。

| 子系统 | 硬件 / 总线 / 地址 / GPIO / IRQ (5.10 观测) | 5.10.240 驱动源码与配置 (`=y`/`=m`/`=n`) | 5.10 静态核查状态 (含 README 声明) | Linux 6.6 移植目标与必要动作 |
|---|---|---|---|---|
| **核心 SoC / 启动 / GIC / PSCI** | `MT6769V/CB (hw_code=0x707)` ARMv8 + GICv3 + PSCI；LK boot v2 (`kernel 0x40080000`, `dtb 0x4bc80000`) | `mt6768.dts` + `mt6768-zpd1203-minimal.dts` (`DTC_FLAGS=-@`)；`init/main.c` (`force_slot_a=1`) | **已静态验证**（5.10 README 声明可进 A12 桌面） | 迁移 ZPD1203 DTS/DTBO 桩节点与 `force_slot_a` 补丁至 6.6 MT6768 DTS |
| **系统极性中断 (`sysirq`)** | `sysirq @ 0x0c53a650`；97 个 active-low/falling SPI 中断 | `drivers/irqchip/irq-mtk-sysirq.c` (`CONFIG_MTK_SYSIRQ=y`)，改为平台驱动并写 `0x0c53a650` | **已静态验证**（核心中断基础设施） | **必迁**：确认 6.6 `irq-mtk-sysirq` 或 ATF 是否仍需显式编程该 97 个 `INTPOL` 位 |
| **时钟 / Pinctrl / PMIC-Wrap** | `topckgen_ao`、`infracfg`、`apmixed`、`mt6768-pinctrl`、`pwrap` | `clk-mt6768*.c` (`=y`)、`pinctrl-mt6768.c` (`=y`)、`mtk-pmic-wrap.c` (`=y`) | **已静态验证** | 使用 6.6 原生 `clk-mt6768`、`pinctrl-mt6768`、`pmic-wrap` |
| **PMIC / Regulator / Watchdog / DevAPC** | `MT6358` PMIC、`mt6768-devapc @ 0x10207000`、`mtk_wdt` | `mt6358_6768.dtsi`、`REGULATOR_MT6358=y`、`MEDIATEK_WATCHDOG=y`、`MTK_DEVAPC=y` | **已静态验证** | 优先使用 6.6 原生 `mt6358` / `mtk-wdt` / `mtk-devapc` |
| **保留内存与无 UART 调试** | `debug-kinfo @ 0x4d000000 (0x10000)`；`ramoops @ 0x4d010000 (0xe0000)`；`apuart0 @ 0x11002000` | `PSTORE=y`, `PSTORE_RAM=y`, `PSTORE_CONSOLE=y`, `PSTORE_PMSG=y`；`8250_mtk.c` (`=y`)；`aee.h` | **已静态验证**（含 `zpd_disp_regs` debugfs） | 保留 `0x4d000000`/`0x4d010000` 保留区；迁移 `8250_mtk` 时钟顺序修复与三级无串口取证 |
| **内部存储 (eMMC / RPMB)** | `mmc0: mmc@11230000` (`mediatek,mt6768-mmc`)、`msdc0_top @ 0x11cd0000` | `drivers/mmc/host/mtk-sd.c` (`CONFIG_MMC_MTK=y`, `MMC_BLOCK=y`)；`CONFIG_RPMB=m` (**未打包**) | eMMC **已静态验证**；RPMB **尚未验证**（未打包） | 6.6 原生 `mtk-sd`；编译并验证 `RPMB`（如 TEE/Keymaster 需要） |
| **USB / ADB** | MTK USB2.0 (`musb`/hdrc，DT 覆写 `dr_mode="peripheral"` 删 `usb-role-switch`) + TPHY | `drivers/misc/mediatek/usb20/musb_core.c` (`CONFIG_USB_MTK_HDRC=y`, `USB_MTU3=n`)、`PHY_MTK_TPHY=y`、`USB_CONFIGFS_F_FS=y` | **已静态验证**（5.10 README 声明 ADB 可用；Host OTG 被禁用） | 评估 6.6 原生 `mtu3`/`musb` 与 TPHY，在恢复 Type-C 探测的同时保证 ADB 稳定 |
| **显示系统 / 背光** | LK 预置管道 (`OVL0 @ 0x1400b000`, `DSI0 @ 0x14014000`, LCM `jt120wul005`)；`FB @ 0x7d350000` (`1200x2000`, stride `4864`, `a8r8g8b8`)；DAL `0x7dcaa000` | `FB_SIMPLE=y` (`simplefb.c` 关 OVL0 L3)；`DRM_MEDIATEK=n` (`dispsys_config`/`dsi0` disabled)；用户态 `gralloc_fb0_bridge.c` (NEON) + 遮蔽 `hwcomposer.mt6768.so` | **已静态验证**（5.10 README 声明桌面与横屏显示正常，依赖 `*_ignore_unused`） | 阶段一可用 6.6 `simplefb` + NEON 桥接快速点亮；Phase 5 必须评估移植原生 6.6 MTK DRM/DSI + `jt120wul005` 面板驱动与 PWM 背光 |
| **触摸屏** | **SPI4 (`spi4 @ 0x11014000`)** `zlt_ts@0`；IRQ **GPIO6**；共享复位 **GPIO158**（跳过不拉） | `drivers/input/touchscreen/hxchipset/*` (`=y`)、`Himax_firmware.bin` (83102J) + `Himax_firmware_e.bin` (83102E) 内建 | **已静态验证**（5.10 README 声明触屏可用） | 移植 ZPD1203 Himax SPI4 补丁至 6.6 API（保留 active pinctrl、Mode 3、跳过 GPIO158 硬件复位、内建固件） |
| **GPU / GED / GPUFreq** | Mali-G52 (`mali@13040000`, `"arm,mali-valhall"`), `gpufreq`, `vgpu`/`vsram_gpu` | `mali-r32p1` + `ged` (去 `disp_arr.h`) + `gpufreq_mt6768.c` (`=y`)；`MTK_IOMMU=m`/`MTK_SMI=m` 未打包 | **尚未验证**（已设为内建，但 README 未标明渲染实测且缺 IOMMU/SMI） | **Agent 2 提取原厂 `libGLES_mali.so` DDK 版本后**，在 6.6 对齐 `mali_kbase` DDK ABI 与 `gpufreq`/IOMMU/SMI |
| **ION / DMA-BUF / Codec2** | `/dev/ion` MM Heap + `/dev/dma_heap` | `MTK_ION_MM_HEAP=y` + `MTK_ION_MM_HEAP_CODEC_ABI=y` (`.id = BIT(10)`) + `DMABUF_HEAPS_MTK_MM=y` | **已静态验证**（仅 ABI 补丁核查） | 6.6 已移除主线 `staging/ion`！Phase 6 需实现真实 `/dev/ion` -> `dma_heap` (`BIT(10)`) 兼容层或验证 Codec2 迁移 |
| **Wi-Fi / 蓝牙 / Connsys** | `consys @ 0x18002000`, `btif @ 0x1100c000`, `consys_mem (4M)`, `wifi_mem (3M)` | 4 个树内 + 5 个 Moto `MMI-UHAS34.29-3` `.ko` (`wireless.cpio.xz` + `MS_BIND` + `finit_module`) + `gen4m` fb notifier 补丁 | **已静态验证**（5.10 README 声明 Wi-Fi/BT 可用） | 基于 6.6 兼容 Moto 15/Samsung 6.6 Connsys 源码**全量重编**这 9 个 `.ko`，严禁直接拷贝 5.10 二进制 `.ko` |
| **电池 / 电量计** | `MT6358` Gauge；原厂电池参数 `zpd1203-stock-battery-profile.dtsi` | `mt6358_battery` (`BATTERY_MT6358=y`) + `mediatek,kernel-fuel-gauge` + `mtk_battery.c` 空指针防呆 | **已静态验证**（5.10 README 声明电量百分比可用） | 迁移 `zpd1203-stock-battery-profile.dtsi` 与 `mt6358-gauge`/电池算法至 6.6 |
| **充电 IC / Type-C** | 注释记录 **`sgm41510 @ i2c5 0x6b`** + Type-C (`wusb3801`/`aw35615`?)；5.10 DT 无节点 | `MTK_CHARGER=n`、`CHARGER_SGM415XX=n`、`TCPC_WUSB3801=n`、`MTK_CHARGER_TYPE_DETECT=m`/`EXTCON_MTK_USB=m`（未编译打包） | **已知故障**（USB 插拔/充电状态上报未完成） | **Phase 5 重点修复**：由 Agent 2 核实原厂实际芯片/DTBO，在 6.6 启用完整 `TCPC -> extcon/bc12 -> charger -> power_supply` 上报链 |
| **音频 (ASoC / Codec / PA)** | `afe` + `sound` (`mt6768-mt6358-sound`) + `mt6660` PA(?) + `mtk-btcvsd-snd @ 0x18050000` | `SND_SOC_MT6768=n`、`SND_SOC_MT6358=n`；`ACCDET=m`、`MT6660=m`、`BTCVSD=m`（未打包） | **尚未验证**（Defconfig 关闭/未打包） | Phase 5 启用 6.6 MT6768 ASoC、MT6358 Codec 与原厂 PA/ACCDET 驱动 |
| **摄像头 / 闪光灯** | `kd_camera_hw1 @ 0x1a040000`, `flashlights_aw36515` (空桩), `isp4`? | `MTK_CAMERA_ISP_SUPPORT=n`、`MTK_IMGSENSOR=n`、`MTK_CCU=n`、`MTK_MDP=n`、`dvfsrc` 禁用 | **已知故障**（“相机暂不支持”/完全未移植） | 由 Agent 2 提取原厂 Sensor/ISP/HAL ABI 后，评估 6.6 还原 ISP4/`imgsensor`/DVFSRC/`cam_cal` 可行性 |
| **温控 / 调频 / 休眠 / DVFSRC** | `idle-states` (5 PSCI 状态)、`thermal_data`、`cpufreq` | `CPU_FREQ=y` 但 `ARM_MEDIATEK_CPUFREQ_HW=m`/`CPU_DVFS=m` 未打包；`MTK_THERMAL=n`；`cpuidle.off=1` | **尚未验证**（`cpuidle` 被关闭，调频与温控依赖未编入） | Phase 3/5 在 6.6 启用原生 `mediatek-cpufreq`、Thermal、DVFSRC 与验证安全的 `cpuidle` |
| **传感器** | `zlt_alsps` / `hall` (DTS 空桩) | `MTK_TINYSYS_SCP_SUPPORT=n`，无物理传感器驱动开启 | **尚未验证**（未移植） | 由 Agent 2 提取原厂 Sensor 方案后确定在 6.6 走 SCP 或直接 Linux IIO/Input |
| **SELinux / Binder / TEE / Root** | `binder,hwbinder,vndbinder` | `SECURITY_SELINUX=y` (cmdline `permissive`)、`ANDROID_BINDERFS=y`、`TEE=m` (未打包)、KernelSU v3.3.1 (`KSU=y`) | **已静态验证**（5.10 README 声明 KSU 与系统正常） | 6.6 内建 BinderFS/SELinux（目标恢复 enforcing 评估），集成兼容 6.6 的 KernelSU |

---

## 6. 对 Linux 6.6 移植项目 (Phase 3–7) 的关键技术交接与避坑指南

1. **避免重蹈 5.10 “只编 `Image.gz` 不编 `=m` 模块” 的陷阱**：
   - Test #25 依赖 `build_wireless.sh` 单独编译打包 9 个无线 `.ko`，导致 defconfig 中多达 **115 个 `=m` 核心驱动（包括 `MTK_IOMMU`、`MTK_SMI`、`ARM_MEDIATEK_CPUFREQ_HW`、`RPMB`、`EXTCON_MTK_USB`、`TCPC_CLASS`）实际上形同虚设**。Linux 6.6 的构建脚本 `scripts/build_all.sh` 应将必需底层驱动设为 `=y`，并系统性编译、签名/strip、`depmod` 打包所有实际需要的功能模块进 `vendor_ramdisk`/`vendor_dlkm` 或 pre-init 绑定机制。
2. **必须保留的 5.10 实证板级关键修复**：
   - **`sysirq` 97 个 `INTPOL` 极性位 (`0x0c53a650`)**：由于不能动原厂 4.19 Preloader/ATF，6.6 必须确认 `drivers/irqchip/irq-mtk-sysirq.c` 仍正确配置这批极性位，否则中断会异常。
   - **Himax SPI4 特殊硬件约束**：切勿在内核中拉动 `GPIO158` (`himax,rst-gpio`)，必须沿用 SPI4 `active` pinctrl、`SPI_MODE_3`、`fp_system_reset()` 与内建双固件 `Himax_firmware.bin` / `Himax_firmware_e.bin`。
   - **KernelSU 与 `mt6768.force_slot_a=1`**：KernelSU 6.6 可直接延续 kprobes 方式零侵入接入；`force_slot_a` 补丁在从 `_b` 槽位验证 `_a` 原厂系统时极有价值。
3. **显示系统两阶段推进策略**：
   - **Phase 4（首次启动）**：直接迁移 `simplefb`（保留 `0x7d350000` 内存布局与 `0x1400b000` 清除 OVL0 Layer 3 + `clk/pd/regulator_ignore_unused`）和 `gralloc_fb0_bridge.c` + `a12_init_wrapper` 策略，可最快在 6.6 复现桌面级无 UART 调试界面。
   - **Phase 5（完整驱动）**：在 6.6 上应尝试接入原生 MTK DRM/MIPI-DSI + `jt120wul005` Panel + 背光控制（解除对 `clk_ignore_unused` 和软件拷贝的依赖），`gralloc_fb0_bridge` 可作为保底/调试通道保留。
4. **解决 5.10 两大历史遗留缺陷（充电上报 & 相机）**：
   - **USB 充电上报**：等待 Agent 2 确认原厂 `dtbo` 中 `0x6b` 芯片与 Type-C 芯片的 exact `compatible`、GPIO 与中断号。在 6.6 中将 `sgm415xx`（补齐 `sgm41510` 支持或确认芯片实质为 `sgm41511`/`41513`/`41542`）+ `tcpc` + `extcon-mtk-usb` + `mtk_chg_type_det` + `mt6358` 电池驱动完整串联，不可再仅使用 `mediatek,kernel-fuel-gauge` 旁路。
   - **相机**：5.10 未动相机代码，6.6 需基于 Agent 2 提取的 Sensor 列表、`vendor` 二进制接口和 6.6 BSP `imgsensor`/`isp4` 完整度再决策（不可强行拷贝 5.10/4.19 整目录）。
5. **Android 12 Codec2 `/dev/ion` `BIT(10)` 兼容警报**：
   - Linux 6.6 主线早已移除 `drivers/staging/android/ion/`，全面转向 `DMA-BUF Heaps` (`/dev/dma_heap/*`)。但 ZPD1203 5.10 特地提交了 `CONFIG_MTK_ION_MM_HEAP_CODEC_ABI=y` 强制 MM heap ID 为 `BIT(10)`——这证明**原厂 Android 12 Vendor 存在硬编码访问 `/dev/ion` 且指定 `heap_id_mask = BIT(10)` 的客户端（尤其是 Codec2）**。Phase 6 (Agent 7) 必须重点验证如何在 6.6 通过真实的 `/dev/ion` -> `dma_heap` 兼容驱动转发 `BIT(10)` 分配请求，保证硬解视频不崩溃。
