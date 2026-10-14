#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Documentation & Licensing Verification Test Suite
# ==============================================================================
# - Verifies LICENSE existence and GNU General Public License v3.0 text
# - Verifies README.md has GPL-3.0 badge and NO MIT badge
# - Verifies README.md contains ## 📜 License section
# - Verifies README.md contains updated architecture tree (userprefs, hardware-detect, update, uninstall, tests/, no assets/icons)
# - Verifies README.md contains keybinding cheat sheet table (Super+Tab, Alt+Tab, Fn keys)
# - Verifies README.md contains operational guides for update.sh, uninstall.sh, yusei_settings
# - Verifies README.md keybindings strictly match keybinds.conf (Super+Space floating, Super+D launcher, Super+Shift+F fullscreen, no Super+V floating)
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

echo -e "${BLUE}${BOLD}:: [Test Suite] Documentation & Licensing Verification${NC}"
echo -e "   Target Directory: ${REPO_ROOT}"

LICENSE_FILE="$REPO_ROOT/LICENSE"
README_FILE="$REPO_ROOT/README.md"

TOTAL_TESTS=24
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
# 1. LICENSE File Tests
# ------------------------------------------------------------------------------
assert_check "LICENSE file exists in repository root" \
    "[ -f '$LICENSE_FILE' ]"

assert_check "LICENSE contains GNU General Public License v3.0 header" \
    "grep -qi 'GNU GENERAL PUBLIC LICENSE' '$LICENSE_FILE' 2>/dev/null"

assert_check "LICENSE specifies Version 3, 29 June 2007" \
    "grep -qi 'Version 3, 29 June 2007' '$LICENSE_FILE' 2>/dev/null"

assert_check "LICENSE contains copyright notice" \
    "grep -qiE 'Copyright \(C\).*yusei-hypr' '$LICENSE_FILE' 2>/dev/null || grep -qi 'Copyright (C)' '$LICENSE_FILE' 2>/dev/null"

assert_check "LICENSE contains full terms and conditions text" \
    "grep -qi 'TERMS AND CONDITIONS' '$LICENSE_FILE' 2>/dev/null && grep -qi 'END OF TERMS AND CONDITIONS' '$LICENSE_FILE' 2>/dev/null"

# ------------------------------------------------------------------------------
# 2. README.md Licensing Tests
# ------------------------------------------------------------------------------
assert_check "README.md exists in repository root" \
    "[ -f '$README_FILE' ]"

assert_check "README.md does NOT contain deprecated MIT license badge" \
    "! grep -qiE 'badge/License-MIT|License: MIT' '$README_FILE' 2>/dev/null"

assert_check "README.md contains GPL-3.0 license badge" \
    "grep -qiE 'badge/License-GPL.*3|License: GPL-3.0|GPL--3.0' '$README_FILE' 2>/dev/null"

assert_check "README.md contains dedicated License section" \
    "grep -qE '^## .*License' '$README_FILE' 2>/dev/null"

# ------------------------------------------------------------------------------
# 3. README.md Architectural & Operational Documentation Tests
# ------------------------------------------------------------------------------
assert_check "README.md architecture diagram references userprefs.conf" \
    "grep -qi 'userprefs\.conf' '$README_FILE' 2>/dev/null"

assert_check "README.md architecture diagram references scripts/hardware-detect.sh" \
    "grep -qiE 'hardware-detect\.sh' '$README_FILE' 2>/dev/null"

assert_check "README.md architecture diagram references update.sh and uninstall.sh" \
    "grep -qi 'update\.sh' '$README_FILE' 2>/dev/null && grep -qi 'uninstall\.sh' '$README_FILE' 2>/dev/null"

assert_check "README.md keybinding table covers Super + Tab and Alt + Tab" \
    "grep -qiE 'Super \+ Tab|Super\+Tab' '$README_FILE' 2>/dev/null && grep -qiE 'Alt \+ Tab|Alt\+Tab' '$README_FILE' 2>/dev/null"

assert_check "README.md keybinding reference covers multimedia / Fn keys" \
    "grep -qiE 'XF86Audio|Volume|Brightness|XF86MonBrightness' '$README_FILE' 2>/dev/null"

assert_check "README.md contains operational guides for update.sh and uninstall.sh" \
    "grep -qi 'update\.sh' '$README_FILE' 2>/dev/null && grep -qi 'uninstall\.sh' '$README_FILE' 2>/dev/null && grep -qiE 'cập nhật|update|restore|backup' '$README_FILE' 2>/dev/null"

assert_check "README.md documents yusei_settings features (Theming, Keybinds Cheat Sheet, Maintenance)" \
    "grep -qi 'yusei_settings' '$README_FILE' 2>/dev/null && (grep -qiE 'Keybind|Cheat Sheet|phím tắt' '$README_FILE' 2>/dev/null)"

# ------------------------------------------------------------------------------
# 4. README.md Keybinding & Architecture Fidelity Tests
# ------------------------------------------------------------------------------
assert_check "README.md architecture diagram references tests/ directory and test runner" \
    "grep -qiE 'tests/' '$README_FILE' 2>/dev/null && grep -qiE 'run-all-tests\.sh' '$README_FILE' 2>/dev/null"

assert_check "README.md architecture diagram does NOT reference non-existent assets/icons" \
    "! grep -qiE 'assets/icons' '$README_FILE' 2>/dev/null"

assert_check "README.md documents Super + Space for floating" \
    "grep -i 'togglefloating' '$README_FILE' | grep -qiE 'Super.*\+.*Space'"

assert_check "README.md does NOT document Super + V as floating" \
    "! (grep -i 'togglefloating' '$README_FILE' | grep -qiE 'Super.*\+.*V[ <|]')"

assert_check "README.md documents Super + D for application launcher" \
    "grep -iE 'launcher|rofi' '$README_FILE' | grep -qiE 'Super.*\+.*D[ <|]'"

assert_check "README.md does NOT document Super + Space as launcher" \
    "! (grep -iE 'Application Launcher|rofi.*launcher' '$README_FILE' | grep -qiE 'Super.*\+.*Space')"

assert_check "README.md documents Super + Shift + F for fullscreen" \
    "grep -iE 'fullscreen' '$README_FILE' | grep -qiE 'Super.*\+.*Shift.*\+.*F'"

assert_check "README.md does NOT document Super + F as standalone fullscreen" \
    "! (grep -iE 'fullscreen, 0|true fullscreen' '$README_FILE' | grep -qiE '\| <kbd>Super</kbd> \+ <kbd>F</kbd> \|')"

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}Documentation & Licensing Verification Summary${NC}"
echo -e "${BOLD}======================================================${NC}"
echo -e "Total Checks: ${TOTAL_TESTS}"
echo -e "Passed:       ${GREEN}${PASSED}${NC}"
if [[ $FAILED -gt 0 ]]; then
    echo -e "Failed:       ${RED}${FAILED}${NC}"
    echo -e "\n${YELLOW}Note: Pending milestone implementations may cause some checks to fail until M4 completes.${NC}"
    echo -e "${RED}Unsatisfied requirements:${NC}"
    for item in "${FAILED_LIST[@]}"; do
        echo -e "  - ${RED}${item}${NC}"
    done
    echo -e "${BOLD}======================================================${NC}"
    exit 1
else
    echo -e "Failed:       0"
    echo -e "${GREEN}${BOLD}Status: ALL DOCUMENTATION & LICENSING CHECKS PASSED${NC}"
    echo -e "${BOLD}======================================================${NC}"
    exit 0
fi
