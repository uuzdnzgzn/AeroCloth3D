#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
mode="${1:-headless}"
args=()
if [[ "$mode" == "headless" ]]; then args+=(--headless); fi
mkdir -p artifacts
for characters in 1 3; do
  "$GODOT_BIN" "${args[@]}" --path . --audio-driver Dummy --disable-vsync --max-fps 0 -- \
    --benchmark "--characters=$characters" "--report=res://artifacts/benchmark-${mode}-${characters}.json" \
    > "artifacts/benchmark-${mode}-${characters}.log" 2>&1
  if rg -n 'SCRIPT ERROR|Parse Error|ERROR:' "artifacts/benchmark-${mode}-${characters}.log"; then exit 1; fi
done
python3 scripts/report_benchmark.py
