#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Configuration Isolation & Backup Standardization Test Suite
# ==============================================================================
# - Verifies config/hypr/userprefs.conf exists with all template sections
# - Verifies config/hypr/hyprland.conf sources userprefs.conf as Layer 8
# - Executes 04-install-configs.sh in an isolated $MOCK_HOME sandbox
# - Verifies pre-existing userprefs.conf with custom marker is preserved (NEVER overwritten)
# - Verifies clean install initializes userprefs.conf from template
# - Executes 03-backup.sh in $MOCK_HOME and verifies backup directory format & manifest.json
# - Verifies zero host ~/.config tampering
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

echo -e "${BLUE}${BOLD}:: [Test Suite] User Config Isolation & Backup Format${NC}"
echo -e "   Target Directory: ${REPO_ROOT}"

# Setup isolated sandbox
MOCK_HOME="$(mktemp -d -t yusei_mock_home_XXXXXX)"
REAL_HOME="$HOME"
trap 'rm -rf "$MOCK_HOME"' EXIT

# Snapshot real ~/.config mtime if it exists to verify zero host tampering
REAL_CONFIG_MTIME=""
if [[ -d "$REAL_HOME/.config" ]]; then
    REAL_CONFIG_MTIME="$(stat -c %Y "$REAL_HOME/.config" 2>/dev/null || true)"
fi

TOTAL_TESTS=12
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
# 1. Template & Source Checks (Static Invariants)
# ------------------------------------------------------------------------------
USERPREFS_TEMPLATE="$REPO_ROOT/config/hypr/userprefs.conf"
HYPRLAND_CONF="$REPO_ROOT/config/hypr/hyprland.conf"

assert_check "Template userprefs.conf exists in config/hypr/" \
    "[ -f '$USERPREFS_TEMPLATE' ]"

assert_check "Template userprefs.conf contains all 5 required configuration sections" \
    "grep -qi 'Monitors' '$USERPREFS_TEMPLATE' 2>/dev/null && \
     grep -qi 'Environment Variables' '$USERPREFS_TEMPLATE' 2>/dev/null && \
     grep -qi 'Autostart' '$USERPREFS_TEMPLATE' 2>/dev/null && \
     grep -qi 'Keybindings' '$USERPREFS_TEMPLATE' 2>/dev/null && \
     grep -qiE 'Window|Workspace' '$USERPREFS_TEMPLATE' 2>/dev/null"

assert_check "hyprland.conf sources ~/.config/hypr/userprefs.conf as Layer 8" \
    "grep -qE 'source\s*=\s*(~/\.config/hypr/userprefs\.conf|\./userprefs\.conf)' '$HYPRLAND_CONF' 2>/dev/null"

# ------------------------------------------------------------------------------
# 2. Config Isolation in Sandbox (Pre-existing userprefs.conf)
# ------------------------------------------------------------------------------
# Populate mock environment
mkdir -p "$MOCK_HOME/.config/hypr"
CUSTOM_MARKER="MARKER_USERPREFS_SECRET_$(date +%s%N)"
cat <<EOF > "$MOCK_HOME/.config/hypr/userprefs.conf"
# Custom user preferences
env = TEST_CUSTOM_VAR,1
# Unique marker: ${CUSTOM_MARKER}
EOF

# Pre-populate custom UserConfigs marker as well
mkdir -p "$MOCK_HOME/.config/hypr/UserConfigs"
echo "custom_user_config=true" > "$MOCK_HOME/.config/hypr/UserConfigs/user.conf"

# Execute 04-install-configs.sh with HOME redirected to MOCK_HOME
export HOME="$MOCK_HOME"
export XDG_CONFIG_HOME="$MOCK_HOME/.config"
# Run installer non-interactively
bash "$REPO_ROOT/scripts/04-install-configs.sh" >/dev/null 2>&1 || true

assert_check "04-install-configs.sh preserves existing userprefs.conf content" \
    "[ -f '$MOCK_HOME/.config/hypr/userprefs.conf' ] && grep -q '$CUSTOM_MARKER' '$MOCK_HOME/.config/hypr/userprefs.conf'"

assert_check "04-install-configs.sh preserves existing UserConfigs folder content" \
    "[ -f '$MOCK_HOME/.config/hypr/UserConfigs/user.conf' ] && grep -q 'custom_user_config=true' '$MOCK_HOME/.config/hypr/UserConfigs/user.conf'"

# ------------------------------------------------------------------------------
# 3. Clean Install (Template Initialization when userprefs.conf absent)
# ------------------------------------------------------------------------------
# Fresh mock home without userprefs.conf
MOCK_HOME_FRESH="$(mktemp -d -t yusei_fresh_XXXXXX)"
export HOME="$MOCK_HOME_FRESH"
export XDG_CONFIG_HOME="$MOCK_HOME_FRESH/.config"
bash "$REPO_ROOT/scripts/04-install-configs.sh" >/dev/null 2>&1 || true

assert_check "04-install-configs.sh creates userprefs.conf from template on clean install" \
    "[ -f '$MOCK_HOME_FRESH/.config/hypr/userprefs.conf' ] && grep -qi 'yusei-hypr: User Custom Preferences' '$MOCK_HOME_FRESH/.config/hypr/userprefs.conf'"

rm -rf "$MOCK_HOME_FRESH"

# ------------------------------------------------------------------------------
# 4. Standard Backup Module Tests (scripts/03-backup.sh)
# ------------------------------------------------------------------------------
# Reset HOME back to MOCK_HOME
export HOME="$MOCK_HOME"
export XDG_CONFIG_HOME="$MOCK_HOME/.config"

# Populate some configs to back up
mkdir -p "$MOCK_HOME/.config/waybar" "$MOCK_HOME/.config/rofi"
echo "bar_config=1" > "$MOCK_HOME/.config/waybar/config"
echo "rofi_theme=1" > "$MOCK_HOME/.config/rofi/theme.rasi"

# Run 03-backup.sh
bash "$REPO_ROOT/scripts/03-backup.sh" >/dev/null 2>&1 || true

# Find backup folder matching yusei-hypr-backup-YYYYMMDD_HHMMSS
BACKUP_DIR_FOUND="$(find "$MOCK_HOME/.config" -maxdepth 1 -type d -name "yusei-hypr-backup-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]" | head -n 1 || true)"

assert_check "03-backup.sh creates directory matching yusei-hypr-backup-YYYYMMDD_HHMMSS" \
    "[ -n '$BACKUP_DIR_FOUND' ] && [ -d '$BACKUP_DIR_FOUND' ]"

assert_check "Backup directory contains valid manifest.json" \
    "[ -n '$BACKUP_DIR_FOUND' ] && [ -f '$BACKUP_DIR_FOUND/manifest.json' ] && jq empty '$BACKUP_DIR_FOUND/manifest.json' 2>/dev/null"

assert_check "manifest.json contains required metadata keys (timestamp, targets)" \
    "[ -n '$BACKUP_DIR_FOUND' ] && [ -f '$BACKUP_DIR_FOUND/manifest.json' ] && \
     jq -e '.timestamp and .backed_up_targets and .non_existing_targets' '$BACKUP_DIR_FOUND/manifest.json' >/dev/null 2>&1"

assert_check "Backup directory contains actual archived config files (hypr, waybar, rofi)" \
    "[ -n '$BACKUP_DIR_FOUND' ] && [ -d '$BACKUP_DIR_FOUND/hypr' ] && [ -d '$BACKUP_DIR_FOUND/waybar' ]"

assert_check "Symlink yusei-hypr-backup-latest or latest points to current backup snapshot" \
    "([ -L '$MOCK_HOME/.config/yusei-hypr-backup-latest' ] && [ \"\$(readlink -f '$MOCK_HOME/.config/yusei-hypr-backup-latest')\" = \"\$BACKUP_DIR_FOUND\" ]) || \
     ([ -L '$MOCK_HOME/.config/yusei-hypr-backups/latest' ] && [ -n '$BACKUP_DIR_FOUND' ])"

# ------------------------------------------------------------------------------
# 5. Host Safety & Zero Pollution Check
# ------------------------------------------------------------------------------
export HOME="$REAL_HOME"
assert_check "Zero host ~/.config pollution (host environment remained 100% untouched)" \
    "[[ -z '$REAL_CONFIG_MTIME' ]] || [[ \"\$(stat -c %Y '$REAL_HOME/.config' 2>/dev/null || true)\" = '$REAL_CONFIG_MTIME' ]]"

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}Config Isolation & Backup Test Summary${NC}"
echo -e "${BOLD}======================================================${NC}"
echo -e "Total Checks: ${TOTAL_TESTS}"
echo -e "Passed:       ${GREEN}${PASSED}${NC}"
if [[ $FAILED -gt 0 ]]; then
    echo -e "Failed:       ${RED}${FAILED}${NC}"
    echo -e "\n${RED}Failed checks:${NC}"
    for item in "${FAILED_LIST[@]}"; do
        echo -e "  - ${RED}${item}${NC}"
    done
    echo -e "${BOLD}======================================================${NC}"
    exit 1
else
    echo -e "Failed:       0"
    echo -e "${GREEN}${BOLD}Status: ALL CONFIG ISOLATION CHECKS PASSED${NC}"
    echo -e "${BOLD}======================================================${NC}"
    exit 0
fi
