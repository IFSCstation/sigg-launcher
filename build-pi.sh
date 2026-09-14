#!/usr/bin/env bash
set -euo pipefail

PERF_LOG=true
STRIP=false

for arg in "$@"; do
  case "$arg" in
    --no-perf-log) PERF_LOG=false ;;
    --strip) STRIP=true ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

define_flag=""
if [ "$PERF_LOG" = true ]; then
  define_flag="--dart-define=PERF_LOG=true"
fi

flutter build linux --release $define_flag

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