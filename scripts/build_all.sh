#!/usr/bin/env bash
# End-to-end ZPD1203 Linux 6.6 build, packaging & verification orchestrator.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="full"
CLEAN_FLAG=()

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --clean) CLEAN_FLAG=(--clean); shift ;;
    -h|--help)
      echo "Usage: $0 [--mode full|minimal|both] [--clean]"
      exit 0
      ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

run_one() {
  local m="$1"
  echo "============================================================"
  echo " Building ZPD1203 Linux 6.6.144 [mode=$m]"
  echo "============================================================"
  "$SCRIPT_DIR/build_kernel.sh" --mode "$m" "${CLEAN_FLAG[@]}"
  "$SCRIPT_DIR/build_modules.sh" --mode "$m"
  "$SCRIPT_DIR/build_ramdisk.sh" --mode "$m"
  "$SCRIPT_DIR/package_boot.sh" --mode "$m"
  "$SCRIPT_DIR/verify_build.sh" --mode "$m"
}

case "$MODE" in
  full|minimal)
    run_one "$MODE"
    ;;
  both)
    run_one full
    run_one minimal
    ;;
  *)
    echo "ERROR: --mode must be full, minimal, or both (got: $MODE)" >&2
    exit 2
    ;;
esac
