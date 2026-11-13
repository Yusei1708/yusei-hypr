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
DPMS_BG_PIDS=()
cleanup_dpms_suite() {
    local p
    for p in "${DPMS_BG_PIDS[@]:-}"; do
        kill "$p" 2>/dev/null || true
        wait "$p" 2>/dev/null || true
    done
    rm -rf "$TMP_ROOT"
}
trap cleanup_dpms_suite EXIT

TOTAL_TESTS=42
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

# ------------------------------------------------------------------------------
# 26. launch-daemons.sh Parity & Singleton / Symlink .current_wallpaper Restore
# ------------------------------------------------------------------------------
LAUNCH_MAIN="$REPO_ROOT/scripts/launch-daemons.sh"
LAUNCH_HYPR="$REPO_ROOT/config/hypr/scripts/launch-daemons.sh"

assert_check "scripts/launch-daemons.sh and config/hypr/scripts/launch-daemons.sh exist, pass bash -n, and match identically" \
    "[ -x '$LAUNCH_MAIN' ] && [ -x '$LAUNCH_HYPR' ] && bash -n '$LAUNCH_MAIN' && cmp -s '$LAUNCH_MAIN' '$LAUNCH_HYPR'"

LD_SANDBOX="$TMP_ROOT/launch_daemons"
LD_HOME="$LD_SANDBOX/home"
LD_MOCK_BIN="$LD_SANDBOX/mock_bin"
LD_LOGS="$LD_SANDBOX/logs"
mkdir -p "$LD_HOME/.config/hypr" "$LD_SANDBOX/walls" "$LD_MOCK_BIN" "$LD_LOGS"

# Write a binary PNG header + NUL byte so regression fails if script tries to cat binary bytes
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' > "$LD_SANDBOX/walls/custom-bin.png"
ln -sfn "$LD_SANDBOX/walls/custom-bin.png" "$LD_HOME/.config/hypr/.current_wallpaper"

cat <<'EOF' > "$LD_MOCK_BIN/killall"
#!/usr/bin/env bash
exit 0
EOF
cat <<'EOF' > "$LD_MOCK_BIN/pidof"
#!/usr/bin/env bash
if [[ "${1:-}" == "swww-daemon" && "${MOCK_SWWW_RUNNING:-0}" == "1" ]]; then
    exit 0
fi
if [[ "${1:-}" == "swww-daemon" ]]; then
    exit 1
fi
exit 0
EOF
cat <<'EOF' > "$LD_MOCK_BIN/swww-daemon"
#!/usr/bin/env bash
echo "swww-daemon:$*" >> "$LD_LOGS/swww_daemon.log"
exit 0
EOF
cat <<'EOF' > "$LD_MOCK_BIN/swww"
#!/usr/bin/env bash
echo "swww:$*" >> "$LD_LOGS/swww.log"
exit 0
EOF
for stub in waybar swaync hypridle; do
    cat <<EOF > "$LD_MOCK_BIN/$stub"
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$LD_MOCK_BIN/$stub"
done
chmod +x "$LD_MOCK_BIN/killall" "$LD_MOCK_BIN/pidof" "$LD_MOCK_BIN/swww-daemon" "$LD_MOCK_BIN/swww"

test_launch_daemons_singleton_and_symlink() {
    : > "$LD_LOGS/swww_daemon.log"
    : > "$LD_LOGS/swww.log"
    HOME="$LD_HOME" LD_LOGS="$LD_LOGS" MOCK_SWWW_RUNNING=0 PATH="$LD_MOCK_BIN:$ORIG_PATH" \
        bash "$LAUNCH_HYPR" >/dev/null 2>&1
    local first_daemon_calls first_img
    first_daemon_calls="$(wc -l < "$LD_LOGS/swww_daemon.log")"
    first_img="$(cat "$LD_LOGS/swww.log")"

    : > "$LD_LOGS/swww_daemon.log"
    : > "$LD_LOGS/swww.log"
    HOME="$LD_HOME" LD_LOGS="$LD_LOGS" MOCK_SWWW_RUNNING=1 PATH="$LD_MOCK_BIN:$ORIG_PATH" \
        bash "$LAUNCH_MAIN" >/dev/null 2>&1
    local second_daemon_calls
    second_daemon_calls="$(wc -l < "$LD_LOGS/swww_daemon.log")"

    [ "$first_daemon_calls" -eq 1 ] && \
    grep -q "swww:img $LD_SANDBOX/walls/custom-bin.png" <<< "$first_img" && \
    [ "$second_daemon_calls" -eq 0 ]
}
assert_check "launch-daemons.sh enforces singleton swww-daemon and resolves symlink .current_wallpaper via readlink -f" \
    "test_launch_daemons_singleton_and_symlink"

# ------------------------------------------------------------------------------
# 28-29. hyprland.lua Runtime Verification (monitors, video opacity precedence, UserDecorations/nvidia/userprefs, fadeDpms)
# ------------------------------------------------------------------------------
LUA_SANDBOX="$TMP_ROOT/lua_sandbox"
LUA_HOME="$LUA_SANDBOX/home"
mkdir -p "$LUA_HOME/.config/hypr/UserConfigs"

cat <<'EOF' > "$LUA_HOME/.config/hypr/hyprland.conf"
source = ~/.config/hypr/nvidia.conf
EOF
cat <<'EOF' > "$LUA_HOME/.config/hypr/monitors.conf"
monitor = , preferred, auto, 1
EOF
cat <<'EOF' > "$LUA_HOME/.config/hypr/nvidia.conf"
env = __NV_PRIME_RENDER_OFFLOAD,1
EOF
cat <<'EOF' > "$LUA_HOME/.config/hypr/userprefs.conf"
env = YUSEI_CUSTOM_PREF,42
EOF
cat <<'EOF' > "$LUA_HOME/.config/hypr/UserConfigs/UserDecorations.conf"
decoration {
    rounding = 7
    blur {
        enabled = false
    }
}
EOF
cat <<'EOF' > "$LUA_HOME/.config/hypr/animations.conf"
bezier = customBezier, 0.05, 0.9, 0.1, 1.05
EOF

cat <<'EOF' > "$LUA_SANDBOX/verify_hyprland.lua"
local home = os.getenv("HOME")
assert(home and home ~= "", "HOME must be set")

-- Stub external process inspection/execution inside sandbox
io.popen = function(...)
    return {
        lines = function() return function() return nil end end,
        read = function() return "" end,
        close = function() return true end,
    }
end
os.execute = function() return true, "exit", 0 end

local recorded = {
    monitors = {},
    window_rules = {},
    animations = {},
    envs = {},
    configs = {},
}

local function make_noop_proxy()
    return setmetatable({}, {
        __index = function(self, k)
            local child = make_noop_proxy()
            rawset(self, k, child)
            return child
        end,
        __call = function() return nil end,
    })
end

hl = setmetatable({
    dsp = make_noop_proxy(),
    monitor = function(tbl) table.insert(recorded.monitors, tbl) end,
    window_rule = function(tbl) table.insert(recorded.window_rules, tbl) end,
    animation = function(tbl) table.insert(recorded.animations, tbl) end,
    env = function(k, v) recorded.envs[k] = v end,
    config = function(tbl) table.insert(recorded.configs, tbl) end,
    bind = function() end,
    curve = function() end,
    device = function() end,
    dispatch = function() end,
    exec_cmd = function() end,
    gesture = function() end,
    layer_rule = function() end,
    workspace_rule = function() end,
    on = function() end,
}, {
    __index = function() return function() end end,
})

local chunk, err = loadfile(arg[1])
assert(chunk, err)
chunk()

-- 1. Empty-output monitor rules (both built-in default and monitors.conf empty output)
local empty_out_count = 0
for _, m in ipairs(recorded.monitors) do
    if m.output == "" and m.mode == "preferred" and m.position == "auto" and m.scale == "1" then
        empty_out_count = empty_out_count + 1
    end
end
assert(empty_out_count >= 2, "Expected empty-output preferred monitor rules, got " .. tostring(empty_out_count))

-- 2. Video opacity rule precedence: global wildcard opacity baseline MUST precede video 1.0 override
local global_idx, video_idx = nil, nil
for idx, wr in ipairs(recorded.window_rules) do
    local cls = wr.match and wr.match.class
    local tag = wr.match and wr.match.tag
    if cls == ".*" and wr.opacity then
        global_idx = idx
    elseif tag == "multimedia_video" and wr.opacity and tostring(wr.opacity):match("1%.0") then
        video_idx = idx
    end
end
assert(global_idx and video_idx and global_idx < video_idx,
    string.format("Expected global .* opacity (%s) before multimedia_video override (%s)", tostring(global_idx), tostring(video_idx)))

-- 3. fadeDpms disabled even when animations.conf omits it
local fade_found = false
local fade_enabled = true
for _, a in ipairs(recorded.animations) do
    if a.leaf == "fadeDpms" then
        fade_found = true
        fade_enabled = a.enabled
    end
end
assert(fade_found and fade_enabled == false, "Expected fadeDpms disabled")

-- 4. nvidia.conf & userprefs.conf env loading
assert(recorded.envs["__NV_PRIME_RENDER_OFFLOAD"] == "1", "nvidia.conf env missing")
assert(recorded.envs["YUSEI_CUSTOM_PREF"] == "42", "userprefs.conf env missing")

-- 5. UserDecorations.conf rounding & blur.enabled applied
local got_rounding, got_blur = nil, nil
for _, cfg in ipairs(recorded.configs) do
    if cfg.decoration then
        if cfg.decoration.rounding ~= nil then got_rounding = cfg.decoration.rounding end
        if cfg.decoration.blur and cfg.decoration.blur.enabled ~= nil then got_blur = cfg.decoration.blur.enabled end
    end
end
assert(got_rounding == 7 and got_blur == false,
    string.format("Expected rounding=7, blur=false, got rounding=%s blur=%s", tostring(got_rounding), tostring(got_blur)))

print("LUA_HYPRLAND_OK")
EOF

LUA_VERIFY_OUT=""
LUA_VERIFY_RC=0
set +e
LUA_VERIFY_OUT="$(HOME="$LUA_HOME" XDG_CONFIG_HOME="$LUA_HOME/.config" lua "$LUA_SANDBOX/verify_hyprland.lua" "$HYPRLAND_LUA" 2>&1)"
LUA_VERIFY_RC=$?
set -e

assert_check "hyprland.lua preserves empty-output monitor rules and orders global .* opacity before video 1.0 override" \
    "[ '$LUA_VERIFY_RC' -eq 0 ] && grep -q 'LUA_HYPRLAND_OK' <<< '$LUA_VERIFY_OUT'"

assert_check "hyprland.lua loads UserDecorations.conf, nvidia.conf, userprefs.conf, and disables fadeDpms" \
    "[ '$LUA_VERIFY_RC' -eq 0 ] && grep -q 'LUA_HYPRLAND_OK' <<< '$LUA_VERIFY_OUT'"

# ------------------------------------------------------------------------------
# 30. Tak0-Per-Window-Switch.sh Singleton Listener & Tak0-Autodispatch.sh Safety
# ------------------------------------------------------------------------------
PW_SANDBOX="$TMP_ROOT/per_window"
PW_HOME="$PW_SANDBOX/home"
PW_RUNTIME="$PW_SANDBOX/runtime"
PW_BIN="$PW_SANDBOX/bin"
PW_SOCK_DIR="$PW_RUNTIME/hypr/test-sig"
mkdir -p "$PW_HOME/.cache" "$PW_HOME/.config/hypr" "$PW_SOCK_DIR" "$PW_BIN"

cat <<'EOF' > "$PW_BIN/hyprctl"
#!/usr/bin/env bash
if [[ "${1:-}" == "getoption" ]]; then
    echo '{"str":"us,jp"}'
else
    echo '{}'
fi
EOF
cat <<'EOF' > "$PW_BIN/socat"
#!/usr/bin/env bash
echo "SOCAT_STARTED:$$" >> "${PW_SOCAT_LOG:?}"
sleep 30
EOF
chmod +x "$PW_BIN/hyprctl" "$PW_BIN/socat"

PW_LISTENER_SCRIPT="$REPO_ROOT/config/hypr/scripts/Tak0-Per-Window-Switch.sh"
test_per_window_singleton() {
    # Create an actual listening Unix domain socket path for -S check
    rm -f "$PW_SOCK_DIR/.socket2.sock"
    python3 -c '
import socket, sys, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
s.listen(2)
time.sleep(30)
' "$PW_SOCK_DIR/.socket2.sock" </dev/null >/dev/null 2>&1 &
    local sock_pid=$!
    DPMS_BG_PIDS+=("$sock_pid")

    for _ in $(seq 1 40); do
        [ -S "$PW_SOCK_DIR/.socket2.sock" ] && break
        sleep 0.05
    done

    local socat_log="$PW_SANDBOX/socat.log"
    : > "$socat_log"

    HOME="$PW_HOME" XDG_RUNTIME_DIR="$PW_RUNTIME" HYPRLAND_INSTANCE_SIGNATURE="test-sig" \
        PW_SOCAT_LOG="$socat_log" PATH="$PW_BIN:$ORIG_PATH" \
        bash "$PW_LISTENER_SCRIPT" --listener </dev/null >/dev/null 2>&1 &
    local listener1_pid=$!
    DPMS_BG_PIDS+=("$listener1_pid")

    local pid_file="$PW_RUNTIME/tak0-per-window.pid"
    for _ in $(seq 1 40); do
        if [ -s "$socat_log" ] && [ -s "$pid_file" ]; then
            break
        fi
        sleep 0.05
    done

    local recorded_pid
    recorded_pid="$(tr -d '[:space:]' < "$pid_file" 2>/dev/null || true)"

    HOME="$PW_HOME" XDG_RUNTIME_DIR="$PW_RUNTIME" HYPRLAND_INSTANCE_SIGNATURE="test-sig" \
        PW_SOCAT_LOG="$socat_log" PATH="$PW_BIN:$ORIG_PATH" \
        bash "$PW_LISTENER_SCRIPT" --listener </dev/null >/dev/null 2>&1
    local dup_rc=$?
    local socat_count
    socat_count="$(wc -l < "$socat_log")"
    local after_pid
    after_pid="$(tr -d '[:space:]' < "$pid_file" 2>/dev/null || true)"

    pkill -P "$listener1_pid" 2>/dev/null || true
    kill "$listener1_pid" "$sock_pid" 2>/dev/null || true
    wait "$listener1_pid" "$sock_pid" 2>/dev/null || true

    [ "$dup_rc" -eq 0 ] && [ "$socat_count" -eq 1 ] && [ -n "$recorded_pid" ] && [ "$recorded_pid" = "$after_pid" ]
}
assert_check "Tak0-Per-Window-Switch.sh --listener enforces singleton process without duplicating daemon on reload" \
    "test_per_window_singleton"

AUTO_MAIN="$REPO_ROOT/config/hypr/scripts/Tak0-Autodispatch.sh"
AUTO_USER="$REPO_ROOT/config/hypr/UserScripts/Tak0-Autodispatch.sh"
AUTO_SANDBOX="$TMP_ROOT/autodispatch"
mkdir -p "$AUTO_SANDBOX/bin"
cp "$AUTO_USER" "$AUTO_SANDBOX/Tak0-Autodispatch.sh"
chmod +x "$AUTO_SANDBOX/Tak0-Autodispatch.sh"

cat <<'EOF' > "$AUTO_SANDBOX/bin/hyprctl"
#!/usr/bin/env bash
if [[ "${1:-}" == "clients" && "${2:-}" == "-j" ]]; then
    printf '[{"class":"Firefox","address":"0xaaa111"},{"class":"firefox","address":"0xbbb222"}]'
    exit 0
fi
if [[ "${1:-}" == "dispatch" ]]; then
    echo "dispatch:$*" >> "${AUTO_LOG:?}"
    exit 0
fi
exit 0
EOF
cat <<'EOF' > "$AUTO_SANDBOX/bin/mockapp"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$AUTO_SANDBOX/bin/hyprctl" "$AUTO_SANDBOX/bin/mockapp"

test_autodispatch_jq_safety() {
    local auto_log="$AUTO_SANDBOX/hyprctl.log"
    : > "$auto_log"
    cmp -s "$AUTO_MAIN" "$AUTO_USER" && \
    AUTO_LOG="$auto_log" PATH="$AUTO_SANDBOX/bin:$ORIG_PATH" \
        bash "$AUTO_SANDBOX/Tak0-Autodispatch.sh" "mockapp|Firefox" "3" </dev/null >/dev/null 2>&1 && \
    grep -q "address:0xaaa111" "$auto_log" && \
    ! grep -q "0xbbb222" "$auto_log"
}
assert_check "Tak0-Autodispatch.sh matches scripts/UserScripts parity and selects first() address safely via jq" \
    "test_autodispatch_jq_safety"

# ------------------------------------------------------------------------------
# 32. RainbowBorders.sh Wallust Normalization -> 0xffRRGGBB Gradient Output
# ------------------------------------------------------------------------------
RB_SCRIPTS="$REPO_ROOT/config/hypr/scripts/RainbowBorders.sh"
RB_USER="$REPO_ROOT/config/hypr/UserScripts/RainbowBorders.sh"
RB_SANDBOX="$TMP_ROOT/rainbow"
RB_HOME="$RB_SANDBOX/home"
RB_BIN="$RB_SANDBOX/bin"
mkdir -p "$RB_HOME/.config/hypr/wallust" "$RB_BIN"

cat <<'EOF' > "$RB_HOME/.config/hypr/wallust/wallust-hyprland.conf"
$color0 = rgb(010203)
$color1 = rgb(010203)
$color2 = rgb(010203)
$color3 = rgb(010203)
$color4 = rgb(010203)
$color5 = rgb(010203)
$color6 = rgb(010203)
$color7 = rgb(010203)
$color8 = rgb(010203)
$color9 = rgb(010203)
$color10 = rgb(AABBCC)
$color11 = rgb(010203)
$color12 = rgb(010203)
$color13 = #112233
$color14 = rgb(16, 32, 48)
$color15 = 0xff445566
EOF

cat <<'EOF' > "$RB_BIN/hyprctl"
#!/usr/bin/env bash
echo "HYPRCTL:$*" >> "${RB_LOG:?}"
exit 0
EOF
chmod +x "$RB_BIN/hyprctl"

test_rainbow_borders() {
    local rb_log="$RB_SANDBOX/hyprctl.log"
    : > "$rb_log"
    cmp -s "$RB_SCRIPTS" "$RB_USER" && \
    HOME="$RB_HOME" RB_LOG="$rb_log" PATH="$RB_BIN:$ORIG_PATH" bash "$RB_SCRIPTS" && \
    grep -q "0xff445566 0xff102030 0xff112233 0xffAABBCC" "$rb_log"
}
assert_check "RainbowBorders.sh normalizes wallust rgb(RRGGBB), #RRGGBB, and rgb(r,g,b) into 0xffRRGGBB gradient output" \
    "test_rainbow_borders"

# ------------------------------------------------------------------------------
# 33. ScreenShot.sh Zero-Byte & Cancelled slurp Guards
# ------------------------------------------------------------------------------
SHOT_SCRIPT="$REPO_ROOT/config/hypr/scripts/ScreenShot.sh"
SHOT_SANDBOX="$TMP_ROOT/screenshot"
SHOT_HOME="$SHOT_SANDBOX/home"
SHOT_BIN="$SHOT_SANDBOX/bin"
mkdir -p "$SHOT_HOME/Pictures/Screenshots" "$SHOT_HOME/.config/swaync/icons" "$SHOT_HOME/.config/swaync/images" "$SHOT_HOME/.config/hypr/scripts" "$SHOT_BIN"

cat <<'EOF' > "$SHOT_HOME/.config/hypr/scripts/Sounds.sh"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$SHOT_HOME/.config/hypr/scripts/Sounds.sh"

cat <<'EOF' > "$SHOT_BIN/xdg-user-dir"
#!/usr/bin/env bash
echo "$HOME/Pictures"
EOF
cat <<'EOF' > "$SHOT_BIN/slurp"
#!/usr/bin/env bash
exit 1
EOF
cat <<'EOF' > "$SHOT_BIN/grim"
#!/usr/bin/env bash
# Simulate zero-byte capture failure
dest="${@: -1}"
: > "$dest"
exit 0
EOF
cat <<'EOF' > "$SHOT_BIN/wl-copy"
#!/usr/bin/env bash
echo "WL_COPY_CALLED" >> "${SHOT_LOG:?}"
exit 0
EOF
cat <<'EOF' > "$SHOT_BIN/notify-send"
#!/usr/bin/env bash
exit 0
EOF
cat <<'EOF' > "$SHOT_BIN/hyprctl"
#!/usr/bin/env bash
echo '{"class":"Test","at":[0,0],"size":[100,100]}'
EOF
chmod +x "$SHOT_BIN/xdg-user-dir" "$SHOT_BIN/slurp" "$SHOT_BIN/grim" "$SHOT_BIN/wl-copy" "$SHOT_BIN/notify-send" "$SHOT_BIN/hyprctl"

test_screenshot_empty_guards() {
    local shot_log="$SHOT_SANDBOX/wlcopy.log"
    : > "$shot_log"
    rm -f "$SHOT_HOME/Pictures/Screenshots/"*.png
    HOME="$SHOT_HOME" SHOT_LOG="$shot_log" PATH="$SHOT_BIN:$ORIG_PATH" bash "$SHOT_SCRIPT" --area >/dev/null 2>&1
    HOME="$SHOT_HOME" SHOT_LOG="$shot_log" PATH="$SHOT_BIN:$ORIG_PATH" bash "$SHOT_SCRIPT" --now >/dev/null 2>&1
    local png_count
    png_count="$(find "$SHOT_HOME/Pictures/Screenshots" -maxdepth 1 -name '*.png' | wc -l)"
    [ "$png_count" -eq 0 ] && [ ! -s "$shot_log" ]
}
assert_check "ScreenShot.sh discards cancelled slurp (--area) and zero-byte grim captures (--now) without keeping PNG or calling wl-copy" \
    "test_screenshot_empty_guards"

# ------------------------------------------------------------------------------
# 34-35. bin/notify-send Action/Timeout/Sync-Hint Passthrough & Zero Leakage
# ------------------------------------------------------------------------------
NOTIFY_WRAPPER="$REPO_ROOT/bin/notify-send"
NS_SANDBOX="$TMP_ROOT/notify_sandbox"
NS_RUNTIME="$NS_SANDBOX/runtime"
NS_BIN="$NS_SANDBOX/bin"
mkdir -p "$NS_RUNTIME" "$NS_BIN"

cat <<'EOF' > "$NS_BIN/real-notify-send"
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${NS_LOG:?}"
EOF
chmod +x "$NS_BIN/real-notify-send"

test_notify_send_passthrough() {
    local ns_log="$NS_SANDBOX/calls.log"
    : > "$ns_log"
    REAL_NOTIFY_SEND="$NS_BIN/real-notify-send" XDG_RUNTIME_DIR="$NS_RUNTIME" NS_LOG="$ns_log" \
        "$NOTIFY_WRAPPER" -A "open=Open" "Action Title" "Action Body"
    REAL_NOTIFY_SEND="$NS_BIN/real-notify-send" XDG_RUNTIME_DIR="$NS_RUNTIME" NS_LOG="$ns_log" \
        "$NOTIFY_WRAPPER" -t 6000 "Long Title" "Long Body"
    REAL_NOTIFY_SEND="$NS_BIN/real-notify-send" XDG_RUNTIME_DIR="$NS_RUNTIME" NS_LOG="$ns_log" \
        "$NOTIFY_WRAPPER" -h "string:x-canonical-private-synchronous:custom-tag" "Sync Title" "Sync Body"

    local line1 line2 line3
    line1="$(sed -n '1p' "$ns_log")"
    line2="$(sed -n '2p' "$ns_log")"
    line3="$(sed -n '3p' "$ns_log")"

    grep -q -- '-A open=Open' <<< "$line1" && ! grep -q 'yusei-popup' <<< "$line1" && ! grep -q -- '-t 3000' <<< "$line1" && \
    grep -q -- '-t 6000' <<< "$line2" && ! grep -q -- '-t 3000' <<< "$line2" && \
    grep -q 'x-canonical-private-synchronous:custom-tag' <<< "$line3" && ! grep -q 'yusei-popup' <<< "$line3" && \
    [ -f "$NS_RUNTIME/.yusei_swaync_action_pending" ]
}
assert_check "bin/notify-send preserves -A actions, -t >= 5000 timeouts, and caller synchronous hints cleanly in isolated runtime" \
    "test_notify_send_passthrough"

test_notify_send_default_popup() {
    local ns_log="$NS_SANDBOX/default.log"
    : > "$ns_log"
    REAL_NOTIFY_SEND="$NS_BIN/real-notify-send" XDG_RUNTIME_DIR="$NS_RUNTIME" NS_LOG="$ns_log" \
        "$NOTIFY_WRAPPER" "Normal Title" "Normal Body"
    grep -q -- '-t 3000' "$ns_log" && grep -q 'string:x-canonical-private-synchronous:yusei-popup' "$ns_log"
}
assert_check "bin/notify-send enforces 3000ms single-popup defaults when no action, critical urgency, or sync hint given" \
    "test_notify_send_default_popup"

# ------------------------------------------------------------------------------
# 36. config/swaync/config.json Validation & Required Keys
# ------------------------------------------------------------------------------
SWAYNC_CONF="$REPO_ROOT/config/swaync/config.json"
assert_check "config/swaync/config.json is valid JSON with required widgets, vexpand, and single-popup keys" \
    "jq -e '(.widgets | type == \"array\" and length > 0) and .\"widget-config\".notifications.vexpand == true and .scripts.\"single-popup\".exec and .scripts.\"single-popup\".\"run-on\"' '$SWAYNC_CONF' >/dev/null 2>&1"

# ------------------------------------------------------------------------------
# 37. Hyprland Animation Speed Bounds (<= 100.00 across all presets & user config)
# ------------------------------------------------------------------------------
assert_check "All animation presets and UserAnimations.conf enforce speed <= 100.00" \
    "python3 -c '
import glob, re, sys
files = sorted(glob.glob(\"$REPO_ROOT/config/hypr/animations/*.conf\") + [\"$REPO_ROOT/config/hypr/UserConfigs/UserAnimations.conf\", \"$REPO_ROOT/config/hypr/animations.conf\"])
bad = []
for p in files:
    with open(p, encoding=\"utf-8\") as f:
        for i, line in enumerate(f, 1):
            s = line.split(\"#\", 1)[0].strip()
            m = re.match(r\"^animation\\s*=\\s*[^,]+,\\s*[^,]+,\\s*([0-9.]+)\", s)
            if m and float(m.group(1)) > 100.0:
                bad.append(f\"{p}:{i}:{m.group(1)}\")
sys.exit(1 if bad else 0)
'"

# ------------------------------------------------------------------------------
# 38. hyprland.lua Clamps Speed > 100 at Runtime via Lua Harness
# ------------------------------------------------------------------------------
test_hyprland_lua_speed_clamp() {
    local lua_bin=""
    lua_bin="$(command -v lua || command -v lua5.4 || command -v luajit || true)"
    [[ -n "$lua_bin" ]] || return 1

    local lua_home="$TMP_ROOT/lua_home"
    mkdir -p "$lua_home/.config/hypr/UserConfigs"
    cat <<'EOF' > "$lua_home/.config/hypr/animations.conf"
animations {
    enabled = yes
    animation = borderangle, 1, 180, liner, loop
    animation = fadeDpms, 0
}
EOF
    cat <<'EOF' > "$lua_home/.config/hypr/UserConfigs/UserAnimations.conf"
animations {
    animation = borderangle, 1, 250, liner, loop
}
EOF

    HOME="$lua_home" "$lua_bin" -e '
        local calls = {}
        local noop_mt
        noop_mt = {
            __index = function(_, k)
                return setmetatable({}, noop_mt)
            end,
            __call = function(_, ...)
                return setmetatable({}, noop_mt)
            end
        }
        hl = setmetatable({
            animation = function(def)
                table.insert(calls, def)
            end,
        }, noop_mt)
        assert(loadfile("'"$HYPRLAND_LUA"'"))()
        local max_speed = 0
        local saw_borderangle = false
        local final_fadedpms = nil
        for _, c in ipairs(calls) do
            if type(c) == "table" then
                if c.speed and c.speed > max_speed then max_speed = c.speed end
                if c.leaf == "borderangle" then saw_borderangle = true end
                if c.leaf == "fadeDpms" then final_fadedpms = c.enabled end
            end
        end
        assert(saw_borderangle, "borderangle never called")
        assert(max_speed <= 100, "speed exceeded 100: " .. tostring(max_speed))
        assert(final_fadedpms == false, "fadeDpms not disabled")
    '
}
assert_check "hyprland.lua clamps borderangle speed 180/250 -> 100 and keeps fadeDpms disabled" \
    "test_hyprland_lua_speed_clamp"

# ------------------------------------------------------------------------------
# 39. Animations.sh --apply Sanitizes Speed > 100 & Keeps fadeDpms, 0
# ------------------------------------------------------------------------------
test_animations_sh_apply_sanitizes() {
    local anim_home="$TMP_ROOT/anim_home"
    local anim_bin="$TMP_ROOT/anim_bin"
    mkdir -p "$anim_home/.config/hypr/animations" "$anim_home/.config/hypr/UserConfigs" "$anim_home/.config/hypr/scripts" "$anim_bin"
    cat <<'EOF' > "$anim_home/.config/hypr/animations/TestHighSpeed.conf"
animations {
  enabled = yes
  animation = borderangle, 1, 180, liner, loop # test comment
}
EOF
    printf '#!/usr/bin/env bash\nexit 0\n' > "$anim_bin/hyprctl"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$anim_bin/notify-send"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$anim_home/.config/hypr/scripts/RefreshNoWaybar.sh"
    chmod +x "$anim_bin/hyprctl" "$anim_bin/notify-send" "$anim_home/.config/hypr/scripts/RefreshNoWaybar.sh"

    HOME="$anim_home" PATH="$anim_bin:$ORIG_PATH" bash "$REPO_ROOT/config/hypr/scripts/Animations.sh" --apply TestHighSpeed >/dev/null 2>&1

    grep -q 'animation = borderangle, 1, 100, liner, loop' "$anim_home/.config/hypr/UserConfigs/UserAnimations.conf" && \
    ! grep -q '180' "$anim_home/.config/hypr/UserConfigs/UserAnimations.conf" && \
    grep -Eq 'animation[[:space:]]*=[[:space:]]*fadeDpms,[[:space:]]*0' "$anim_home/.config/hypr/UserConfigs/UserAnimations.conf" && \
    grep -Eq 'animation[[:space:]]*=[[:space:]]*fadeDpms,[[:space:]]*0' "$anim_home/.config/hypr/animations.conf"
}
assert_check "Animations.sh --apply clamps speed > 100 to 100 and enforces fadeDpms, 0 in both animation configs" \
    "test_animations_sh_apply_sanitizes"

# ------------------------------------------------------------------------------
# 40. launch-daemons.sh & Refresh.sh Use systemd swaync.service & Prioritize ~/.local/bin
# ------------------------------------------------------------------------------
test_swaync_systemd_and_local_bin() {
    local sd_home="$TMP_ROOT/sd_home"
    local sd_bin="$TMP_ROOT/sd_bin"
    local sd_log="$TMP_ROOT/sd_calls.log"
    mkdir -p "$sd_home/.local/bin" "$sd_home/.config/hypr/scripts" "$sd_home/.config/hypr/UserScripts" "$sd_bin"
    : > "$sd_log"

    cat <<EOF > "$sd_bin/systemctl"
#!/usr/bin/env bash
printf 'systemctl %s\n' "\$*" >> "$sd_log"
if [[ "\${1:-}" == "--user" && "\${2:-}" == "cat" && "\${3:-}" == "swaync.service" ]]; then
    exit 0
fi
exit 0
EOF
    cat <<'EOF' > "$sd_bin/pidof"
#!/usr/bin/env bash
exit 1
EOF
    cat <<EOF > "$sd_home/.local/bin/waybar"
#!/usr/bin/env bash
printf 'local_waybar\n' >> "$sd_log"
exit 0
EOF
    printf '#!/usr/bin/env bash\nexit 1\n' > "$sd_bin/waybar"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$sd_bin/pkill"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$sd_bin/killall"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$sd_bin/swww"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$sd_bin/swww-daemon"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$sd_bin/hypridle"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$sd_bin/hyprctl"
    chmod +x "$sd_bin"/* "$sd_home/.local/bin/waybar"

    HOME="$sd_home" PATH="$sd_bin:$ORIG_PATH" bash "$REPO_ROOT/config/hypr/scripts/launch-daemons.sh" >/dev/null 2>&1
    wait || true
    HOME="$sd_home" PATH="$sd_bin:$ORIG_PATH" bash "$REPO_ROOT/config/hypr/scripts/Refresh.sh" >/dev/null 2>&1
    sleep 0.1

    grep -q 'systemctl --user reset-failed swaync.service' "$sd_log" && \
    [ "$(grep -c 'systemctl --user start swaync.service' "$sd_log")" -ge 2 ] && \
    grep -q 'local_waybar' "$sd_log"
}
assert_check "launch-daemons.sh and Refresh.sh start swaync via user systemd unit and prioritize ~/.local/bin waybar" \
    "test_swaync_systemd_and_local_bin"

# ------------------------------------------------------------------------------
# 41. libwaybar-hyprland-compat Isolates Translation to waybar Process Only
# ------------------------------------------------------------------------------
test_libwaybar_compat_process_isolation() {
    command -v gcc >/dev/null 2>&1 || return 1
    local c_dir="$TMP_ROOT/compat_test"
    mkdir -p "$c_dir"
    cat <<'EOF' > "$c_dir/writer.c"
#include <unistd.h>
#include <string.h>
int main(void) {
    const char *msg = "dispatch workspace 2\n";
    return write(1, msg, strlen(msg)) > 0 ? 0 : 1;
}
EOF
    gcc -O2 "$c_dir/writer.c" -o "$c_dir/other_proc"
    cp "$c_dir/other_proc" "$c_dir/waybar"

    local out_other out_waybar
    out_other="$(LD_PRELOAD="$REPO_ROOT/lib/libwaybar-hyprland.so" "$c_dir/other_proc")"
    out_waybar="$(LD_PRELOAD="$REPO_ROOT/lib/libwaybar-hyprland.so" "$c_dir/waybar")"

    [[ "$out_other" == "dispatch workspace 2" ]] && \
    [[ "$out_waybar" == "dispatch hl.dsp.focus({ workspace = 2 })" ]]
}
assert_check "libwaybar-hyprland-compat passes through non-waybar processes and translates waybar IPC only" \
    "test_libwaybar_compat_process_isolation"

# ------------------------------------------------------------------------------
# 42. bin/notify-send Resolves Missing swaync/images Paths Across All Modes
# ------------------------------------------------------------------------------
test_notify_send_missing_icon_fallback() {
    local fb_log="$NS_SANDBOX/icon_fallback.log"
    local fb_home="$TMP_ROOT/fb_home"
    mkdir -p "$fb_home/.config/swaync/icons"
    : > "$fb_home/.config/swaync/icons/timer.png"
    : > "$fb_log"

    # Missing image with -A (passthrough=true) -> Freedesktop dialog-error
    HOME="$fb_home" REAL_NOTIFY_SEND="$NS_BIN/real-notify-send" XDG_RUNTIME_DIR="$NS_RUNTIME" NS_LOG="$fb_log" \
        "$NOTIFY_WRAPPER" -A "ok=OK" -i "$fb_home/.config/swaync/images/error.png" "Err" "Body"
    # Missing image with default mode -> existing icons/timer.png
    HOME="$fb_home" REAL_NOTIFY_SEND="$NS_BIN/real-notify-send" XDG_RUNTIME_DIR="$NS_RUNTIME" NS_LOG="$fb_log" \
        "$NOTIFY_WRAPPER" --icon="$fb_home/.config/swaync/images/timer.png" "Timer" "Body"
    # Missing ja.png -> dialog-information
    HOME="$fb_home" REAL_NOTIFY_SEND="$NS_BIN/real-notify-send" XDG_RUNTIME_DIR="$NS_RUNTIME" NS_LOG="$fb_log" \
        "$NOTIFY_WRAPPER" -i "$fb_home/.config/swaync/images/ja.png" "Info" "Body"

    local l1 l2 l3
    l1="$(sed -n '1p' "$fb_log")"
    l2="$(sed -n '2p' "$fb_log")"
    l3="$(sed -n '3p' "$fb_log")"

    grep -q -- '-i dialog-error' <<< "$l1" && \
    grep -q -- "--icon=$fb_home/.config/swaync/icons/timer.png" <<< "$l2" && \
    grep -q -- '-i dialog-information' <<< "$l3"
}
assert_check "bin/notify-send falls back missing swaync/images paths to icons/ or standard Freedesktop icon names" \
    "test_notify_send_missing_icon_fallback"

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
