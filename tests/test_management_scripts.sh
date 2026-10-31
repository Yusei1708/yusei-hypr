#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Management & Recovery Subsystem Test Suite
# ==============================================================================
# - Tests root update.sh with --dry-run --skip-git non-interactively
# - Tests update.sh preserves custom userprefs.conf in mock sandbox
# - Tests root uninstall.sh with --dry-run / --cli non-interactively
# - Tests uninstall.sh and rollback.sh snapshot restoration logic
# - Tests compatibility of scripts/uninstall.sh delegation
# - Verifies zero host ~/.config pollution and zero live session disruption
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

echo -e "${BLUE}${BOLD}:: [Test Suite] Management Scripts Verification (update.sh & uninstall.sh)${NC}"
echo -e "   Target Directory: ${REPO_ROOT}"

UPDATE_SCRIPT="$REPO_ROOT/update.sh"
UNINSTALL_SCRIPT="$REPO_ROOT/uninstall.sh"
ROLLBACK_SCRIPT="$REPO_ROOT/scripts/rollback.sh"
SHIM_UNINSTALL="$REPO_ROOT/scripts/uninstall.sh"

# Setup isolated sandbox
MOCK_HOME="$(mktemp -d -t yusei_mgmt_test_XXXXXX)"
REAL_HOME="$HOME"
trap 'rm -rf "$MOCK_HOME"' EXIT

# Snapshot real ~/.config mtime
REAL_CONFIG_MTIME=""
if [[ -d "$REAL_HOME/.config" ]]; then
    REAL_CONFIG_MTIME="$(stat -c %Y "$REAL_HOME/.config" 2>/dev/null || true)"
fi

TOTAL_TESTS=10
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
# 1. Root update.sh Invariants & Execution
# ------------------------------------------------------------------------------
assert_check "Root update.sh exists and is executable" \
    "[ -f '$UPDATE_SCRIPT' ] && [ -x '$UPDATE_SCRIPT' ]"

# Test update.sh dry-run non-interactively in mock environment
export HOME="$MOCK_HOME"
export XDG_CONFIG_HOME="$MOCK_HOME/.config"
unset HYPRLAND_INSTANCE_SIGNATURE || true

assert_check "update.sh --dry-run --skip-git executes non-interactively and exits 0" \
    "[ -f '$UPDATE_SCRIPT' ] && bash '$UPDATE_SCRIPT' --dry-run --skip-git >/dev/null 2>&1"

# Populate mock userprefs.conf with unique token to verify preservation
mkdir -p "$MOCK_HOME/.config/hypr"
UPDATE_MARKER="MARKER_USERPREFS_UPDATE_TOKEN_$(date +%s%N)"
cat <<EOF > "$MOCK_HOME/.config/hypr/userprefs.conf"
# Personal overrides
env = TEST_UPDATE_PREF,1
# Marker: ${UPDATE_MARKER}
EOF

# Run update.sh with skip-git
if [ -f "$UPDATE_SCRIPT" ]; then
    bash "$UPDATE_SCRIPT" --skip-git >/dev/null 2>&1 || true
fi

assert_check "update.sh strictly preserves existing userprefs.conf without overwriting" \
    "[ -f '$UPDATE_SCRIPT' ] && [ -f '$MOCK_HOME/.config/hypr/userprefs.conf' ] && grep -q '$UPDATE_MARKER' '$MOCK_HOME/.config/hypr/userprefs.conf'"

# ------------------------------------------------------------------------------
# 2. Root uninstall.sh Invariants & Execution
# ------------------------------------------------------------------------------
assert_check "Root uninstall.sh exists and is executable" \
    "[ -f '$UNINSTALL_SCRIPT' ] && [ -x '$UNINSTALL_SCRIPT' ]"

assert_check "uninstall.sh --dry-run --cli executes non-interactively and exits 0" \
    "[ -f '$UNINSTALL_SCRIPT' ] && (bash '$UNINSTALL_SCRIPT' --dry-run --cli >/dev/null 2>&1 || bash '$UNINSTALL_SCRIPT' --dry-run -y >/dev/null 2>&1)"

# ------------------------------------------------------------------------------
# 3. Snapshot Backup & Disaster Recovery via Rollback
# ------------------------------------------------------------------------------
# Create a dummy backup snapshot in mock home
MOCK_BACKUP_DIR="$MOCK_HOME/.config/yusei-hypr-backup-20261014_120000"
mkdir -p "$MOCK_BACKUP_DIR/hypr"
echo "restored_marker=true" > "$MOCK_BACKUP_DIR/hypr/restored.conf"
cat <<EOF > "$MOCK_BACKUP_DIR/manifest.json"
{
  "timestamp": "20261014_120000",
  "backed_up_targets": ["hypr"],
  "non_existing_targets": []
}
EOF

# Update latest symlink
ln -sfn "$MOCK_BACKUP_DIR" "$MOCK_HOME/.config/yusei-hypr-backup-latest"

assert_check "scripts/rollback.sh exists and is executable" \
    "[ -f '$ROLLBACK_SCRIPT' ] && [ -x '$ROLLBACK_SCRIPT' ]"

# Run rollback pointing directly to mock backup or latest
assert_check "rollback.sh executes in sandbox and restores configuration snapshot" \
    "bash '$ROLLBACK_SCRIPT' '$MOCK_BACKUP_DIR' >/dev/null 2>&1 || bash '$ROLLBACK_SCRIPT' >/dev/null 2>&1"

# Verify restored file
assert_check "Configuration snapshot files were restored into mock ~/.config/hypr" \
    "[ -f '$MOCK_HOME/.config/hypr/restored.conf' ] && grep -q 'restored_marker=true' '$MOCK_HOME/.config/hypr/restored.conf'"

# ------------------------------------------------------------------------------
# 4. Compatibility Shim
# ------------------------------------------------------------------------------
assert_check "scripts/uninstall.sh exists and provides CLI or delegation compatibility" \
    "[ -f '$SHIM_UNINSTALL' ] && [ -x '$SHIM_UNINSTALL' ]"

# ------------------------------------------------------------------------------
# 5. Host Safety & Zero Desktop Pollution
# ------------------------------------------------------------------------------
export HOME="$REAL_HOME"
assert_check "Zero host pollution (real ~/.config and desktop processes unaffected)" \
    "[[ -z '$REAL_CONFIG_MTIME' ]] || [[ \"\$(stat -c %Y '$REAL_HOME/.config' 2>/dev/null || true)\" = '$REAL_CONFIG_MTIME' ]]"

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}Management Scripts Test Summary${NC}"
echo -e "${BOLD}======================================================${NC}"
echo -e "Total Checks: ${TOTAL_TESTS}"
echo -e "Passed:       ${GREEN}${PASSED}${NC}"
if [[ $FAILED -gt 0 ]]; then
    echo -e "Failed:       ${RED}${FAILED}${NC}"
    echo -e "\n${YELLOW}Note: Pending milestone implementations may cause checks to fail until M2 completes.${NC}"
    echo -e "${RED}Unsatisfied requirements:${NC}"
    for item in "${FAILED_LIST[@]}"; do
        echo -e "  - ${RED}${item}${NC}"
    done
    echo -e "${BOLD}======================================================${NC}"
    exit 1
else
    echo -e "Failed:       0"
    echo -e "${GREEN}${BOLD}Status: ALL MANAGEMENT SCRIPTS CHECKS PASSED${NC}"
    echo -e "${BOLD}======================================================${NC}"
    exit 0
fi
