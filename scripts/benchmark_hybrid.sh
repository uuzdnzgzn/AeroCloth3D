#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts
for backend in cpu gpu; do
  "${GODOT_BIN:-godot}" --path . --audio-driver Dummy --disable-vsync --max-fps 0 --fixed-fps 60 -- \
    --benchmark --comparison-fixed-step --characters=3 --cloth-accessory "--cloth-renderer=$backend" "--report=res://artifacts/hybrid-$backend-3.json" \
    > "artifacts/hybrid-$backend-3.log" 2>&1
  if rg -n 'SCRIPT ERROR|Parse Error|ERROR:' "artifacts/hybrid-$backend-3.log"; then exit 1; fi
done
