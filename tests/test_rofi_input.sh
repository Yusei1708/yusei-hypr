#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Rofi Input Method & Focus Stability Regression Test Suite
# ==============================================================================
# - Verifies bin/rofi exists, is executable, passes bash -n
# - Verifies hyprland.lua (luac -p), keybinds, layer rules (no_anim), and
#   keybinds_parser.py compatibility
# - Tests bin/rofi with isolated mock real-rofi & fcitx5-remote binaries:
#   * CLI introspection passthrough (-h, -dump-config, -V)
#   * Active (2) -> -c before rofi, -o after rofi exit
#   * Inactive (1), Close (0), missing daemon, exit code preservation (1, 10)
#   * dmenu stdin/stdout pipeline fidelity
#   * SIGTERM signal toggle cleanup + restore
#   * Concurrent/double-launch refcount protection
#   * Rapid replacement handoff during post-exit grace window
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ROFI_WRAPPER="$REPO_ROOT/bin/rofi"
HYPRLAND_LUA="$REPO_ROOT/config/hypr/hyprland.lua"
KEYBINDS_CONF="$REPO_ROOT/config/hypr/keybinds.conf"
LEGACY_KEYBINDS_CONF="$REPO_ROOT/config/hypr/configs/Keybinds.conf"
WINDOW_RULES="$REPO_ROOT/config/hypr/configs/WindowRules.conf"
WINDOW_RULES_V3="$REPO_ROOT/config/hypr/configs/WindowRules-config-v3.conf"
STARTUP_APPS="$REPO_ROOT/config/hypr/UserConfigs/Startup_Apps.conf"
PARSER_PY="$REPO_ROOT/config/hypr/scripts/keybinds_parser.py"

TMP_ROOT="$(mktemp -d -t yusei_rofi_test_XXXXXX)"
BG_PIDS=()
cleanup_rofi_suite() {
    local p
    for p in "${BG_PIDS[@]:-}"; do
        kill "$p" 2>/dev/null || true
        wait "$p" 2>/dev/null || true
    done
    rm -rf "$TMP_ROOT"
}
trap cleanup_rofi_suite EXIT

TOTAL_TESTS=11
echo -e "${BLUE}${BOLD}:: [Test Suite] Rofi IME & Input Stability${NC}"
echo "1..${TOTAL_TESTS}"

TEST_INDEX=0
PASSED=0
FAILED=0
FAILED_LIST=()

assert_check() {
    local description="$1"
    local condition_cmd="$2"
    TEST_INDEX=$((TEST_INDEX + 1))

    if eval "$condition_cmd"; then
        echo "ok ${TEST_INDEX} - ${description}"
        PASSED=$((PASSED + 1))
    else
        echo "not ok ${TEST_INDEX} - ${description} # FAIL"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("${description}")
    fi
}

# ------------------------------------------------------------------------------
# Mock binaries (isolated real rofi & fcitx5-remote)
# ------------------------------------------------------------------------------
MOCK_BIN="$TMP_ROOT/bin"
mkdir -p "$MOCK_BIN"

cat <<'EOF' > "$MOCK_BIN/real-rofi"
#!/usr/bin/env bash
set -euo pipefail
echo "ROFI_START args=$*" >> "${MOCK_LOG:?}"
if [[ "${MOCK_READ_STDIN:-0}" == "1" ]]; then
    while IFS= read -r line; do
        echo "STDIN:${line}" >> "$MOCK_LOG"
    done
    printf '%s\n' "${MOCK_STDOUT:-selected_item}"
fi
if [[ -n "${MOCK_MARKER_FILE:-}" ]]; then
    printf '%s\n' "$$" > "$MOCK_MARKER_FILE"
fi
trap 'echo "ROFI_SIGTERM" >> "$MOCK_LOG"; exit 143' TERM
if [[ -n "${MOCK_HOLD_SEC:-}" && "${MOCK_HOLD_SEC}" != "0" ]]; then
    sleep "$MOCK_HOLD_SEC" &
    wait $! || exit $?
fi
echo "ROFI_END" >> "${MOCK_LOG}"
exit "${MOCK_EXIT:-0}"
EOF

cat <<'EOF' > "$MOCK_BIN/fcitx5-remote"
#!/usr/bin/env bash
set -euo pipefail
STATE_FILE="${MOCK_FCITX_STATE_FILE:?}"
LOG_FILE="${MOCK_LOG:?}"
if [[ "${MOCK_FCITX_DEAD:-0}" == "1" ]]; then
    exit 1
fi
case "${1:-}" in
    --check)
        echo "FCITX_CHECK" >> "$LOG_FILE"
        exit 0
        ;;
    -c)
        echo "FCITX_DEACTIVATE" >> "$LOG_FILE"
        printf '1\n' > "$STATE_FILE"
        exit 0
        ;;
    -o)
        echo "FCITX_ACTIVATE" >> "$LOG_FILE"
        printf '2\n' > "$STATE_FILE"
        exit 0
        ;;
    "")
        cat "$STATE_FILE"
        exit 0
        ;;
    *)
        echo "FCITX_OTHER:$*" >> "$LOG_FILE"
        exit 0
        ;;
esac
EOF

chmod +x "$MOCK_BIN/real-rofi" "$MOCK_BIN/fcitx5-remote"

# ------------------------------------------------------------------------------
# 1-4: Static & Config Validation
# ------------------------------------------------------------------------------
assert_check "bin/rofi exists, is executable, and passes bash -n syntax check" \
    "[ -f '$ROFI_WRAPPER' ] && [ -x '$ROFI_WRAPPER' ] && bash -n '$ROFI_WRAPPER'"

check_lua_rofi_config() {
    if command -v luac >/dev/null 2>&1; then
        luac -p "$HYPRLAND_LUA"
    fi
    grep -q 'local rofiMenu    = "pkill -x rofi || rofi -show drun' "$HYPRLAND_LUA"
    grep -q 'current_path:sub(1, #local_bin + 1)' "$HYPRLAND_LUA"
    grep -q 'bindCommand(mainMod .. " + D", rofiMenu, { release = true })' "$HYPRLAND_LUA"
    grep -q 'bindCommand(mainMod .. " + CTRL + S", "rofi -show window", { release = true })' "$HYPRLAND_LUA"
    grep -q 'hl.layer_rule({ match = { namespace = "rofi" }, blur = true, ignore_alpha = 0.5, no_anim = true })' "$HYPRLAND_LUA"
}

assert_check "hyprland.lua passes luac -p and configures release binds, PATH prefix check, and rofi no_anim" \
    "check_lua_rofi_config"

check_conf_files() {
    grep -qE '^binddr = \$mainMod, D, app launcher, exec, pkill -x rofi \|\| rofi ' "$KEYBINDS_CONF"
    grep -qE '^binddr = \$mainMod CTRL, S, window switcher, exec, rofi -show window' "$KEYBINDS_CONF"
    grep -qE '^binddr = \$mainMod, D, app launcher, exec, pkill -x rofi \|\| rofi ' "$LEGACY_KEYBINDS_CONF"
    grep -qE '^binddr = \$mainMod CTRL, S, window switcher, exec, rofi -show window' "$LEGACY_KEYBINDS_CONF"
    grep -q '^layerrule = match:namespace rofi, no_anim on' "$WINDOW_RULES"
    grep -q '^layerrule = match:namespace rofi, ignore_alpha 0.5' "$WINDOW_RULES"
    grep -q '^layerrule = match:namespace rofi, no_anim on' "$WINDOW_RULES_V3"
    ! grep -qE '^[[:space:]]*exec-once[[:space:]]*=[[:space:]]*fcitx5' "$STARTUP_APPS"
}

assert_check "keybinds.conf, Keybinds.conf, WindowRules*.conf, and Startup_Apps.conf match Rofi IME stability policy" \
    "check_conf_files"

check_parser_compat() {
    if ! command -v python3 >/dev/null 2>&1; then
        return 0
    fi
    python3 - "$PARSER_PY" "$HYPRLAND_LUA" "$KEYBINDS_CONF" <<'PY'
import importlib.util
import sys

parser_path, lua_path, conf_path = sys.argv[1:4]
spec = importlib.util.spec_from_file_location("kp", parser_path)
kp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kp)

lua_binds, _ = kp.parse_files([lua_path])
assert any("SUPER, D" in b and "exec, pkill -x rofi" in b for b in lua_binds), lua_binds[:5]
lua_fmt = kp.format_for_rofi(lua_binds)
assert any("SUPER+D" in item and "pkill -x rofi" in item for item in lua_fmt), lua_fmt[:5]

conf_binds, _ = kp.parse_files([conf_path])
conf_fmt = kp.format_for_rofi(conf_binds)
assert any("SUPER+D" in item and "app launcher" in item for item in conf_fmt), conf_fmt[:5]
PY
}

assert_check "keybinds_parser.py parses updated hyprland.lua and keybinds.conf cleanly including SUPER+D" \
    "check_parser_compat"

# ------------------------------------------------------------------------------
# 5: CLI introspection passthrough
# ------------------------------------------------------------------------------
test_passthrough() {
    local d="$TMP_ROOT/t5"
    mkdir -p "$d"
    : > "$d/log"
    printf '2\n' > "$d/fcitx_state"

    ROFI_REAL_BIN="$MOCK_BIN/real-rofi" \
    FCITX5_REMOTE_BIN="$MOCK_BIN/fcitx5-remote" \
    MOCK_LOG="$d/log" \
    MOCK_FCITX_STATE_FILE="$d/fcitx_state" \
    ROFI_IM_STATE_DIR="$d/state" \
        "$ROFI_WRAPPER" -dump-config >/dev/null

    ROFI_REAL_BIN="$MOCK_BIN/real-rofi" \
    FCITX5_REMOTE_BIN="$MOCK_BIN/fcitx5-remote" \
    MOCK_LOG="$d/log" \
    MOCK_FCITX_STATE_FILE="$d/fcitx_state" \
    ROFI_IM_STATE_DIR="$d/state" \
        "$ROFI_WRAPPER" -V >/dev/null

    ! grep -q 'FCITX_' "$d/log" && grep -q 'ROFI_START args=-dump-config' "$d/log" && grep -q 'ROFI_START args=-V' "$d/log"
}

assert_check "CLI introspection flags (-dump-config, -V) pass through directly without querying fcitx5-remote" \
    "test_passthrough"

# ------------------------------------------------------------------------------
# 6: Active (2) -> Deactivate (-c) before Rofi, Restore (-o) after Rofi
# ------------------------------------------------------------------------------
test_active_cycle() {
    local d="$TMP_ROOT/t6"
    mkdir -p "$d"
    : > "$d/log"
    printf '2\n' > "$d/fcitx_state"

    ROFI_REAL_BIN="$MOCK_BIN/real-rofi" \
    FCITX5_REMOTE_BIN="$MOCK_BIN/fcitx5-remote" \
    MOCK_LOG="$d/log" \
    MOCK_FCITX_STATE_FILE="$d/fcitx_state" \
    ROFI_IM_STATE_DIR="$d/state" \
    ROFI_IM_RESTORE_DELAY="0.01" \
        "$ROFI_WRAPPER" -show drun >/dev/null

    local expected=$'FCITX_CHECK\nFCITX_DEACTIVATE\nROFI_START args=-show drun\nROFI_END\nFCITX_ACTIVATE'
    [ "$(cat "$d/log")" = "$expected" ] && [ "$(cat "$d/fcitx_state")" = "2" ]
}

assert_check "Active Fcitx5 (2) is deactivated before launching rofi and restored after exit" \
    "test_active_cycle"

# ------------------------------------------------------------------------------
# 7: Inactive (1), Close (0), Dead daemon & exit codes (1, 10)
# ------------------------------------------------------------------------------
test_inactive_and_exit_codes() {
    local d="$TMP_ROOT/t7"
    mkdir -p "$d"
    : > "$d/log"

    printf '1\n' > "$d/fcitx_state"
    set +e
    ROFI_REAL_BIN="$MOCK_BIN/real-rofi" \
    FCITX5_REMOTE_BIN="$MOCK_BIN/fcitx5-remote" \
    MOCK_LOG="$d/log" \
    MOCK_FCITX_STATE_FILE="$d/fcitx_state" \
    MOCK_EXIT=10 \
    ROFI_IM_STATE_DIR="$d/state" \
        "$ROFI_WRAPPER" -dmenu >/dev/null
    local rc10=$?
    set -e

    printf '0\n' > "$d/fcitx_state"
    set +e
    ROFI_REAL_BIN="$MOCK_BIN/real-rofi" \
    FCITX5_REMOTE_BIN="$MOCK_BIN/fcitx5-remote" \
    MOCK_LOG="$d/log" \
    MOCK_FCITX_STATE_FILE="$d/fcitx_state" \
    MOCK_EXIT=1 \
    ROFI_IM_STATE_DIR="$d/state" \
        "$ROFI_WRAPPER" -dmenu >/dev/null
    local rc1=$?
    set -e

    set +e
    ROFI_REAL_BIN="$MOCK_BIN/real-rofi" \
    FCITX5_REMOTE_BIN="$MOCK_BIN/fcitx5-remote" \
    MOCK_LOG="$d/log" \
    MOCK_FCITX_STATE_FILE="$d/fcitx_state" \
    MOCK_FCITX_DEAD=1 \
    MOCK_EXIT=1 \
    ROFI_IM_STATE_DIR="$d/state" \
        "$ROFI_WRAPPER" -dmenu >/dev/null
    local rc_dead=$?
    set -e

    [ "$rc10" -eq 10 ] && [ "$rc1" -eq 1 ] && [ "$rc_dead" -eq 1 ] && \
    ! grep -qE 'FCITX_(ACTIVATE|DEACTIVATE)' "$d/log"
}

assert_check "Inactive (1), Close (0), and dead fcitx5 do not toggle IME state and preserve exit codes (1, 10)" \
    "test_inactive_and_exit_codes"

# ------------------------------------------------------------------------------
# 8: dmenu pipe stdin/stdout integrity
# ------------------------------------------------------------------------------
test_dmenu_pipe() {
    local d="$TMP_ROOT/t8"
    mkdir -p "$d"
    : > "$d/log"
    printf '2\n' > "$d/fcitx_state"

    local out
    out="$(printf 'alpha\nbeta\ngamma\n' | \
        ROFI_REAL_BIN="$MOCK_BIN/real-rofi" \
        FCITX5_REMOTE_BIN="$MOCK_BIN/fcitx5-remote" \
        MOCK_LOG="$d/log" \
        MOCK_FCITX_STATE_FILE="$d/fcitx_state" \
        MOCK_READ_STDIN=1 \
        MOCK_STDOUT="beta" \
        ROFI_IM_STATE_DIR="$d/state" \
        ROFI_IM_RESTORE_DELAY="0.01" \
        "$ROFI_WRAPPER" -dmenu -i)"

    [ "$out" = "beta" ] && \
    grep -q 'STDIN:alpha' "$d/log" && \
    grep -q 'STDIN:beta' "$d/log" && \
    grep -q 'STDIN:gamma' "$d/log" && \
    grep -q 'FCITX_ACTIVATE' "$d/log"
}

assert_check "dmenu pipeline preserves full stdin rows and stdout selection verbatim" \
    "test_dmenu_pipe"

# ------------------------------------------------------------------------------
# 9: SIGTERM toggle forwards to child and restores IME once
# ------------------------------------------------------------------------------
test_sigterm_toggle() {
    local d="$TMP_ROOT/t9"
    mkdir -p "$d"
    : > "$d/log"
    printf '2\n' > "$d/fcitx_state"

    ROFI_REAL_BIN="$MOCK_BIN/real-rofi" \
    FCITX5_REMOTE_BIN="$MOCK_BIN/fcitx5-remote" \
    MOCK_LOG="$d/log" \
    MOCK_FCITX_STATE_FILE="$d/fcitx_state" \
    MOCK_HOLD_SEC=5 \
    MOCK_MARKER_FILE="$d/child.pid" \
    ROFI_IM_STATE_DIR="$d/state" \
    ROFI_IM_RESTORE_DELAY="0.01" \
        "$ROFI_WRAPPER" -show drun >/dev/null &
    local wrap_pid=$!
    BG_PIDS+=("$wrap_pid")

    local i
    for ((i = 0; i < 40; i++)); do
        [[ -s "$d/child.pid" ]] && break
        sleep 0.02
    done
    [[ -s "$d/child.pid" ]] || return 1

    kill -TERM "$wrap_pid"
    local rc=0
    wait "$wrap_pid" || rc=$?

    [ "$rc" -eq 143 ] && \
    grep -q 'ROFI_SIGTERM' "$d/log" && \
    [ "$(grep -c 'FCITX_ACTIVATE' "$d/log")" -eq 1 ] && \
    [ "$(cat "$d/fcitx_state")" = "2" ]
}

assert_check "SIGTERM toggle forwards kill to child rofi and restores Fcitx5 Active (2) cleanly" \
    "test_sigterm_toggle"

# ------------------------------------------------------------------------------
# 10: Concurrent/failed second rofi does not restore early while primary is open
# ------------------------------------------------------------------------------
test_concurrent_no_early_restore() {
    local d="$TMP_ROOT/t10"
    mkdir -p "$d"
    : > "$d/log"
    printf '2\n' > "$d/fcitx_state"

    ROFI_REAL_BIN="$MOCK_BIN/real-rofi" \
    FCITX5_REMOTE_BIN="$MOCK_BIN/fcitx5-remote" \
    MOCK_LOG="$d/log" \
    MOCK_FCITX_STATE_FILE="$d/fcitx_state" \
    MOCK_HOLD_SEC=0.30 \
    MOCK_MARKER_FILE="$d/primary.pid" \
    ROFI_IM_STATE_DIR="$d/state" \
    ROFI_IM_RESTORE_DELAY="0.01" \
        "$ROFI_WRAPPER" -show drun >/dev/null &
    local p1=$!
    BG_PIDS+=("$p1")

    local i
    for ((i = 0; i < 40; i++)); do
        [[ -s "$d/primary.pid" ]] && break
        sleep 0.01
    done
    [[ -s "$d/primary.pid" ]] || return 1

    set +e
    ROFI_REAL_BIN="$MOCK_BIN/real-rofi" \
    FCITX5_REMOTE_BIN="$MOCK_BIN/fcitx5-remote" \
    MOCK_LOG="$d/log" \
    MOCK_FCITX_STATE_FILE="$d/fcitx_state" \
    MOCK_HOLD_SEC=0 \
    MOCK_EXIT=1 \
    ROFI_IM_STATE_DIR="$d/state" \
    ROFI_IM_RESTORE_DELAY="0.01" \
        "$ROFI_WRAPPER" -show drun >/dev/null
    local p2_rc=$?
    set -e

    # Primary is still alive right after p2 exited: state must still be Inactive (1)
    local mid_state mid_activations
    mid_state="$(cat "$d/fcitx_state")"
    mid_activations="$(grep -c 'FCITX_ACTIVATE' "$d/log" || true)"

    wait "$p1"

    [ "$p2_rc" -eq 1 ] && \
    [ "$mid_state" = "1" ] && \
    [ "$mid_activations" -eq 0 ] && \
    [ "$(grep -c 'FCITX_ACTIVATE' "$d/log")" -eq 1 ] && \
    [ "$(cat "$d/fcitx_state")" = "2" ]
}

assert_check "Concurrent failed second rofi leaves IM inactive while primary stays open and restores once at final exit" \
    "test_concurrent_no_early_restore"

# ------------------------------------------------------------------------------
# 11: Replacement relaunch inside post-exit restore grace delay inherits SAVED_ACTIVE
# ------------------------------------------------------------------------------
test_grace_window_handoff() {
    local d="$TMP_ROOT/t11"
    mkdir -p "$d"
    : > "$d/log"
    printf '2\n' > "$d/fcitx_state"

    ROFI_REAL_BIN="$MOCK_BIN/real-rofi" \
    FCITX5_REMOTE_BIN="$MOCK_BIN/fcitx5-remote" \
    MOCK_LOG="$d/log" \
    MOCK_FCITX_STATE_FILE="$d/fcitx_state" \
    MOCK_HOLD_SEC=0.02 \
    ROFI_IM_STATE_DIR="$d/state" \
    ROFI_IM_RESTORE_DELAY="0.25" \
        "$ROFI_WRAPPER" -show drun >/dev/null &
    local p1=$!
    BG_PIDS+=("$p1")

    # Wait until p1's ROFI_END is logged (so p1 is inside its 0.25s restore grace delay)
    local i
    for ((i = 0; i < 40; i++)); do
        grep -q 'ROFI_END' "$d/log" && break
        sleep 0.01
    done
    grep -q 'ROFI_END' "$d/log" || return 1

    # Launch replacement rofi while live fcitx5 state is temporarily 1
    ROFI_REAL_BIN="$MOCK_BIN/real-rofi" \
    FCITX5_REMOTE_BIN="$MOCK_BIN/fcitx5-remote" \
    MOCK_LOG="$d/log" \
    MOCK_FCITX_STATE_FILE="$d/fcitx_state" \
    MOCK_HOLD_SEC=0.35 \
    ROFI_IM_STATE_DIR="$d/state" \
    ROFI_IM_RESTORE_DELAY="0.02" \
        "$ROFI_WRAPPER" -dmenu >/dev/null

    wait "$p1"

    [ "$(grep -c 'FCITX_ACTIVATE' "$d/log")" -eq 1 ] && \
    [ "$(cat "$d/fcitx_state")" = "2" ] && \
    tail -n 1 "$d/log" | grep -q '^FCITX_ACTIVATE$'
}

assert_check "Replacement rofi during restore grace delay inherits active IM state and restores once at end" \
    "test_grace_window_handoff"

echo ""
echo -e "${BOLD}Summary: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC} (total ${TOTAL_TESTS})"
if [[ $FAILED -gt 0 ]]; then
    printf 'Failed checks:\n'
    printf ' - %s\n' "${FAILED_LIST[@]}"
    exit 1
fi
exit 0
