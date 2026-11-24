# ZPD1203 Linux 6.6 移植进度追踪 (PORTING_STATUS.md)

- **当前阶段**：**Phase 0–7 宿主机开发、洁净集成构建与静态校验已全部完成**（`full` + `minimal` 双模式均达 **`已编译通过` / `已静态验证`**）；待用户在真机执行非破坏性测试并返回实机日志。
- **目标内核**：**`6.6.144-zpd1203-g91af1aa18e1a`**（零 `-dirty` 后缀；`AOSP android15-6.6` `91af1aa18e1a` + `Addster09` BSP `8ed4bf689504` + Moto GPU `2d3b928b88ce` + Moto Connsys 5 仓）
- **原厂基线**：ZYB Android 12 (`vendor_boot_a.img` 4.19.191 / VNDK 31，`super` 含 LineageOS 21 Android 14 GSI `system_a`)
- **参考移植**：`idkwhatismyname123/zpd1203-5.10.240` (`test25` / `8a74a527`)

## 阶段里程碑状态

| 阶段 | 描述 | 状态 | 备注 |
|---|---|---|---|
| Phase 0 | 工程文档、Git 仓库与 WSL2 工具链检查 | 已完成 | 8 份规范文档 + WSL2 工具链校验通过 |
| Phase 1 | 5.10 仓库深度解析 + 原厂备份只读提取分析 | 已完成 | `analysis/phase1_510_port_analysis.md` & `analysis/phase1_stock_analysis.md` |
| Phase 2 | 六系内核源码调查与基底选型 | 已完成 | `analysis/phase2_bsp_survey.md`，定案 Linux 6.6.144 组合架构 |
| Phase 3 | 核心板级支持迁移（DTS/时钟/PMIC/存储/USB/Android核心） | 已编译通过 / 已静态验证 | 补丁归档 `patches/phase3_4/` |
| Phase 4 | 无 UART 调试体系与最小可启动内核构建 | 已编译通过 / 已静态验证 | 洁净重建 `out/minimal/boot-minimal-6.6.img` (Boot v2, `< 32 MiB`) |
| Phase 5 | 完整硬件驱动（DRM 显示/触屏/GPU/无线/音频/SGM41510+AW35615充电/Thermal） | 已编译通过 / 已静态验证 | 补丁 `patches/phase5_display_gpu_touch/` + `patches/phase5_wireless_audio_power/`；摄像头 EL2 依赖标为 `已知故障` |
| Phase 6 | Android 12 Vendor ABI 兼容（`/dev/ion` -> DMA-BUF Heap `mtk_mm` + `a12_init_wrapper`） | 已编译通过 / 已静态验证 | 补丁 `patches/phase6_abi/`；见 `analysis/phase6_7_abi_tooling.md` |
| Phase 7 | 主配置固化、全自动化构建/校验/安全测试与恢复脚本交付 | 已编译通过 / 已静态验证 | `scripts/` 14 份脚本全部验证；`full` + `minimal` 均 PASS |

## 实机测试说明
> 当前尚未进行任何实机刷机或启动测试。所有主机端编译与静态校验产出均严格标注为 **`已编译通过`** 或 **`已静态验证`**，绝不使用 `已实机验证`。

## 构建历史记录（洁净集成终版 `6.6.144-zpd1203-g91af1aa18e1a`）

> 全部 8 个 WSL2 Git 仓库均已清洁提交（`clean=True`）；以下全部大小与 SHA256 均取自本次洁净重编后 `d:\P3066\out\{full,minimal}\SHA256SUMS.txt` 与 `scripts/verify_build.sh` 实测输出。

### 1. 全量模式 (`mode=full`, `zpd1203_defconfig`)

| 目标产物 | 大小 (Bytes) | SHA256 | 验证状态 |
|---|---|---|---|
| `out/full/Image` | 39,406,080 | `5a0c248b7b23a3bdbaa582cbc9f62659e82e0511d432933a6cdd9f65763d7160` | 已编译通过 (`ARM\x64` 有效) |
| `out/full/Image.gz` | 15,691,027 | `80dce85ee2858585f092fe7c7da09779027ef511f57a87f584d36218d57da0a7` | 已编译通过 (Banner 无 `-dirty`) |
| `out/full/mt6768-zpd1203.dtb` | 172,563 | `435b65dd9cd1af5f60aec83aa4ee34520a6bfb5c07299d4f1e9a929ade3a2e83` | 已静态验证 (`fdtoverlay` `dtbo_a_0.dtb` -> 202,774 B, 0 错误) |
| `out/full/dtb-full-6.6.dtimg` | 172,627 | `6f5e3777816f1b29ee5ef5d992c47a71d311a160bc775ff95c7eec5311e86840` | 已静态验证 (DT Table `0xd7b7ab1e`) |
| `out/full/initramfs-full-6.6.cpio.xz` | 12,343,696 | `ba24f8bef7f31b18870a86fa2c0cc6102f5c67d13226caee5b0d53eca1447349` | 已静态验证 (`xz --check=crc32`, 含 11 枚 `.ko`) |
| `out/full/boot-full-6.6.raw.img` | 28,213,248 | `0ab20bece1fe4bde4788bd8ae03ee6bc6b8ea2154647965a9c46722a4d4c7f8f` | 已静态验证 (Boot v2, `< 32 MiB`) |
| `out/full/boot-full-6.6.img` | 33,554,432 | `81df1add2b4f225ad7bdf3bc5219da961aa04a3c54915ad06ac234c642842fc5` | 已静态验证 (`avbtool` + `unpack_bootimg` + `verify_build.sh` PASS) |
| `out/full/modules/*.ko` (11 枚 Stripped) | 10,432,680 (总和) | 见 [out/full/SHA256SUMS.txt](file:///d:/P3066/out/full/SHA256SUMS.txt) | 已静态验证 (`vermagic=6.6.144-zpd1203-g91af1aa18e1a`, CRC `0x2933d34f`, 0 undef) |

#### 全量模式 11 枚内核模块明细 (`vermagic=6.6.144-zpd1203-g91af1aa18e1a`, CRC `0x2933d34f`)

| 模块 | Stripped 大小 (B) | Unstripped 大小 (B) | Stripped SHA256 | Unstripped SHA256 | 符号闭环 |
|---|---|---|---|---|---|
| `mali_mgm_mt6768.ko` | 24,696 | 211,592 | `52f7b2f0...` | `1310ecda...` | 0 undef (PASS) |
| `mali_kbase_mt6768.ko` | 1,093,016 | 14,922,112 | `b4eda3fc...` | `3181d838...` | 0 undef (PASS) |
| `rfkill.ko` | 51,400 | 266,016 | `55c33f9d...` | `f00d7dda...` | 0 undef (PASS) |
| `cfg80211.ko` | 1,649,040 | 7,500,112 | `efaace34...` | `591a502f...` | 0 undef (PASS) |
| `btif_drv.ko` | 198,872 | 806,552 | `92af1cd5...` | `efe380b4...` | 0 undef (PASS) |
| `conn_md_drv.ko` | 50,912 | 338,992 | `7a5812af...` | `12ccf511...` | 0 undef (PASS) |
| `connfem.ko` | 172,856 | 741,744 | `281e6a1d...` | `ebd70fc5...` | 0 undef (PASS) |
| `wmt_drv.ko` | 1,699,032 | 6,496,520 | `4f029b88...` | `77ac6162...` | 0 undef (PASS) |
| `wmt_chrdev_wifi.ko` | 52,312 | 318,728 | `2cd03111...` | `73ee6047...` | 0 undef (PASS) |
| `bt_drv_connac1x.ko` | 96,208 | 658,800 | `fd038228...` | `5a9f1bdd...` | 0 undef (PASS) |
| `wlan_drv_gen4m.ko` | 5,344,336 | 49,593,112 | `f9919d7b...` | `e710e9be...` | 0 undef (PASS) |

### 2. 最小诊断模式 (`mode=minimal`, `zpd1203_minimal_defconfig`)

| 目标产物 | 大小 (Bytes) | SHA256 | 验证状态 |
|---|---|---|---|
| `out/minimal/Image` | 28,510,720 | `f6cfe3cb1a6df0718b3b00aaa8a323fa8b226c457daa9de399a51b68e3dee105` | 已编译通过 |
| `out/minimal/Image.gz` | 11,731,820 | `91ff116b15406dd7570ebf06b5bce88faa500c785c0f5107c9be7815ea591209` | 已编译通过 |
| `out/minimal/mt6768-zpd1203-minimal.dtb` | 167,757 | `e51835447e6bc11d98f4ab444e1231fad2780745afe4fa54e9056dced790062d` | 已静态验证 (`fdtoverlay` -> 199,454 B, 0 错误) |
| `out/minimal/dtb-minimal-6.6.dtimg` | 167,821 | `3c5781ebbb6e41beae2ef26c4ba3b857af119c3a9c291b8f8b744ab3db1c4948` | 已静态验证 (`0xd7b7ab1e`) |
| `out/minimal/initramfs-minimal-6.6.cpio.gz` | 15,553,088 | `98611657d54920f79aced69b713fe9f521c9440a55d442d705e36b1d5c0fafb2` | 已静态验证 (`gzip`, 更新版 `a12_init_wrapper`) |
| `out/minimal/boot-minimal-6.6.raw.img` | 27,457,536 | `f8897899e64bcdfc9e9be938b0e459217725dc349dbdc966b127a6496cef6afe` | 已静态验证 (Boot v2, `< 32 MiB`) |
| `out/minimal/boot-minimal-6.6.img` | 33,554,432 | `72c92725458ac735d29401ed3c196d1080ed6429dd10efb2b10bfa707e5b76e4` | 已静态验证 (`avbtool` + `unpack_bootimg` + `verify_build.sh` PASS) |
