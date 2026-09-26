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
echo "== Close legacy overview surface =="
if command -v qs >/dev/null 2>&1; then
  qs -c gendbyte-workspace-overview ipc call gendbyte-workspace-overview hide >/dev/null 2>&1 || true
  qs -p "$ROOT/quickshell/gendbyte-workspace-overview" ipc call gendbyte-workspace-overview hide >/dev/null 2>&1 || true
fi

echo
echo "== Verify Super+Tab ownership =="
super_tab_ready=0
for _ in $(seq 1 50); do
  binds_now="$(hyprctl -j binds 2>/dev/null || true)"
  if BINDS_JSON="$binds_now" python3 - <<'PY'
import json
import os

try:
    binds = json.loads(os.environ["BINDS_JSON"])
except Exception:
    raise SystemExit(1)

descriptions = [str(item.get("description") or "") for item in binds if isinstance(item, dict)]
live = sum(desc == "Spatial Window Overview" for desc in descriptions)
loading = sum(desc == "Spatial Window Overview (Loading)" for desc in descriptions)
legacy = sum("Legacy Fallback" in desc and "Overview" in desc for desc in descriptions)

raise SystemExit(0 if live == 1 and loading == 0 and legacy == 0 else 1)
PY
  then
    super_tab_ready=1
    break
  fi
  sleep 0.1
done

[[ "$super_tab_ready" -eq 1 ]] || {
  echo "Super+Tab ownership is not stable:" >&2
  hyprctl -j binds 2>/dev/null | python3 -c '
import json
import sys

try:
    binds = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)

for item in binds:
    if not isinstance(item, dict):
        continue
    desc = str(item.get("description") or "")
    if "Overview" in desc or "Spatial" in desc:
        print(f"{item.get('modmask')}  {item.get('key')}  {desc}")
' >&2 || true
  die "Super+Tab must have exactly one live owner: Spatial Window Overview"
}

echo "Super+Tab owner: Spatial Window Overview"

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
lua_check="$(hyprctl eval 'assert(type(hl.plugin.gendbyte_spatial) == "table", "missing hl.plugin.gendbyte_spatial"); assert(type(hl.plugin.gendbyte_spatial.enabled) == "function", "missing enabled"); assert(type(hl.plugin.gendbyte_spatial.toggle) == "function", "missing toggle"); assert(type(hl.plugin.gendbyte_spatial.overview) == "function", "missing overview"); assert(type(hl.plugin.gendbyte_spatial.select) == "function", "missing select"); assert(type(hl.plugin.gendbyte_spatial.pan) == "function", "missing pan"); assert(type(hl.plugin.gendbyte_spatial.nudge) == "function", "missing nudge"); assert(type(hl.plugin.gendbyte_spatial.brake) == "function", "missing brake"); assert(type(hl.plugin.gendbyte_spatial.reset) == "function", "missing reset")')"
printf '%s\n' "$lua_check"
[[ "$lua_check" != error:* ]] || die "Lua plugin namespace validation failed"
echo "Lua API: OK"

echo
echo "== Spatial keybindings =="
binds="$(hyprctl -j binds)"

BINDS_JSON="$binds" python3 - <<'PY' || die "Spatial binding contract validation failed"
import json
import os

binds = json.loads(os.environ["BINDS_JSON"])

expected = {
    "Toggle Spatial Desktop",
    "Toggle Spatial Desktop (Try Omarchy)",
    "Spatial Window Overview",
    "Spatial Camera Left",
    "Spatial Camera Right",
    "Spatial Camera Up",
    "Spatial Camera Down",
    "Spatial Camera Left (Mode)",
    "Spatial Camera Right (Mode)",
    "Spatial Camera Up (Mode)",
    "Spatial Camera Down (Mode)",
    "Reset Spatial Camera",
    "Reset Spatial Camera (Mode)",
    "Select Spatial Window",
}

spatial = [
    item for item in binds
    if isinstance(item, dict)
    and "spatial" in str(item.get("description") or "").lower()
]

for item in spatial:
    print(f"{item.get('modmask')}  {item.get('key')}  {item.get('description') or ''}")

descriptions = [str(item.get("description") or "") for item in spatial]
actual = set(descriptions)

missing = sorted(expected - actual)
unexpected = sorted(actual - expected)
duplicates = sorted({name for name in descriptions if descriptions.count(name) > 1})

if missing or unexpected or duplicates or len(spatial) != len(expected):
    if missing:
        print("missing:", ", ".join(missing))
    if unexpected:
        print("unexpected:", ", ".join(unexpected))
    if duplicates:
        print("duplicates:", ", ".join(duplicates))
    print(f"expected {len(expected)} Spatial bindings, found {len(spatial)}")
    raise SystemExit(1)

print(f"Spatial bindings: {len(spatial)}/{len(expected)} OK")
PY

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
echo "== All-workspace capture =="

monitor_count="$(hyprctl -j monitors | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
if [[ "$monitor_count" -eq 1 ]]; then
  expected_windows="$(
    hyprctl -j clients | python3 -c '
import json
import sys

clients = json.load(sys.stdin)
count = 0
for window in clients:
    if window.get("mapped") is False:
        continue

    workspace = window.get("workspace") or {}
    name = str(workspace.get("name") or "")
    if not name or name.startswith("special:"):
        continue

    fullscreen = window.get("fullscreen", 0)
    try:
        if int(fullscreen) != 0:
            continue
    except (TypeError, ValueError):
        pass

    monitor = window.get("monitor", 0)
    try:
        if int(monitor) < 0:
            continue
    except (TypeError, ValueError):
        continue

    count += 1

print(count)
'
  )"

  managed_windows="$(
    STATUS_JSON="$status_on" python3 -c '
import json
import os
print(int(json.loads(os.environ["STATUS_JSON"]).get("managed_window_count", 0)))
'
  )"

  echo "eligible normal-workspace windows: $expected_windows"
  echo "Spatial managed windows:          $managed_windows"

  [[ "$managed_windows" -eq "$expected_windows" ]]     || die "Spatial did not capture every eligible window across normal workspaces ($managed_windows/$expected_windows)"
else
  echo "All-workspace capture check skipped: $monitor_count monitors detected."
  echo "Multi-monitor tiled cross-workspace projection remains fail-safe/deferred."
fi

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
echo "== Fit-all Spatial Overview =="
overview_on="$(hyprctl eval 'hl.plugin.gendbyte_spatial.overview()')"
printf '%s\n' "$overview_on"
[[ "$overview_on" != error:* ]] || die "Direct Lua overview ON failed"
sleep 0.25

overview_status="$(hyprctl gendbyte-spatial status)"
printf '%s\n' "$overview_status"
[[ "$overview_status" == *'"enabled":true'* ]] || die "Spatial overview did not enable"

overview_clients="$(hyprctl -j clients)"
CLIENTS_JSON="$overview_clients" python3 - <<'PY' || die "Spatial overview windows overlap"
import json
import os

clients = json.loads(os.environ["CLIENTS_JSON"])
rects = []

for window in clients:
    if window.get("mapped") is False:
        continue

    workspace = window.get("workspace") or {}
    name = str(workspace.get("name") or "")
    if not name or name.startswith("special:"):
        continue

    try:
        if int(window.get("fullscreen", 0)) != 0:
            continue
        if int(window.get("monitor", 0)) < 0:
            continue
    except (TypeError, ValueError):
        continue

    at = window.get("at") or [0, 0]
    size = window.get("size") or [0, 0]
    if len(at) < 2 or len(size) < 2:
        continue

    x, y = float(at[0]), float(at[1])
    width, height = float(size[0]), float(size[1])
    if width <= 0 or height <= 0:
        continue

    rects.append((str(window.get("address") or "?"), x, y, width, height))

tolerance = 3.0
overlaps = []

for index, left in enumerate(rects):
    _, ax, ay, aw, ah = left
    for right in rects[index + 1:]:
        _, bx, by, bw, bh = right

        overlap_width = min(ax + aw, bx + bw) - max(ax, bx)
        overlap_height = min(ay + ah, by + bh) - max(ay, by)

        if overlap_width > tolerance and overlap_height > tolerance:
            overlaps.append((left, right, overlap_width, overlap_height))

if overlaps:
    for left, right, ow, oh in overlaps:
        print(
            "overlap:",
            left[0], f"({left[1]:.0f},{left[2]:.0f},{left[3]:.0f}x{left[4]:.0f})",
            "<->",
            right[0], f"({right[1]:.0f},{right[2]:.0f},{right[3]:.0f}x{right[4]:.0f})",
            f"intersection={ow:.0f}x{oh:.0f}",
        )
    raise SystemExit(1)

print(f"Fit-all overview: {len(rects)} windows, no overlaps")
PY

overview_off="$(hyprctl eval 'hl.plugin.gendbyte_spatial.overview()')"
printf '%s\n' "$overview_off"
[[ "$overview_off" != error:* ]] || die "Direct Lua overview OFF failed"
sleep 0.2

overview_status_off="$(hyprctl gendbyte-spatial status)"
[[ "$overview_status_off" == *'"enabled":false'* ]] || die "Spatial overview did not restore normal mode"

echo
echo
echo "Note: Windows Xbox Game Bar intercepts Win+Alt+G before Hyprland."
echo "Use Super+Tab for the fit-all Spatial Overview; Super+F12 keeps the free Spatial camera mode; click a window to restore its workspace and focus it."
echo "=============================================="
echo "Spatial plugin is versioned, installed, and config-managed."
echo "Spatial HUD: $SPATIAL_HUD_ID"
echo "Lua API: OK"
echo "Spatial bindings: OK"
echo
echo "Hotkeys:"
echo "  Super+Alt+G      Toggle Spatial Desktop (native Linux)"
echo "  Super+Tab        Fit-all Spatial Window Overview"
echo "  Super+F12        Toggle free Spatial camera mode (Try Omarchy)"
echo "  Super+Alt+Arrow  Camera movement (native Linux)"
echo "  Arrow keys       Camera movement while Spatial is ON"
echo "  Super+Alt+0      Reset camera (native Linux)"
echo "  0                Reset camera while Spatial is ON"
echo "  Left click       Select window, exit Spatial, restore its workspace/focus"
echo
echo "Single-monitor Spatial mode captures eligible windows from every normal workspace."
echo "Normal workspaces are projected as horizontal world lanes without moving windows out of their layout trees."
echo "Ordinary workspace switching while Spatial is ON jumps the camera to that workspace lane."
echo "Special workspaces and multi-monitor tiled cross-seam projection remain deferred."
echo "No manual 'hyprctl dispatch setfloating' step is required."

echo
echo "== Prune superseded plugin builds =="
while IFS= read -r -d '' old_plugin; do
  if [[ "$old_plugin" != "$INSTALLED_PLUGIN" ]]; then
    rm -f -- "$old_plugin"
  fi
done < <(find "$INSTALL_DIR" -maxdepth 1 -type f -name 'gendbyte-spatial-*.so' -print0 2>/dev/null || true)

echo "kept: $INSTALLED_PLUGIN"
echo "=============================================="
