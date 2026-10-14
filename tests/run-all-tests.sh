#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Master Test Runner (E2E Test Harness)
# ==============================================================================
# Executes all test suites across the repository:
# 1. tests/test_syntax.sh (Static bash -n & jq JSON/JSONC linting)
# 2. tests/test_docs_and_licensing.sh (GPL-3.0 LICENSE & README standards)
# 3. tests/test_config_isolation.sh (userprefs.conf preservation & backup format)
# 4. tests/test_hardware_detect.sh (hardware-detect.sh dry-run, json & mock tests)
# 5. tests/test_management_scripts.sh (update.sh & uninstall.sh management tests)
# 6. python3 -m unittest discover -s yusei_settings/tests (Settings app unit tests)
#
# Emits TAP-compatible stream, formatted progress, and comprehensive summary matrix.
# Exits 0 if and only if all test suites pass.
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}================================================================================${NC}"
echo -e "${CYAN}${BOLD}               🧪  yusei-hypr: MASTER E2E TEST RUNNER                           ${NC}"
echo -e "${CYAN}${BOLD}================================================================================${NC}"
echo -e " Target Repository: ${REPO_ROOT}"
echo -e " Started At:        $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo ""

SUITES=(
    "Syntax & JSON Linting|tests/test_syntax.sh"
    "Documentation & Licensing|tests/test_docs_and_licensing.sh"
    "Config Isolation & Backups|tests/test_config_isolation.sh"
    "Hardware Detect Subsystem|tests/test_hardware_detect.sh"
    "Management Scripts|tests/test_management_scripts.sh"
    "yusei_settings Unit Tests|python3 -m unittest discover -s yusei_settings/tests"
)

TOTAL_SUITES=${#SUITES[@]}
SUITE_INDEX=0
GLOBAL_PASS=0
GLOBAL_FAIL=0

declare -a SUITE_NAMES
declare -a SUITE_STATUS
declare -a SUITE_DURATIONS
declare -a SUITE_OUTPUTS

TMP_LOG_DIR="$(mktemp -d -t yusei_test_logs_XXXXXX)"
trap 'rm -rf "$TMP_LOG_DIR"' EXIT

echo "1..${TOTAL_SUITES}"

for item in "${SUITES[@]}"; do
    SUITE_INDEX=$((SUITE_INDEX + 1))
    IFS="|" read -r name cmd <<< "$item"
    SUITE_NAMES+=("$name")
    
    echo -e "${BLUE}:: [${SUITE_INDEX}/${TOTAL_SUITES}] Running ${BOLD}${name}${NC} (${cmd})...${NC}"
    
    START_TIME=$(date +%s%N)
    LOG_FILE="$TMP_LOG_DIR/suite_${SUITE_INDEX}.log"
    
    # Execute suite
    set +e
    if [[ "$cmd" == python3* ]]; then
        (cd "$REPO_ROOT" && $cmd > "$LOG_FILE" 2>&1)
        EXIT_CODE=$?
    else
        (cd "$REPO_ROOT" && bash "$REPO_ROOT/$cmd" > "$LOG_FILE" 2>&1)
        EXIT_CODE=$?
    fi
    set -u
    
    END_TIME=$(date +%s%N)
    DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))
    SUITE_DURATIONS+=("${DURATION_MS}ms")
    
    if [[ $EXIT_CODE -eq 0 ]]; then
        echo -e "   ${GREEN}✓ PASSED${NC} in ${DURATION_MS}ms"
        echo "ok ${SUITE_INDEX} - ${name} (${DURATION_MS}ms)"
        SUITE_STATUS+=("PASS")
        GLOBAL_PASS=$((GLOBAL_PASS + 1))
    else
        echo -e "   ${RED}✗ FAILED${NC} (exit code: ${EXIT_CODE}) in ${DURATION_MS}ms"
        echo "not ok ${SUITE_INDEX} - ${name} # FAIL (exit code ${EXIT_CODE})"
        SUITE_STATUS+=("FAIL")
        GLOBAL_FAIL=$((GLOBAL_FAIL + 1))
    fi
done

# Print Summary Table
echo ""
echo -e "${CYAN}${BOLD}================================================================================${NC}"
echo -e "${BOLD}                        TEST EXECUTION SUMMARY MATRIX                           ${NC}"
echo -e "${CYAN}${BOLD}================================================================================${NC}"
printf "%-4s | %-32s | %-10s | %-12s\n" "#" "Test Suite" "Status" "Duration"
echo "--------------------------------------------------------------------------------"

for i in $(seq 0 $((TOTAL_SUITES - 1))); do
    num=$((i + 1))
    name="${SUITE_NAMES[$i]}"
    status="${SUITE_STATUS[$i]}"
    duration="${SUITE_DURATIONS[$i]}"
    
    if [[ "$status" == "PASS" ]]; then
        status_colored="${GREEN}${BOLD}PASS${NC}      "
    else
        status_colored="${RED}${BOLD}FAIL${NC}      "
    fi
    
    printf "%-4d | %-32s | %b | %-12s\n" "$num" "$name" "$status_colored" "$duration"
done

echo "--------------------------------------------------------------------------------"
echo -e "Total Suites: ${TOTAL_SUITES} | ${GREEN}Passed: ${GLOBAL_PASS}${NC} | ${RED}Failed: ${GLOBAL_FAIL}${NC}"
echo -e "Finished At:  $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo -e "${CYAN}${BOLD}================================================================================${NC}"

if [[ $GLOBAL_FAIL -gt 0 ]]; then
    echo -e "${YELLOW}Detailed logs for failing suites:${NC}"
    for i in $(seq 0 $((TOTAL_SUITES - 1))); do
        if [[ "${SUITE_STATUS[$i]}" == "FAIL" ]]; then
            num=$((i + 1))
            echo -e "\n${RED}${BOLD}--- [Failure Log: Suite ${num} - ${SUITE_NAMES[$i]}] ---${NC}"
            tail -n 25 "$TMP_LOG_DIR/suite_${num}.log"
        fi
    done
    echo ""
    echo -e "${RED}${BOLD}❌ TEST RUN FAILED: ${GLOBAL_FAIL} of ${TOTAL_SUITES} test suites did not pass.${NC}"
    exit 1
else
    echo -e "${GREEN}${BOLD}🎉 ALL TEST SUITES PASSED CLEANLY (100% SUCCESS)${NC}"
    exit 0
fi
