#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
task_cache="${TMPDIR:-/tmp}/aerocloth-validation-${UID}"
mkdir -p "$task_cache/data" "$task_cache/config" "$task_cache/cache" artifacts
export XDG_DATA_HOME="$task_cache/data"
export XDG_CONFIG_HOME="$task_cache/config"
export XDG_CACHE_HOME="$task_cache/cache"
check_log() {
  if rg -n 'SCRIPT ERROR|Parse Error|ERROR:' "$1"; then
    cat "$1"
    exit 1
  fi
}
"$GODOT_BIN" --version
"$GODOT_BIN" --headless --editor --path . --import --quit > artifacts/import.log 2>&1
check_log artifacts/import.log
for suite in tests/test_damage.gd tests/test_scenario.gd tests/test_workspace.gd tests/test_profile.gd tests/test_hybrid.gd tests/test_surface_socket.gd; do
  log="artifacts/$(basename "$suite" .gd).log"
  timeout 60s "$GODOT_BIN" --headless --path . --script "$suite" > "$log" 2>&1
  check_log "$log"
  cat "$log"
done
"$GODOT_BIN" --headless --path . --quit-after 30 > artifacts/smoke.log 2>&1
check_log artifacts/smoke.log
printf 'Import, core, character scenario, workspace and scene smoke checks passed.\n'
