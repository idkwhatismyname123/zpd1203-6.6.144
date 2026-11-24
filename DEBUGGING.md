# ZPD1203 无物理 UART 多级调试方案与真实日志 (DEBUGGING.md)

## 1. 约束条件
- ZPD1203 设备**没有物理 UART**，**严禁要求拆机焊接调试串口**。
- 所有内核带板调试必须依赖重启保留内存、分区转储、屏幕早期输出与 USB/ADB 通道。

## 2. 多级调试机制设计（将在 Phase 3–4 落地）

### Level 1：内核早期异常与重启后日志留存 (`ramoops` / `pstore`)
- **原理**：在 `reserved-memory` 中划定一段不随热重启清零的固定物理内存（避开 Preloader/LK/TEE/SSPM/GZ/MD1 使用区，优先对齐原厂 MTK `ramoops` 区间或 5.10 已验证地址）。
- **内核配置**：
  - `CONFIG_PSTORE=y`
  - `CONFIG_PSTORE_CONSOLE=y`
  - `CONFIG_PSTORE_PMSG=y`
  - `CONFIG_PSTORE_RAM=y`
- **取证方式**：当某次内核启动崩溃或看门狗复位后，重启进入能启动的系统（例如 5.10、原厂恢复或带有 ADB 的测试镜像），读取 `/sys/fs/pstore/console-ramoops-0` 与 `dmesg-ramoops-*`。

### Level 2：MTK `EXPDB` 分区转储分析
- 设备存在独立 `expdb` 分区（`0x1400000` = 20 MiB，`linear_start_addr: 0x108000`）。
- 我们将首先从只读原厂备份 `expdb.img` 分析其中是否有 MTK AEE/PL/LK 日志头格式，若实机发生无 ADB 崩溃，可通过 MTKClient/Fastboot/Recovery 回读 `expdb` 进行离线解码。

### Level 3：早期屏幕输出（Framebuffer / SimpleDRM）
- 若 LK 已点亮显示面板并留下连续帧缓冲，将在最小调试内核中评估开启 `CONFIG_DRM_SIMPLEDRM` / `earlycon` 屏幕输出或 initramfs 文本提示，以便在 USB 尚未枚举前直观看见启动卡死阶段。

### Level 4：Initramfs 阶段标记与早期 USB Gadget ADB
- 在 Android `init` 接管或加载全部内核模块前，由调试包装脚本执行：
  1. 输出清晰阶段标记（`[ZPD1203-6.6] STAGE 1..N`）至 `/dev/kmsg`。
  2. 记录 `/proc/cmdline`、`/proc/device-tree` 关键节点、`lsmod`、`dmesg` 及 `/sys/fs/pstore/*` 快照。
  3. 当 Android `init` 未能启动或 `adbd` 异常时，提供最小 ConfigFS USB Gadget + FunctionFS 恢复诊断分支（可配合 `loglevel=8 ignore_loglevel printk.devkmsg=on`）。

### Level 5：非破坏性测试与安全回退
- 优先使用 `fastboot boot <boot-test.img>`（仅驻留内存，不擦写 eMMC）。
- 仅在用户明确知晓并确认 LK 不支持 `fastboot boot` 且核对恢复方案后，方可在用户手动确认下写入测试槽位。

---

## 3. 真实设备日志档案

> 当前尚无 Linux 6.6 实机测试日志。实机测试后将在此追加真实 `dmesg`、`pstore`、`logcat` 摘要与排查结论。
