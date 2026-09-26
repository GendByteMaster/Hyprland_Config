#!/usr/bin/env bash
set -euo pipefail

BRANCH="feat/issue-24-developer-spatial-desktop"
BUILD_DIR="build/spatial-plugin"
PLUGIN="$BUILD_DIR/gendbyte-spatial.so"
INSTALL_DIR="$HOME/.local/lib/gendbyte-spatial"
CURRENT_PATH_FILE="$INSTALL_DIR/current-path"
SPATIAL_HUD_ID="gendbyte.spatial-hud"
SPATIAL_HUD_INSTALLER="spatial/core/tools/install-spatial-hud.sh"
MIN_FREE_KB=262144
MIN_FREE_INODES=2048

die() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v git >/dev/null || die "git not found"
command -v cmake >/dev/null || die "cmake not found"
command -v hyprctl >/dev/null || die "hyprctl not found"
command -v install >/dev/null || die "install not found"
command -v sha256sum >/dev/null || die "sha256sum not found"
command -v df >/dev/null || die "df not found"
command -v python3 >/dev/null || die "python3 not found"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Run this inside the Hyprland_Config repository"
cd "$ROOT"

echo "== Repository =="
echo "$ROOT"

echo
echo "== Pre-update cleanup =="

# Free generated build space before switching/pulling. This path is disposable
# and can otherwise prevent git itself from updating on small Try Omarchy disks.
rm -rf -- "$BUILD_DIR"

echo
echo "== Branch =="
git switch "$BRANCH"
git pull --ff-only

echo
echo "== Disk preflight =="

# Keep only the currently referenced installed plugin before rebuilding.
# Old content-addressed builds are safe to remove and can accumulate quickly
# on the small Try Omarchy virtual disk.
if [[ -d "$INSTALL_DIR" ]]; then
  current_plugin="$(cat "$CURRENT_PATH_FILE" 2>/dev/null || true)"
  while IFS= read -r -d '' old_plugin; do
    if [[ -n "$current_plugin" && "$old_plugin" == "$current_plugin" ]]; then
      continue
    fi
    rm -f -- "$old_plugin"
  done < <(find "$INSTALL_DIR" -maxdepth 1 -type f -name 'gendbyte-spatial-*.so' -print0 2>/dev/null || true)
fi

# The generated build directory was already removed before git pull so the
# repository update itself has room to complete on small filesystems.
df -h "$ROOT" || true
df -ih "$ROOT" || true

free_kb="$(df -Pk "$ROOT" | awk 'NR == 2 { print $4 }')"
free_inodes="$(df -Pi "$ROOT" | awk 'NR == 2 { print $4 }')"

if [[ -z "$free_kb" || ! "$free_kb" =~ ^[0-9]+$ ]]; then
  die "Could not determine free disk space"
fi

if [[ -z "$free_inodes" || ! "$free_inodes" =~ ^[0-9]+$ ]]; then
  die "Could not determine free inode count"
fi

if (( free_kb < MIN_FREE_KB || free_inodes < MIN_FREE_INODES )); then
  echo >&2
  echo "Spatial build needs more free filesystem capacity." >&2
  echo "Available: $((free_kb / 1024)) MiB and $free_inodes inodes." >&2
  echo "Required preflight minimum: $((MIN_FREE_KB / 1024)) MiB and $MIN_FREE_INODES inodes." >&2
  echo >&2
  echo "Largest user directories:" >&2
  du -xhd1 "$HOME" 2>/dev/null | sort -h | tail -n 12 >&2 || true
  echo >&2
  echo "Free some disk space, then rerun this script." >&2
  echo "The Spatial build directory has already been cleaned safely." >&2
  exit 1
fi

echo
echo "== Build spatial plugin =="
cmake -S spatial/core -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DSPATIAL_BUILD_PLUGIN=ON \
  -DSPATIAL_BUILD_TESTS=ON

cmake --build "$BUILD_DIR" --parallel 2

[[ -f "$PLUGIN" ]] || die "Plugin was not built: $PLUGIN"

echo
echo "== Native tests =="
ctest --test-dir "$BUILD_DIR" --output-on-failure

echo
echo "== Install versioned user plugin =="
PLUGIN_HASH="$(sha256sum "$PLUGIN" | awk '{print substr($1, 1, 16)}')"
INSTALLED_PLUGIN="$INSTALL_DIR/gendbyte-spatial-$PLUGIN_HASH.so"

install -Dm755 "$PLUGIN" "$INSTALLED_PLUGIN"
mkdir -p "$INSTALL_DIR"

tmp_pointer="$CURRENT_PATH_FILE.tmp.$$"
printf '%s\n' "$INSTALLED_PLUGIN" >"$tmp_pointer"
mv -f "$tmp_pointer" "$CURRENT_PATH_FILE"

echo "installed: $INSTALLED_PLUGIN"
echo "pointer:   $CURRENT_PATH_FILE"

echo
echo "== Install Spatial HUD =="

[[ -x "$SPATIAL_HUD_INSTALLER" ]] || chmod +x "$SPATIAL_HUD_INSTALLER"
"$SPATIAL_HUD_INSTALLER"

echo
echo "== Reload Lua config =="
echo "spatial.lua declares versioned plugin: $INSTALLED_PLUGIN"

# Do NOT manually unload a config-managed plugin here.
# Hyprland 0.56.2 caches the last config plugin path list. A manual unload
# followed by the same config path can leave the plugin unloaded because
# updateConfigPlugins() returns early when the path list is unchanged.
# The versioned path above intentionally changes when the .so content changes,
# so config reconciliation unloads the old build and loads this one.
hyprctl reload

echo
echo "== Wait for config-managed plugin =="
plugin_ready=0
for _ in $(seq 1 120); do
  if hyprctl plugin list 2>/dev/null | grep -q "gendbyte-spatial"; then
    plugin_ready=1
    break
  fi
  sleep 0.1
done

[[ "$plugin_ready" -eq 1 ]] || {
  echo
  echo "== Config errors after failed plugin load =="
  hyprctl configerrors || true
  echo
  echo "current pointer:"
  cat "$CURRENT_PATH_FILE" 2>/dev/null || true
  echo
  echo "plugin list:"
  hyprctl plugin list || true
  die "gendbyte-spatial was not loaded by Lua config from $INSTALLED_PLUGIN"
}

# PluginSystem performs a second config reload after loading the .so.
sleep 1

echo
echo "== Plugin list =="
hyprctl plugin list

echo
echo "== Config errors =="
config_errors="$(hyprctl configerrors)"
printf '%s\n' "$config_errors"
[[ "$config_errors" != *"gendbyte"* ]] || die "Spatial-related config error detected"

echo
echo "== Check direct Lua API =="
lua_check="$(hyprctl eval 'assert(type(hl.plugin.gendbyte_spatial) == "table", "missing hl.plugin.gendbyte_spatial"); assert(type(hl.plugin.gendbyte_spatial.enabled) == "function", "missing enabled"); assert(type(hl.plugin.gendbyte_spatial.toggle) == "function", "missing toggle"); assert(type(hl.plugin.gendbyte_spatial.pan) == "function", "missing pan"); assert(type(hl.plugin.gendbyte_spatial.nudge) == "function", "missing nudge"); assert(type(hl.plugin.gendbyte_spatial.brake) == "function", "missing brake"); assert(type(hl.plugin.gendbyte_spatial.reset) == "function", "missing reset")')"
printf '%s\n' "$lua_check"
[[ "$lua_check" != error:* ]] || die "Lua plugin namespace validation failed"
echo "Lua API: OK"

echo
echo "== Spatial keybindings =="
binds="$(hyprctl -j binds)"
if command -v jq >/dev/null 2>&1; then
  printf '%s\n' "$binds" | jq -r '
    .[]
    | select((.description // "") | ascii_downcase | contains("spatial"))
    | "\(.modmask)  \(.key)  \(.description // "")"
  '
  count="$(printf '%s\n' "$binds" | jq '[.[] | select((.description // "") | ascii_downcase | contains("spatial"))] | length')"
  [[ "$count" -eq 12 ]] || die "Expected 12 Spatial bindings, found $count"
else
  printf '%s\n' "$binds" | grep -i spatial || true
fi

echo
echo "== Normalize Spatial state =="
hyprctl gendbyte-spatial disable >/dev/null 2>&1 || true
baseline_status="$(hyprctl gendbyte-spatial status)"
printf '%s\n' "$baseline_status"
[[ "$baseline_status" == *'"enabled":false'* ]] || die "Could not normalize Spatial state to disabled"

echo
echo "== Direct Lua toggle ON =="
toggle_on="$(hyprctl eval 'hl.plugin.gendbyte_spatial.toggle()')"
printf '%s\n' "$toggle_on"
[[ "$toggle_on" != error:* ]] || die "Direct Lua toggle ON failed"
sleep 0.2
status_on="$(hyprctl gendbyte-spatial status)"
printf '%s\n' "$status_on"
[[ "$status_on" == *'"enabled":true'* ]] || die "Direct Lua toggle did not enable spatial mode"
STATUS_JSON="$status_on" python3 - <<'PY' || die "Spatial mode did not start at 74 percent zoom"
import json
import math
import os
status = json.loads(os.environ["STATUS_JSON"])
zoom = float(status["camera"]["zoom"])
if not math.isclose(zoom, 0.74, rel_tol=0.0, abs_tol=1e-9):
    raise SystemExit(f"unexpected zoom: {zoom}")
PY

echo
echo "== Direct Lua toggle OFF =="
toggle_off="$(hyprctl eval 'hl.plugin.gendbyte_spatial.toggle()')"
printf '%s\n' "$toggle_off"
[[ "$toggle_off" != error:* ]] || die "Direct Lua toggle OFF failed"
sleep 0.2
status_off="$(hyprctl gendbyte-spatial status)"
printf '%s\n' "$status_off"
[[ "$status_off" == *'"enabled":false'* ]] || die "Direct Lua toggle did not disable spatial mode"

echo
echo
echo "Note: Windows Xbox Game Bar intercepts Win+Alt+G before Hyprland."
echo "On Try Omarchy, use Super+F12 to toggle Spatial Desktop; while enabled, use plain Arrow keys to move the camera."
echo "=============================================="
echo "Spatial plugin is versioned, installed, and config-managed."
echo "Spatial HUD: $SPATIAL_HUD_ID"
echo "Lua API: OK"
echo "Spatial bindings: OK"
echo
echo "Hotkeys:"
echo "  Super+Alt+G      Toggle Spatial Desktop (native Linux)"
echo "  Super+F12        Toggle Spatial Desktop (Try Omarchy)"
echo "  Super+Alt+Arrow  Camera movement (native Linux)"
echo "  Arrow keys       Camera movement while Spatial is ON"
echo "  Super+Alt+0      Reset camera (native Linux)"
echo "  0                Reset camera while Spatial is ON"
echo
echo "Single-monitor sessions can use ordinary tiled windows directly."
echo "No manual 'hyprctl dispatch setfloating' step is required."
echo "On multi-monitor sessions, tiled cross-seam projection is still deferred."

echo
echo "== Prune superseded plugin builds =="
while IFS= read -r -d '' old_plugin; do
  if [[ "$old_plugin" != "$INSTALLED_PLUGIN" ]]; then
    rm -f -- "$old_plugin"
  fi
done < <(find "$INSTALL_DIR" -maxdepth 1 -type f -name 'gendbyte-spatial-*.so' -print0 2>/dev/null || true)

echo "kept: $INSTALLED_PLUGIN"
echo "=============================================="
