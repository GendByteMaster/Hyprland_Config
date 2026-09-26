#!/usr/bin/env bash
set -euo pipefail

SPATIAL_HUD_ID="gendbyte.spatial-hud"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SOURCE_DIR="$ROOT/omarchy/plugins/$SPATIAL_HUD_ID"
TARGET_DIR="$HOME/.config/omarchy/plugins/$SPATIAL_HUD_ID"
DISCOVERY_ATTEMPTS="${SPATIAL_HUD_DISCOVERY_ATTEMPTS:-60}"
DISCOVERY_SLEEP="${SPATIAL_HUD_DISCOVERY_SLEEP:-0.1}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v readlink >/dev/null || die "readlink not found"
command -v python3 >/dev/null || die "python3 not found"

[[ -d "$SOURCE_DIR" ]] || die "Spatial HUD source is missing: $SOURCE_DIR"
mkdir -p "$(dirname "$TARGET_DIR")"

if [[ -L "$TARGET_DIR" ]]; then
  target_real="$(readlink -f "$TARGET_DIR" 2>/dev/null || true)"
  source_real="$(readlink -f "$SOURCE_DIR" 2>/dev/null || true)"
  [[ -n "$target_real" && "$target_real" == "$source_real" ]]     || die "Spatial HUD target is owned by another source: $TARGET_DIR"
elif [[ -e "$TARGET_DIR" ]]; then
  die "Spatial HUD target is occupied by another file: $TARGET_DIR"
else
  ln -s "$SOURCE_DIR" "$TARGET_DIR"
fi

if ! command -v omarchy-shell >/dev/null 2>&1; then
  echo "Spatial HUD linked, but omarchy-shell is unavailable; HUD enable skipped."
  exit 0
fi

omarchy-shell shell rescanPlugins >/dev/null   || die "Omarchy Shell failed to rescan plugins for Spatial HUD"

plugin_list_json() {
  if command -v omarchy-plugin-list >/dev/null 2>&1; then
    omarchy-plugin-list --json 2>/dev/null || true
    return
  fi

  if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin list --json 2>/dev/null || true
    return
  fi

  omarchy-shell shell listPlugins 2>/dev/null || true
}

plugin_discovered() {
  local plugins_json
  plugins_json="$(plugin_list_json)"
  [[ -n "$plugins_json" ]] || return 1

  PLUGINS_JSON="$plugins_json" SPATIAL_HUD_ID="$SPATIAL_HUD_ID" python3 - <<'PY'
import json
import os

try:
    data = json.loads(os.environ["PLUGINS_JSON"])
except Exception:
    raise SystemExit(1)

if isinstance(data, dict):
    candidates = data.get("plugins", [])
    if not isinstance(candidates, list):
        candidates = []
elif isinstance(data, list):
    candidates = data
else:
    candidates = []

wanted = os.environ["SPATIAL_HUD_ID"]
raise SystemExit(0 if any(isinstance(item, dict) and item.get("id") == wanted for item in candidates) else 1)
PY
}

discovered=0
for _ in $(seq 1 "$DISCOVERY_ATTEMPTS"); do
  if plugin_discovered; then
    discovered=1
    break
  fi
  sleep "$DISCOVERY_SLEEP"
done

if [[ "$discovered" -ne 1 ]]; then
  echo "Omarchy plugin registry after timeout:" >&2
  plugin_list_json >&2 || true
  die "Omarchy Shell did not discover $SPATIAL_HUD_ID after rescan"
fi

hud_enabled=""
for _ in $(seq 1 10); do
  hud_enabled="$(omarchy-shell shell setPluginEnabled "$SPATIAL_HUD_ID" true 2>/dev/null || true)"
  if [[ "$hud_enabled" == "ok" ]]; then
    break
  fi
  sleep 0.05
done

if [[ "$hud_enabled" != "ok" ]]; then
  echo "Omarchy plugin registry before failed enable:" >&2
  plugin_list_json >&2 || true
  die "Omarchy Shell failed to enable $SPATIAL_HUD_ID: ${hud_enabled:-no response}"
fi

echo "Spatial HUD enabled: $SPATIAL_HUD_ID"
