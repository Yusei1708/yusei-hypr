#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: DPMS, Idle & Sleep-Wake Regression Test Suite
# ==============================================================================
# - Verifies DpmsControl.sh exists, is executable, and passes bash -n
# - Verifies hypridle.conf does not use bare toggle syntax hl.dsp.dpms('on'/'off')
# - Verifies hyprland.lua disables fadeDpms and fixes Lua disabled animation pattern
# - Tests idempotent DPMS on/off, Lua table syntax, legacy fallback, dim/restore,
#   and post-suspend wake recovery via isolated mock hyprctl/brightnessctl binaries
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
HYPRIDLE_CONF="$REPO_ROOT/config/hypr/hypridle.conf"
HYPRLAND_LUA="$REPO_ROOT/config/hypr/hyprland.lua"

TMP_ROOT="$(mktemp -d -t yusei_dpms_test_XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

TOTAL_TESTS=12
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
