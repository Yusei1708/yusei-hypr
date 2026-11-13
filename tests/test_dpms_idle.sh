#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: DPMS, Idle, Lock & Sleep-Wake Regression Test Suite
# ==============================================================================
# - Verifies DpmsControl.sh and LockScreen.sh exist, are executable, pass bash -n
# - Verifies hypridle.conf does not use bare toggle syntax hl.dsp.dpms('on'/'off')
# - Verifies hyprland.lua disables fadeDpms and fixes Lua disabled animation pattern
# - Verifies no-grace lock policy (--grace absent, inhibit_sleep = 3, $PAMFAIL,
#   pre-sleep --lock-and-wait wiring in wlogout/hyprland.lua/keybinds/waybar)
# - Tests idempotent DPMS on/off, Lua table syntax, legacy fallback, dim/restore,
#   post-suspend wake recovery, and LockScreen.sh fallback/wait behavior via
#   isolated mock binaries
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

DPMS_SCRIPT="$REPO_ROOT/config/hypr/scripts/DpmsControl.sh"
LOCK_SCRIPT="$REPO_ROOT/config/hypr/scripts/LockScreen.sh"
HYPRIDLE_CONF="$REPO_ROOT/config/hypr/hypridle.conf"
HYPRLOCK_CONF="$REPO_ROOT/config/hypr/hyprlock.conf"
HYPRLAND_LUA="$REPO_ROOT/config/hypr/hyprland.lua"
KEYBINDS_CONF="$REPO_ROOT/config/hypr/keybinds.conf"
WLOGOUT_LAYOUT="$REPO_ROOT/config/wlogout/layout"
WAYBAR_CUSTOM="$REPO_ROOT/config/waybar/ModulesCustom"

TMP_ROOT="$(mktemp -d -t yusei_dpms_test_XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

TOTAL_TESTS=25
echo -e "${BLUE}${BOLD}:: [Test Suite] DPMS & Idle/Wake Stability${NC}"
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

# 1. Static checks
assert_check "DpmsControl.sh exists and is executable" \
    "[ -f '$DPMS_SCRIPT' ] && [ -x '$DPMS_SCRIPT' ]"

assert_check "DpmsControl.sh passes bash -n syntax check" \
    "bash -n '$DPMS_SCRIPT'"

assert_check "hypridle.conf has zero bare toggle hl.dsp.dpms('on'/'off') calls" \
    "! grep -qE \"hl\\.dsp\\.dpms\\('(on|off)'\\)\" '$HYPRIDLE_CONF'"

assert_check "hypridle.conf wires sleep/wake/dim/dpms to DpmsControl.sh" \
    "grep -q 'DpmsControl.sh.*--wake' '$HYPRIDLE_CONF' && \
     grep -q 'DpmsControl.sh.*--dim' '$HYPRIDLE_CONF' && \
     grep -q 'DpmsControl.sh.*--restore-brightness' '$HYPRIDLE_CONF' && \
     grep -q 'DpmsControl.sh.*--off' '$HYPRIDLE_CONF' && \
     grep -q 'DpmsControl.sh.*--on' '$HYPRIDLE_CONF'"

assert_check "hyprland.lua disables fadeDpms and uses valid Lua disabled animation match" \
    "grep -qE 'leaf\\s*=\\s*\"fadeDpms\".*enabled\\s*=\\s*false' '$HYPRLAND_LUA' && \
     ! grep -q '(0|false|no|off)' '$HYPRLAND_LUA'"

# 2. Setup isolated mock binaries (hyprctl + brightnessctl)
MOCK_BIN="$TMP_ROOT/bin"
MOCK_STATE="$TMP_ROOT/state"
mkdir -p "$MOCK_BIN" "$MOCK_STATE"

cat <<'EOF' > "$MOCK_BIN/hyprctl"
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${MOCK_STATE_DIR:?}"
LOG_FILE="$STATE_DIR/hyprctl.log"
MODE="${MOCK_HYPR_MODE:-lua}"
DPMS_STATE_FILE="$STATE_DIR/dpms_state"

cmd="${1:-}"
shift || true

if [[ "$cmd" == "monitors" ]]; then
    cur="$(cat "$DPMS_STATE_FILE" 2>/dev/null || echo true)"
    cat <<JSON
[{"id":0,"name":"eDP-1","disabled":false,"dpmsStatus":${cur}}]
JSON
    exit 0
fi

if [[ "$cmd" == "dispatch" ]]; then
    arg="${1:-}"
    echo "dispatch:${arg}" >> "$LOG_FILE"
    if [[ "$arg" == hl.dsp.* ]]; then
        if [[ "$MODE" == "legacy" ]]; then
            echo "Invalid dispatcher"
            exit 7
        fi
        if [[ "$arg" == *'action = "on"'* ]]; then
            echo "true" > "$DPMS_STATE_FILE"
        elif [[ "$arg" == *'action = "off"'* ]]; then
            echo "false" > "$DPMS_STATE_FILE"
        fi
        echo "ok"
        exit 0
    fi
    if [[ "$arg" == "dpms" ]]; then
        sub="${2:-}"
        echo "dispatch_legacy:dpms ${sub}" >> "$LOG_FILE"
        if [[ "$sub" == "on" ]]; then
            echo "true" > "$DPMS_STATE_FILE"
        elif [[ "$sub" == "off" ]]; then
            echo "false" > "$DPMS_STATE_FILE"
        fi
        echo "ok"
        exit 0
    fi
fi
exit 0
EOF
chmod +x "$MOCK_BIN/hyprctl"

cat <<'EOF' > "$MOCK_BIN/brightnessctl"
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${MOCK_STATE_DIR:?}"
LOG_FILE="$STATE_DIR/brightnessctl.log"
PCT_FILE="$STATE_DIR/pct"
SAVED_FILE="$STATE_DIR/saved_pct"

echo "bctl:$*" >> "$LOG_FILE"
cur="$(cat "$PCT_FILE" 2>/dev/null || echo 65)"
padded=" $* "

if [[ "$padded" == *" -l "* ]]; then
    echo "intel_backlight,backlight,62400,${cur}%,96000"
    exit 0
fi

if [[ "$padded" == *" -s "* && "$padded" == *" set "* ]]; then
    echo "$cur" > "$SAVED_FILE"
    target="${@: -1}"
    echo "${target%\%}" > "$PCT_FILE"
    exit 0
fi

if [[ "$padded" == *" -r "* ]]; then
    if [[ -f "$SAVED_FILE" ]]; then
        cp -f "$SAVED_FILE" "$PCT_FILE"
    fi
    exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN/brightnessctl"

export MOCK_STATE_DIR="$MOCK_STATE"
export YUSEI_DIM_FLAG_FILE="$TMP_ROOT/dim_flag"
export YUSEI_WAKE_SETTLE_DELAY=0
ORIG_PATH="$PATH"
export PATH="$MOCK_BIN:$PATH"

reset_logs() {
    : > "$MOCK_STATE/hyprctl.log"
    : > "$MOCK_STATE/brightnessctl.log"
}

# Test 6: --on when OFF uses Lua table syntax
echo "false" > "$MOCK_STATE/dpms_state"
export MOCK_HYPR_MODE="lua"
reset_logs
"$DPMS_SCRIPT" --on
assert_check "--on turns display ON using Lua table hl.dsp.dpms({action = \"on\"})" \
    "grep -q 'hl.dsp.dpms({action = \"on\"})' '$MOCK_STATE/hyprctl.log' && [ \"\$(cat '$MOCK_STATE/dpms_state')\" = 'true' ]"

# Test 7: --on when ALREADY ON is a safe no-op
echo "true" > "$MOCK_STATE/dpms_state"
reset_logs
"$DPMS_SCRIPT" --on
assert_check "--on is idempotent no-op when all displays already ON" \
    "[ ! -s '$MOCK_STATE/hyprctl.log' ]"

# Test 8: --off when ALREADY OFF is a safe no-op
echo "false" > "$MOCK_STATE/dpms_state"
reset_logs
"$DPMS_SCRIPT" --off
assert_check "--off is idempotent no-op when all displays already OFF" \
    "[ ! -s '$MOCK_STATE/hyprctl.log' ]"

# Test 9: --off when ON turns OFF via Lua table syntax
echo "true" > "$MOCK_STATE/dpms_state"
reset_logs
"$DPMS_SCRIPT" --off
assert_check "--off turns display OFF using Lua table hl.dsp.dpms({action = \"off\"})" \
    "grep -q 'hl.dsp.dpms({action = \"off\"})' '$MOCK_STATE/hyprctl.log' && [ \"\$(cat '$MOCK_STATE/dpms_state')\" = 'false' ]"

# Test 10: legacy fallback when hl.dsp returns error
echo "false" > "$MOCK_STATE/dpms_state"
export MOCK_HYPR_MODE="legacy"
reset_logs
"$DPMS_SCRIPT" --on
assert_check "--on falls back to legacy 'hyprctl dispatch dpms on' when Lua API unavailable" \
    "grep -q 'dispatch_legacy:dpms on' '$MOCK_STATE/hyprctl.log' && [ \"\$(cat '$MOCK_STATE/dpms_state')\" = 'true' ]"

# Test 11: --dim / --restore-brightness guard against double save & low brightness
echo "65" > "$MOCK_STATE/pct"
rm -f "$YUSEI_DIM_FLAG_FILE" "$MOCK_STATE/saved_pct"
reset_logs
"$DPMS_SCRIPT" --dim
"$DPMS_SCRIPT" --dim
pct_after_dim="$(cat "$MOCK_STATE/pct")"
saved_pct="$(cat "$MOCK_STATE/saved_pct")"
set_calls="$(grep -c ' set ' "$MOCK_STATE/brightnessctl.log" || true)"
"$DPMS_SCRIPT" --restore-brightness
"$DPMS_SCRIPT" --restore-brightness
pct_after_restore="$(cat "$MOCK_STATE/pct")"
restore_calls="$(grep -c -- ' -r' "$MOCK_STATE/brightnessctl.log" || true)"

# Test low manual brightness is never raised to 10%
echo "8" > "$MOCK_STATE/pct"
"$DPMS_SCRIPT" --dim
pct_low_kept="$(cat "$MOCK_STATE/pct")"

assert_check "--dim saves once without overwriting saved brightness and --restore-brightness restores cleanly" \
    "[ '$pct_after_dim' = '10' ] && [ '$saved_pct' = '65' ] && [ '$set_calls' = '1' ] && [ '$pct_after_restore' = '65' ] && [ '$restore_calls' = '1' ] && [ '$pct_low_kept' = '8' ]"

# Test 12: --wake enables DPMS and restores brightness after sleep
export MOCK_HYPR_MODE="lua"
echo "65" > "$MOCK_STATE/pct"
rm -f "$YUSEI_DIM_FLAG_FILE"
"$DPMS_SCRIPT" --dim
echo "false" > "$MOCK_STATE/dpms_state"
reset_logs
"$DPMS_SCRIPT" --wake
assert_check "--wake restores DPMS ON and restores backlight brightness after suspend" \
    "[ \"\$(cat '$MOCK_STATE/dpms_state')\" = 'true' ] && [ \"\$(cat '$MOCK_STATE/pct')\" = '65' ] && [ ! -f '$YUSEI_DIM_FLAG_FILE' ]"

# ------------------------------------------------------------------------------
# 3. No-Grace Lock Policy & LockScreen.sh Static + Mocked Runtime Checks
# ------------------------------------------------------------------------------
check_lock_static_no_grace() {
    ! grep -q -- '--grace' "$HYPRIDLE_CONF" && ! grep -q -- '--grace' "$LOCK_SCRIPT"
}

check_hypridle_lock_policy() {
    grep -qE '^[[:space:]]*inhibit_sleep[[:space:]]*=[[:space:]]*3[[:space:]]*$' "$HYPRIDLE_CONF" && \
    grep -qE '^[[:space:]]*lock_cmd[[:space:]]*=[[:space:]]*pidof hyprlock \|\| hyprlock -q[[:space:]]*$' "$HYPRIDLE_CONF"
}

check_hyprlock_pamfail() {
    grep -qE '^[[:space:]]*fail_text[[:space:]]*=.*\$PAMFAIL' "$HYPRLOCK_CONF"
}

check_pre_sleep_lock_wiring() {
    jq -se '
        (.[] | select(.label=="suspend") | .action | test("LockScreen\\.sh.*--lock-and-wait\\s*&&\\s*systemctl suspend")) and
        (.[] | select(.label=="hibernate") | .action | test("LockScreen\\.sh.*--lock-and-wait\\s*&&\\s*systemctl hibernate"))
    ' "$WLOGOUT_LAYOUT" >/dev/null && \
    grep -qE 'hl\.bind\("XF86Sleep".*LockScreen\.sh --lock-and-wait && systemctl suspend' "$HYPRLAND_LUA" && \
    grep -qE 'XF86Sleep.*LockScreen\.sh --lock-and-wait && systemctl suspend' "$KEYBINDS_CONF"
}

check_waybar_hypridle_right_click() {
    grep -A10 '"custom/hypridle"' "$WAYBAR_CUSTOM" | grep -qE '"on-click-right"[[:space:]]*:[[:space:]]*".*LockScreen\.sh"'
}

assert_check "LockScreen.sh exists, is executable, and passes bash -n syntax check" \
    "[ -f '$LOCK_SCRIPT' ] && [ -x '$LOCK_SCRIPT' ] && bash -n '$LOCK_SCRIPT'"

assert_check "hypridle.conf and LockScreen.sh contain zero --grace flags" \
    "check_lock_static_no_grace"

assert_check "hypridle.conf enforces inhibit_sleep = 3 and lock_cmd = pidof hyprlock || hyprlock -q" \
    "check_hypridle_lock_policy"

assert_check "hyprlock.conf exposes \$PAMFAIL in fail_text" \
    "check_hyprlock_pamfail"

assert_check "wlogout suspend/hibernate, hyprland.lua XF86Sleep, and keybinds.conf XF86Sleep invoke LockScreen.sh --lock-and-wait before sleep" \
    "check_pre_sleep_lock_wiring"

assert_check "waybar/ModulesCustom custom/hypridle on-click-right invokes LockScreen.sh" \
    "check_waybar_hypridle_right_click"

# Setup isolated mocks for pgrep, pidof, loginctl, hyprlock, plus isolated HOME
cat <<'EOF' > "$MOCK_BIN/pidof"
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${MOCK_STATE_DIR:?}"
target="${1:-}"
if [[ "$target" == "hyprlock" && -f "$STATE_DIR/hyprlock_running" ]]; then
    echo "4242"
    exit 0
fi
exit 1
EOF
chmod +x "$MOCK_BIN/pidof"

cat <<'EOF' > "$MOCK_BIN/pgrep"
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${MOCK_STATE_DIR:?}"
echo "pgrep:$*" >> "$STATE_DIR/pgrep.log"
if [[ "${MOCK_HYPRIDLE_ACTIVE:-0}" == "1" ]]; then
    echo "9999"
    exit 0
fi
exit 1
EOF
chmod +x "$MOCK_BIN/pgrep"

cat <<'EOF' > "$MOCK_BIN/loginctl"
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${MOCK_STATE_DIR:?}"
echo "loginctl:$*" >> "$STATE_DIR/loginctl.log"
if [[ "$*" == *"lock-session"* && "${MOCK_LOGINCTL_SPAWNS_HYPRLOCK:-0}" == "1" ]]; then
    : > "$STATE_DIR/hyprlock_running"
fi
exit 0
EOF
chmod +x "$MOCK_BIN/loginctl"

cat <<'EOF' > "$MOCK_BIN/hyprlock"
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${MOCK_STATE_DIR:?}"
if [[ "${MOCK_HYPRLOCK_SLEEP:-0}" != "0" ]]; then
    sleep "${MOCK_HYPRLOCK_SLEEP}"
fi
if [[ "${MOCK_HYPRLOCK_FAIL:-0}" == "1" ]]; then
    echo "hyprlock:$*" >> "$STATE_DIR/hyprlock.log"
    exit 1
fi
: > "$STATE_DIR/hyprlock_running"
echo "hyprlock:$*" >> "$STATE_DIR/hyprlock.log"
exit 0
EOF
chmod +x "$MOCK_BIN/hyprlock"

ORIG_HOME="$HOME"
FAKE_HOME="$TMP_ROOT/fake_home"
mkdir -p "$FAKE_HOME"
export HOME="$FAKE_HOME"
export YUSEI_LOCK_SETTLE_DELAY=0

reset_lock_state() {
    rm -f "$MOCK_STATE/hyprlock_running" \
          "$MOCK_STATE/suspend_allowed" \
          "$MOCK_STATE/suspend_blocked" \
          "$MOCK_STATE/lock_err.log"
    : > "$MOCK_STATE/pgrep.log"
    : > "$MOCK_STATE/loginctl.log"
    : > "$MOCK_STATE/hyprlock.log"
}

wait_for_file_content() {
    local file="$1"
    local pattern="$2"
    local attempts=40
    local i=0
    while (( i < attempts )); do
        if [[ -f "$file" ]] && grep -qE -- "$pattern" "$file" 2>/dev/null; then
            return 0
        fi
        sleep 0.05
        i=$((i + 1))
    done
    return 1
}

# Test 19: Dead hypridle + loginctl returning 0 -> directly launches hyprlock -q
reset_lock_state
MOCK_HYPRIDLE_ACTIVE=0 MOCK_LOGINCTL_SPAWNS_HYPRLOCK=0 MOCK_HYPRLOCK_FAIL=0 MOCK_HYPRLOCK_SLEEP=0 \
    "$LOCK_SCRIPT"
assert_check "LockScreen.sh launches hyprlock -q directly when hypridle is dead" \
    "wait_for_file_content '$MOCK_STATE/hyprlock.log' '^hyprlock:-q$' && [ ! -s '$MOCK_STATE/loginctl.log' ]"

# Test 20: Active hypridle + loginctl lock-session spawns hyprlock -> calls loginctl, no duplicate hyprlock
reset_lock_state
MOCK_HYPRIDLE_ACTIVE=1 MOCK_LOGINCTL_SPAWNS_HYPRLOCK=1 MOCK_HYPRLOCK_FAIL=0 MOCK_HYPRLOCK_SLEEP=0 \
    "$LOCK_SCRIPT"
sleep 0.1
assert_check "LockScreen.sh calls loginctl lock-session without duplicate hyprlock when hypridle spawns hyprlock" \
    "grep -q '^loginctl:lock-session$' '$MOCK_STATE/loginctl.log' && [ ! -s '$MOCK_STATE/hyprlock.log' ]"

# Test 21: Active hypridle + loginctl lock-session exits 0 silently without spawning hyprlock -> falls back to hyprlock -q
reset_lock_state
MOCK_HYPRIDLE_ACTIVE=1 MOCK_LOGINCTL_SPAWNS_HYPRLOCK=0 MOCK_HYPRLOCK_FAIL=0 MOCK_HYPRLOCK_SLEEP=0 \
    "$LOCK_SCRIPT"
assert_check "LockScreen.sh falls back to hyprlock -q when loginctl lock-session exits 0 without spawning hyprlock" \
    "grep -q '^loginctl:lock-session$' '$MOCK_STATE/loginctl.log' && wait_for_file_content '$MOCK_STATE/hyprlock.log' '^hyprlock:-q$'"

# Test 22: Already locked (pidof hyprlock exits 0) -> no-op
reset_lock_state
: > "$MOCK_STATE/hyprlock_running"
MOCK_HYPRIDLE_ACTIVE=1 MOCK_LOGINCTL_SPAWNS_HYPRLOCK=1 MOCK_HYPRLOCK_FAIL=0 MOCK_HYPRLOCK_SLEEP=0 \
    "$LOCK_SCRIPT"
sleep 0.1
assert_check "LockScreen.sh is a safe no-op when hyprlock is already running" \
    "[ ! -s '$MOCK_STATE/loginctl.log' ] && [ ! -s '$MOCK_STATE/hyprlock.log' ]"

# Test 23: --lock-and-wait succeeds (exit 0) once hyprlock appears via pidof
reset_lock_state
set +e
MOCK_HYPRIDLE_ACTIVE=0 MOCK_LOGINCTL_SPAWNS_HYPRLOCK=0 MOCK_HYPRLOCK_FAIL=0 MOCK_HYPRLOCK_SLEEP=0.15 \
    "$LOCK_SCRIPT" --lock-and-wait && : > "$MOCK_STATE/suspend_allowed"
rc_wait_ok=$?
set -e
assert_check "LockScreen.sh --lock-and-wait exits 0 once hyprlock appears via pidof" \
    "[ '$rc_wait_ok' -eq 0 ] && [ -f '$MOCK_STATE/suspend_allowed' ] && wait_for_file_content '$MOCK_STATE/hyprlock.log' '^hyprlock:-q$'"

# Test 24: --lock-and-wait fails non-zero (exit 1) if hyprlock never starts
reset_lock_state
set +e
MOCK_HYPRIDLE_ACTIVE=0 MOCK_LOGINCTL_SPAWNS_HYPRLOCK=0 MOCK_HYPRLOCK_FAIL=1 MOCK_HYPRLOCK_SLEEP=0 \
    "$LOCK_SCRIPT" --lock-and-wait 2>"$MOCK_STATE/lock_err.log" && : > "$MOCK_STATE/suspend_blocked"
rc_wait_fail=$?
set -e
assert_check "LockScreen.sh --lock-and-wait exits 1 when hyprlock never starts so chained suspend cannot run unlocked" \
    "[ '$rc_wait_fail' -eq 1 ] && [ ! -f '$MOCK_STATE/suspend_blocked' ] && grep -q 'refusing to unlock-bypass wait' '$MOCK_STATE/lock_err.log'"

# Test 25: -h/--help exits 0; unknown flag exits 2
reset_lock_state
check_lock_cli_flags() {
    local help_short_rc=0 help_long_rc=0 bad_rc=0
    local out_short="" out_long="" err_bad=""
    out_short="$("$LOCK_SCRIPT" -h)" || help_short_rc=$?
    out_long="$("$LOCK_SCRIPT" --help)" || help_long_rc=$?
    set +e
    err_bad="$("$LOCK_SCRIPT" --unknown-flag 2>&1 >/dev/null)"
    bad_rc=$?
    set -e
    [ "$help_short_rc" -eq 0 ] && [ "$help_long_rc" -eq 0 ] && [ "$bad_rc" -eq 2 ] && \
    grep -q -- '--lock-and-wait' <<< "$out_short" && \
    grep -q -- '--lock-and-wait' <<< "$out_long" && \
    grep -q 'Unknown option: --unknown-flag' <<< "$err_bad" && \
    [ ! -s "$MOCK_STATE/loginctl.log" ] && [ ! -s "$MOCK_STATE/hyprlock.log" ]
}
assert_check "LockScreen.sh -h/--help exits 0 and unknown flag exits 2" \
    "check_lock_cli_flags"

export HOME="$ORIG_HOME"
export PATH="$ORIG_PATH"

echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}DPMS & Idle/Wake Test Summary${NC}"
echo -e "${BOLD}======================================================${NC}"
echo -e "Total Checks: ${TOTAL_TESTS}"
echo -e "Passed:       ${GREEN}${PASSED}${NC}"
if [[ $FAILED -gt 0 ]]; then
    echo -e "Failed:       ${RED}${FAILED}${NC}"
    for item in "${FAILED_LIST[@]}"; do
        echo -e "  - ${RED}${item}${NC}"
    done
    echo -e "${BOLD}======================================================${NC}"
    exit 1
else
    echo -e "Failed:       0"
    echo -e "${GREEN}${BOLD}Status: ALL DPMS & IDLE CHECKS PASSED${NC}"
    echo -e "${BOLD}======================================================${NC}"
    exit 0
fi
