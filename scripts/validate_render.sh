#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  printf 'A graphical display is required; headless rendering cannot validate shaders.\n' >&2
  exit 1
fi
task_cache="${TMPDIR:-/tmp}/aerocloth-render-${UID}"
mkdir -p "$task_cache/data" "$task_cache/config" "$task_cache/cache" artifacts
export XDG_DATA_HOME="$task_cache/data"
export XDG_CONFIG_HOME="$task_cache/config"
export XDG_CACHE_HOME="$task_cache/cache"
for suite in tests/test_hybrid_render.gd tests/test_damage_material_render.gd tests/test_proxy_surface.gd tests/test_wearable_rig.gd tests/test_authoring_workspace.gd; do
  log="artifacts/$(basename "$suite" .gd)_render.log"
  timeout 120s "${GODOT_BIN:-godot}" --path . --audio-driver Dummy --script "$suite" > "$log" 2>&1
  if rg -n 'SCRIPT ERROR|Parse Error|ERROR:' "$log"; then cat "$log"; exit 1; fi
  cat "$log"
done
