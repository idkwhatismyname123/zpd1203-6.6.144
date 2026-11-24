# ZPD1203 Linux 6.6 编译与打包说明 (BUILD.md)

## 1. 环境要求
- **宿主机**：Windows 11 + WSL2 Ubuntu（已检测：10 核心，15 GiB RAM，764 GiB 可用 ext4 空间）
- **已验证宿主机工具**（2026-11-24 检测）：
  - Clang / LLD：`clang-21` (`/usr/bin/clang -> clang-21`), `ld.lld`, `llvm-ar`
  - 交叉编译：`aarch64-linux-gnu-gcc` (`gcc 15.2.0`)
  - 辅助构建：`make`, `git`, `python3`, `bc`, `bison`, `flex`, `dtc`, `pahole`, `libssl-dev`, `libelf-dev`, `kmod`, `fakeroot`
  - Android 镜像工具：`mkbootimg` (`1:34.0.5`), `avbtool` (`/usr/local/bin/avbtool`), `lpunpack` (`/usr/local/bin/lpunpack`), `simg2img`, `fsck.erofs`, `abootimg`, `cpio`, `lz4`, `gzip`, `xz`, `zstd`, `fastboot`

## 2. 目录布局（WSL2）
- `/home/asus/zpd1203-6.6/survey/` — Phase 2 候选六系源码调查区
- `/home/asus/zpd1203-6.6/extracted_stock/` — 原厂分区备份只读解包产物
- `/home/asus/zpd1203-6.6/ref-5.10.240/` — `zpd1203-5.10.240` 参考源码克隆
- `/home/asus/zpd1203-6.6/kernel/` — 选定的 Linux 6.6 工作内核树
- `/home/asus/zpd1203-6.6/modules/` — 外置模块（Connsys 无线 / Mali GPU 等）构建区
- `/home/asus/zpd1203-6.6/out/` — 编译及打包临时输出，校验后同步至 `d:\P3066\out\`

## 3. 构建命令
> （待 Phase 2 选定 6.6 基线与 Phase 7 完成脚本后，在此固化完整一键复现命令与环境变量说明）
