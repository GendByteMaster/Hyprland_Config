#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /absolute/path/to/gendbyte-spatial.so" >&2
  exit 2
fi

PLUGIN_PATH="$1"
if [[ "$PLUGIN_PATH" != /* || ! -f "$PLUGIN_PATH" ]]; then
  echo "plugin path must be an existing absolute file: $PLUGIN_PATH" >&2
  exit 2
fi

for bin in Hyprland hyprctl jq foot weston; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "missing required executable: $bin" >&2
    exit 2
  }
done

RUNTIME_ROOT="$(mktemp -d)"
CONFIG_PATH="$RUNTIME_ROOT/hyprland.conf"
LOG_PATH="$RUNTIME_ROOT/hyprland.log"
export XDG_RUNTIME_DIR="$RUNTIME_ROOT/xdg"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

cat >"$CONFIG_PATH" <<'EOF'
animations {
  enabled = false
}

misc {
  disable_hyprland_logo = true
  disable_splash_rendering = true
  force_default_wallpaper = 0
}
EOF

WESTON_PID=""
HYPR_PID=""
loaded=0

cleanup() {
  set +e

  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && "$loaded" -eq 1 ]]; then
    hyprctl gendbyte-spatial disable >/dev/null 2>&1 || true
    hyprctl plugin unload "$PLUGIN_PATH" >/dev/null 2>&1 || true
  fi

  if [[ -n "$HYPR_PID" ]]; then
    kill "$HYPR_PID" >/dev/null 2>&1 || true
    wait "$HYPR_PID" >/dev/null 2>&1 || true
  fi

  if [[ -n "$WESTON_PID" ]]; then
    kill "$WESTON_PID" >/dev/null 2>&1 || true
    wait "$WESTON_PID" >/dev/null 2>&1 || true
  fi

  rm -rf "$RUNTIME_ROOT"
}
trap cleanup EXIT INT TERM

echo "== Starting isolated headless Hyprland =="
HYPRLAND_NO_CRASHREPORTER=1   Hyprland --i-am-really-stupid --config "$CONFIG_PATH" >"$LOG_PATH" 2>&1 &
HYPR_PID=$!

for _ in $(seq 1 80); do
  if ! kill -0 "$HYPR_PID" 2>/dev/null; then
    echo "Hyprland exited before publishing an instance" >&2
    cat "$LOG_PATH" >&2
    exit 1
  fi

  instance_json="$(hyprctl -j instances 2>/dev/null || true)"
  instance="$(printf '%s' "$instance_json" | jq -r '.[-1].instance // empty' 2>/dev/null || true)"
  if [[ -n "$instance" ]]; then
    export HYPRLAND_INSTANCE_SIGNATURE="$instance"
    break
  fi

  sleep 0.1
done

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  echo "Hyprland instance did not become available" >&2
  cat "$LOG_PATH" >&2
  exit 1
fi

echo "instance: $HYPRLAND_INSTANCE_SIGNATURE"

echo "== Waiting for nested Hyprland output =="
for _ in $(seq 1 80); do
  monitors="$(hyprctl -j monitors 2>/dev/null || true)"
  count="$(printf '%s' "$monitors" | jq 'length' 2>/dev/null || echo 0)"
  if [[ "$count" -gt 0 ]]; then
    break
  fi
  sleep 0.1
done

monitors="$(hyprctl -j monitors)"
if [[ "$(printf '%s' "$monitors" | jq 'length')" -lt 1 ]]; then
  echo "no active headless monitor became available" >&2
  cat "$LOG_PATH" >&2
  exit 1
fi
printf '%s
' "$monitors" | jq .

echo "== Loading plugin =="
hyprctl plugin load "$PLUGIN_PATH"
loaded=1
hyprctl plugin list

status="$(hyprctl gendbyte-spatial status)"
printf '%s
' "$status" | jq -e '.protocol == 1 and .enabled == false' >/dev/null

echo "== Launching test Wayland client =="
hyprctl dispatch exec "foot --title spatial-ci"

client_address=""
for _ in $(seq 1 80); do
  clients="$(hyprctl -j clients 2>/dev/null || true)"
  client_address="$(printf '%s' "$clients" | jq -r '.[] | select(.title == "spatial-ci") | .address' | head -n1)"
  if [[ -n "$client_address" ]]; then
    break
  fi
  sleep 0.1
done

if [[ -z "$client_address" ]]; then
  echo "test foot client did not appear" >&2
  hyprctl -j clients >&2 || true
  cat "$LOG_PATH" >&2
  exit 1
fi

echo "client: $client_address"

hyprctl dispatch focuswindow "address:$client_address"
hyprctl dispatch setfloating

for _ in $(seq 1 30); do
  floating="$(hyprctl -j clients | jq -r --arg address "$client_address" '.[] | select(.address == $address) | .floating')"
  [[ "$floating" == "true" ]] && break
  sleep 0.1
done

if [[ "$floating" != "true" ]]; then
  echo "test client did not become floating" >&2
  hyprctl -j clients >&2
  exit 1
fi

before_client="$(hyprctl -j clients | jq -c --arg address "$client_address" '.[] | select(.address == $address)')"
before_x="$(printf '%s' "$before_client" | jq '.at[0]')"
before_y="$(printf '%s' "$before_client" | jq '.at[1]')"
before_w="$(printf '%s' "$before_client" | jq '.size[0]')"
before_h="$(printf '%s' "$before_client" | jq '.size[1]')"

echo "before: x=$before_x y=$before_y w=$before_w h=$before_h"

echo "== Enable spatial mode =="
enabled="$(hyprctl gendbyte-spatial enable)"
printf '%s
' "$enabled" | jq -e '.enabled == true and .managed_window_count >= 1' >/dev/null

world_before="$(hyprctl gendbyte-spatial windows | jq -cS '.windows')"

echo "== Pan camera +64,+32 =="
camera="$(hyprctl gendbyte-spatial pan 64 32)"
printf '%s
' "$camera" | jq -e '.camera.x == 64 and .camera.y == 32' >/dev/null

after_client="$(hyprctl -j clients | jq -c --arg address "$client_address" '.[] | select(.address == $address)')"
after_x="$(printf '%s' "$after_client" | jq '.at[0]')"
after_y="$(printf '%s' "$after_client" | jq '.at[1]')"
after_w="$(printf '%s' "$after_client" | jq '.size[0]')"
after_h="$(printf '%s' "$after_client" | jq '.size[1]')"

jq -e -n   --argjson before_x "$before_x"   --argjson before_y "$before_y"   --argjson after_x "$after_x"   --argjson after_y "$after_y"   '($after_x == ($before_x - 64)) and ($after_y == ($before_y - 32))' >/dev/null

jq -e -n   --argjson before_w "$before_w"   --argjson before_h "$before_h"   --argjson after_w "$after_w"   --argjson after_h "$after_h"   '($after_w == $before_w) and ($after_h == $before_h)' >/dev/null

world_after="$(hyprctl gendbyte-spatial windows | jq -cS '.windows')"
if [[ "$world_before" != "$world_after" ]]; then
  echo "world rectangles changed after camera pan" >&2
  echo "before: $world_before" >&2
  echo "after:  $world_after" >&2
  exit 1
fi

echo "== Pan camera back =="
camera="$(hyprctl gendbyte-spatial pan -64 -32)"
printf '%s
' "$camera" | jq -e '.camera.x == 0 and .camera.y == 0' >/dev/null

echo "== Disable and verify restoration =="
disabled="$(hyprctl gendbyte-spatial disable)"
printf '%s
' "$disabled" | jq -e '.enabled == false' >/dev/null

restored_client="$(hyprctl -j clients | jq -c --arg address "$client_address" '.[] | select(.address == $address)')"
restored_x="$(printf '%s' "$restored_client" | jq '.at[0]')"
restored_y="$(printf '%s' "$restored_client" | jq '.at[1]')"
restored_w="$(printf '%s' "$restored_client" | jq '.size[0]')"
restored_h="$(printf '%s' "$restored_client" | jq '.size[1]')"

jq -e -n   --argjson before_x "$before_x"   --argjson before_y "$before_y"   --argjson before_w "$before_w"   --argjson before_h "$before_h"   --argjson restored_x "$restored_x"   --argjson restored_y "$restored_y"   --argjson restored_w "$restored_w"   --argjson restored_h "$restored_h"   '($restored_x == $before_x) and
   ($restored_y == $before_y) and
   ($restored_w == $before_w) and
   ($restored_h == $before_h)' >/dev/null

echo "== Config errors =="
config_errors="$(hyprctl configerrors)"
printf '%s
' "$config_errors"
if [[ "$config_errors" == *"gendbyte-spatial"* ]]; then
  echo "spatial-related config error detected" >&2
  exit 1
fi

echo "== Unload plugin =="
hyprctl plugin unload "$PLUGIN_PATH"
loaded=0

if ! kill -0 "$HYPR_PID" 2>/dev/null; then
  echo "Hyprland died during runtime test" >&2
  cat "$LOG_PATH" >&2
  exit 1
fi

echo "PASS: headless runtime projection test completed."
