#!/usr/bin/env bash
set -euo pipefail

BRANCH="feat/issue-24-developer-spatial-desktop"
BUILD_DIR="build/spatial-plugin"
PLUGIN="$BUILD_DIR/gendbyte-spatial.so"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v git >/dev/null || die "git not found"
command -v cmake >/dev/null || die "cmake not found"
command -v hyprctl >/dev/null || die "hyprctl not found"
command -v realpath >/dev/null || die "realpath not found"

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

PLUGIN_ABS="$(realpath "$PLUGIN")"

echo
echo "== Native tests =="
ctest --test-dir "$BUILD_DIR" --output-on-failure

echo
echo "== Unload old plugin if loaded =="
hyprctl gendbyte-spatial disable >/dev/null 2>&1 || true
hyprctl plugin unload "$PLUGIN_ABS" >/dev/null 2>&1 || true

echo
echo "== Load plugin =="
hyprctl plugin load "$PLUGIN_ABS"

# Plugin queues a Lua config reload after registering its Lua API.
sleep 2

echo
echo "== Plugin list =="
hyprctl plugin list

echo
echo "== Config errors =="
hyprctl configerrors

echo
echo "== Check direct Lua API =="
hyprctl eval 'print("spatial-api:", type(hl.plugin.gendbyte_spatial), type(hl.plugin.gendbyte_spatial.toggle), type(hl.plugin.gendbyte_spatial.pan), type(hl.plugin.gendbyte_spatial.reset))'

echo
echo "== Spatial keybindings =="
if command -v jq >/dev/null 2>&1; then
  hyprctl -j binds | jq -r '
    .[]
    | select(
        ((.description // "") | ascii_downcase | contains("spatial"))
        or ((.key // "") | ascii_downcase | contains("spatial"))
      )
    | "\(.modmask)  \(.key)  \(.description // "")"
  '
else
  hyprctl -j binds | grep -i spatial || true
fi

echo
echo "== Direct Lua toggle ON =="
hyprctl eval 'hl.plugin.gendbyte_spatial.toggle()'
sleep 0.3
hyprctl gendbyte-spatial status

echo
echo "== Direct Lua toggle OFF =="
hyprctl eval 'hl.plugin.gendbyte_spatial.toggle()'
sleep 0.3
hyprctl gendbyte-spatial status

echo
echo "=============================================="
echo "Spatial plugin and Lua API check completed."
echo
echo "Hotkeys:"
echo "  Ctrl+Super+G     Toggle Spatial Desktop"
echo "  Super+Alt+Left   Camera left"
echo "  Super+Alt+Right  Camera right"
echo "  Super+Alt+Up     Camera up"
echo "  Super+Alt+Down   Camera down"
echo "  Super+Alt+0      Reset camera"
echo
echo "Before testing camera movement, make a window floating:"
echo "  hyprctl dispatch setfloating"
echo "=============================================="
