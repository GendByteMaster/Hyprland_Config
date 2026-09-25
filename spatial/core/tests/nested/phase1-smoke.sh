#!/usr/bin/env bash
set -euo pipefail

ACK_EXPECTED="I_UNDERSTAND_THIS_MUST_RUN_IN_A_DISPOSABLE_HYPRLAND_SESSION"

if [[ "${SPATIAL_TEST_ACK:-}" != "$ACK_EXPECTED" ]]; then
  cat >&2 <<'EOF'
Refusing to run.

This smoke test moves real Hyprland windows and unloads a compositor plugin.
Run it only inside a disposable/nested Hyprland session, then set:

  export SPATIAL_TEST_ACK=I_UNDERSTAND_THIS_MUST_RUN_IN_A_DISPOSABLE_HYPRLAND_SESSION
EOF
  exit 2
fi

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /absolute/path/to/gendbyte-spatial.so" >&2
  exit 2
fi

PLUGIN_PATH="$1"

if [[ "$PLUGIN_PATH" != /* ]]; then
  echo "plugin path must be absolute" >&2
  exit 2
fi

if [[ ! -f "$PLUGIN_PATH" ]]; then
  echo "plugin not found: $PLUGIN_PATH" >&2
  exit 2
fi

command -v hyprctl >/dev/null 2>&1 || {
  echo "hyprctl is required" >&2
  exit 2
}

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required for compositor-geometry validation" >&2
  exit 2
}

read_active_rect() {
  hyprctl -j activewindow | python3 -c '
import json
import sys

data = json.load(sys.stdin)
address = data.get("address")
at = data.get("at")
size = data.get("size")

if not address or not isinstance(at, list) or len(at) < 2 or not isinstance(size, list) or len(size) < 2:
    raise SystemExit("active window JSON does not contain address/at/size")

print(address, at[0], at[1], size[0], size[1])
'
}

assert_rect_delta() {
  python3 - "$@" <<'PY'
import math
import sys

label = sys.argv[1]
bx, by, bw, bh, ax, ay, aw, ah, expected_dx, expected_dy = map(float, sys.argv[2:])

checks = (
    math.isclose(ax - bx, expected_dx, abs_tol=1.0),
    math.isclose(ay - by, expected_dy, abs_tol=1.0),
    math.isclose(aw, bw, abs_tol=1.0),
    math.isclose(ah, bh, abs_tol=1.0),
)

if not all(checks):
    print(
        f"FAIL: {label}: "
        f"before=({bx},{by},{bw},{bh}) "
        f"after=({ax},{ay},{aw},{ah}) "
        f"expected_delta=({expected_dx},{expected_dy})",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
}

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  echo "HYPRLAND_INSTANCE_SIGNATURE is not set; no Hyprland session detected" >&2
  exit 2
fi

loaded=0

cleanup() {
  set +e
  if [[ "$loaded" -eq 1 ]]; then
    hyprctl gendbyte-spatial disable >/dev/null 2>&1 || true
    hyprctl plugin unload "$PLUGIN_PATH" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

assert_contains() {
  local value="$1"
  local expected="$2"
  local label="$3"

  if [[ "$value" != *"$expected"* ]]; then
    echo "FAIL: $label" >&2
    echo "expected substring: $expected" >&2
    echo "actual: $value" >&2
    exit 1
  fi
}

run_lua_eval() {
  local code="$1"
  local label="$2"
  local output
  local rc

  set +e
  output="$(hyprctl eval "$code" 2>&1)"
  rc=$?
  set -e

  if [[ "$rc" -ne 0 ]]; then
    echo "FAIL: $label" >&2
    echo "Lua code: $code" >&2
    echo "hyprctl exit: $rc" >&2
    echo "hyprctl output: $output" >&2
    return "$rc"
  fi

  printf '%s\n' "$output"
}

echo "== Hyprland =="
hyprctl version

echo
echo "== Load plugin =="
hyprctl plugin load "$PLUGIN_PATH"
loaded=1
hyprctl plugin list

echo
echo "== Initial status =="
status="$(hyprctl gendbyte-spatial status)"
echo "$status"
assert_contains "$status" '"protocol":1' "protocol version"
assert_contains "$status" '"enabled":false' "spatial starts disabled"

echo
echo "== Active floating test window =="
read -r active_address before_x before_y before_w before_h < <(read_active_rect)
echo "address=$active_address rect=($before_x,$before_y ${before_w}x${before_h})"

echo
echo "== Enable =="
enabled="$(hyprctl gendbyte-spatial enable)"
echo "$enabled"
assert_contains "$enabled" '"enabled":true' "spatial enable"

managed_count="$(printf '%s\n' "$enabled" | sed -n 's/.*"managed_window_count":\([0-9][0-9]*\).*/\1/p')"
if [[ -z "$managed_count" || "$managed_count" -lt 1 ]]; then
  cat >&2 <<'EOF'
FAIL: spatial mode enabled with zero managed windows.

Task 7 projection cannot be validated without at least one eligible window.
Before rerunning this smoke test, open a normal window and make it floating
on the currently visible workspace. Tiled and fullscreen windows are
intentionally excluded by the Phase 1 eligibility policy.
EOF
  exit 1
fi

echo
echo "== Managed windows =="
windows_before="$(hyprctl gendbyte-spatial windows)"
echo "$windows_before"

active_is_managed="$(
  ACTIVE_ADDRESS="$active_address" python3 -c '
import json
import os
import sys

def norm(value):
    return str(value).lower().removeprefix("0x")

data = json.load(sys.stdin)
active = norm(os.environ["ACTIVE_ADDRESS"])
print("yes" if any(norm(w.get("session_id", "")) == active for w in data.get("windows", [])) else "no")
' <<<"$windows_before"
)"

if [[ "$active_is_managed" != "yes" ]]; then
  cat >&2 <<EOF
FAIL: the active test window is not managed by spatial mode.

Active address: $active_address

Focus a floating, non-fullscreen window on the visible workspace and rerun.
This makes the geometry assertion deterministic instead of checking an
unrelated managed window.
EOF
  exit 1
fi

normalize_windows() {
  printf '%s\n' "$1" | sed -E 's/"epoch":[0-9]+,//'
}

PAN_X=320
PAN_Y=0

echo
echo "== Pan +${PAN_X},+${PAN_Y} =="
camera="$(hyprctl gendbyte-spatial pan "$PAN_X" "$PAN_Y")"
echo "$camera"
assert_contains "$camera" '"x":320' "camera x after direct Lua pan"
assert_contains "$camera" '"y":0' "camera y after direct Lua pan"

windows_after_pan="$(hyprctl gendbyte-spatial windows)"
if [[ "$(normalize_windows "$windows_before")" != "$(normalize_windows "$windows_after_pan")" ]]; then
  echo "FAIL: managed world rectangles changed after camera pan" >&2
  echo "before: $windows_before" >&2
  echo "after:  $windows_after_pan" >&2
  exit 1
fi

read -r after_address after_x after_y after_w after_h < <(read_active_rect)
if [[ "$after_address" != "$active_address" ]]; then
  echo "FAIL: active window changed during pan: $active_address -> $after_address" >&2
  exit 1
fi

assert_rect_delta \
  "live compositor projection" \
  "$before_x" "$before_y" "$before_w" "$before_h" \
  "$after_x" "$after_y" "$after_w" "$after_h" \
  "-$PAN_X" "-$PAN_Y"

echo
echo "PASS: hyprctl reports the active window moved by -${PAN_X}px horizontally."
echo "Visually verify the same large movement now."
echo "World rectangles were also checked automatically and remained unchanged."
echo "Holding the projected geometry for 5 seconds..."
sleep 5

echo
echo "== Pan back =="
camera="$(hyprctl gendbyte-spatial pan "-$PAN_X" "-$PAN_Y")"
echo "$camera"
assert_contains "$camera" '"x":0' "camera x returned to zero after direct Lua reset"
assert_contains "$camera" '"y":0' "camera y returned to zero after direct Lua reset"

read -r back_address back_x back_y back_w back_h < <(read_active_rect)
assert_rect_delta \
  "reverse pan restoration" \
  "$before_x" "$before_y" "$before_w" "$before_h" \
  "$back_x" "$back_y" "$back_w" "$back_h" \
  0 0

echo
echo "== Disable =="
disabled="$(hyprctl gendbyte-spatial disable)"
echo "$disabled"
assert_contains "$disabled" '"enabled":false' "spatial disable"

read -r restored_address restored_x restored_y restored_w restored_h < <(read_active_rect)
assert_rect_delta \
  "disable restoration" \
  "$before_x" "$before_y" "$before_w" "$before_h" \
  "$restored_x" "$restored_y" "$restored_w" "$restored_h" \
  0 0

echo
echo "PASS: hyprctl confirms the active window returned to its pre-enable compositor geometry."

echo
echo "== Config errors =="
hyprctl configerrors

echo
echo "== Unload =="
hyprctl plugin unload "$PLUGIN_PATH"
loaded=0
trap - EXIT INT TERM

echo
echo "PASS: command/lifecycle smoke sequence completed with $managed_count managed window(s)."
echo "PASS: managed world rectangles remained unchanged across camera pan."
echo "PASS: live compositor geometry moved by the expected delta and restored."
echo "NOTE: keybinding registration, focus/pointer behavior, and compositor stability still require human observation in the nested session."
