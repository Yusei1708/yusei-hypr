#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Hyprsunset Night Light & Package Verification Test Suite
# ==============================================================================
# - Verifies config/hypr/scripts/Hyprsunset.sh exists, is executable, passes bash -n
# - Verifies config/waybar/ModulesCustom Night Light module (signal & dynamic tooltip)
# - Tests Hyprsunset.sh with isolated mock binaries (no host process interference):
#   * Missing hyprsunset binary (toggle notify + status JSON + init reset)
#   * Healthy hyprsunset daemon lifecycle (toggle ON -> status on -> toggle OFF -> status off)
#   * Stale state-file desync recovery (state=on but dead, state=off but running)
#   * Immediate startup crash detection (non-zero exit -> state=off + Failed notify)
#   * Idempotent init (no duplicate spawn when already running)
#   * Invalid HYPRSUNSET_TEMP fallback to 4500K
# - Verifies scripts/02-packages.sh --list-missing and scripts/05-verify.sh checks
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

HYPRSUNSET_SH="$REPO_ROOT/config/hypr/scripts/Hyprsunset.sh"
MODULES_CUSTOM="$REPO_ROOT/config/waybar/ModulesCustom"
PKG_SCRIPT="$REPO_ROOT/scripts/02-packages.sh"
VERIFY_SCRIPT="$REPO_ROOT/scripts/05-verify.sh"

TMP_ROOT="$(mktemp -d -t yusei_hyprsunset_test_XXXXXX)"
cleanup_hyprsunset_suite() {
    if [[ -f "$TMP_ROOT/daemon.pid" ]]; then
        local dpid
        dpid="$(cat "$TMP_ROOT/daemon.pid" 2>/dev/null || true)"
        if [[ -n "$dpid" ]]; then
            kill -9 "$dpid" 2>/dev/null || true
        fi
    fi
    rm -rf "$TMP_ROOT"
}
trap cleanup_hyprsunset_suite EXIT

TOTAL_TESTS=13
echo -e "${BLUE}${BOLD}:: [Test Suite] Hyprsunset Night Light & Package Guard${NC}"
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
# 1. Static checks: Hyprsunset.sh & Waybar ModulesCustom
# ------------------------------------------------------------------------------
assert_check "Hyprsunset.sh exists, is executable, and passes bash -n" \
    "[ -f '$HYPRSUNSET_SH' ] && [ -x '$HYPRSUNSET_SH' ] && bash -n '$HYPRSUNSET_SH'"

assert_check "Waybar ModulesCustom custom/nightlight uses signal=8 and dynamic JSON tooltip" \
    "python3 - '$MODULES_CUSTOM' <<'PYEOF'
import json, sys
text = open(sys.argv[1], encoding='utf-8').read()
# String-aware comment and trailing comma strip
out, in_str, i, n = [], False, 0, len(text)
while i < n:
    c = text[i]
    if in_str:
        out.append(c)
        if c == '\\\\' and i + 1 < n:
            out.append(text[i + 1]); i += 2; continue
        if c == '\"':
            in_str = False
        i += 1
        continue
    if c == '\"':
        in_str = True; out.append(c); i += 1
    elif c == '/' and i + 1 < n and text[i + 1] == '/':
        i += 2
        while i < n and text[i] != '\n': i += 1
    elif c == '/' and i + 1 < n and text[i + 1] == '*':
        i += 2
        while i + 1 < n and not (text[i] == '*' and text[i + 1] == '/'):
            if text[i] == '\n': out.append('\n')
            i += 1
        i += 2
    else:
        out.append(c); i += 1
cleaned = ''.join(out)
res, in_str, j, m = [], False, 0, len(cleaned)
while j < m:
    c = cleaned[j]
    if in_str:
        res.append(c)
        if c == '\\\\' and j + 1 < m:
            res.append(cleaned[j + 1]); j += 2; continue
        if c == '\"': in_str = False
    elif c == '\"':
        in_str = True; res.append(c)
    elif c == ',':
        k = j + 1
        while k < m and cleaned[k].isspace(): k += 1
        if k < m and cleaned[k] in ']}':
            j += 1; continue
        res.append(c)
    else:
        res.append(c)
    j += 1
data = json.loads(''.join(res))
nl = data['custom/nightlight']
assert nl['return-type'] == 'json', nl
assert nl['signal'] == 8, nl
assert nl['tooltip'] is True, nl
assert 'tooltip-format' not in nl, nl
PYEOF"

# ------------------------------------------------------------------------------
# Setup isolated sandbox & mock binaries
# ------------------------------------------------------------------------------
MOCK_HOME="$TMP_ROOT/home"
MOCK_RUNTIME="$TMP_ROOT/runtime"
MOCK_BIN="$TMP_ROOT/bin"
MOCK_NOMISSING_BIN="$TMP_ROOT/bin_missing"
NOTIFY_LOG="$TMP_ROOT/notify.log"
PKILL_LOG="$TMP_ROOT/pkill.log"
HYPR_ARGS_LOG="$TMP_ROOT/hyprsunset_args.log"
DAEMON_PID_FILE="$TMP_ROOT/daemon.pid"
DAEMON_MODE_FILE="$TMP_ROOT/daemon.mode"

mkdir -p "$MOCK_HOME" "$MOCK_RUNTIME" "$MOCK_BIN" "$MOCK_NOMISSING_BIN"

cat <<'EOF' > "$MOCK_BIN/notify-send"
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_NOTIFY_LOG"
EOF

cat <<'EOF' > "$MOCK_BIN/pgrep"
#!/usr/bin/env bash
# Match only our isolated mock hyprsunset daemon
if [[ "$*" == *"hyprsunset"* && -f "$TEST_DAEMON_PID" ]]; then
    pid="$(cat "$TEST_DAEMON_PID" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        echo "$pid"
        exit 0
    fi
fi
exit 1
EOF

cat <<'EOF' > "$MOCK_BIN/pkill"
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_PKILL_LOG"
if [[ "$*" == *"hyprsunset"* && -f "$TEST_DAEMON_PID" ]]; then
    pid="$(cat "$TEST_DAEMON_PID" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        if [[ "$*" == *"-9"* ]]; then
            kill -9 "$pid" 2>/dev/null || true
        else
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$TEST_DAEMON_PID"
        exit 0
    fi
    rm -f "$TEST_DAEMON_PID"
fi
exit 1
EOF

cat <<'EOF' > "$MOCK_BIN/hyprsunset"
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_HYPR_ARGS_LOG"
mode="$(cat "$TEST_DAEMON_MODE" 2>/dev/null || echo healthy)"
if [[ "$mode" == "crash" ]]; then
    echo "CTM manager unavailable (mock error)" >&2
    exit 1
fi
echo "$$" > "$TEST_DAEMON_PID"
trap 'rm -f "$TEST_DAEMON_PID"; exit 0' TERM INT
sleep 30 &
wait $!
EOF

chmod +x "$MOCK_BIN/notify-send" "$MOCK_BIN/pgrep" "$MOCK_BIN/pkill" "$MOCK_BIN/hyprsunset"

# Copy non-hyprsunset mock tools to bin_missing; also create safe isolated PATH without system /usr/bin hyprsunset
for cmd in bash dirname mkdir cat echo printf sleep kill wait head tr cut rm nohup wc pgrep pkill notify-send flock id; do
    if [[ -x "$MOCK_BIN/$cmd" ]]; then
        ln -sf "$MOCK_BIN/$cmd" "$MOCK_NOMISSING_BIN/$cmd"
    elif real_bin="$(command -v "$cmd" 2>/dev/null || true)" && [[ -n "$real_bin" ]]; then
        ln -sf "$real_bin" "$MOCK_NOMISSING_BIN/$cmd"
    fi
done

run_hs_missing() {
    env -i \
        HOME="$MOCK_HOME" \
        XDG_RUNTIME_DIR="$MOCK_RUNTIME" \
        PATH="$MOCK_NOMISSING_BIN" \
        TEST_NOTIFY_LOG="$NOTIFY_LOG" \
        TEST_PKILL_LOG="$PKILL_LOG" \
        TEST_DAEMON_PID="$DAEMON_PID_FILE" \
        bash "$HYPRSUNSET_SH" "$@"
}

run_hs_present() {
    env -i \
        HOME="$MOCK_HOME" \
        XDG_RUNTIME_DIR="$MOCK_RUNTIME" \
        PATH="$MOCK_BIN:$MOCK_NOMISSING_BIN" \
        HYPRSUNSET_TEMP="${TEST_HYPRSUNSET_TEMP:-4500}" \
        TEST_NOTIFY_LOG="$NOTIFY_LOG" \
        TEST_PKILL_LOG="$PKILL_LOG" \
        TEST_HYPR_ARGS_LOG="$HYPR_ARGS_LOG" \
        TEST_DAEMON_PID="$DAEMON_PID_FILE" \
        TEST_DAEMON_MODE="$DAEMON_MODE_FILE" \
        bash "$HYPRSUNSET_SH" "$@"
}

# ------------------------------------------------------------------------------
# 2. Missing binary behavior (even when ~/.cache does not exist yet)
# ------------------------------------------------------------------------------
rm -rf "$MOCK_HOME/.cache"
: > "$NOTIFY_LOG"
assert_check "Missing hyprsunset: toggle creates state dir, sets off, notifies Not Installed, returns 1" \
    "! run_hs_missing toggle && \
     [ \"\$(cat '$MOCK_HOME/.cache/.hyprsunset_state')\" = 'off' ] && \
     grep -q 'Hyprsunset: Not Installed' '$NOTIFY_LOG' && \
     grep -q 'sudo pacman -S' '$NOTIFY_LOG'"

assert_check "Missing hyprsunset: status returns valid JSON with unavailable tooltip, compact icon, and class=off" \
    "STATUS_OUT=\$(run_hs_missing status) && \
     echo \"\$STATUS_OUT\" | jq -e '.class == \"off\" and (.text | contains(\"size=\\u0027115%\\u0027\")) and (.tooltip | contains(\"hyprsunset not installed\"))' >/dev/null"

echo "on" > "$MOCK_HOME/.cache/.hyprsunset_state"
assert_check "Missing hyprsunset: init resets stale on state to off and exits 0" \
    "run_hs_missing init && [ \"\$(cat '$MOCK_HOME/.cache/.hyprsunset_state')\" = 'off' ]"

# ------------------------------------------------------------------------------
# 3. Healthy daemon lifecycle & state/process synchronization
# ------------------------------------------------------------------------------
echo "healthy" > "$DAEMON_MODE_FILE"
rm -f "$DAEMON_PID_FILE"
: > "$NOTIFY_LOG"
: > "$PKILL_LOG"
: > "$HYPR_ARGS_LOG"

assert_check "Healthy toggle ON starts hyprsunset -t 4500, sets state=on, signals waybar, notifies Enabled" \
    "run_hs_present toggle && \
     [ \"\$(cat '$MOCK_HOME/.cache/.hyprsunset_state')\" = 'on' ] && \
     grep -q -- '-t 4500' '$HYPR_ARGS_LOG' && \
     grep -q -- '-RTMIN+8 waybar' '$PKILL_LOG' && \
     grep -q 'Hyprsunset: Enabled' '$NOTIFY_LOG' && \
     [ -f '$DAEMON_PID_FILE' ]"

assert_check "Healthy status returns class=on, compact 80% sunset icon, and 4500K tooltip while running" \
    "STATUS_OUT=\$(run_hs_present status) && \
     echo \"\$STATUS_OUT\" | jq -e '.class == \"on\" and (.text | contains(\"size=\\u002780%\\u0027\")) and .tooltip == \"Night light on @ 4500K\"' >/dev/null"

: > "$NOTIFY_LOG"
: > "$HYPR_ARGS_LOG"
assert_check "Healthy toggle OFF applies -i, stops daemon cleanly, sets state=off, notifies Disabled" \
    "run_hs_present toggle && \
     [ \"\$(cat '$MOCK_HOME/.cache/.hyprsunset_state')\" = 'off' ] && \
     grep -q -- '-i' '$HYPR_ARGS_LOG' && \
     grep -q 'Hyprsunset: Disabled' '$NOTIFY_LOG' && \
     [ ! -f '$DAEMON_PID_FILE' ]"

# Stale state=on when daemon is dead -> status must say off, toggle must turn ON
echo "on" > "$MOCK_HOME/.cache/.hyprsunset_state"
rm -f "$DAEMON_PID_FILE"
: > "$NOTIFY_LOG"
assert_check "Desync recovery (state=on, daemon dead): status reports off and toggle starts ON" \
    "STATUS_OUT=\$(run_hs_present status) && \
     echo \"\$STATUS_OUT\" | jq -e '.class == \"off\" and .tooltip == \"Night light off\"' >/dev/null && \
     run_hs_present toggle && \
     [ \"\$(cat '$MOCK_HOME/.cache/.hyprsunset_state')\" = 'on' ] && \
     grep -q 'Hyprsunset: Enabled' '$NOTIFY_LOG' && \
     [ -f '$DAEMON_PID_FILE' ]"

# Stale state=off when daemon is running -> toggle must turn OFF
echo "off" > "$MOCK_HOME/.cache/.hyprsunset_state"
: > "$NOTIFY_LOG"
assert_check "Desync recovery (state=off, daemon alive): toggle stops daemon cleanly and notifies Disabled" \
    "run_hs_present toggle && \
     [ \"\$(cat '$MOCK_HOME/.cache/.hyprsunset_state')\" = 'off' ] && \
     grep -q 'Hyprsunset: Disabled' '$NOTIFY_LOG' && \
     [ ! -f '$DAEMON_PID_FILE' ]"

# Idempotent init + invalid HYPRSUNSET_TEMP fallback
echo "on" > "$MOCK_HOME/.cache/.hyprsunset_state"
: > "$HYPR_ARGS_LOG"
assert_check "cmd_init is idempotent and falls back invalid HYPRSUNSET_TEMP to 4500K" \
    "TEST_HYPRSUNSET_TEMP='invalid' run_hs_present init && \
     TEST_HYPRSUNSET_TEMP='invalid' run_hs_present init && \
     [ \"\$(wc -l < '$HYPR_ARGS_LOG')\" -eq 1 ] && \
     grep -q -- '-t 4500' '$HYPR_ARGS_LOG' && \
     run_hs_present toggle"

# ------------------------------------------------------------------------------
# 4. Immediate startup crash detection
# ------------------------------------------------------------------------------
echo "crash" > "$DAEMON_MODE_FILE"
echo "off" > "$MOCK_HOME/.cache/.hyprsunset_state"
: > "$NOTIFY_LOG"
assert_check "Startup crash: toggle detects immediate exit, keeps state=off, notifies Failed with stderr reason" \
    "! run_hs_present toggle && \
     [ \"\$(cat '$MOCK_HOME/.cache/.hyprsunset_state')\" = 'off' ] && \
     grep -q 'Hyprsunset: Failed' '$NOTIFY_LOG' && \
     grep -q 'CTM manager unavailable' '$NOTIFY_LOG'"

# ------------------------------------------------------------------------------
# 5. Package checker & 05-verify.sh integration
# ------------------------------------------------------------------------------
MOCK_PAC_BIN="$TMP_ROOT/pac_bin"
mkdir -p "$MOCK_PAC_BIN"
cat <<'EOF' > "$MOCK_PAC_BIN/pacman"
#!/usr/bin/env bash
if [[ "$1" == "-Qi" ]]; then
    if [[ "$2" == "hyprsunset" ]]; then
        exit 1
    fi
    exit 0
fi
exit 1
EOF
chmod +x "$MOCK_PAC_BIN/pacman"

assert_check "02-packages.sh --list-missing reports hyprsunset when missing and 05-verify.sh surfaces it" \
    "MISSING_OUT=\$(PATH='$MOCK_PAC_BIN:/usr/bin:/bin' bash '$PKG_SCRIPT' --list-missing) && \
     [ \"\$MISSING_OUT\" = 'hyprsunset' ] && \
     VERIFY_OUT=\$(PATH='$MOCK_PAC_BIN:$MOCK_NOMISSING_BIN:/usr/bin:/bin' HOME='$MOCK_HOME' bash '$VERIFY_SCRIPT' --dry-run) && \
     echo \"\$VERIFY_OUT\" | grep -q 'Hyprsunset (Night Light)'"

# Summary
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}Hyprsunset Regression Test Summary${NC}"
echo -e "${BOLD}======================================================${NC}"
echo -e "Total Checks: ${TOTAL_TESTS}"
echo -e "Passed:       ${GREEN}${PASSED}${NC}"
if [[ $FAILED -gt 0 ]]; then
    echo -e "Failed:       ${RED}${FAILED}${NC}"
    for item in "${FAILED_LIST[@]}"; do
        echo -e "  - ${RED}${item}${NC}"
    done
    exit 1
else
    echo -e "Failed:       0"
    echo -e "${GREEN}${BOLD}Status: ALL HYPRSUNSET CHECKS PASSED${NC}"
    exit 0
fi
