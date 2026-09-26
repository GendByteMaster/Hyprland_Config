#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
INSTALLER="$ROOT/spatial/core/tools/install-spatial-hud.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE_BIN="$TMP/bin"
FAKE_STATE="$TMP/state"
LOG="$TMP/omarchy-shell.log"
COUNT="$TMP/list-count"
HOME_DIR="$TMP/home"

mkdir -p "$FAKE_BIN" "$FAKE_STATE" "$HOME_DIR"
printf '0\n' >"$COUNT"
: >"$LOG"

cat >"$FAKE_BIN/omarchy-shell" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "$*" >>"$FAKE_LOG"

case "$*" in
  "shell rescanPlugins")
    echo ok
    ;;
  "shell listPlugins")
    count="$(cat "$FAKE_COUNT")"
    count=$((count + 1))
    printf '%s\n' "$count" >"$FAKE_COUNT"

    if [[ "${FAKE_NEVER_DISCOVER:-0}" == "1" || "$count" -lt 3 ]]; then
      echo '[]'
    else
      echo '[{"id":"gendbyte.spatial-hud","name":"Spatial Desktop HUD"}]'
    fi
    ;;
  "shell setPluginEnabled gendbyte.spatial-hud true")
    count="$(cat "$FAKE_COUNT")"
    if (( count < 3 )); then
      echo "enable-before-discovery" >&2
      exit 9
    fi
    echo ok
    ;;
  *)
    echo "unexpected omarchy-shell call: $*" >&2
    exit 8
    ;;
esac
EOF
chmod +x "$FAKE_BIN/omarchy-shell"

export FAKE_LOG="$LOG"
export FAKE_COUNT="$COUNT"

echo "== delayed discovery =="
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" SPATIAL_HUD_DISCOVERY_ATTEMPTS=6 SPATIAL_HUD_DISCOVERY_SLEEP=0 bash "$INSTALLER"

TARGET="$HOME_DIR/.config/omarchy/plugins/gendbyte.spatial-hud"
[[ -L "$TARGET" ]] || {
  echo "FAIL: Spatial HUD target was not installed as a symlink" >&2
  exit 1
}

expected_source="$ROOT/omarchy/plugins/gendbyte.spatial-hud"
[[ "$(readlink -f "$TARGET")" == "$(readlink -f "$expected_source")" ]] || {
  echo "FAIL: Spatial HUD symlink points to the wrong source" >&2
  exit 1
}

list_calls="$(grep -c '^shell listPlugins$' "$LOG")"
[[ "$list_calls" -ge 3 ]] || {
  echo "FAIL: installer did not wait for delayed plugin discovery" >&2
  cat "$LOG" >&2
  exit 1
}

enable_line="$(grep -n '^shell setPluginEnabled gendbyte.spatial-hud true$' "$LOG" | cut -d: -f1)"
third_list_line="$(grep -n '^shell listPlugins$' "$LOG" | sed -n '3p' | cut -d: -f1)"
[[ -n "$enable_line" && -n "$third_list_line" && "$enable_line" -gt "$third_list_line" ]] || {
  echo "FAIL: plugin was enabled before discovery completed" >&2
  cat "$LOG" >&2
  exit 1
}

echo "== idempotent install =="
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" SPATIAL_HUD_DISCOVERY_ATTEMPTS=2 SPATIAL_HUD_DISCOVERY_SLEEP=0 bash "$INSTALLER"

echo "== discovery timeout =="
TIMEOUT_HOME="$TMP/timeout-home"
mkdir -p "$TIMEOUT_HOME"
printf '0\n' >"$COUNT"
: >"$LOG"

if HOME="$TIMEOUT_HOME"   PATH="$FAKE_BIN:$PATH"   FAKE_NEVER_DISCOVER=1   SPATIAL_HUD_DISCOVERY_ATTEMPTS=2   SPATIAL_HUD_DISCOVERY_SLEEP=0   bash "$INSTALLER"; then
  echo "FAIL: installer unexpectedly succeeded without plugin discovery" >&2
  exit 1
fi

if grep -q '^shell setPluginEnabled ' "$LOG"; then
  echo "FAIL: installer attempted enable after discovery timeout" >&2
  cat "$LOG" >&2
  exit 1
fi

echo "spatial_hud_installer_test: PASS"
