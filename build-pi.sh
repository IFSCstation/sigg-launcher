#!/usr/bin/env bash
set -euo pipefail

PERF_LOG=true
FPS_OVERLAY=false
STRIP=false

for arg in "$@"; do
  case "$arg" in
    --no-perf-log) PERF_LOG=false ;;
    --fps-overlay) FPS_OVERLAY=true ;;
    --strip) STRIP=true ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

define_flag=""
if [ "$PERF_LOG" = true ]; then
  define_flag="-dart-define=PERF_LOG=true"
fi

fps_flag=""
if [ "$FPS_OVERLAY" = true ]; then
  fps_flag="-dart-define=FPS_OVERLAY=true"
fi

flutter build linux --release $define_flag $fps_flag

case "$(uname -m)" in
  aarch64) arch="arm64" ;;
  x86_64) arch="x64" ;;
  armv7l) arch="arm" ;;
  *)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

bundle="build/linux/$arch/release/bundle"

if [ "$STRIP" = true ]; then
  strip "$bundle/sigg_launcher"
fi

echo "Built: $bundle/sigg_launcher"