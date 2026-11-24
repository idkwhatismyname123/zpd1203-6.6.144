#!/usr/bin/env bash
# Non-destructive RAM boot test for ZPD1203 via fastboot boot (does NOT modify any partition).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="full"
IMG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --image) IMG="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--mode full|minimal] [--image path/to/boot.img]"
      exit 0
      ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$IMG" ]; then
  IMG="$REPO_ROOT/out/$MODE/boot-$MODE-6.6.img"
fi
[ -f "$IMG" ] || { echo "ERROR: missing boot image: $IMG" >&2; exit 1; }

SZ=$(stat -c %s "$IMG")
[ "$SZ" -le 33554432 ] || { echo "ERROR: image $SZ B > 33554432 B" >&2; exit 1; }

SUMS="$(dirname "$IMG")/SHA256SUMS.txt"
if [ -f "$SUMS" ]; then
  ACTUAL=$(sha256sum "$IMG" | awk '{print $1}')
  EXPECTED=$(awk -v f="$(basename "$IMG")" '$2 == f {print $1}' "$SUMS")
  if [ -n "$EXPECTED" ] && [ "$ACTUAL" != "$EXPECTED" ]; then
    echo "ERROR: SHA256 mismatch! expected=$EXPECTED actual=$ACTUAL" >&2
    exit 1
  fi
  echo "[PASS] SHA256 verified: $ACTUAL"
fi

command -v fastboot >/dev/null 2>&1 || { echo "ERROR: fastboot not found in PATH" >&2; exit 1; }
DEVS=$(fastboot devices)
[ -n "$DEVS" ] || { echo "ERROR: no fastboot device connected" >&2; exit 1; }
echo "$DEVS"

echo "[INFO] Running non-destructive RAM boot: fastboot boot $IMG"
fastboot boot "$IMG"
