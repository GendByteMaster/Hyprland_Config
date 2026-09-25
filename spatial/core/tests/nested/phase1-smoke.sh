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

echo
echo "== Managed windows =="
hyprctl gendbyte-spatial windows

echo
echo "== Pan +64,+32 =="
camera="$(hyprctl gendbyte-spatial pan 64 32)"
echo "$camera"
assert_contains "$camera" '"x":64' "camera x after positive pan"
assert_contains "$camera" '"y":32' "camera y after positive pan"

echo
echo "Visually verify that every managed floating window moved exactly -64 px horizontally and -32 px vertically."
echo "World coordinates reported by 'gendbyte-spatial windows' must remain unchanged."

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
echo "PASS: command/lifecycle smoke sequence completed."
echo "NOTE: visual geometry correctness and compositor stability still require human observation in the nested session."
