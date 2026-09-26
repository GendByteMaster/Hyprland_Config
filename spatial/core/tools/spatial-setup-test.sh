#!/usr/bin/env bash
set -euo pipefail

BRANCH="feat/issue-24-developer-spatial-desktop"
BUILD_DIR="build/spatial-plugin"
PLUGIN="$BUILD_DIR/gendbyte-spatial.so"
INSTALL_DIR="$HOME/.local/lib/gendbyte-spatial"
CURRENT_PATH_FILE="$INSTALL_DIR/current-path"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v git >/dev/null || die "git not found"
command -v cmake >/dev/null || die "cmake not found"
command -v hyprctl >/dev/null || die "hyprctl not found"
command -v install >/dev/null || die "install not found"
command -v sha256sum >/dev/null || die "sha256sum not found"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Run this inside the Hyprland_Config repository"
cd "$ROOT"

echo "== Repository =="
echo "$ROOT"

echo
echo "== Branch =="
git switch "$BRANCH"
git pull --ff-only

echo
echo "== Build spatial plugin =="
cmake -S spatial/core -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DSPATIAL_BUILD_PLUGIN=ON \
  -DSPATIAL_BUILD_TESTS=ON

cmake --build "$BUILD_DIR" --parallel

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

tmp_pointer="$CURRENT_PATH_FILE.tmp.$"
printf '%s\n' "$INSTALLED_PLUGIN" >"$tmp_pointer"
mv -f "$tmp_pointer" "$CURRENT_PATH_FILE"

echo "installed: $INSTALLED_PLUGIN"
echo "pointer:   $CURRENT_PATH_FILE"

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
lua_check="$(hyprctl eval 'assert(type(hl.plugin.gendbyte_spatial) == "table", "missing hl.plugin.gendbyte_spatial"); assert(type(hl.plugin.gendbyte_spatial.toggle) == "function", "missing toggle"); assert(type(hl.plugin.gendbyte_spatial.pan) == "function", "missing pan"); assert(type(hl.plugin.gendbyte_spatial.nudge) == "function", "missing nudge"); assert(type(hl.plugin.gendbyte_spatial.brake) == "function", "missing brake"); assert(type(hl.plugin.gendbyte_spatial.reset) == "function", "missing reset")')"
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
echo "On Try Omarchy, use Ctrl+Alt+G and Ctrl+Alt+Arrow keys; these avoid the Windows Super/Win key."
echo "=============================================="
echo "Spatial plugin is versioned, installed, and config-managed."
echo "Lua API: OK"
echo "Spatial bindings: OK"
echo
echo "Hotkeys:"
echo "  Super+Alt+G      Toggle Spatial Desktop (native Linux)"
echo "  Ctrl+Alt+G       Toggle Spatial Desktop (Try Omarchy)"
echo "  Super+Alt+Arrow  Camera movement (native Linux)"
echo "  Ctrl+Alt+Arrow   Camera movement (Try Omarchy)"
echo "  Super+Alt+0      Reset camera (native Linux)"
echo "  Ctrl+Alt+0       Reset camera (Try Omarchy)"
echo
echo "For visible movement first make the active window floating:"
echo "  hyprctl dispatch setfloating"
echo "=============================================="
