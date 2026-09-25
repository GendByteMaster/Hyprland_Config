#!/usr/bin/env bash
set -euo pipefail

BRANCH="feat/issue-24-developer-spatial-desktop"
BUILD_DIR="build/spatial-plugin"
PLUGIN="$BUILD_DIR/gendbyte-spatial.so"
INSTALL_DIR="$HOME/.local/lib/gendbyte-spatial"
INSTALLED_PLUGIN="$INSTALL_DIR/gendbyte-spatial.so"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v git >/dev/null || die "git not found"
command -v cmake >/dev/null || die "cmake not found"
command -v hyprctl >/dev/null || die "hyprctl not found"
command -v install >/dev/null || die "install not found"

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
echo "== Remove old loaded copies =="
hyprctl gendbyte-spatial disable >/dev/null 2>&1 || true
hyprctl plugin unload "$ROOT/$PLUGIN" >/dev/null 2>&1 || true
hyprctl plugin unload "$INSTALLED_PLUGIN" >/dev/null 2>&1 || true

echo
echo "== Install stable user plugin =="
install -Dm755 "$PLUGIN" "$INSTALLED_PLUGIN"
echo "$INSTALLED_PLUGIN"

echo
echo "== Reload Lua config =="
echo "spatial.lua declares: $INSTALLED_PLUGIN"
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
lua_check="$(hyprctl eval 'assert(type(hl.plugin.gendbyte_spatial) == "table", "missing hl.plugin.gendbyte_spatial"); assert(type(hl.plugin.gendbyte_spatial.toggle) == "function", "missing toggle"); assert(type(hl.plugin.gendbyte_spatial.pan) == "function", "missing pan"); assert(type(hl.plugin.gendbyte_spatial.reset) == "function", "missing reset")')"
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
  [[ "$count" -eq 6 ]] || die "Expected 6 Spatial bindings, found $count"
else
  printf '%s\n' "$binds" | grep -i spatial || true
fi

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
echo "=============================================="
echo "Spatial plugin is installed and config-managed."
echo "Lua API: OK"
echo "Spatial bindings: OK"
echo
echo "Hotkeys:"
echo "  Ctrl+Super+G     Toggle Spatial Desktop"
echo "  Super+Alt+Left   Camera left"
echo "  Super+Alt+Right  Camera right"
echo "  Super+Alt+Up     Camera up"
echo "  Super+Alt+Down   Camera down"
echo "  Super+Alt+0      Reset camera"
echo
echo "For visible movement first make the active window floating:"
echo "  hyprctl dispatch setfloating"
echo "=============================================="
