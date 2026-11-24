#!/usr/bin/env bash
# Static verification of boot-minimal-6.6.img + DTB + DTBO overlay + unpack_bootimg + avbtool.
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BASE="${BASE:-$(cd "$ROOT/.." && pwd)}"
IMG="${1:-$BASE/out/boot-minimal-6.6.img}"
STOCK_DTBO="${STOCK_DTBO:-$BASE/extracted_stock/dtbo/dtbo_a_0.dtb}"

if [ ! -f "$IMG" ]; then
  echo "ERROR: image not found: $IMG" >&2
  exit 1
fi

python3 - "$IMG" "$ROOT/data/boot_structure.json" <<'PY'
import gzip, json, struct, sys
from pathlib import Path

img_path = Path(sys.argv[1])
stock = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))["boot_a"]
data = img_path.read_bytes()

errors = []
warnings = []

def chk(cond, msg, warn_only=False):
    if not cond:
        (warnings if warn_only else errors).append(msg)
    print(f"[{'PASS' if cond else ('WARN' if warn_only else 'FAIL')}] {msg}")

chk(len(data) <= 33554432, f"File size {len(data)} <= 33554432 (32 MiB)")
chk(data[:8] == b"ANDROID!", "ANDROID! magic present")

(k_sz, k_addr, r_sz, r_addr, s_sz, s_addr, t_addr, page_sz, hdr_ver, os_ver) = struct.unpack_from("<10I", data, 8)
cmdline = data[64:64+512].split(b"\x00", 1)[0].decode("utf-8", errors="replace")
(hdr_size,) = struct.unpack_from("<I", data, 1632)
(dtb_sz, dtb_addr) = struct.unpack_from("<IQ", data, 1648)

chk(hdr_ver == stock["header_version"], f"header_version={hdr_ver} (expected {stock['header_version']})")
chk(page_sz == stock["page_size"], f"page_size={page_sz} (expected {stock['page_size']})")
chk(f"0x{k_addr:x}" == stock["kernel_addr"], f"kernel_addr=0x{k_addr:x} (expected {stock['kernel_addr']})")
chk(f"0x{r_addr:x}" == stock["ramdisk_addr"], f"ramdisk_addr=0x{r_addr:x} (expected {stock['ramdisk_addr']})")
chk(f"0x{t_addr:x}" == stock["tags_addr"], f"tags_addr=0x{t_addr:x} (expected {stock['tags_addr']})")
chk(f"0x{dtb_addr:x}" == stock["dtb_addr"], f"dtb_addr=0x{dtb_addr:x} (expected {stock['dtb_addr']})")
chk(f"0x{os_ver:x}" == stock["os_version_raw"], f"os_version_raw=0x{os_ver:x} (expected {stock['os_version_raw']})", warn_only=True)
chk("mt6768.force_slot_a=1" in cmdline, "mt6768.force_slot_a=1 present in boot cmdline")
chk(k_sz > 0 and r_sz > 0 and dtb_sz > 0, f"non-empty kernel({k_sz}), ramdisk({r_sz}), dtb({dtb_sz})")

def align(n, p):
    return ((n + p - 1) // p) * p

k_off = page_sz
r_off = k_off + align(k_sz, page_sz)
s_off = r_off + align(r_sz, page_sz)
(rdtbo_sz,) = struct.unpack_from("<I", data, 1636)
rdtbo_off = s_off + align(s_sz, page_sz)
dtb_off = rdtbo_off + align(rdtbo_sz, page_sz)

k_blob = data[k_off:k_off+k_sz]
chk(k_blob[:2] == b"\x1f\x8b", "kernel payload is gzip-compressed")
if k_blob[:2] == b"\x1f\x8b":
    k_raw = gzip.decompress(k_blob)
    arm64_magic = k_raw[56:60]
    (text_off, img_size, flags) = struct.unpack_from("<QQQ", k_raw, 8)
    chk(arm64_magic == b"ARM\x64", f"ARM64 Image magic valid (size={len(k_raw)}, text_off=0x{text_off:x}, image_size=0x{img_size:x})")
    ver_idx = k_raw.find(b"Linux version ")
    if ver_idx >= 0:
        banner = k_raw[ver_idx:k_raw.find(b"\x00", ver_idx)].decode("utf-8", errors="replace").strip()
        print(f"[INFO] Kernel banner: {banner}")
        chk("Linux version 6.6.144" in banner, "kernel banner confirms Linux version 6.6.144")
    else:
        chk(False, "Linux version banner found in kernel")

r_blob = data[r_off:r_off+r_sz]
chk(r_blob[:2] == b"\x1f\x8b", f"ramdisk payload is gzip-compressed ({r_sz} B)")

dtb_blob = data[dtb_off:dtb_off+dtb_sz]
dt_magic = struct.unpack_from(">I", dtb_blob, 0)[0]
chk(dt_magic == 0xD7B7AB1E, f"DTB slot wrapped in Android DT Table 0xd7b7ab1e (got 0x{dt_magic:08x})")
if dt_magic == 0xD7B7AB1E:
    (tot, hsz, esz, cnt, eoff, dpg, dver) = struct.unpack_from(">7I", dtb_blob, 4)
    (dt_sz, dt_off) = struct.unpack_from(">2I", dtb_blob, eoff)
    fdt = dtb_blob[dt_off:dt_off+dt_sz]
    chk(fdt[:4] == b"\xd0\x0d\xfe\xed", f"DT Table entry[0] contains valid FDT (offset=0x{dt_off:x}, size={dt_sz})")
    Path("/tmp/verify_extracted_66.dtb").write_bytes(fdt)

print(f"[INFO] cmdline: {cmdline}")
if data[-64:-60] == b"AVBf":
    print("[INFO] AVB footer present at end of image")
else:
    print("[INFO] No AVB footer (raw mkbootimg output)")

if errors:
    print(f"\nFAILED with {len(errors)} error(s).")
    sys.exit(1)
print(f"\nHEADER/PAYLOAD CHECK PASSED ({len(warnings)} warning(s)).")
PY

echo "=== unpack_bootimg check ==="
rm -rf /tmp/verify_unpack_66 && mkdir -p /tmp/verify_unpack_66
unpack_bootimg --boot_img "$IMG" --out /tmp/verify_unpack_66

if command -v avbtool >/dev/null 2>&1 && avbtool info_image --image "$IMG" >/dev/null 2>&1; then
  echo "=== avbtool info_image ==="
  avbtool info_image --image "$IMG"
fi

echo "=== dtc round-trip check ==="
dtc -I dtb -O dts -o /tmp/verify_extracted_66.dts /tmp/verify_extracted_66.dtb 2>/tmp/dtc_warn.txt || true
wc -l /tmp/verify_extracted_66.dts
grep -nE 'simple-framebuffer|intpol-init|zpd1203|usb0@11200000|mmc@11230000|dispsys' /tmp/verify_extracted_66.dts | head -n 30

if [ -f "$STOCK_DTBO" ]; then
  echo "=== fdtoverlay stock dtbo_a_0.dtb test ==="
  fdtoverlay -i /tmp/verify_extracted_66.dtb -o /tmp/verify_merged_66.dtb "$STOCK_DTBO"
  ls -lh /tmp/verify_merged_66.dtb
  echo "[PASS] fdtoverlay applied stock dtbo_a_0.dtb cleanly with 0 errors"
fi
rm -rf /tmp/verify_unpack_66 /tmp/verify_extracted_66.dtb /tmp/verify_extracted_66.dts /tmp/verify_merged_66.dtb /tmp/dtc_warn.txt
