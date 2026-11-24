#!/usr/bin/env bash
# Collect live ADB kernel/pstore/hardware logs, or print no-UART expdb fallback guidance.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/out/logs_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"

if ! command -v adb >/dev/null 2>&1 || ! adb devices | grep -Eq $'[[:space:]]device$'; then
  echo "No active ADB device found."
  echo "=== No-UART Offline Crash Forensics ==="
  echo "1. If USB Composite Gadget ACM enumerated, connect to serial COM /dev/ttyACM* and send: status | pstore | reboot-fb"
  echo "2. If early boot crashed before ADB, read back 'expdb' partition via GeekFlashTool/mtkclient."
  echo "   Confirmed ramoops/pstore DRAM base = 0x4d010000 (size 0xe0000); see DEBUGGING.md."
  exit 1
fi

echo "[INFO] Collecting ADB logs into $OUT_DIR ..."
adb shell "cat /proc/version" > "$OUT_DIR/proc_version.txt" 2>&1 || true
adb shell "dmesg" > "$OUT_DIR/dmesg.txt" 2>&1 || true
adb shell "lsmod" > "$OUT_DIR/lsmod.txt" 2>&1 || true
adb shell "cat /dev/.pstore_dump.log 2>/dev/null || ls -la /sys/fs/pstore 2>/dev/null" > "$OUT_DIR/pstore.txt" 2>&1 || true
adb shell "cat /dev/.fb0_bridge.log 2>/dev/null" > "$OUT_DIR/fb0_bridge.log" 2>&1 || true
adb shell "ls -la /dev/dri /dev/mali0 /dev/ion /dev/stpwmt /dev/wmtWifi /dev/stpbt /dev/input 2>/dev/null" > "$OUT_DIR/dev_nodes.txt" 2>&1 || true
adb shell "grep -H . /sys/class/power_supply/*/{type,online,status,capacity,voltage_now,current_now,present} 2>/dev/null" > "$OUT_DIR/power_supply.txt" 2>&1 || true
adb shell "dumpsys battery" > "$OUT_DIR/dumpsys_battery.txt" 2>&1 || true
adb shell "dumpsys SurfaceFlinger" > "$OUT_DIR/dumpsys_surfaceflinger.txt" 2>&1 || true
adb logcat -b all -d > "$OUT_DIR/logcat_all.txt" 2>&1 || true
echo "[DONE] Logs saved to $OUT_DIR"
