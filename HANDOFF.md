# 当前工作现场交接文档 (HANDOFF.md)

- **最后更新**：2026-11-24
- **当前状态**：Phase 0 初始化已完成大半，即将并行启动 Phase 1（Agent 2、Agent 3）与 Phase 2（Agent 1）。

## 已确认的现场事实
1. WSL2 Ubuntu 已就绪（10 核、15 GiB RAM、764 GiB 可用空间，用户名 `asus`）。
2. `clang-21`, `ld.lld`, `dtc`, `pahole`, `mkbootimg`, `avbtool`, `lpunpack`, `simg2img`, `fsck.erofs`, `fastboot` 等工具已预装在 WSL2 中（仅缺 `gcc-arm-linux-gnueabi` 32 位交叉编译器，如 6.6 compat vdso 需要时补装或使用 LLVM/Clang）。
3. 原厂分区备份完整存在于 `D:\备份\p\GeekFlashTool_Readback_20260820162108246`，含 A/B 分区布局（`boot_a` 32 MiB、`vendor_boot_a` 64 MiB、`dtbo_a` 8 MiB、`expdb` 20 MiB、`super` 15 GiB），**严格保持只读**。
4. 独立 WSL2 工作区已创建：`/home/asus/zpd1203-6.6/`。注意 `/home/asus/` 下已有用户历史项目目录（`zpd1203-5.10.240`、`zpd1203`、`mt6768_build`），**严禁改动这些历史目录**。
5. 已初步确认 GitHub 存在的 6.6 候选仓库：`mt6768-mainline/android_kernel_samsung_mt6768` (6.6.50)、`Theman-Fromfar/a05m-kernel-6.6` (6.6.50)、`MotorolaMobilityLLC/kernel-kernel_device_modules-6.6` (`android-15-release-v1tl35.73-60-3`)、`Mayuri-Chan/MTK_kernel_device_modules_6.6` (`lineage-22.1`)、`mt6768-mainline/linux`。

## 下一步行动
1. 完成 `d:\P3066` 初始 Git commit。
2. 并行派发三个子代理：
   - **Agent 1 (`bsp-survey`)** -> `d:\P3066\analysis\phase2_bsp_survey.md`
   - **Agent 2 (`stock-backup-analyzer`)** -> `d:\P3066\analysis\phase1_stock_analysis.md`
   - **Agent 3 (`kernel510-analyzer`)** -> `d:\P3066\analysis\phase1_510_port_analysis.md`
3. 汇总三方报告，在 `DECISIONS.md` 确定最终 Linux 6.6 移植基底，启动 Phase 3 核心板级移植。
