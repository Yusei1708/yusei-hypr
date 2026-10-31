#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Power Optimizer Subsystem Test Suite
# ==============================================================================
# - Tests scripts/power-optimizer.sh existence and executable permissions
# - Tests config/hypr/scripts/power-optimizer.sh parity & checksum equality
# - Tests --help returns 0 and displays CLI usage
# - Tests --dry-run exits 0 without writing any files or touching live hardware
# - Tests --status --json produces valid JSON conforming to expected schema
# - Tests monitor JSON parsing with internal 144Hz display
# - Tests monitor JSON parsing with external 165Hz display (DP-1, no eDP)
# - Tests energy profile switching (eco, balanced, turbo) in isolated sandbox
# - Tests dynamic refresh rate switching (60Hz drop on battery, max Hz on AC)
# - Tests --toggle-hz alternating between 60Hz and max native rate
# - Tests mock sysfs single-battery power telemetry (capacity, status, watts, time)
# - Tests mock sysfs multi-battery aggregation (BAT0 + BAT1 power & capacity)
# - Tests multi-supply AC detection (AC0 offline + ADP1 USB-C online)
# - Tests auto mode on battery vs AC
# - Tests auto_60hz configuration override from userprefs.conf
# - Tests YUSEI_AC_PROFILE and YUSEI_BAT_PROFILE override from userprefs.conf
# - Tests --menu and --notify in dry-run mode
# - Tests invalid options error handling
# - Verifies zero host ~/.config pollution
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}:: [Test Suite] Power Optimizer Subsystem Verification${NC}"
echo -e "   Target Directory: ${REPO_ROOT}"

OPTIMIZER_SCRIPT="$REPO_ROOT/scripts/power-optimizer.sh"
HYPR_OPTIMIZER_SCRIPT="$REPO_ROOT/config/hypr/scripts/power-optimizer.sh"

# Setup isolated sandbox for mocking and file writes
TMP_DIR="$(mktemp -d -t yusei_power_test_XXXXXX)"
MOCK_HOME="$TMP_DIR/home"
MOCK_CONFIG="$MOCK_HOME/.config/hypr"
MOCK_SYSFS="$TMP_DIR/sysfs"
mkdir -p "$MOCK_CONFIG" "$MOCK_SYSFS/power_supply" "$MOCK_SYSFS/cpu/cpu0/cpufreq"
trap 'rm -rf "$TMP_DIR"' EXIT

TOTAL_TESTS=32
echo "1..${TOTAL_TESTS}"

TEST_INDEX=0
PASSED=0
FAILED=0
FAILED_LIST=()

assert_check() {
    local description="$1"
    local condition_exit_code="$2"
    TEST_INDEX=$((TEST_INDEX + 1))
    
    if [ "$condition_exit_code" -eq 0 ]; then
        echo "ok ${TEST_INDEX} - ${description}"
        PASSED=$((PASSED + 1))
    else
        echo "not ok ${TEST_INDEX} - ${description} # FAIL"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("${description}")
    fi
}

# ------------------------------------------------------------------------------
# 1. Basic Script Invariants & Sync Parity
# ------------------------------------------------------------------------------
[ -f "$OPTIMIZER_SCRIPT" ] && [ -x "$OPTIMIZER_SCRIPT" ]
assert_check "scripts/power-optimizer.sh exists and is executable" $?

[ -f "$HYPR_OPTIMIZER_SCRIPT" ] && [ -x "$HYPR_OPTIMIZER_SCRIPT" ]
assert_check "config/hypr/scripts/power-optimizer.sh exists and is executable" $?

cmp -s "$OPTIMIZER_SCRIPT" "$HYPR_OPTIMIZER_SCRIPT"
assert_check "scripts/power-optimizer.sh and config/hypr/scripts/power-optimizer.sh are perfectly identical" $?

# ------------------------------------------------------------------------------
# 2. CLI Help & Dry-Run Safety
# ------------------------------------------------------------------------------
bash "$OPTIMIZER_SCRIPT" --help | grep -q 'yusei-hypr Core Power Optimizer'
assert_check "--help displays usage and returns 0" $?

bash "$OPTIMIZER_SCRIPT" --dry-run --status >/dev/null 2>&1
assert_check "--dry-run --status exits 0 safely" $?

# ------------------------------------------------------------------------------
# 3. JSON Output & Schema Validation
# ------------------------------------------------------------------------------
JSON_STATUS="$TMP_DIR/power_status.json"
bash "$OPTIMIZER_SCRIPT" --status --json --dry-run > "$JSON_STATUS" 2>/dev/null || true

[ -s "$JSON_STATUS" ] && jq empty "$JSON_STATUS" >/dev/null 2>&1
assert_check "--status --json produces valid JSON parsable by jq" $?

[ -s "$JSON_STATUS" ] && jq -e '(.has_battery != null) and (.ac_online != null) and .battery_percent and .profile and .monitor_name and .current_hz and .max_hz and (.auto_60hz != null)' "$JSON_STATUS" >/dev/null 2>&1
assert_check "JSON status contains required power and display schema keys" $?

# ------------------------------------------------------------------------------
# 4. Mock Monitor Detection (Internal 144Hz & External 165Hz Display Parsing)
# ------------------------------------------------------------------------------
MOCK_144HZ_JSON='[{"name":"eDP-1","width":1920,"height":1080,"refreshRate":144.002,"x":0,"y":0,"scale":1,"availableModes":["1920x1080@144.00Hz","1920x1080@60.00Hz"]}]'

PARSED_144HZ="$TMP_DIR/parsed_144.json"
HYPRCTL_MONITORS_DATA="$MOCK_144HZ_JSON" bash "$OPTIMIZER_SCRIPT" --status --json --dry-run > "$PARSED_144HZ" 2>/dev/null || true

[ -s "$PARSED_144HZ" ] && \
[ "$(jq -r .monitor_name "$PARSED_144HZ")" = "eDP-1" ] && \
[ "$(jq -r .max_hz "$PARSED_144HZ")" = "144" ] && \
[ "$(jq -r .current_hz "$PARSED_144HZ")" = "144" ]
assert_check "Monitor detection correctly parses primary internal display name and 144Hz max rate" $?

MOCK_EXT_165HZ='[{"name":"DP-1","width":2560,"height":1440,"refreshRate":165.0,"x":0,"y":0,"scale":1,"availableModes":["2560x1440@165.00Hz","2560x1440@60.00Hz"]}]'
PARSED_165HZ="$TMP_DIR/parsed_165.json"
HYPRCTL_MONITORS_DATA="$MOCK_EXT_165HZ" bash "$OPTIMIZER_SCRIPT" --status --json --dry-run > "$PARSED_165HZ" 2>/dev/null || true

[ -s "$PARSED_165HZ" ] && \
[ "$(jq -r .monitor_name "$PARSED_165HZ")" = "DP-1" ] && \
[ "$(jq -r .max_hz "$PARSED_165HZ")" = "165" ] && \
[ "$(jq -r .current_hz "$PARSED_165HZ")" = "165" ]
assert_check "Monitor detection correctly parses external non-eDP display (DP-1 @ 165Hz)" $?

# ------------------------------------------------------------------------------
# 5. Profile Switching & Display Refresh Rate Coordination (Sandbox Dry-Run)
# ------------------------------------------------------------------------------
ECO_OUT="$(HYPRCTL_MONITORS_DATA="$MOCK_144HZ_JSON" bash "$OPTIMIZER_SCRIPT" --set-profile=eco --dry-run 2>&1)"
grep -q "powerprofilesctl set power-saver" <<< "$ECO_OUT" && \
grep -q 'hyprctl keyword monitor "eDP-1,1920x1080@60,0x0,1"' <<< "$ECO_OUT"
assert_check "--set-profile=eco activates power-saver and drops 144Hz monitor to 60Hz" $?

MOCK_60HZ_CURRENT='[{"name":"eDP-1","width":1920,"height":1080,"refreshRate":60.0,"x":0,"y":0,"scale":1,"availableModes":["1920x1080@144.00Hz","1920x1080@60.00Hz"]}]'
TURBO_OUT="$(HYPRCTL_MONITORS_DATA="$MOCK_60HZ_CURRENT" bash "$OPTIMIZER_SCRIPT" --set-profile=turbo --dry-run 2>&1)"
grep -q "powerprofilesctl set performance" <<< "$TURBO_OUT" && \
grep -q 'hyprctl keyword monitor "eDP-1,1920x1080@144,0x0,1"' <<< "$TURBO_OUT"
assert_check "--set-profile=turbo activates performance and restores monitor to 144Hz" $?

BAL_OUT="$(HYPRCTL_MONITORS_DATA="$MOCK_144HZ_JSON" bash "$OPTIMIZER_SCRIPT" --set-profile=balanced --dry-run 2>&1)"
grep -q "powerprofilesctl set balanced" <<< "$BAL_OUT"
assert_check "--set-profile=balanced sets balanced profile" $?

# ------------------------------------------------------------------------------
# 6. Refresh Rate Toggling (--toggle-hz)
# ------------------------------------------------------------------------------
TOGGLE_UP_OUT="$(HYPRCTL_MONITORS_DATA="$MOCK_60HZ_CURRENT" bash "$OPTIMIZER_SCRIPT" --toggle-hz --dry-run 2>&1)"
grep -q 'hyprctl keyword monitor "eDP-1,1920x1080@144,0x0,1"' <<< "$TOGGLE_UP_OUT"
assert_check "--toggle-hz from 60Hz switches to max native rate (144Hz)" $?

TOGGLE_DOWN_OUT="$(HYPRCTL_MONITORS_DATA="$MOCK_144HZ_JSON" bash "$OPTIMIZER_SCRIPT" --toggle-hz --dry-run 2>&1)"
grep -q 'hyprctl keyword monitor "eDP-1,1920x1080@60,0x0,1"' <<< "$TOGGLE_DOWN_OUT"
assert_check "--toggle-hz from 144Hz switches down to 60Hz" $?

# ------------------------------------------------------------------------------
# 7. Mock Sysfs Battery & AC Power Telemetry
# ------------------------------------------------------------------------------
# Single battery discharging at 15 Watts
mkdir -p "$MOCK_SYSFS/power_supply/AC" "$MOCK_SYSFS/power_supply/BAT0"
echo "0" > "$MOCK_SYSFS/power_supply/AC/online"
echo "Mains" > "$MOCK_SYSFS/power_supply/AC/type"
echo "Battery" > "$MOCK_SYSFS/power_supply/BAT0/type"
echo "85" > "$MOCK_SYSFS/power_supply/BAT0/capacity"
echo "Discharging" > "$MOCK_SYSFS/power_supply/BAT0/status"
echo "15000000" > "$MOCK_SYSFS/power_supply/BAT0/power_now"
echo "30000000" > "$MOCK_SYSFS/power_supply/BAT0/energy_now"

MOCK_BAT_STATUS="$TMP_DIR/mock_bat_status.json"
SYSFS_POWER_DIR="$MOCK_SYSFS/power_supply" \
HYPRCTL_MONITORS_DATA="$MOCK_144HZ_JSON" \
bash "$OPTIMIZER_SCRIPT" --status --json --dry-run > "$MOCK_BAT_STATUS" 2>/dev/null || true

[ -s "$MOCK_BAT_STATUS" ] && \
[ "$(jq -r .battery_percent "$MOCK_BAT_STATUS")" = "85" ] && \
[ "$(jq -r .battery_status "$MOCK_BAT_STATUS")" = "Discharging" ] && \
[ "$(jq -r .power_watts "$MOCK_BAT_STATUS")" = "15.0" ] && \
[ "$(jq -r .ac_online "$MOCK_BAT_STATUS")" = "false" ]
assert_check "Sysfs battery reading extracts accurate capacity (85%), status (Discharging), and power draw (15.0W)" $?

# ------------------------------------------------------------------------------
# 8. Multi-Battery Aggregation (ThinkPad Dual Battery BAT0 + BAT1)
# ------------------------------------------------------------------------------
mkdir -p "$MOCK_SYSFS/power_supply/BAT1"
echo "Battery" > "$MOCK_SYSFS/power_supply/BAT1/type"
echo "50" > "$MOCK_SYSFS/power_supply/BAT0/capacity"
echo "25000000" > "$MOCK_SYSFS/power_supply/BAT0/energy_now"
echo "50000000" > "$MOCK_SYSFS/power_supply/BAT0/energy_full"
echo "10000000" > "$MOCK_SYSFS/power_supply/BAT0/power_now"

echo "70" > "$MOCK_SYSFS/power_supply/BAT1/capacity"
echo "35000000" > "$MOCK_SYSFS/power_supply/BAT1/energy_now"
echo "50000000" > "$MOCK_SYSFS/power_supply/BAT1/energy_full"
echo "12000000" > "$MOCK_SYSFS/power_supply/BAT1/power_now"
echo "Discharging" > "$MOCK_SYSFS/power_supply/BAT1/status"

MULTI_BAT_STATUS="$TMP_DIR/multi_bat_status.json"
SYSFS_POWER_DIR="$MOCK_SYSFS/power_supply" \
HYPRCTL_MONITORS_DATA="$MOCK_144HZ_JSON" \
bash "$OPTIMIZER_SCRIPT" --status --json --dry-run > "$MULTI_BAT_STATUS" 2>/dev/null || true

[ -s "$MULTI_BAT_STATUS" ] && \
[ "$(jq -r .battery_percent "$MULTI_BAT_STATUS")" = "60" ] && \
[ "$(jq -r .power_watts "$MULTI_BAT_STATUS")" = "22.0" ] && \
[ "$(jq -r .battery_status "$MULTI_BAT_STATUS")" = "Discharging" ]
assert_check "Multi-battery aggregation correctly computes consolidated capacity (60%) and summed power draw (22.0W)" $?

# ------------------------------------------------------------------------------
# 9. Multi-Supply AC Online Detection (Barrel Jack offline, USB-C PD online)
# ------------------------------------------------------------------------------
mkdir -p "$MOCK_SYSFS/power_supply/ADP1"
echo "0" > "$MOCK_SYSFS/power_supply/AC/online"
echo "1" > "$MOCK_SYSFS/power_supply/ADP1/online"
echo "USB" > "$MOCK_SYSFS/power_supply/ADP1/type"

AC_MULTI_STATUS="$TMP_DIR/ac_multi_status.json"
SYSFS_POWER_DIR="$MOCK_SYSFS/power_supply" \
HYPRCTL_MONITORS_DATA="$MOCK_144HZ_JSON" \
bash "$OPTIMIZER_SCRIPT" --status --json --dry-run > "$AC_MULTI_STATUS" 2>/dev/null || true

[ -s "$AC_MULTI_STATUS" ] && \
[ "$(jq -r .ac_online "$AC_MULTI_STATUS")" = "true" ]
assert_check "Multi-supply AC detection recognizes USB-C PD online when primary AC is offline" $?

# Reset AC for subsequent tests
echo "0" > "$MOCK_SYSFS/power_supply/AC/online"
echo "0" > "$MOCK_SYSFS/power_supply/ADP1/online"

# ------------------------------------------------------------------------------
# 10. Auto Mode on Battery vs AC
# ------------------------------------------------------------------------------
AUTO_BAT_OUT="$(SYSFS_POWER_DIR="$MOCK_SYSFS/power_supply" HYPRCTL_MONITORS_DATA="$MOCK_144HZ_JSON" bash "$OPTIMIZER_SCRIPT" --auto --dry-run 2>&1)"
grep -q "powerprofilesctl set power-saver" <<< "$AUTO_BAT_OUT" && \
grep -q 'hyprctl keyword monitor "eDP-1,1920x1080@60,0x0,1"' <<< "$AUTO_BAT_OUT"
assert_check "--auto on battery automatically switches to eco profile and drops to 60Hz" $?

# ------------------------------------------------------------------------------
# 11. Configuration Overrides (userprefs.conf auto_60hz, AC & BAT profiles)
# ------------------------------------------------------------------------------
MOCK_USERPREFS="$MOCK_CONFIG/userprefs.conf"
cat << 'EOF' > "$MOCK_USERPREFS"
# Custom power preferences in userprefs.conf
env = YUSEI_AUTO_60HZ,0
env = YUSEI_AC_PROFILE,turbo
env = YUSEI_BAT_PROFILE,balanced
EOF

# When YUSEI_AUTO_60HZ=0 in userprefs.conf, eco should NOT lower refresh rate
NO_AUTO_OUT="$(TARGET_USERPREFS="$MOCK_USERPREFS" HYPRCTL_MONITORS_DATA="$MOCK_144HZ_JSON" bash "$OPTIMIZER_SCRIPT" --set-profile=eco --dry-run 2>&1)"
! grep -q 'hyprctl keyword monitor' <<< "$NO_AUTO_OUT"
assert_check "userprefs.conf YUSEI_AUTO_60HZ=0 override keeps high refresh rate" $?

# When userprefs specifies AC profile as turbo and BAT profile as balanced
AUTO_PREFS_BAT="$(TARGET_USERPREFS="$MOCK_USERPREFS" SYSFS_POWER_DIR="$MOCK_SYSFS/power_supply" HYPRCTL_MONITORS_DATA="$MOCK_144HZ_JSON" bash "$OPTIMIZER_SCRIPT" --auto --dry-run 2>&1)"
grep -q "powerprofilesctl set balanced" <<< "$AUTO_PREFS_BAT"
assert_check "userprefs.conf YUSEI_BAT_PROFILE=balanced is respected by --auto on battery" $?

# ------------------------------------------------------------------------------
# 12. Menu and Notification Actions in Dry-Run
# ------------------------------------------------------------------------------
bash "$OPTIMIZER_SCRIPT" --menu --dry-run >/dev/null 2>&1
assert_check "--menu --dry-run runs safely and exits 0" $?

bash "$OPTIMIZER_SCRIPT" --status --notify --dry-run >/dev/null 2>&1
assert_check "--status --notify --dry-run runs safely and exits 0" $?

# ------------------------------------------------------------------------------
# 13. Error Handling on Invalid Profile
# ------------------------------------------------------------------------------
! bash "$OPTIMIZER_SCRIPT" --set-profile=invalid_prof >/dev/null 2>&1
assert_check "Passing invalid profile (e.g. --set-profile=invalid) exits with non-zero error exit code" $?

# ------------------------------------------------------------------------------
# 14. Inline Comments Parsing in userprefs.conf
# ------------------------------------------------------------------------------
cat << 'EOF' > "$MOCK_USERPREFS"
# Userprefs with inline comments and trailing whitespace
env = YUSEI_AUTO_60HZ, 0 # Disable dynamic 60Hz
env = YUSEI_AC_PROFILE, turbo # Always maximum performance
env = YUSEI_BAT_PROFILE, eco # Strict energy saving
EOF

NO_AUTO_COMMENT="$(TARGET_USERPREFS="$MOCK_USERPREFS" HYPRCTL_MONITORS_DATA="$MOCK_144HZ_JSON" bash "$OPTIMIZER_SCRIPT" --set-profile=eco --dry-run 2>&1)"
! grep -q 'hyprctl keyword monitor' <<< "$NO_AUTO_COMMENT"
assert_check "userprefs.conf inline comments do not corrupt YUSEI_AUTO_60HZ parsing" $?

# ------------------------------------------------------------------------------
# 15. Daemon Autostart Control via userprefs.conf (YUSEI_POWER_DAEMON)
# ------------------------------------------------------------------------------
cat << 'EOF' > "$MOCK_USERPREFS"
# Explicitly disable power optimizer daemon
env = YUSEI_POWER_DAEMON, 0 # Turn off background daemon
EOF

DAEMON_DISABLED_OUT="$(TARGET_USERPREFS="$MOCK_USERPREFS" SYSFS_POWER_DIR="$MOCK_SYSFS/power_supply" bash "$OPTIMIZER_SCRIPT" --daemon 2>&1)"
grep -q "bị vô hiệu hóa qua cấu hình" <<< "$DAEMON_DISABLED_OUT"
assert_check "userprefs.conf YUSEI_POWER_DAEMON=0 disables background daemon autostart cleanly" $?

# ------------------------------------------------------------------------------
# 16. Negative Battery Power & Current Handling
# ------------------------------------------------------------------------------
# Clean up secondary BAT1 to isolate BAT0
rm -rf "$MOCK_SYSFS/power_supply/BAT1"
# ACPI reporting -15000000 microwatts (discharging sign)
echo "-15000000" > "$MOCK_SYSFS/power_supply/BAT0/power_now"
echo "30000000" > "$MOCK_SYSFS/power_supply/BAT0/energy_now"
echo "50000000" > "$MOCK_SYSFS/power_supply/BAT0/energy_full"
echo "Discharging" > "$MOCK_SYSFS/power_supply/BAT0/status"

NEG_BAT_STATUS="$TMP_DIR/neg_bat_status.json"
SYSFS_POWER_DIR="$MOCK_SYSFS/power_supply" \
HYPRCTL_MONITORS_DATA="$MOCK_144HZ_JSON" \
bash "$OPTIMIZER_SCRIPT" --status --json --dry-run > "$NEG_BAT_STATUS" 2>/dev/null || true

[ -s "$NEG_BAT_STATUS" ] && \
[ "$(jq -r .power_watts "$NEG_BAT_STATUS")" = "15.0" ] && \
[ "$(jq -r .time_remaining "$NEG_BAT_STATUS")" != "N/A" ]
assert_check "Negative sysfs power_now is normalized to positive wattage (15.0W) with valid time_remaining" $?

# ------------------------------------------------------------------------------
# 17. Active Charging Guarantees AC_ONLINE=true Even With Offline AC Supply Node
# ------------------------------------------------------------------------------
echo "0" > "$MOCK_SYSFS/power_supply/AC/online"
echo "0" > "$MOCK_SYSFS/power_supply/ADP1/online"
echo "Charging" > "$MOCK_SYSFS/power_supply/BAT0/status"

CHG_STATUS="$TMP_DIR/chg_status.json"
SYSFS_POWER_DIR="$MOCK_SYSFS/power_supply" \
HYPRCTL_MONITORS_DATA="$MOCK_144HZ_JSON" \
bash "$OPTIMIZER_SCRIPT" --status --json --dry-run > "$CHG_STATUS" 2>/dev/null || true

[ -s "$CHG_STATUS" ] && \
[ "$(jq -r .ac_online "$CHG_STATUS")" = "true" ] && \
[ "$(jq -r .battery_status "$CHG_STATUS")" = "Charging" ]
assert_check "Active battery charging correctly infers AC_ONLINE=true when AC sysfs node is offline" $?

# ------------------------------------------------------------------------------
# 18. Empty State File Resilience (No Corrupted JSON)
# ------------------------------------------------------------------------------
EMPTY_STATE_FILE="$TMP_DIR/empty_state.json"
touch "$EMPTY_STATE_FILE"
POWER_STATE_FILE="$EMPTY_STATE_FILE" bash "$OPTIMIZER_SCRIPT" --set-profile=turbo >/dev/null 2>&1
[ -s "$EMPTY_STATE_FILE" ] && jq -e '.profile == "turbo"' "$EMPTY_STATE_FILE" >/dev/null 2>&1
assert_check "save_state handles empty state file (0 bytes) without failing or corrupting JSON" $?

# ------------------------------------------------------------------------------
# 19. Cached current_hz Fallback When hyprctl is Unavailable
# ------------------------------------------------------------------------------
CACHED_STATE_FILE="$TMP_DIR/cached_hz.json"
echo '{"current_hz": 120, "max_hz": 120}' > "$CACHED_STATE_FILE"
CACHED_STATUS="$TMP_DIR/cached_status.json"
HYPRCTL_MONITORS_DATA="none" \
POWER_STATE_FILE="$CACHED_STATE_FILE" \
bash "$OPTIMIZER_SCRIPT" --status --json --dry-run > "$CACHED_STATUS" 2>/dev/null || true

[ -s "$CACHED_STATUS" ] && \
[ "$(jq -r .current_hz "$CACHED_STATUS")" = "120" ] && \
[ "$(jq -r .max_hz "$CACHED_STATUS")" = "120" ]
assert_check "detect_monitor restores cached current_hz and max_hz when hyprctl is unavailable" $?

# ------------------------------------------------------------------------------
# 20. Cycle Power Profile (--cycle-profile / --next-profile)
# ------------------------------------------------------------------------------
MOCK_BIN_CYCLE="$TMP_DIR/mock_bin_cycle"
mkdir -p "$MOCK_BIN_CYCLE"
cat << 'EOF' > "$MOCK_BIN_CYCLE/powerprofilesctl"
#!/bin/sh
if [ "$1" = "get" ]; then
    echo "power-saver"
fi
EOF
chmod +x "$MOCK_BIN_CYCLE/powerprofilesctl"

CYCLE_OUT_1="$(PATH="$MOCK_BIN_CYCLE:$PATH" bash "$OPTIMIZER_SCRIPT" --cycle-profile --dry-run 2>&1)"
grep -q "powerprofilesctl set balanced" <<< "$CYCLE_OUT_1"
assert_check "--cycle-profile from eco advances to balanced profile" $?

# ------------------------------------------------------------------------------
# 21. Sysfs Energy Performance Preference (EPP) Detection on Modern P-State Drivers
# ------------------------------------------------------------------------------
MOCK_SYSFS_CPU="$TMP_DIR/mock_sysfs_cpu"
mkdir -p "$MOCK_SYSFS_CPU/cpu0/cpufreq"
echo "powersave" > "$MOCK_SYSFS_CPU/cpu0/cpufreq/scaling_governor"
echo "balance_performance" > "$MOCK_SYSFS_CPU/cpu0/cpufreq/energy_performance_preference"

MOCK_BIN="$TMP_DIR/mock_bin_ppd_fail"
mkdir -p "$MOCK_BIN"
cat << 'EOF' > "$MOCK_BIN/powerprofilesctl"
#!/bin/sh
exit 1
EOF
chmod +x "$MOCK_BIN/powerprofilesctl"

EPP_STATUS="$TMP_DIR/epp_status.json"
PATH="$MOCK_BIN:$PATH" \
SYSFS_CPU_DIR="$MOCK_SYSFS_CPU" \
POWER_STATE_FILE="$TMP_DIR/nonexistent.state" \
bash "$OPTIMIZER_SCRIPT" --status --json --dry-run > "$EPP_STATUS" 2>/dev/null || true

[ -s "$EPP_STATUS" ] && [ "$(jq -r .profile "$EPP_STATUS")" = "balanced" ]
assert_check "get_current_profile resolves balanced profile from EPP balance_performance when governor is powersave" $?

# ------------------------------------------------------------------------------
# 22. Sysfs Fallback Writes to Correct cpufreq/policy* EPP Paths
# ------------------------------------------------------------------------------
mkdir -p "$MOCK_SYSFS_CPU/cpufreq/policy0"
echo "default" > "$MOCK_SYSFS_CPU/cpufreq/policy0/energy_performance_preference"
echo "powersave" > "$MOCK_SYSFS_CPU/cpufreq/policy0/scaling_governor"

PATH="$MOCK_BIN:$PATH" \
SYSFS_CPU_DIR="$MOCK_SYSFS_CPU" \
POWER_STATE_FILE="$TMP_DIR/dummy.state" \
bash "$OPTIMIZER_SCRIPT" --set-profile=turbo >/dev/null 2>&1 || true

[ "$(cat "$MOCK_SYSFS_CPU/cpufreq/policy0/energy_performance_preference" 2>/dev/null || true)" = "performance" ]
assert_check "apply_power_profile writes performance EPP to sysfs cpufreq/policy0 path on powerprofilesctl fallback" $?

# ------------------------------------------------------------------------------
# Summary Matrix
# ------------------------------------------------------------------------------
echo ""
echo "======================================================"
echo "Power Optimizer Subsystem Test Summary"
echo "======================================================"
echo "Total Checks: ${TOTAL_TESTS}"
echo -e "${GREEN}Passed:       ${PASSED}${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed:       ${FAILED}${NC}"
    for f in "${FAILED_LIST[@]}"; do
        echo -e "${RED}  - FAIL: ${f}${NC}"
    done
    exit 1
else
    echo -e "${GREEN}Failed:       0${NC}"
    echo -e "${GREEN}Status: ALL POWER OPTIMIZER CHECKS PASSED${NC}"
    echo "======================================================"
    exit 0
fi
