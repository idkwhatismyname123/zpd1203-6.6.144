# ZPD1203 (MT6768) 原厂备份只读深度分析报告 (Phase 1)

> **分析原则声明**：本报告所有数据均基于对只读原厂备份目录 `D:\备份\p\GeekFlashTool_Readback_20260820162108246`（WSL2 路径 `/mnt/d/备份/p/GeekFlashTool_Readback_20260820162108246`）的严格只读提取与分析。所有工作副本均提取至 WSL2 Ubuntu 目录 `/home/asus/zpd1203-6.6/extracted_stock/`，原厂备份与原有 5.10 工作目录未作任何写入或修改。
>
> **状态标注说明**：本报告所述硬件、配置与镜像事实均来自原厂备份及真实 `expdb` 回读日志的直接静态/取证观测。

---

## 1. 核心摘要与关键发现 (Executive Summary)

对 47 个原厂回读文件及 `MT6768_Android_scatter.txt` 完成完整提取与交叉校验后，得出以下对 Linux 6.6 移植具有决定性影响的实证发现：

1. **Boot 镜像格式与 A/B 槽位真实状态（关键防踩坑发现）**：
   - 尽管设备存在 `boot_a/b`（各 32 MiB）和 `vendor_boot_a/b`（各 64 MiB）分区，但原厂实际采用的是 **Android Boot Image Header v2 (`ANDROID!`)**，并非 v3/v4 分离架构；`lk_a.img` 与 `lk_b.img` 也均为 MTK Header v2 启动链路。
   - **`vendor_boot_a.img` 与 `vendor_boot_b.img` 完全一致**（SHA256: `5245a4627a3c1cb1f3ac0d6c85a6333cd273c1d32817ebff01c3828a614a1318`），内部实际存放着**完全未修改的原厂纯净 `boot.img`（Linux 4.19.191）**。
   - **`boot_a.img`**（`23db8b53...`）包含**同一份原厂 4.19.191 内核 `Image` 与 `dtb`**，但 ramdisk 已被 **Magisk 修补**（包含 `.backup/.magisk`）。
   - **`boot_b.img`**（`4ad257a3...`）存放的是前期测试刷入的 **`5.10.198-v44-early-wdt-kernel-stage-diagnostic+`** 诊断内核（GCC 11 编译），搭配原厂 ramdisk 与原厂 DTB，且无 AVB footer。
   - **`super.img` 内部现状**：`lpdump` 仅在 slot A 存在逻辑分区（`product_a`、`system_a`、`vendor_a`）；其中 **`system_a` 已被替换为第三方 Treble GSI（LineageOS 21 / Android 14 `UQ1A.240205.004`）**，而 **`vendor_a`、`vendor/odm` 与 `product_a` 为完整原厂 ZYB Android 12**（`ZYB/full_k69v1_64_k419/k69v1_64_k419:12/SP1A.210812.016/730_731_732-215:user/release-keys`，VNDK 31）。

2. **Bootloader (`lk_a.img`) 能力与 `fastboot boot` 可行性**：
   - `lk_a.img` 与 `lk_b.img` 均包含完整的 `cmd_boot` 实现（支持 `fastboot boot`）：校验 `Android Boot IMG Hdr`、检查镜像不得与 `lk` 及 download buffer 重叠、校验内存边界。在已解锁状态（`[AVB20] lock_state = 0x3` -> `verifiedbootstate=orange`）下跳过签名强制拦截。
   - 物理串口虽未引出，但 `expdb.img` 完整保存了最近一次真实启动的 Preloader + LK + GenieZone 日志，提供了极具价值的实机硬件与内存布局真值。

3. **实机屏幕型号与显示/触控硬件真值（修正 DTB 静态误导）**：
   - 静态 `merged_stock.dts` 的 `chosen` 节点中残留 MTK 参考默认字符串 `hx83112b_fhdp_dsi_cmd_auo_rt5081_drv`，**并非实机面板**。
   - **`expdb.img` 实机启动日志明确确认**：LK 探测到的实际面板为 **`jt120wul005_a01_dsi_vdo`**（`islcmfound = 1`, `fps = 5996`, `fb_base = 0x7d350000`, `vram = 34275328`）。
   - 对 `lk_a.img` 反汇编确认：`jt120wul005_a01_dsi_vdo` 为 **Himax HX83102-E/J TDDI**（DCS ID `0xDA/0xDB/0xDC = 0x83, 0x10, 0x21`），竖屏物理分辨率 **1200×2000**（`156×261 mm`），DSI 4-lane `BURST_VDO_MODE`，`PLL_CLOCK=612`，使用 **I2C7 `aw37503@3e`** 提供正负偏压并由 GPIO 153 (`lcm_bias`) / GPIO 70 (`lcm_enn`) / GPIO 165 (`lcm_1v8_en`) / GPIO 45 (`lcm_rst`) 控制上电。
   - **触摸屏总线是 SPI 而非 I2C**：挂载于 **`spi4@11014000`**（`zlt_ts@0`，`compatible = "himax,hxcommon", "focaltech,fts"`，`9.6 MHz`，SPI4 引脚 GPIO 17..20，中断 GPIO 6，复位 GPIO 158）。`vendor/firmware/` 内含 6 份 `Himax_firmware*.bin`（`HX83102-J` 1.0.2.51/43/38 与 `HX83102-E` 1.0.2.41/38）和 2 份 `focaltech_ts_fw*.bin`。

4. **GPU 与显示 HAL ABI 关键约束**：
   - **Mali-G52 MC2 GPU**：用户态 `libGLES_mali.so`（64 位 `39,697,968` B / 32 位 `28,508,688` B，Vulkan 同为符号链接）确认为 **`1.4 Bifrost-"r32p1-01eac0"`**（构建源码路径 `mali_valhall/r32p1-00bet0`，与内核 `CONFIG_MTK_GPU_VERSION="mali valhall r32p1"` 一致），打开 `/dev/mali` (`/dev/mali0`) 并依赖 `libged.so` (`/proc/ged`)、`libdmabufheap.so`、`libion_mtk.so`、`libion.so`、`libgralloc_extra.so`。
   - **显示 HAL 核心差异（Phase 5/6 最大挑战之一）**：原厂 `hwcomposer.mt6768.so` 基于旧版 MTK FB/DispMgr 架构（打开 `/dev/mtk_disp_mgr`、`DISP_IOCTL_*`、`/dev/graphics/fb`、`/proc/m4u` 及 `libdpframework.so` 的 `/dev/mtk_cmdq`、`/dev/mdp_sync`），而 `stock.config` 中 `# CONFIG_DRM is not set`；仅 `pq@2.15-impl.so` 与 `mapper@4.0-impl-mediatek.so` 引用了 `/dev/dri/card0` / `libdrm.so`。在 6.6 上若仅采用标准 DRM/KMS，需要评估使用适配层/桥接、扩展或 HAL 兼容方案。

5. **电源 / USB / Type-C / 充电全链路（解释 5.10 充电状态缺失原因）**：
   - USB 控制器在原厂为 **`musb-hdrc`**（`usb0@11200000`, `mediatek,mt6768-usb20`, `CONFIG_USB_MTK_HDRC=y`, `# CONFIG_USB_MTU3 is not set`），HAL `usb@1.2` 与 `init.mt6768.usb.rc` 硬编码 UDC 名 `"musb-hdrc"` 及 `/sys/class/typec/`、`/sys/class/udc/musb-hdrc/device/{cmode,saving}`。
   - 充电芯片链路异常丰富：主充 **I2C5 `sgm41510@6b`**（`primary_chg`, `sgm,sgm41510`）+ 从充 **I2C7 `slave_charger@4b`** + `subpmic_pmu@34` + `usb_type_c@4e`（I2C5）+ **PD 协议芯片 I2C6 `aw35615@22`** + **CC 芯片 I2C6 `wusb3801@60`** + **QC3.5 芯片 I2C6 `z350@35`** + **PMIC 库仑计 `mt6358_gauge` / `mediatek,bat_gm30`** + 电池鼓包检测 `battery_swell_det`。

6. **安全与加密 / 摄像头现状**：
   - `keymaster@4.1` 与 `gatekeeper@1.0` 均为**纯软件实现**（无硬件 TEE Keymaster 阻塞），但 `tee_a.img` 与 GenieZone (`gz_a.img`) 在启动早期运行。
   - 摄像头为四颗可选 Sensor 组合（后摄 `sc800cs_mipi_raw hi849_mipi_raw` / 前摄 `sc800cssub_mipi_raw s5k4h7_mipi_raw`，主摄 I2C2、副摄 I2C3、前摄 I2C4、闪光灯 I2C7 `aw36515@63`），且 **`camerahalserver` 与 GenieZone EL2 强绑定**（打开 `/dev/gz_kree` 并加载 `[ISP_HA]` 与 `[MTEE_SENINF]` 安全服务）。

---

## 2. 底层分区、Scatter 布局与启动链分析

### 2.1 Readback 备份文件与 Scatter 分区表

原厂备份目录共 **47 个文件**，基于 `MT6768_Android_scatter.txt`（平台 `MT6768`，存储类型 `EMMC`，`boot_channel: MSDC_0`，`block_size: 0x200`）。关键分区与 SHA256 实测校验如下：

| 分区名 | 文件名 | 大小 (Bytes / MiB) | 起始地址 (`MT6768_Android_scatter.txt`) | SHA256 / 备注 |
|---|---|---|---|---|
| `preloader` | `preloader_k69v1_64_k419.bin` | 319,676 B (`BOOT_1/2` 各 4 MiB) | `0x0` (`EMMC_BOOT1_BOOT2`) | `389bfcc13081fa60442207acd44e561274c0368da3d1d4340494b74d0eb23a18` |
| `expdb` | `expdb.img` | 20,971,520 B (20 MiB) | `0x108000` | `8e92ea52164187afbbf8aca39e007f064fed3b3fec0f8790bf1ea2aec3587b6e`（含 PL/LK/GZ 日志） |
| `vbmeta_a` | `vbmeta_a.img` | 8,388,608 B (8 MiB) | `0x1608000` | `2f3fb6474d7ff35ac4c48ab2bef71247ba50de4a94de2474b7d1b60cd6654f51` (`Flags: 3`) |
| `vbmeta_b` | `vbmeta_b.img` | 8,388,608 B (8 MiB) | `0x2E08000` | `d4d1b364a5efedba3c892c9ebea91fd23c53888214884a53208c8ee34b0eb003` (`Flags: 0`) |
| `vbmeta_system_a` | `vbmeta_system_a.img` | 8,388,608 B (8 MiB) | `0x1E08000` | `c1d8a6c8c31258d77bf7a53db4c360b6013829ba4f4e3d0647e38be8e53a7897` (`Flags: 3`) |
| `vbmeta_vendor_a` | `vbmeta_vendor_a.img` | 8,388,608 B (8 MiB) | `0x2608000` | `6b6e3f3441d4bdf05713ea21c22f4ecf9a47588491d6936a642de77ce39a6559` (`Flags: 3`) |
| `lk_a` | `lk_a.img` | 2,097,152 B (2 MiB) | `0x18A00000` *(以 scatter 为准)* | `731730c2a899895e9f9d4d2dfddf5f839f1e89a96a7efe8f920e26df25ece7a9` |
| `lk_b` | `lk_b.img` | 2,097,152 B (2 MiB) | — | `090f6db7f2d6dab5d29f81e3f1d3769e313b3b514cb5a67f553180234386f547` |
| `boot_a` | `boot_a.img` | 33,554,432 B (32 MiB) | `0x18C00000` | `23db8b5325826d95a46d83806c4b27cf8a79861d621da98a29ae9a76edaae9b5` (**Magisk Ramdisk**) |
| `boot_b` | `boot_b.img` | 33,554,432 B (32 MiB) | `0x2FC00000` | `4ad257a335a2a9a11839ffc033560321029484a47cdf1277e6f590fc48bdfe31` (**5.10.198 诊断内核**) |
| `vendor_boot_a` | `vendor_boot_a.img` | 67,108,864 B (64 MiB) | `0x1AC00000` | `5245a4627a3c1cb1f3ac0d6c85a6333cd273c1d32817ebff01c3828a614a1318` (**纯净原厂 boot v2**) |
| `vendor_boot_b` | `vendor_boot_b.img` | 67,108,864 B (64 MiB) | `0x31C00000` | `5245a4627a3c1cb1f3ac0d6c85a6333cd273c1d32817ebff01c3828a614a1318` (**与 `_a` 字节级一致**) |
| `dtbo_a` | `dtbo_a.img` | 8,388,608 B (8 MiB) | `0x1EC00000` | `0e2116106f575454eef5c374155443e9332cec67e2563c648528b0a2683a96dc` |
| `dtbo_b` | `dtbo_b.img` | 8,388,608 B (8 MiB) | `0x35C00000` | `12923bb121a40cb4fda9f5999d2d9fbd2449fe72de69334778d8587319f4b9cd` (DTBO payload 与 `_a` 相同) |
| `gz_a` / `gz_b` | `gz_a/b.img` | 16,777,216 B (16 MiB) | — | GenieZone Hypervisor (EL2) |
| `tee_a` / `tee_b` | `tee_a/b.img` | 5,242,880 B (5 MiB) | — | TrustZone OS |
| `sspm_a/b` / `spmfw_a/b` | `*.img` | 1,048,576 B (1 MiB) | — | SSPM / SPM 固件 |
| `md1img_a/b` | `md1img_a/b.img` | 134,217,728 B (128 MiB) | — | Modem 基带镜像 |
| `logo_a/b` | `logo_a/b.img` | 15,728,640 B (15 MiB) | — | 开机 Logo 资源 |
| `super` | `super.img` | 16,106,127,360 B (15 GiB) | `0x37800000` | 动态分区容器 (`product_a`, `system_a`, `vendor_a`) |
| `userdata` | — (未完整回读) | `0x191C7F8000` | `0x3F7800000` | ext4 + FBE (`aes-256-xts:aes-256-cts:v2` + `inlinecrypt`) |

> 其他核心持久化/校准分区：`misc` (512 KiB), `para` (512 KiB), `frp` (1 MiB), `md_udc` (`0x169A000` B, `/metadata`), `nvcfg` (32 MiB), `nvdata` (64 MiB), `nvram` (`0x4100000` B), `proinfo` (3 MiB), `protect1`/`protect2`, `sec1` (2 MiB), `seccfg` (8 MiB), `boot_para` (26 MiB), `otp` (`0xA008000` B)。

---

### 2.2 `boot_a.img`、`vendor_boot_a.img` 与 `boot_b.img` 解包对比

使用 `unpack_bootimg` 对三份镜像解包，关键参数与组件哈希如下：

| 项目 | `vendor_boot_a.img`（纯净原厂基线） | `boot_a.img`（日常槽位 A） | `boot_b.img`（槽位 B 诊断镜像） |
|---|---|---|---|
| **Boot Header 版本** | **Header v2** (`ANDROID!`, header_size=1660) | **Header v2** (`ANDROID!`, header_size=1660) | Header v2 |
| **Page Size** | `2048` (`0x800`) | `2048` (`0x800`) | `2048` |
| **Kernel Load Addr** | `0x40080000` | `0x40080000` | `0x40080000` |
| **Ramdisk Load Addr** | `0x47c80000` | `0x47c80000` | `0x47c80000` |
| **Tags / DTB Addr** | `0x4bc80000` | `0x4bc80000` | `0x4bc80000` |
| **OS Version / Patch** | `12.0.0` / `2024-07` | `12.0.0` / `2024-07` | — |
| **Header Cmdline** | `bootopt=64S3,32N2,64N2 buildvariant=user` | `bootopt=64S3,32N2,64N2 buildvariant=user` | `fw_devlink=permissive root=/dev/ram vmalloc=400M ... ramoops.mem_address=0x4d010000 ...` |
| **压缩 Kernel 大小** | `10,741,543` B | `10,741,543` B | — |
| **解压 `Image` SHA256** | `49dc10d82864720233ebcc5a0e6dca0cd5097d877c31040adc7bfa4b27c30f68` | `49dc10d82864720233ebcc5a0e6dca0cd5097d877c31040adc7bfa4b27c30f68` (完全一致) | `2d1f76d3ec61ed13d287dcb537abd8d1c2b4b282056ee4a351d7469248c375bc` |
| **解压 `Image` 版本** | `Linux version 4.19.191 (root@cc91249e5201) (Android clang 11.0.1 r383902 / LLD 11.0.1) #1 SMP PREEMPT Thu May 7 15:20:15 UTC 2026` (`25,798,656` B) | 与 `vendor_boot_a` 完全一致 | `Linux version 5.10.198-v44-early-wdt-kernel-stage-diagnostic+ (asus@DESKTOP-LR31PMJ) (aarch64-linux-gnu-gcc-11) #1 SMP PREEMPT Wed Aug 12 17:56:12 CST 2026` (`31,848,960` B) |
| **Ramdisk 大小与内容** | `15,278,198` B（462 文件，**0 个 `.ko`**，纯净原厂） | `15,627,973` B（含 `.backup/.magisk`） | 原厂 ramdisk |
| **DTB 大小与 SHA256** | `116,667` B (`cef9072fd8058bf6afe907dce4389a7ecc6b920fd6f0ddfbda52045b06c6a983`) | `116,667` B (`cef9072f...` 一致) | `cef9072fd8058bf6afe907dce4389a7ecc6b920fd6f0ddfbda52045b06c6a983` |
| **AVB Footer** | 有（签名 key `9d808b09...`, `Original size: 26140672`, `Hash Image Size: 26181632`） | 有（原厂 footer 保留，`Original size: 26488832`） | 无 |

**注意**：在后续制作测试 `boot.img` 或恢复原厂时，**必须使用 `vendor_boot_a.img`（未带 Magisk 侵入）作为纯净原厂基线**。

---

### 2.3 原厂 Kernel 4.19.191 `.config` (`IKCFG_ST`) 关键配置摘要

从 `vendor_boot_a` 解压内核提取 `stock.config` 共 **5,432 行**（`146,927` 字节；作为对比，`boot_b` 5.10.198 配置为 `7,796` 行 / `219,485` 字节）。原厂内核关键配置如下：

- **构建与模块**：`CONFIG_CC_IS_CLANG=y` (`110001`), `CONFIG_LD_IS_LLD=y`, `CONFIG_MODULES=y`, `CONFIG_MODVERSIONS=y`, `CONFIG_KALLSYMS=y`, `CONFIG_BLK_DEV_RAM=y`
- **Android / IPC / 安全**：`CONFIG_ANDROID=y`, `CONFIG_ANDROID_BINDER_IPC=y`, `CONFIG_ANDROID_BINDERFS=y`, `CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"`, `CONFIG_ASHMEM=y`, `CONFIG_SECURITY_SELINUX=y`, `CONFIG_DM_VERITY=y`
- **内存分配 / ION / Pstore**：`CONFIG_ION=y`, `CONFIG_MTK_ION=y`, `CONFIG_PSTORE=y`, `CONFIG_PSTORE_RAM=y`, `CONFIG_PSTORE_CONSOLE=y`, `CONFIG_PSTORE_PMSG=y`, `CONFIG_PSTORE_COMPRESS=y` (`deflate`), `CONFIG_ZRAM=y`
- **文件系统与加密**：`CONFIG_EXT4_FS=y`, `CONFIG_EXT4_ENCRYPTION=y`, `CONFIG_EXT4_FS_ENCRYPTION=y`, `CONFIG_CRYPTO_AES_ARM64_CE_BLK=y`, `CONFIG_CRYPTO_XTS=y`, `CONFIG_CRYPTO_CTS=y`, **`# CONFIG_EROFS_FS is not set`**, **`# CONFIG_F2FS_FS is not set`**
- **核心平台 / 存储 / USB**：`CONFIG_COMMON_CLK_MT6768=y`, `CONFIG_PINCTRL_MT6768=y`, `CONFIG_PINCTRL_MTK_PARIS=y`, `CONFIG_REGULATOR_MT6358=y`, `CONFIG_MMC_MTK=y`, `CONFIG_MMC_CQHCI=y`, `CONFIG_RPMB=y`, **`CONFIG_USB_MTK_HDRC=y`**, `CONFIG_USB_MTK_OTG=y`, `CONFIG_MTK_MUSB_DRV_36BIT=y`, `CONFIG_MTK_MUSB_DUAL_ROLE=y`, **`# CONFIG_USB_MTU3 is not set`**, `CONFIG_EXTCON=y`, `CONFIG_USB_CONFIGFS=y`, `CONFIG_USB_CONFIGFS_F_FS=y`, `CONFIG_USB_CONFIGFS_MTK_FASTMETA=y`
- **显示 / GPU**：`CONFIG_MTK_FB=y`, **`# CONFIG_DRM is not set`**, `CONFIG_MTK_GPU_SUPPORT=y`, `CONFIG_MTK_GPU_COMMON_DVFS_SUPPORT=y`, **`CONFIG_MTK_GPU_VERSION="mali valhall r32p1"`**
- **触控 / 电源 / 音频 / 无线 / GZ**：
  - `CONFIG_TOUCHSCREEN_HIMAX_COMMON=y`, `CONFIG_TOUCHSCREEN_HIMAX_IC_HX83102E=y`, `CONFIG_TOUCHSCREEN_HIMAX_IC_HX83102J=y`, `CONFIG_TOUCHSCREEN_FTS=y`, `CONFIG_TOUCHSCREEN_PHYSICAL_ROTATION_WITH_LCM=y`
  - `CONFIG_MTK_CHARGER=y`, `CONFIG_CHARGER_SGM41510=y`, `CONFIG_AW35615_PD=y`, `CONFIG_MTK_GAUGE_VERSION=30`
  - `CONFIG_SND_SOC_MT6768=y`, `CONFIG_SND_SOC_MT6358=y`, `CONFIG_SND_SOC_MT6768_MT6358=y`, `CONFIG_SND_SOC_MTK_SRAM=y`（以及 `CONFIG_SND_SOC_MT6357_ACCDET=m`, `CONFIG_SND_SOC_MT6359_ACCDET=m`，但实际 `vendor/lib/modules` 中未打入这两个 `.ko`）
  - `CONFIG_MTK_COMBO=y`, `CONFIG_MTK_GZ_MAIN=y`, `CONFIG_MTK_GZ_KREE=y`, `CONFIG_MTK_GZ_LOG=y`, `CONFIG_MTK_GZ_VIRTIO=y`, `CONFIG_TRUSTY_INTERRUPT_MAP=y`
  - `CONFIG_THERMAL=y`, `CONFIG_CPU_FREQ=y`

---

### 2.4 原厂 Ramdisk 内容与 `fstab.mt6768`

`vendor_boot_a` 解压后的 ramdisk（`/home/asus/zpd1203-6.6/extracted_stock/vendor_boot/ramdisk_unpacked/`）共有 **462 个文件**，**不含任何 `.ko` 内核模块**，主要包含：
- `/init`, `/system/bin/init`, `/prop.default`, `/default.prop`, `/system/etc/ramdisk/build.prop`
- `prop.default` 设备标识：`ro.product.system.brand=ZYB`, `ro.product.system.device=k69v1_64_k419`, `ro.product.system.model=ZPD1203`, `ro.product.system.name=full_k69v1_64_k419`, `ro.product.system.zybname=ZYBPAD`, `ro.system.build.fingerprint=ZYB/full_k69v1_64_k419/k69v1_64_k419:12/SP1A.210812.016/730_731_732-215:user/release-keys`, `ro.system.build.version.release=12`, `sdk=31`。
- `first_stage_ramdisk/fstab.mt6768`（与 `/vendor/etc/fstab.mt6768` **完全一致**，diff 为空）：
  - 动态逻辑分区：`system`, `system_ext`, `vendor`, `product` 均为 **`ext4 ro wait,slotselect,avb...,logical,first_stage_mount`**（其中 `system` 与 `system_ext` 绑定 `avb=vbmeta_system` 与 GSI 公钥 `/avb/{q,r,s}-gsi.avbpubkey`）。
  - `/metadata` (`/dev/block/by-name/md_udc`): `ext4`, `discard,first_stage_mount`。
  - `/data` (`/dev/block/by-name/userdata`): `ext4`, **`inlinecrypt`**, `quota`, `checkpoint=block`, **`fileencryption=aes-256-xts:aes-256-cts:v2,keydirectory=/metadata/vold/metadata_encryption`**。
  - `/vendor/etc/fstab.enableswap`: `/dev/block/zram0 none swap defaults zramsize=55%`（`lz4` 压缩）。

---

### 2.5 AVB 与 DTBO 校验机制

- **`vbmeta_a.img`**：`avbtool info_image` 显示 **`Flags: 3`**（即 `AVB_VBMETA_IMAGE_FLAGS_HASHTREE_DISABLED | AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED`），说明设备已刷入关闭验证的 `vbmeta`，其链式描述符分别指向 `vbmeta_system`（公钥 sha1 `fa41159a...`）、`vbmeta_vendor`（`9577bc6c...`）与 `boot`（`9d808b09...`）。
- **`vbmeta_b.img`**：`Flags: 0`。
- **`vbmeta_system_a.img` & `vbmeta_vendor_a.img`**：均带有 `Flags: 3`，内部记录原厂 `system`（5,559,595,008 B）、`product`（177,668,096 B）和 `vendor`（779,022,336 B）的 dm-verity hashtree 描述符。
- **`dtbo_a.img` & `dtbo_b.img`**：无 AVB footer。头部为标准 Android `dt_table_header`（`magic=0xd7b7ab1e`, `total_size=45460`, `dt_entry_count=1`, `dt_offset=0x40`, `dt_size=45396`），后附 MTK `cert1` 签名尾（`0x58881688`）。解包后的 `dtbo_a_0.dts` 与 `dtbo_b_0.dts` **内容完全相同**（2,032 行）。
- **`main_dtb`**：`boot_a` / `vendor_boot_a` / `boot_b` 中的 `dtb`（116,667 B）均封装为 `dt_table_header`（`count=1`, `dt_offset=0x40`, `dt_size=116603`），内嵌 `main_dtb_0.dtb`（SHA256 `35a9bc4f...`）与 `lk_a.img` 中 `lk_main_dtb` 匹配。

---

### 2.6 Preloader、LK (`lk_a.img`) 与 `expdb.img` 实机取证分析

1. **Preloader (`preloader_k69v1_64_k419.bin`, 319,676 B)**：
   - 构建工程代号：`zpd_mt8788_android12`，开启 A/B 检测（`ab_bootcheck.c`），PMIC 为 **MT6358 (`CHIP Code = 0x5820`)**，通过 GPIO 110 判断 DDR 最高频率（`0 -> 3600`, `1 -> 3200`），`usbdl_vfy_da:disabled`。

2. **LK (`lk_a.img`, 加载地址 `0x4c400000`) Fastboot 与 AVB 能力**：
   - 包含完整 `cmd_boot`（支持 `fastboot boot <boot.img>`），校验流程：检查 `"ANDROID!"` 头 -> 验证下载区域与 `lk`/buffer 无重叠 -> 校验 DDR 范围 -> 加载内核与 DTB。
   - 支持命令：`flash:`, `erase:`, `getvar:`, `set_active:`, `flashing lock`, `flashing get_unlock_ability`, `continue`, `reboot-bootloader`, `reboot-fastboot`, `reboot-recovery`, `oem dump_pllk_log`, `oem p2u`, `oem off-mode-charge`, `oem usb2jtag`, `oem printk-ratelimit`, `oem lks`, `oem get_socid`, `oem ultraflash`。
   - 屏幕探测内置 8 个 LCM 驱动：`hjr120001d_a01_dsi_vdo`, `hjr120008d_dsi_vdo`, `hjr120017d_dsi_vdo`, `jt120wuh017_dsi_vdo`, **`jt120wul005_a01_dsi_vdo`**, `lmibe120117840_dsi_vdo`, `lmibe120118440_dsi_vdo`, `lmibe120118960_dsi_vdo`。

3. **`expdb.img` 实机启动日志与内存保留区真值**：
   在 `expdb.img` 偏移 `0x1200000..0x1222000` 提取到完整 Preloader + LK + GenieZone 日志（`/home/asus/zpd1203-6.6/extracted_stock/misc/expdb_pl_lk_log.txt`）：
   - **真实物理内存**：双 Rank 共 **6 GiB DRAM**：
     - `mblock[0] start=0x40000000 size=0xC0000000` (3 GiB)
     - `mblock[1] start=0x100000000 size=0xC0000000` (3 GiB)
   - **实机保留内存映射 (`mblock_alloc_range` / `mblock_reserve`)**：
     | 用途 | 起始物理地址 | 大小 | 说明 |
     |---|---|---|---|
     | `atf-reserved` | `0x4CE00000` | `0x60000` | ARM Trusted Firmware |
     | `aee_debug_kinfo` | `0x4D000000` | `0x10000` | AEE 内核异常信息 |
     | **`pstore` (`ramoops`)** | **`0x4D010000`** | **`0xE0000`** | **`console=0x40000`, `pmsg=0x10000`（实机验证可用通道）** |
     | `minirdump` | `0x4D0F0000` | `0x10000` | MTK MRDUMP 头部 |
     | `SPM-reserved` | `0x77FF0000` | `0x10000` | Suspend/Power Manager |
     | `framebuffer` | `0x7D350000` | `0x20B0000` | Bootloader 显存 (`vram = 34275328` B) |
     | `tee-secmem` | `0x7F400000` | `0x200000` | TEE 安全内存 |
     | `gz-log` | `0x7F600000` | `0x41000` | GenieZone 日志缓冲 |
     | `SSPM-reserved` | `0x7F700000` | `0xC0000` | SSPM 协处理器 |
     | `log_store` | `0x7F7C0000` | `0x40000` | PL/LK 跨重启日志（SRAM 句柄 `0x10F200`） |
     | `gz` | `0x7F800000` | `0x800000` | GenieZone EL2 Hypervisor |
     | `atf-log-reserved` | `0xBFE00000` | `0x40000` | ATF 运行日志 |
     | `atf-ramdump-reserved` | `0xBFF80000` | `0x80000` | ATF Ramdump |
     | `dramc-rk0` / `dramc-rk1` | `0xFFFFF000` / `0x1BFFFF000` | 各 `0x1000` | DRAMC 保留页 |
   - **实机屏幕参数**：`videolfb - fb_base = 0x7d350000`, `videolfb - islcmfound = 1`, `videolfb - fps = 5996`, `videolfb - vram = 34275328`, **`videolfb - lcmname = jt120wul005_a01_dsi_vdo`**。
   - **GenieZone EL2 引导路径**：`GZ (0)[7.817863] boot linux-64 via EL2, pc=0x40080000, x0=0x4bc80000, x1=0x0, mode=0x3c5`，同时在 EL2 中拉起 `[ISP_HA] <com.mediatek.geniezone.isp>` 和 `[MTEE_SENINF] <com.mediatek.geniezone.srv.imgsensor>`。
   - **LK 传递的完整内核命令行（实机捕获，1036 B）**：包含 `ramoops.mem_address=0x4d010000 ramoops.mem_size=0xe0000 ramoops.pmsg_size=0x10000 ramoops.console_size=0x40000`、`androidboot.boot_devices=bootdevice,soc/11230000.mmc,11230000.mmc,soc/11230000.msdc,11230000.msdc`、`androidboot.verifiedbootstate=orange`、`mtk_printk_ctrl.disable_uart=1`、`androidboot.set_valtage=4304`、`androidboot.dtbo_idx=0` 等。

4. **逆向 `jt120wul005_a01_dsi_vdo` 面板参数（来自 `lk_a.img`）**：
   - **Panel IC**：Himax HX83102-E/J TDDI（`compare_id` 读取 DCS `0xDA/0xDB/0xDC` 期待 **`0x83, 0x10, 0x21`**）。
   - **分辨率与物理尺寸**：`1200 x 2000`，物理尺寸 `156 x 261 mm`。
   - **DSI 配置**：4-Lane，`BURST_VDO_MODE (3)`，`RGB888 (2)`，`packet_size = 256`，`PLL_CLOCK = 612` (`cont_clock = 1`)。
   - **精确时序 (`get_params`)**：
     - 垂直：`VSA = 8`, `VBP = 28`, `VFP = 100`, `VACT = 2000`（总计 2136 行）
     - 水平：`HSA = 59`, `HBP = 100`, `HFP = 140`, `HACT = 1200`（总计 1499 像素）
   - **上电时序 (`lcm_init_power`)**：GPIO 153 (`lcm_bias`) 拉高 -> I2C `0x3e` (AW37503) 写 `reg 0x00 = 0x12` -> 延时 5ms -> GPIO 70 (`lcm_enn`) 拉高 -> I2C `0x3e` 写 `reg 0x01 = 0x12`。
   - **DCS 初始化表**：共 **73 条目**（含 `0xB9 0x83 0x10 0x21 ...` 解锁扩展指令及各页面配置、`0x11` Sleep Out + 100ms、`0x29` Display On + 40ms），完整命令表已保存至 `/home/asus/zpd1203-6.6/extracted_stock/misc/jt120wul005_init_cmds.txt`。

---

## 3. 设备树 (`merged_stock.dts`) 硬件资源与驱动映射

将 `main_dtb_0.dtb` 与 `dtbo_a_0.dtb` 通过 `fdtoverlay` 合并得到完整 `merged_stock.dts`（5,968 行）。

### 3.1 DTS `reserved-memory` 节点（需与 LK `mblock` 协同）

| 节点名 | Compatible | 属性 / 大小 | 分配范围 |
|---|---|---|---|
| `ssmr-reserved-cma_memory` | `shared-dma-pool` | `reusable`, `256 MiB` (`0x10000000`), align `16 MiB` | `0xc0000000 .. 0xd0000000` |
| `reserve-memory-sspm_share` | `mediatek,reserve-memory-sspm_share` | `no-map`, `0x510000` (~5.06 MiB) | `0x40000000 .. 0xa0000000` |
| `reserve-memory-scp_share` | `mediatek,reserve-memory-scp_share` | `no-map`, `13 MiB` (`0xd00000`) | `0x40000000 .. 0x90000000` |
| `ion-carveout-heap` | `mediatek,ion-carveout-heap` | `no-map`, `36 KiB` (`0x9000`) | `0xc0000000 ..` |
| `consys-reserve-memory` | `mediatek,consys-reserve-memory` | `no-map`, `4 MiB` (`0x400000`) | `0x40000000 .. 0xc0000000` |
| `wifi-reserve-memory` | `shared-dma-pool` | `no-map`, `3 MiB` (`0x300000`) | `0x40000000 .. 0xc0000000` |

### 3.2 总线、外设 IC 与 DTS Compatible 映射表

| 子系统 | DTS 节点 / 总线地址 | Compatible 字符串 | 关键硬件参数 / GPIO / 中断 | 状态 |
|---|---|---|---|---|
| **显示控制器** | `dsi0@14014000`, `mtkfb@0`, `lcm` | `mediatek,dsi0`, `mediatek,mtkfb`, `mediatek,mt6769-lcm` | `dsi0` IRQ SPI `0xee`; `lcm_rst`=GPIO 45, `lcm_dsi_te`=GPIO 44 (func1), `lcm_1v8_en`=GPIO 165, `lcm_bias`=GPIO 153, `lcm_enn`=GPIO 70, `key_rom`=GPIO 92 | `okay` |
| **显示偏压 PMIC** | **I2C7 (`0x11004000`)** `aw37503@3e` | `aw,aw37503` | I2C 地址 `0x3e`（正负压 +/- 5.xV） | `okay` |
| **背光 PWM** | `disp_pwm@1100e000`, `led@6` | `mediatek,disp_pwm`, `mediatek,lcd-backlight` | `led_mode = <5>`, `pwm_config = <0 3 0 0 0>` | `okay` |
| **触摸屏 (TDDI)** | **SPI4 (`0x11014000`)** `zlt_ts@0` | `"himax,hxcommon", "focaltech,fts"` | `spi-max-frequency = 9600000` (`0x927c00`), `himax,display-coords = <1200 2000>`, SPI4 IRQ `0x74`, CS/CLK/MO/MI = **GPIO 17..20 (func2)**, **INT = GPIO 6**, **RST = GPIO 158** (`0x9e`) | `ok` |
| **GPU** | `mali@13040000`, `ged` | `"mediatek,mali", "arm,mali-valhall"`, `mediatek,ged` | IRQ `0x112..0x116` (`GPU/MMU/JOB/EVENT/PWR`), `ged-supply` | `okay` |
| **PMIC & 库仑计** | `pwrap@1000d000` -> `mt6358-pmic`, `battery` | `mediatek,mt6358-pmic`, `mt6358-auxadc`, `mt6358_gauge`, `mediatek,bat_gm30` | `batteryID-channel` AUXADC ch2; 含多温区 `battery0/1` OCV 曲线 (`R_FG_VALUE=5`, `CAR_TUNE_VALUE=0x61`) | `okay` |
| **主充电 IC** | **I2C5 (`0x11016000`)** `sgm41510@6B` | `sgm,sgm41510` (`primary_chg`) | **IRQ = GPIO 26 (`0x1a`)**, **CHG_EN = GPIO 166 (`0xa6`)**, AUXADC ch4, `charge-current=2.04A`, `vreg=4.336V`, `boost=5V/2.4A`, `en-ilim=1` | `okay` |
| **从充电 & SubPMIC** | **I2C7** `slave_charger@4b`; **I2C5** `subpmic_pmu@34`, `usb_type_c@4e` | `mediatek,slave_charger`, `mediatek,subpmic_pmu`, `mediatek,usb_type_c` | `charger` 节点算法 `"SwitchCharging"`, 使能 `enable_type_c`, `enable_sw_jeita`, `power_path_support`, `ta_9v_support` | `okay` |
| **Type-C PD / CC / QC** | **I2C6 (`0x1100d000`)** `aw35615@22`, `wusb3801@60`, `z350@35` | `awinic,aw35615`, `mtk,i2c_wusb3801`, `fire,i2c_z350` | `aw35615`: `int_n`=**GPIO 8**, `id-gpio`=**GPIO 159** (`0x9f`); `wusb3801`: `irq`=**GPIO 8**; `z350`: `irq`=**GPIO 10**, `reset`=**GPIO 71** (`0x47`) | `okay` |
| **电池鼓包检测** | `battery_swell_det` | `battery-swell-det` | `left`=**GPIO 56** (`0x38`), `right`=**GPIO 69** (`0x45`), AUXADC ch3, debounce `100` | `okay` |
| **USB 2.0 OTG** | `usb0@11200000`, `extcon_usb` | `mediatek,mt6768-usb20`, `mediatek,extcon-usb` | IRQ `0x61`, `dr_mode = "otg"`, `usb-role-switch`, `id-gpios` = **GPIO 41** (`0x29`) | `okay` |
| **eMMC 存储** | `mmc@11230000` | `mediatek,mt6768-mmc` | `bus-width=8`, `200MHz`, HS400 + **`mediatek,cqhci`**, `no-sdio`, `no-sd`, `non-removable` | `okay` |
| **SD 卡控制器** | `mmc@11240000` | `mediatek,mt6768-mmc` | — | **`disabled`** |
| **音频 SoC / Codec** | `mt6768-afe-pcm@11220000`, `mt6358_snd`, `sound`, `accdet` | `mediatek,mt6768-sound`, `mediatek,mt6358-sound`, `mediatek,mt6768-mt6358-sound`, `mediatek,pmic-accdet` | `mtk_spk_i2s_out = 3`, `mtk_spk_i2s_in = 0`, DAI -> `speaker_amp@34` | `okay` |
| **外置音频功放** | **I2C3 (`0x1100f000`)** & **I2C7** | `foursemi,fs15xx` (`@35`, `@36`), `awinic,aw87xxx_pa` (`@59`, `@5a`), `mediatek,speaker_amp` (`@34`) | 注：`aw87xxx_pa@58/@5b` 为 `disabled`；DTS 中同时启用两对双路兼容 PA 节点供运行时探测 | `okay` |
| **Wi-Fi / BT / GPS / FM** | `consys@18002000` | `mediatek,mt6768-consys` | `wifi_ant_swap_gpio` = **GPIO 108** (`0x6c`), `gps_lna` = **GPIO 94** (`0x5e`), 绑定 `consys-reserve-memory` | `okay` |
| **传感器** | **I2C1 (`0x11008000`)** | `mediatek,sc7a20` (`@18`), `mediatek,mc3416` (`@36`), `mediatek,gsensor` (`@4c`), `mediatek,ucs14266` (`@38`), `mediatek,ls9801i` (`@54`) | `ucs14266` & `ls9801i` 共用 **EINT 7**；`zlt_alsps` LED = **GPIO 159** (`0x9f00`) | `okay` |
| **霍尔 / 按键 / 红外 / 其他** | 平台节点 | `mediatek,hall`, `mediatek,hall-sensor`, `mediatek,kp`, `mediatek,irtx-pwm`, `mediatek, mrdump_ext_rst-eint`, `zlt-sysfs` | `hall` EINT 9, `hall_sensor` EINT 32, `kp` GPIO 93 (func1), `irtx_pwm` GPIO 12 (func0/1), `mrdump_ext_rst` EINT 0 / GPIO 0 | `okay` |
| **摄像头 & 闪光灯** | `kd_camera_hw1@1a040000`, **I2C2 / I2C3 / I2C4 / I2C7** | `mediatek,camera_main@1a` (I2C2), `camera_main_two@10` (I2C3), `camera_sub@2d` (I2C4), `flashlight,aw36515_i2c@63` (I2C7) | `cam0_enable_sensor = "sc800cs_mipi_raw hi849_mipi_raw"`, `cam1_enable_sensor = "sc800cssub_mipi_raw s5k4h7_mipi_raw"` | `okay` |

### 3.3 I2C 总线引脚汇总 (`merged_stock.dts`)

| 总线 | 基地址 | SCL / SDA GPIO | 挂载设备 |
|---|---|---|---|
| `i2c0` | `0x11007000` | GPIO 83 / GPIO 82 | （保留/无板载子节点） |
| `i2c1` | `0x11008000` | GPIO 84 / GPIO 81 | 加速度计 (`sc7a20@18`, `mc3416@36`, `gsensor@4c`)、光距感 (`ucs14266@38`, `ls9801i@54`) |
| `i2c2` | `0x11009000` | GPIO 103 / GPIO 104 | 主摄传感器 (`camera_main@1a`, EEPROM, AF, CCU) |
| `i2c3` | `0x1100f000` | GPIO 50 / GPIO 51 | 双功放 (`fs15xx@35/36`, `aw87xxx_pa@59/5a`)、副摄 (`camera_main_two@10`) |
| `i2c4` | `0x11011000` | GPIO 105 / GPIO 106 | 前摄传感器 (`camera_sub@2d`, EEPROM, CCU) |
| `i2c5` | `0x11016000` | GPIO 48 / GPIO 49 | 主充 `sgm41510@6b`、`subpmic_pmu@34`、`usb_type_c@4e` |
| `i2c6` | `0x1100d000` | GPIO 89 / GPIO 90 | PD `aw35615@22`、CC `wusb3801@60`、QC3.5 `z350@35` |
| `i2c7` | `0x11004000` | GPIO 175 / GPIO 176 | 屏偏压 `aw37503@3e`、从充 `slave_charger@4b`、闪光灯 `aw36515@63`、功放 `speaker_amp@34` |
| `i2c8` | `0x11005000` | — | 无启用外设 |

---

## 4. `super.img` 逻辑分区与系统属性分析

使用 `lpdump` 检查 `/mnt/d/备份/p/GeekFlashTool_Readback_20260820162108246/super.img`（`16,106,127,360` 字节）：
- **Metadata 版本**：`10.2`，标志 `virtual_ab_device`，Group `qti_dynamic_partitions_a/b`。
- **实际分区布局**：仅 Slot `_a` 分配有 Extent（`_b` 全为空）：
  - `product_a`：`388,136` sectors = **`198,725,632` B (~190 MiB)**，ext4，原厂 ZYB Android 12 (`ro.product.ab_ota_partitions=boot,system,product,vendor`)。
  - `system_a`：`4,876,096` sectors = **`2,496,561,152` B (~2.33 GiB)**，ext4。**实测为第三方 GSI** (`ro.build.id=UQ1A.240205.004`, `ro.build.version.release=14`, `ro.build.version.sdk=34`, `ro.lineage.version=21.0-20240217-UNOFFICIAL-arm64_bvN`, `ro.lineage.device=tdgsi_arm64_ab`)。
  - `vendor_a`：`1,723,976` sectors = **`882,675,712` B (~842 MiB)**，ext4，**完整原厂 ZYB Android 12**。

**核心 `vendor/build.prop` 与 `odm/etc/build.prop` 属性**：
- 设备代号：`ro.product.vendor.brand=ZYB`, `model=ZPD1203`, `device=k69v1_64_k419`, `zybname=ZYBPAD`, `ro.board.platform=mt6768`, `ro.vendor.mediatek.platform=MT6768`
- 版本与 ABI：`ro.vendor.build.version.release=12`, `sdk=31`, `ro.vndk.version=31`, `ro.product.first_api_level=31`, `ro.board.first_api_level=30`, `ro.vendor.build.security_patch=2024-07-05`, `abilist=arm64-v8a,armeabi-v7a,armeabi`
- 显示与旋转关键属性：
  - **`ro.minui.default_rotation=ROTATION_LEFT`**
  - **`vendor.lcm_rotation=1`**
  - `ro.sf.lcd_density=280`
  - `ro.hardware.hwcomposer=mtk_common`
  - `ro.opengles.version=196610` (OpenGL ES 3.2)
  - `ro.vendor.mtk_pq_support=2`, `ro.vendor.mtk_pq_color_mode=1`, `ro.vendor.mtk_ovl_bringup=0`

---

## 5. 原厂内核模块 (`vendor/lib/modules`) 与固件 (`vendor/firmware`)

### 5.1 `vendor/lib/modules/` 全部 11 个 `.ko` 模块清单

所有模块均编译自原厂 `4.19.191` 内核（`vermagic: 4.19.191 SMP preempt mod_unload modversions aarch64`），严格按 `/vendor/lib/modules/modules.load` 顺序管理。**Linux 6.6 严禁直接复用这些旧 `.ko`，必须按功能重新编译或替代。**

| 加载顺序 (`modules.load`) | 模块名 | 大小 (B) | `depends` | 关键 MTK/WCN 外部符号依赖 (`nm -u`) |
|---|---|---|---|---|
| 1 | `trace_mmstat.ko` | 32,880 | (无) | `ion_mm_heap_total_memory`, `mtk_get_gpu_memory_usage` |
| 2 | `bt_drv_connac1x.ko` | 89,456 | `wmt_drv` | `mtk_wcn_stp_*`, `mtk_wcn_wmt_*`, `connsys_log_*` (23 项) |
| 3 | `wmt_drv.ko` | 1,586,336 | (无) | `mtk_wcn_btif_*`, `connectivity_export_*`, `emi_mpu_set_protection`, `aed_combo_exception_api`, `aee_*` (37 项，SDIO alias `0x037A:*`) |
| 4 | `connfem.ko` | 70,256 | (无) | 仅标准内核 chrdev/OF 符号 |
| 5 | `fmradio_drv_mt6631.ko` | 395,208 | `wmt_drv` | `mtk_wcn_stp_*`, `mtk_wcn_wmt_*` (12 项) |
| 6 | `gps_drv.ko` | 61,296 | `wmt_drv` | `mtk_wcn_stp_*`, `mtk_wcn_wmt_*`, `mtk_wmt_get_gps_lna_pin_num`, `mtk_wmt_gps_*`, `connsys_log_*` (22 项) |
| 7 | `wmt_chrdev_wifi.ko` | 73,368 | `wmt_drv` | `mtk_wcn_wmt_func_on/off`, `connsys_log_*` (10 项) |
| 8 | `wlan_drv_gen4m.ko` | 3,936,656 | `wmt_drv`, `wmt_chrdev_wifi` | `mtk_wcn_wmt_wlan_reg/unreg`, `gConEmiPhyBase`, `gConEmiSize`, `emi_mpu_set_protection`, `lbat_user_register`, `wifi_fwlog_*`, `wifi_ics_*`, `wifi_reset_*` (29 项) |
| 9 | `fpsgo.ko` | 62,920 | (无) | `fpsgo_xgf2ko_*`, `xgf_get_display_rate` (3 项，License: Proprietary) |
| 10 | `met.ko` | 4,384 | (无) | 仅标准符号 |
| 11 | `udc_lib.ko` | 45,608 | (无) | 仅标准符号 |

*(注：完整符号列表见 `/home/asus/zpd1203-6.6/extracted_stock/modules/all_modinfo.txt` 与 `all_undef_syms.txt`。)*

### 5.2 `vendor/firmware/` 全部 25 个固件文件清单

| 分类 | 文件名 | 大小 (B) | 内部标识 / 用途 |
|---|---|---|---|
| **Himax 触控** | `Himax_firmware.bin` | 261,120 | `HX83102-J`, `1.0.2.51`, `WBOE11.97` *(已提取至 `extracted_stock/firmware/`)* |
| **Himax 触控** | `Himax_firmware_j02.bin` | 261,120 | `HX83102-J`, `1.0.2.43`, `WZYB_BOE11.97` *(已提取)* |
| **Himax 触控** | `Himax_firmware_hjr.bin` | 261,120 | `HX83102-J`, `1.0.2.38` *(已提取)* |
| **Himax 触控** | `Himax_firmware_lce.bin` | 261,120 | `HX83102-J`, `1.0.2.38` *(已提取)* |
| **Himax 触控** | `Himax_firmware_e.bin` | 131,072 | `HX83102-E`, `1.0.2.41` *(已提取)* |
| **Himax 触控** | `Himax_firmware_e_lmibe.bin` | 131,072 | `HX83102-E`, `1.0.2.38`, `WLCE_YK_102E` *(已提取)* |
| **FocalTech 触控** | `focaltech_ts_fw_hjr.bin`, `focaltech_ts_fw_lce.bin` | 120,860 / 127,280 | 兼容触控固件 |
| **Connsys Wi-Fi/BT** | `WIFI_RAM_CODE_soc1_0_1a_1.bin` | 648,088 | Wi-Fi RAM Code |
| **Connsys MCU/Patch** | `soc1_0_patch_mcu_1a_1_hdr.bin`, `soc1_0_ram_mcu_1a_1_hdr.bin`, `soc1_0_ram_wifi_1a_1_hdr.bin`, `soc1_0_ram_bt_1a_1_hdr.bin` | 25,790 / 105,440 / 197,628 / 571,125 | Connsys ROM Patch 与 Wi-Fi/BT/MCU 固件 |
| **Connsys 配置** | `WMT_SOC.cfg` (166 B), `BT_FW.cfg` (443 B) | 166 / 443 | WMT/BT 固件加载参数 |
| **FM 收音机** | `fm_cust.cfg` (304 B), `mt6631_fm_v1_coeff.bin` (1,092 B), `mt6631_fm_v1_patch.bin` (1,028 B) | 304 / 1,092 / 1,028 | MT6631 FM 系数与补丁 |
| **音频 SmartPA** | `aw87xxx_acf.bin` (1,556 B), `awinic_params.bin` (16,416 B), `awinic_sinwave_params.bin` (16,416 B) | 1,556 / 16,416 | Awinic AW87xxx 算法参数 |
| **音频 SmartPA** | `fs15xx.fsm` (692 B), `fs1801.fsm` (7,816 B) | 692 / 7,816 | FourSemi FS15xx 固件参数 |
| **相机 / SCP** | `lib3a.ccu` (38,400 B), `remoteproc_scp` (32 B) | 38,400 / 32 | 相机 CCU 3A 与 SCP 固件 |

---

## 6. 原厂 Vendor HAL 与用户空间 ABI 依赖矩阵（Phase 5 & 6 核心依据）

### 6.1 Mali-G52 MC2 GPU 用户空间 ABI

- **库文件**：`/vendor/lib64/egl/libGLES_mali.so` (39.7 MB)、`/vendor/lib/egl/libGLES_mali.so` (28.5 MB)、`/vendor/lib64/hw/vulkan.mt6768.so -> /vendor/lib64/egl/libGLES_mali.so`
- **GPU 型号与 DDK 版本（实测字符串）**：
  - **`Mali-G52 MC2`**
  - **`1.4 Bifrost-"r32p1-01eac0"`** / `U:r32p1-01eac0`
  - 构建源码路径：`vendor/mediatek/proprietary/hardware/gpu_mali/mali_valhall/r32p1-00bet0/...`
  - **严格匹配要求**：6.6 内核侧必须提供 **Mali kbase `r32p1` 兼容版本（或确认 UK_VERSION 完全兼容 `r32p1-01eac0`）** 及配套 `ged` 内核接口，才可保证真实 GPU 硬件渲染。
- **设备节点与链接依赖 (`readelf -d`)**：
  - 打开设备节点：`/dev/mali`（`ueventd.rc` 创建 `/dev/mali0 0666 system graphics`）。
  - 核心依赖共享库：`libged.so`（访问 `/proc/ged` 调度与 DVFS ioctl）、`libdmabufheap.so`、`libion_mtk.so`、`libion.so`、`libgralloc_extra.so`、`libgpu_aux.so`、`libgpud.so`、`libladder.so`、`libgralloc_metadata.so`、`libgralloctypes_mtk.so`、`arm.graphics-V1-ndk_platform.so`、`android.hardware.graphics.mapper@4.0.so`。

### 6.2 显示合成、内存分配、PQ 与 Memtrack HAL

| Vendor 二进制 / SO | 打开的 `/dev`、`/proc`、`/sys` 节点 | 关键 IOCTL / 动态库依赖 |
|---|---|---|
| `hwcomposer.mt6768.so` (`composer@2.1-service`) | `/dev/mtk_disp_mgr`, `/dev/graphics/fb` (`fb0`), `/proc/m4u` | `DISP_IOCTL_CREATE_SESSION`, `DESTROY_SESSION`, `FRAME_CONFIG`, `GET_DISPLAY_CAPS`, `GET_MULTI_CONFIGS`, `GET_PRESENT_FENCE`, `GET_SESSION_INFO`, `PREPARE_INPUT_BUFFER`, `PREPARE_OUTPUT_BUFFER`, `QUERY_VALID_LAYER`, `SET_INPUT_BUFFER`, `SET_OUTPUT_BUFFER`, `SET_SESSION_MODE`, `SUPPORT_COLOR_TRANSFORM`, `TRIGGER_SESSION`, `WAIT_ALL_JOBS_DONE`, `WAIT_DISP_SELF_REFRESH`, `WAIT_FOR_VSYNC`, `FBIOBLANK`; 依赖 `libdpframework.so` (`/dev/mtk_cmdq`, `/dev/mdp_sync`, `/dev/sw_sync`) |
| `vendor.mediatek.hardware.pq@2.15-impl.so` | `/dev/dri/card0` 及 `/dev/mtk_disp_mgr` | `DISP_IOCTL_GET_LCMINDEX`, `IOCTL_MTK_GET_CHIST`, `IOCTL_MTK_BYPASS_COLOR`, `IOCTL_MTK_PQ_SET_WINDOW` |
| `android.hardware.graphics.allocator@4.0-impl-mediatek.so` & `mapper@4.0-impl-mediatek.so` | `/dev/ion`, `/dev/dma_heap/mtk_mm`, `mtk_mm-uncached`, `mtk_svp_*`, `mtk_wfd_*` (`ueventd.rc`) | 同时链接 `libdmabufheap.so`, `libion_mtk.so`, `libion.so`, `libdrm.so`, `libged.so`, `libgralloc_extra.so`, `arm.graphics-V1-ndk_platform.so` |
| `libgralloc_extra.so` | `/dev/ion` | `ION_IOC_CUSTOM` |
| `android.hardware.memtrack-service.mediatek` | `/proc/dma_heap/rss_pid`, `/proc/ion/clients/clients_summary`, `/proc/mali/memory_usage`, `/proc/mtk_mali/gpu_memory`, `/sys/kernel/debug/ion/clients/clients_summary` | — |

### 6.3 无线、音频、电源/充电、USB、传感器、相机与安全 HAL

| 子系统 | Vendor HAL / 守护进程 / Init RC | 关键设备节点 / Sysfs / Procfs / IOCTL |
|---|---|---|
| **无线 Connsys (Wi-Fi/BT/FM/GPS)** | `init.wmt_drv.rc`, `init.wlan_drv.rc`, `wmt_loader`, `wmt_launcher`, `wlan_assistant`, `bluetooth@1.1-service-mediatek`, `gnss-service.mediatek`, `wpa_supplicant`, `hostapd` | `/dev/wmtdetect` (`COMBO_IOCTL_CONNSYS_SOC_HW_INIT`), `/dev/stpwmt` (`WMT_IOCTL_SET_ROM_PATCH_INFO`), `/dev/wmtWifi`, `/dev/stpbt`, `/dev/stpgps`, `/dev/gps`, `/dev/gps_emi`, `/dev/stpant`, `/dev/fm` (`FM_IOCTL_*`), `/dev/btif`, `/proc/driver/wmt_dbg`, 属性 `vendor.connsys.driver.ready=yes` |
| **USB / ADB / MTP** | `android.hardware.usb@1.2-service-mediatekv2`, `init.mt6768.usb.rc` | ConfigFS `/config/usb_gadget/g1` (`idVendor=0x0E8D`), **UDC 硬编码 `"musb-hdrc"`**, `/dev/usb-ffs/{adb,mtp,ptp}`, `/sys/class/typec/`, `/sys/class/udc/`, `/sys/class/usb_role/`（以及 `cmode`/`saving`/`portmode`） |
| **电池 / 充电 / 电量计** | `android.hardware.health@2.1-service`, `fuelgauged`, `fuelgauged_nvram`, `battery_health` | `/sys/class/power_supply/{battery,ac}`, `/dev/MT_pmic_adc_cali`, `/dev/RT_Monitor`, `/dev/otp`, `/sys/devices/platform/battery/bat_health`, `/sys/devices/platform/battery_swell_det/battery_swell`, `/sys/devices/platform/battery_meter/FG_daemon_log_level`, `/sys/bus/platform/devices/battery/FG_daemon_log_level` |
| **音频** | `android.hardware.audio.service.mediatek`, `audio.primary.mt6768.so`, `awinic.audio.effect.so`, `audio_device.xml` | ALSA 卡名 `mt6768mt6358`; `/dev/accdet`, `/dev/ebc`, `/dev/fm`, `/dev/ccci_aud`, `/proc/asound/*`, `/sys/bus/platform/devices/zlt_sysfs/zlt_codec_name`, `/sys/bus/platform/drivers/Accdet_Driver/state`, `Ext_Speaker_Amp Switch` |
| **传感器** | `android.hardware.sensors@2.0-service.multihal-mediatek`, `sensors.mt6768.so` | `/dev/m_{acc,als,ps,gyro,mag,...}_misc`, `/dev/sensorlist`, `/sys/class/sensor/m_*_misc/*` |
| **温控 / 背光** | `android.hardware.thermal@2.0-service.mtk`, `thermal`, `android.hardware.lights-service.mediatek` | `/sys/class/thermal/thermal_zone%d/{temp,type}`, `/sys/class/thermal/cooling_device%d/*`, `/proc/driver/thermal/{clwmt_pid,tp_pid}`, `/sys/class/leds/lcd-backlight/brightness` |
| **相机** | `camerahalserver` (`camera.provider@2.6`), `libmtkcam_*.so` | `/dev/kd_camera_hw`, `/dev/camera-isp`, `/dev/camera-{dip,tsf,dpe,mfb,rsc,owe,fdvt,wpe,mem,sysram,pipemgr}`, `/dev/seninf`, `/dev/flashlight`, **`/dev/gz_kree`**, `/proc/m4u` |
| **加密 / Boot / ZRAM / NVRAM** | `keymaster@4.1-service`, `gatekeeper@1.0-service`, `boot@1.2-service`, `nvram_daemon`, `init.mt6768.rc` | Keymaster/Gatekeeper 为**纯软件实现**；`boot@1.2` 读 `/dev/block/by-name` 与 `/proc/bootconfig`/`/proc/cmdline`；`nvram_daemon` 访问 `/dev/mtk-adc-cali`；`init.mt6768.rc` 写 `/sys/block/zram0/comp_algorithm` (`lz4`)、`/proc/bootprof`、`/dev/spm` |

---

## 7. 对 Linux 6.6 移植工作的直接指导意义 (Phase 3–7 Actionable Checklist)

1. **Boot 打包与测试策略 (Agent 4 / Agent 7)**：
   - 必须以 Boot Header v2（page_size=2048，基地址 `0x40080000`/`0x47c80000`/`0x4bc80000`）打包 `boot.img`，并使用 **`vendor_boot_a.img` 解出的纯净 ramdisk** 作为基础，避免引入 `boot_a` 的 Magisk 残留。
   - **重要安全提示**：原厂设备 Slot A 为实际可用 Android 12 Vendor + 第三方 GSI (`system_a`)，而 Slot B `super` 中无任何逻辑分区映射。因此测试时优先验证 `lk_a` 的 `fastboot boot`；若需临时写入，务必保留针对 `vendor_boot_a` 原始镜像和 `boot_a` 原始镜像的一键恢复方案。
   - 显式保留与 LK 一致的 **`ramoops` 地址 `0x4d010000` (大小 `0xe0000`)** 并在 `reserved-memory` 中添加 `no-map`（避开 LK 已占用的 ATF/TEE/GZ/SSPM/Framebuffer 地址），实现无 UART 多级日志留存。

2. **显示、触摸与 GPU 适配路线 (Agent 5)**：
   - **Panel 驱动**：围绕 **`jt120wul005_a01_dsi_vdo` (HX83102-E/J 1200×2000)** 实现真实 DSI 面板与 AW37503 (`I2C7 @0x3e`) + 4 路 GPIO 控制。**禁止被静态 DTB 中的 `hx83112b` 误导。**
   - **显示 HAL 架构决策**：原厂 `hwcomposer.mt6768.so` 依赖 `/dev/mtk_disp_mgr` + `/dev/graphics/fb0`（而非单纯 DRM/KMS）。若 6.6 BSP 仅提供标准 MTK DRM/KMS，则必须评估“提供符合 DRM 的 HWC/显示桥接兼容性方案（需真实硬件加速）”或“在 6.6 兼容层中支持关键 `mtk_disp_mgr` / `fb0` 接口”。
   - **触摸屏**：必须在 6.6 上移植或适配 **SPI4 (`11014000.spi`, CS/CLK/MO/MI=GPIO17..20, INT=GPIO6, RST=GPIO158)** 下的 Himax `HX83102-E/J` 驱动（配合 `/vendor/firmware/Himax_firmware*.bin` 及横屏坐标映射）。
   - **Mali-G52 GPU**：用户态确定为 **`r32p1-01eac0`**。6.6 内核需集成匹配 `r32p1` UK ABI 的 `mali_kbase` 与 `ged` 驱动（暴露 `/dev/mali0` 和 `/proc/ged`），并验证与原厂 `libGLES_mali.so` 的 `dmabufheap`/`ion` 兼容。

3. **USB、充电状态上报修复与电源管理 (Agent 6)**：
   - **USB 控制器路径核对**：原厂 USB 为 **`musb-hdrc` (`11200000`)**，且 `init.mt6768.usb.rc` 与 USB HAL 期待 `"musb-hdrc"` 及 `/sys/class/typec/`。若在 6.6 中使用 `musb` 或切换 `mtu3`，必须同步确认控制器与 UDC 节点匹配 `vendor/etc/init/hw/init.mt6768.usb.rc`。
   - **重点修复 5.10 USB 充电状态上报缺失**：原厂电路在 **I2C5 (`sgm41510@6b`, `usb_type_c@4e`) + I2C6 (`aw35615@22` PD, `wusb3801@60` CC, `z350@35` QC3.5) + I2C7 (`slave_charger@4b`) + `mt6358_gauge` + `extcon_usb` (ID GPIO 41)** 间存在多芯片协同上报。6.6 移植必须打通 Type-C/CC/PD -> USB 角色/充电器类型识别 (`power_supply` `usb`/`ac`/`battery` 的 `online`/`status`/`type`/`current_max`/`voltage_max`)，并检查 `/sys/class/power_supply/*` 节点与 `health@2.1` HAL 的真实联动。

4. **无线 Connsys、音频与相机评估 (Agent 6 & Agent 7)**：
   - **无线模块**：参考原厂 11 个 `.ko` 的依赖树（`connfem` -> `wmt_drv` -> `wmt_chrdev_wifi` / `bt_drv_connac1x` / `gps_drv` / `fmradio_drv_mt6631` -> `wlan_drv_gen4m`），全部基于目标 6.6 内核源码树重新编译，并加载 `/vendor/firmware/soc1_0_*` 及 `WIFI_RAM_CODE_soc1_0_1a_1.bin`。
   - **存储与加密**：必须开启 `CONFIG_MMC_MTK`, `CONFIG_MMC_CQHCI`, `CONFIG_EXT4_FS`, `CONFIG_EXT4_FS_ENCRYPTION`, `CONFIG_BLK_INLINE_ENCRYPTION` (`inlinecrypt`), `CONFIG_DM_VERITY`, `CONFIG_ZRAM` (`lz4`)，否则无法挂载 `/data` 与 `super` 动态分区。
   - **DMA-BUF / ION**：`allocator@4.0` / `mapper@4.0` 与 `libGLES_mali.so` 同时链接 `libdmabufheap.so` 和 `libion_mtk.so`/`libion.so`，而 Linux 6.6 已彻底移除内核 ION 框架。6.6 必须提供完整 `/dev/dma_heap/*`（包括与 `ueventd.rc` 对应的 `mtk_mm`、`mtk_mm-uncached` 等命名堆或兼容包装）并验证 `mapper@4.0` 与 `libgralloc_extra.so` 的实际运行路径。
   - **相机阻塞警告**：`camerahalserver` 依赖 `/dev/gz_kree` 与 GenieZone EL2 内的安全相机服务 (`ISP_HA`/`MTEE_SENINF`)。6.6 移植若无法完整对接 `mtk_gz_kree` 与全套 MTK ISP/Seninf 内核驱动，相机将继续无法工作，需要在 Phase 5 结合 6.6 BSP 源码深度核查。

---

## 8. 已提取原厂工作文件索引 (`/home/asus/zpd1203-6.6/extracted_stock/`)

| 提取目录 / 文件 | 内容说明 |
|---|---|
| `vendor_boot/` | 纯净原厂 `boot.img` 解包产物（`Image`, `dtb`, `stock.config` 5,432 行, `ramdisk_unpacked/` 462 文件, `unpack_human.txt`） |
| `boot/` & `boot_b/` | `boot_a.img` (Magisk) 与 `boot_b.img` (5.10.198 诊断内核 `7,796` 行 config) 解包对比产物 |
| `dtbo/` & `dts/` | `dtbo_a_0.dtb`, `dtbo_b_0.dtb`, `main_dtb_0.dts` (4,636 行), `dtbo_a_0.dts` (2,032 行), `merged_stock.dts` (5,968 行) |
| `misc/` | `expdb_pl_lk_log.txt` (PL/LK/GZ 实机日志), `lk_a_detailed.txt`, `lk_a_interesting_strings.txt`, `jt120wul005_init_cmds.txt` (73 条面板 DCS 指令) |
| `super/` | `lpdump.txt`, `images/{product_a,system_a,vendor_a}.img`, `vendor/`, `product/`, `system_meta/` |
| `modules/` | `all_modinfo.txt`, `all_undef_syms.txt` (全部 11 个原厂 `.ko` 元信息与符号依赖) |
| `firmware/` | 提取出的 6 份 `Himax_firmware*.bin` 与 `vendor_firmware_list.txt` |
| `hal/` | `hal_nodes_ioctls.txt` (全部核心 Vendor HAL/BIN 节点、属性与 IOCTL 字符串提取) |
