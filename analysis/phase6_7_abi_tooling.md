# Phase 6–7 分析与设计报告：Android 12 Vendor ABI 兼容与无修改用户态适配（Linux 6.6.144）

> **状态声明**：Phase 6 内核兼容驱动与用户态静态包装工具均达到 **已编译通过 / 已静态验证** 状态，**尚未进行实机验证**。所有兼容层均调用真实 Linux 6.6 子系统，未使用空函数或虚假返回值。

---

## 1. Phase 6 提交与补丁

- **`kernel_device_modules-6.6` (分支 `zpd1203-6.6`)**：`7082ee8` — `zpd1203: abi: add /dev/ion -> DMA-BUF Heap compat driver and ABI config`
- **导出补丁**：[0001-zpd1203-abi-add-dev-ion-DMA-BUF-Heap-compat-driver-a.patch](file:///d:/P3066/patches/phase6_abi/0001-zpd1203-abi-add-dev-ion-DMA-BUF-Heap-compat-driver-a.patch)
- **修改 / 新增文件**：
  - `drivers/dma-buf/heaps/mtk_ion_compat.c`
  - `drivers/dma-buf/heaps/Kconfig`（新增 `CONFIG_ZPD1203_ION_DMABUF_COMPAT`）
  - `drivers/dma-buf/heaps/Makefile`
  - `arch/arm64/configs/zpd1203_abi.config`

---

## 2. Linux 4.19/5.10 -> Linux 6.6 Android 12 Vendor ABI 兼容策略

### 2.1 `/dev/ion` -> DMA-BUF Heap（`mtk_ion_compat.c`）

原厂 Android 12 Vendor 中的 Codec2 与多媒体 HAL 依赖 `/dev/ion` 与 `BIT(10)` 多媒体堆 ID（`libion_mtk.so`）。Linux 6.6 已移除 `drivers/staging/android/ion/`。本移植保留原厂用户态不变，在 `drivers/dma-buf/heaps/` 编写真实转发兼容驱动 `mtk_ion_compat.c`：

- **堆启用与防重名隔离**：
  - 启用 `CONFIG_DMABUF_HEAPS=y`、`CONFIG_DEVICE_MODULES_DMABUF_HEAPS_DEFERRED_FREE=y`、`CONFIG_DEVICE_MODULES_DMABUF_HEAPS_PAGE_POOL=y`、`CONFIG_DEVICE_MODULES_DMABUF_HEAPS_SYSTEM=y`、`CONFIG_ZPD1203_ION_DMABUF_COMPAT=y`。
  - 显式关闭上游 `# CONFIG_DMABUF_HEAPS_SYSTEM is not set`，避免与 `mtk_system_heap.c` 注册 `"system"` + `"system-uncached"` 发生设备名冲突。`mtk_system_heap_create()` 同时创建 `"mtk_mm"` 与 `"mtk_mm-uncached"`。
- **真实 ioctl 转发**：
  - 注册 `/dev/ion` misc 设备（`mode = 0666`，同时接管 `unlocked_ioctl` 与 `compat_ptr_ioctl`）。
  - `ZPD_ION_IOC_ABI_VERSION` 返回 ABI 版本 `2`；`ZPD_ION_IOC_HEAP_QUERY` 动态调用 `dma_heap_find()` 检测堆存在并支持 `heaps == 0` 计数查询，暴露 `heap_id = 0`（`"system"`，`ION_HEAP_TYPE_SYSTEM`）与 `heap_id = 10`（`"mtk_ion_mm_heap"`，`ION_HEAP_TYPE_CUSTOM`）。
  - `ZPD_ION_IOC_ALLOC` 对 `len` 执行溢出检查与 `PAGE_ALIGN`，按 `heap_id_mask`（优先 `BIT(10)` 匹配 `mtk_mm`/`mtk_mm-uncached`，次选 `BIT(0)` 匹配 `system`/`system-uncached`）调用真实内核导出接口 `dma_heap_bufferfd_alloc(heap, len, O_RDWR | O_CLOEXEC, 0)` 分配真实 `dma_buf` fd，并在释放 `dma_heap_put(heap)` 后返回。
  - 所有未实现 ioctl（含历史 `ION_IOC_CUSTOM`）严格对齐 5.10 `ion.c` 返回 `-ENOTTY`，不做虚假成功欺骗。

### 2.2 启动包装器扩展（`a12_init_wrapper.c`）与双显示模式切换

[a12_init_wrapper.c](file:///d:/P3066/zpd1203/tools/a12_init_wrapper.c) 已扩展并静态交叉编译通过（`-Wall -Wextra -Werror`）：

1. **严格拓扑顺序加载 6.6 `.ko` 模块**：
   - 在 `main()` 进入 `/system/bin/init` 前读取 `/zpd_modules/`，按依赖顺序通过 `syscall(__NR_finit_module, fd, "", 0)` 加载 11 个模块：`mali_mgm_mt6768.ko` -> `mali_kbase_mt6768.ko` -> `rfkill.ko` -> `cfg80211.ko` -> `btif_drv.ko` -> `conn_md_drv.ko` -> `connfem.ko` -> `wmt_drv.ko` -> `wmt_chrdev_wifi.ko` -> `bt_drv_connac1x.ko` -> `wlan_drv_gen4m.ko`。
   - 保持对各 `.ko` 只读文件描述符打开并跨 `fork()` 传递至子进程；`SwitchRoot` 完成进入新根后，先对未能 pre-init 加载的模块执行一次 `post-switchroot` 重试，再将匹配 `/vendor/lib/modules/<name>` 的 6.6 模块复制到 `/dev/.zpd_modules/<name>` 并 `MS_BIND` 覆盖原厂 4.19 `.ko` 二进制，防止 vendor init 重复加载旧版本模块。
   - 若 initramfs 未打包 `/zpd_modules/`（即 `minimal` 模式），加载逻辑自动跳过，完全兼容最小诊断镜像。
2. **DRM/Mali 与 `simplefb` 门控分流**：
   - `SwitchRoot` 完成后检查 `/dev/dri/card0`（最多短暂等待 `200 ms`）：当原生 MTK DRM v2 成功探测出 `/dev/dri/card0` 时，记录日志并跳过 `hwcomposer.mt6768.so` 空桩与 `gralloc.fb0_bridge.so` 挂载，让 SurfaceFlinger 与 HWC 使用原生 `/dev/dri/card0` + `/dev/mali0`；当 `/dev/dri/card0` 不存在（`minimal` 模式或 DRM 探测失败降级场景）时，保持 `simplefb` + NEON `gralloc.fb0_bridge.so` 桥接保底机制。
   - 新增 `/dev/mali0` 与 `/dev/ion` 的 `0666` 权限守护，并将 `dri`/`mali`/`ion` 就绪状态纳入 USB ACM 串口实时调试命令 `status`。

### 2.3 工具链产物静态校验

- `a12_init_wrapper`：`ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked`（`597,928` 字节，`readelf -d` 无动态段）。
- `gralloc.fb0_bridge.so`：`ELF 64-bit LSB shared object, ARM aarch64`（`67,640` 字节，`readelf -d` 零 `NEEDED` 依赖，导出 `HMI` 符号）。

---

## 3. Ramdisk 大小预算与 `CONFIG_RD_XZ=y`

原厂 `vendor_boot_a` Ramdisk 未压缩 `cpio` 为 `30.49 MiB`（`gzip -9` 为 `15,549,025` 字节）；全量 `Image.gz` 为 `14.96 MiB`（`15,690,408` 字节），叠加 11 个 stripped `.ko`（`9.95 MiB` 未压缩 / `2.57 MiB` `gzip -9` / `1.75 MiB` `xz`）后，`gzip` Ramdisk 将逼近或超过 `boot` 分区 `32 MiB`（`33,554,432` 字节）硬上限。启用 `CONFIG_RD_XZ=y` 后使用 `xz --check=crc32` 压缩全量 Ramdisk（实测纯净 Ramdisk `xz -9` 为 `9,959,100` 字节，加上模块总包预期 `~11.7 MiB`），全量 `boot-full-6.6.img` 将保留超过 `5 MiB` 的安全冗余。
