#!/usr/bin/env bash
# Strict static verification gate for built ZPD1203 Linux 6.6 artifacts (full or minimal).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE="${ZPD_WSL_BASE:-/home/asus/zpd1203-6.6}"
MODE="full"

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--mode full|minimal]"
      exit 0
      ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

PUB_DIR="$REPO_ROOT/out/$MODE"
STOCK_JSON="$REPO_ROOT/zpd1203/data/boot_structure.json"
STOCK_DTBO="$BASE/extracted_stock/dtbo/dtbo_a_0.dtb"

if [ "$MODE" = "full" ]; then
  KOUT="$BASE/out/kernel-6.6-full"
  IMG="$PUB_DIR/boot-full-6.6.img"
  EXPECTED_RD_KIND="xz"
elif [ "$MODE" = "minimal" ]; then
  KOUT="$BASE/out/kernel-6.6"
  IMG="$PUB_DIR/boot-minimal-6.6.img"
  EXPECTED_RD_KIND="gzip"
else
  echo "ERROR: --mode must be full or minimal (got: $MODE)" >&2
  exit 2
fi

if [ ! -f "$IMG" ]; then
  echo "ERROR: boot image missing: $IMG" >&2
  exit 1
fi

echo "=== [verify_build:$MODE] 1. Checking SHA256SUMS.txt ==="
(cd "$PUB_DIR" && sha256sum -c --quiet SHA256SUMS.txt)
echo "[PASS] SHA256SUMS.txt verified cleanly"

echo "=== [verify_build:$MODE] 2. Checking Boot Header v2, kernel banner, ramdisk, DT Table ==="
python3 - "$IMG" "$STOCK_JSON" "$EXPECTED_RD_KIND" <<'PY'
import gzip, json, struct, sys
from pathlib import Path

img_path = Path(sys.argv[1])
stock = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))["boot_a"]
rd_kind = sys.argv[3]
data = img_path.read_bytes()
errors = []

def chk(cond, msg):
    if not cond:
        errors.append(msg)
    print(f"[{'PASS' if cond else 'FAIL'}] {msg}")

chk(len(data) <= 33554432, f"Size {len(data)} <= 33554432 (32 MiB)")
chk(data[:8] == b"ANDROID!", "ANDROID! magic present")

(k_sz, k_addr, r_sz, r_addr, s_sz, s_addr, t_addr, page_sz, hdr_ver, os_ver) = struct.unpack_from("<10I", data, 8)
cmdline = data[64:64+512].split(b"\x00", 1)[0].decode("utf-8", errors="replace")
(dtb_sz, dtb_addr) = struct.unpack_from("<IQ", data, 1648)

chk(hdr_ver == stock["header_version"], f"header_version={hdr_ver} == {stock['header_version']}")
chk(page_sz == stock["page_size"], f"page_size={page_sz} == {stock['page_size']}")
chk(f"0x{k_addr:x}" == stock["kernel_addr"], f"kernel_addr=0x{k_addr:x}")
chk(f"0x{r_addr:x}" == stock["ramdisk_addr"], f"ramdisk_addr=0x{r_addr:x}")
chk(f"0x{t_addr:x}" == stock["tags_addr"], f"tags_addr=0x{t_addr:x}")
chk(f"0x{dtb_addr:x}" == stock["dtb_addr"], f"dtb_addr=0x{dtb_addr:x}")
chk("mt6768.force_slot_a=1" in cmdline, "mt6768.force_slot_a=1 in cmdline")
chk("panic=8" in cmdline, "panic=8 in cmdline")
chk("console=tty0" in cmdline, "console=tty0 in cmdline")
chk("fbcon=rotate:3,font:TER16x32" in cmdline, "fbcon=rotate:3,font:TER16x32 in cmdline")

def align(n, p):
    return ((n + p - 1) // p) * p

k_off = page_sz
r_off = k_off + align(k_sz, page_sz)
s_off = r_off + align(r_sz, page_sz)
(rdtbo_sz,) = struct.unpack_from("<I", data, 1636)
rdtbo_off = s_off + align(s_sz, page_sz)
dtb_off = rdtbo_off + align(rdtbo_sz, page_sz)

k_blob = data[k_off:k_off+k_sz]
chk(k_blob[:2] == b"\x1f\x8b", "Kernel payload is gzip")
k_raw = gzip.decompress(k_blob)
chk(k_raw[56:60] == b"ARM\x64", f"ARM64 Image magic valid (raw {len(k_raw)} B)")
ver_idx = k_raw.find(b"Linux version ")
banner = k_raw[ver_idx:k_raw.find(b"\x00", ver_idx)].decode("utf-8", errors="replace").strip() if ver_idx >= 0 else ""
print(f"[INFO] Kernel banner: {banner}")
chk("Linux version 6.6.144" in banner, "Banner confirms Linux 6.6.144")
chk("-dirty" not in banner, "Banner has zero -dirty suffix")

r_blob = data[r_off:r_off+r_sz]
if rd_kind == "xz":
    chk(r_blob[:6] == b"\xfd7zXZ\x00", f"Ramdisk payload is xz ({r_sz} B)")
else:
    chk(r_blob[:2] == b"\x1f\x8b", f"Ramdisk payload is gzip ({r_sz} B)")

dtb_blob = data[dtb_off:dtb_off+dtb_sz]
dt_magic = struct.unpack_from(">I", dtb_blob, 0)[0]
chk(dt_magic == 0xD7B7AB1E, f"DT Table magic 0x{dt_magic:08x} == 0xd7b7ab1e")
(tot, hsz, esz, cnt, eoff, dpg, dver) = struct.unpack_from(">7I", dtb_blob, 4)
(dt_sz, dt_off) = struct.unpack_from(">2I", dtb_blob, eoff)
fdt = dtb_blob[dt_off:dt_off+dt_sz]
chk(fdt[:4] == b"\xd0\x0d\xfe\xed", f"DT Table entry[0] FDT valid ({dt_sz} B)")
Path("/tmp/verify_extracted_zpd.dtb").write_bytes(fdt)

if errors:
    sys.exit(1)
PY

echo "=== [verify_build:$MODE] 3. Running unpack_bootimg, avbtool, fdtoverlay ==="
rm -rf /tmp/verify_unpack_zpd && mkdir -p /tmp/verify_unpack_zpd
unpack_bootimg --boot_img "$IMG" --out /tmp/verify_unpack_zpd >/dev/null
avbtool info_image --image "$IMG"
fdtoverlay -i /tmp/verify_extracted_zpd.dtb -o /tmp/verify_merged_zpd.dtb "$STOCK_DTBO"
echo "[PASS] fdtoverlay applied stock dtbo_a_0.dtb cleanly ($(stat -c %s /tmp/verify_merged_zpd.dtb) B)"

echo "=== [verify_build:$MODE] 4. Checking mandatory .config flags & clean kernel.release ==="
CFG="$PUB_DIR/config-$MODE"
KREL="$(cat "$KOUT/include/config/kernel.release")"
if [[ "$KREL" == *"-dirty"* ]]; then
  echo "FAIL: kernel.release is dirty: $KREL" >&2
  exit 1
fi
echo "[PASS] kernel.release clean: $KREL"

REQ_COMMON=(
  CONFIG_USB_MTK_HDRC
  CONFIG_USB_CONFIGFS_F_FS
  CONFIG_USB_F_ACM
  CONFIG_USB_CONFIGFS_ACM
  CONFIG_U_SERIAL_CONSOLE
  CONFIG_DEVTMPFS
  CONFIG_FB_SIMPLE
  CONFIG_VT
  CONFIG_VT_CONSOLE
  CONFIG_FRAMEBUFFER_CONSOLE
  CONFIG_FRAMEBUFFER_CONSOLE_ROTATION
  CONFIG_FONT_TER16x32
  CONFIG_KSU
)
for c in "${REQ_COMMON[@]}"; do
  grep -q "^${c}=y$" "$CFG" || { echo "FAIL: missing ${c}=y in $CFG" >&2; exit 1; }
done

if [ "$MODE" = "full" ]; then
  REQ_FULL=(
    CONFIG_MTK_MUSB_DUAL_ROLE
    CONFIG_MTK_CHARGER
    CONFIG_CHARGER_BQ2589X
    CONFIG_BATTERY_MT6358
    CONFIG_AW_USBPD
    CONFIG_AW35615_PD
    CONFIG_EXTCON_MTK_USB
    CONFIG_DRM_MEDIATEK_V2
    CONFIG_DRM_PANEL_HIMAX_JT120WUL005_VDO
    CONFIG_TOUCHSCREEN_HIMAX_COMMON
    CONFIG_REGULATOR_AW37503
    CONFIG_MTK_GPU_MT6768_SUPPORT
    CONFIG_SND_SOC_MT6768_MT6358
    CONFIG_SND_SOC_AW87XXX
    CONFIG_MTK_SPM
    CONFIG_MEDIATEK_MCDI
    CONFIG_DMABUF_HEAPS
    CONFIG_DEVICE_MODULES_DMABUF_HEAPS_SYSTEM
    CONFIG_ZPD1203_ION_DMABUF_COMPAT
    CONFIG_RD_XZ
  )
  for c in "${REQ_FULL[@]}"; do
    grep -q "^${c}=y$" "$CFG" || { echo "FAIL: missing ${c}=y in $CFG" >&2; exit 1; }
  done
  grep -q "^# CONFIG_DMABUF_HEAPS_SYSTEM is not set$" "$CFG" || { echo "FAIL: CONFIG_DMABUF_HEAPS_SYSTEM must be unset" >&2; exit 1; }
  echo "[PASS] All full-mode mandatory .config checks passed"

  echo "=== [verify_build:full] 5. Checking all 11 .ko vermagic, CRCs & symbol closure ==="
  python3 - "$KOUT" "$PUB_DIR" <<'PY'
import os, subprocess, sys
kout, pub_dir = sys.argv[1], sys.argv[2]
krel = open(f"{kout}/include/config/kernel.release").read().strip()

syms = {}
with open(f"{kout}/Module.symvers") as f:
    for line in f:
        parts = line.split()
        if len(parts) >= 2:
            syms[parts[1]] = parts[0]

mod_list = [
    "mali_mgm_mt6768.ko",
    "mali_kbase_mt6768.ko",
    "rfkill.ko",
    "cfg80211.ko",
    "btif_drv.ko",
    "conn_md_drv.ko",
    "connfem.ko",
    "wmt_drv.ko",
    "wmt_chrdev_wifi.ko",
    "bt_drv_connac1x.ko",
    "wlan_drv_gen4m.ko",
]

defined = set(syms.keys())
for m in mod_list:
    up = f"{pub_dir}/unstripped/{m}"
    nm = subprocess.check_output(["llvm-nm", up], text=True)
    for l in nm.splitlines():
        p = l.split()
        if not p: continue
        s = p[-1]
        for pref in ("__ksymtab_", "__ksymtab+", "___ksymtab+", "__crc_"):
            if s.startswith(pref):
                defined.add(s[len(pref):])

for m in mod_list:
    sp = f"{pub_dir}/modules/{m}"
    up = f"{pub_dir}/unstripped/{m}"
    assert os.path.exists(sp) and os.path.exists(up), f"Missing {m}"
    mi = subprocess.check_output(["modinfo", sp], text=True)
    vm = [l.split(":", 1)[1].strip() for l in mi.splitlines() if l.startswith("vermagic:")][0]
    assert krel in vm and "-dirty" not in vm, f"{m} bad vermagic: {vm} vs {krel}"
    mv = subprocess.check_output(["modprobe", "--show-modversions", sp], text=True)
    ml = [l.split()[0] for l in mv.splitlines() if l.strip().endswith("module_layout")][0]
    assert ml == syms["module_layout"], f"{m} CRC mismatch: {ml} vs {syms['module_layout']}"
    und = subprocess.check_output(["llvm-nm", "--undefined-only", up], text=True)
    miss = [l.split()[-1] for l in und.splitlines() if l.strip() and l.split()[-1] not in defined]
    assert not miss, f"{m} unresolved symbols: {miss}"
    print(f"[PASS] {m:22s} | strip={os.path.getsize(sp):8d} B | vermagic={krel} | CRC={ml} | 0 undef")
PY
else
  echo "[PASS] Minimal-mode mandatory .config checks passed"
fi

rm -rf /tmp/verify_unpack_zpd /tmp/verify_extracted_zpd.dtb /tmp/verify_merged_zpd.dtb
echo "=== [verify_build:$MODE] ALL CHECKS PASSED ==="
