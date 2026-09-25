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

normalize_windows() {
  printf '%s\n' "$1" | sed -E 's/"epoch":[0-9]+,//'
}

echo
echo "== Pan +64,+32 =="
camera="$(hyprctl gendbyte-spatial pan 64 32)"
echo "$camera"
assert_contains "$camera" '"x":64' "camera x after positive pan"
assert_contains "$camera" '"y":32' "camera y after positive pan"

windows_after_pan="$(hyprctl gendbyte-spatial windows)"
if [[ "$(normalize_windows "$windows_before")" != "$(normalize_windows "$windows_after_pan")" ]]; then
  echo "FAIL: managed world rectangles changed after camera pan" >&2
  echo "before: $windows_before" >&2
  echo "after:  $windows_after_pan" >&2
  exit 1
fi

echo
echo "Visually verify that every managed floating window moved exactly -64 px horizontally and -32 px vertically."
echo "World rectangles were also checked automatically and remained unchanged."

echo
echo "== Pan back =="
camera="$(hyprctl gendbyte-spatial pan -64 -32)"
echo "$camera"
assert_contains "$camera" '"x":0' "camera x returned to zero"
assert_contains "$camera" '"y":0' "camera y returned to zero"

echo
echo "== Disable =="
disabled="$(hyprctl gendbyte-spatial disable)"
echo "$disabled"
assert_contains "$disabled" '"enabled":false' "spatial disable"

echo
echo "Visually verify that managed windows returned to their pre-enable compositor geometry."

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
echo "NOTE: visual geometry correctness, focus/pointer behavior, and compositor stability still require human observation in the nested session."
