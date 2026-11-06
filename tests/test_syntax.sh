#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Automated Syntax & JSON Integrity Test Suite
# ==============================================================================
# - Runs 'bash -n' across all .sh scripts in the repository (excluding .agents, .git)
# - Runs 'jq empty' on all .json and .jsonc configuration files
# - Emits TAP output (Test Anything Protocol) and a summary table
# - Exits 0 if and only if all syntax checks pass
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

# Temporary workdir for preprocessed JSONC
TMP_DIR="$(mktemp -d -t yusei_syntax_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo -e "${BLUE}${BOLD}:: [Test Suite] Syntax & Structure Validation${NC}"
echo -e "   Target Directory: ${REPO_ROOT}"

# Collect files
mapfile -t SH_FILES < <(find "$REPO_ROOT" -type f -name "*.sh" -not -path "*/.agents/*" -not -path "*/.git/*" | sort)
mapfile -t JSON_FILES < <(find "$REPO_ROOT" -type f \( -name "*.json" -o -name "*.jsonc" \) -not -path "*/.agents/*" -not -path "*/.git/*" | sort)

TOTAL_SH=${#SH_FILES[@]}
TOTAL_JSON=${#JSON_FILES[@]}

# Explicitly verified v1.5.0 Power Tools
MANDATORY_V15_SCRIPTS=(
    "config/hypr/scripts/ScreenRecord.sh"
    "config/hypr/scripts/OcrGrab.sh"
)
TOTAL_V15=${#MANDATORY_V15_SCRIPTS[@]}
TOTAL_TESTS=$((TOTAL_SH + TOTAL_JSON + TOTAL_V15))

if [[ $TOTAL_TESTS -eq 0 ]]; then
    echo "1..0 # No scripts or JSON files found"
    exit 0
fi

echo "1..${TOTAL_TESTS}"

TEST_INDEX=0
PASSED=0
FAILED=0
FAILED_LIST=()

# 1. Check Shell Scripts
for sh_file in "${SH_FILES[@]}"; do
    TEST_INDEX=$((TEST_INDEX + 1))
    rel_path="${sh_file#$REPO_ROOT/}"
    if bash -n "$sh_file" 2>"$TMP_DIR/err.log"; then
        echo "ok ${TEST_INDEX} - bash -n ${rel_path}"
        PASSED=$((PASSED + 1))
    else
        err_msg="$(head -n 1 "$TMP_DIR/err.log" 2>/dev/null || echo "Syntax error")"
        echo "not ok ${TEST_INDEX} - bash -n ${rel_path} # FAIL: ${err_msg}"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("${rel_path} (${err_msg})")
    fi
done

# 2. Check JSON / JSONC Files
for json_file in "${JSON_FILES[@]}"; do
    TEST_INDEX=$((TEST_INDEX + 1))
    rel_path="${json_file#$REPO_ROOT/}"
    
    if [[ "$json_file" == *.jsonc ]]; then
        # Strip C/C++ style comments and trailing commas before piping to jq
        if python3 -c '
import sys, re
content = sys.stdin.read()
# Strip block comments
content = re.sub(r"/\*.*?\*/", "", content, flags=re.DOTALL)
# Strip line comments outside string literals
lines = []
for line in content.splitlines():
    res = []
    in_quote = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == "\\" and in_quote:
            res.append(c)
            if i + 1 < len(line):
                res.append(line[i+1])
                i += 2
                continue
        elif c == "\"":
            in_quote = not in_quote
            res.append(c)
        elif not in_quote and c == "/" and i + 1 < len(line) and line[i+1] == "/":
            break
        else:
            res.append(c)
        i += 1
    lines.append("".join(res))
clean = "\n".join(lines)
clean = re.sub(r",\s*([\]}])", r"\1", clean)
print(clean)
' < "$json_file" | jq empty 2>"$TMP_DIR/err.log"; then
            echo "ok ${TEST_INDEX} - jq empty (jsonc) ${rel_path}"
            PASSED=$((PASSED + 1))
        else
            err_msg="$(head -n 1 "$TMP_DIR/err.log" 2>/dev/null || echo "Invalid JSONC")"
            echo "not ok ${TEST_INDEX} - jq empty (jsonc) ${rel_path} # FAIL: ${err_msg}"
            FAILED=$((FAILED + 1))
            FAILED_LIST+=("${rel_path} (${err_msg})")
        fi
    else
        if jq empty "$json_file" 2>"$TMP_DIR/err.log"; then
            echo "ok ${TEST_INDEX} - jq empty ${rel_path}"
            PASSED=$((PASSED + 1))
        else
            err_msg="$(head -n 1 "$TMP_DIR/err.log" 2>/dev/null || echo "Invalid JSON")"
            echo "not ok ${TEST_INDEX} - jq empty ${rel_path} # FAIL: ${err_msg}"
            FAILED=$((FAILED + 1))
            FAILED_LIST+=("${rel_path} (${err_msg})")
        fi
    fi
done

# 3. Explicit Verification of Critical v1.5.0 Power Tools (ScreenRecord.sh & OcrGrab.sh)
for script_rel in "${MANDATORY_V15_SCRIPTS[@]}"; do
    TEST_INDEX=$((TEST_INDEX + 1))
    script_abs="$REPO_ROOT/$script_rel"
    if [[ ! -f "$script_abs" ]]; then
        echo "not ok ${TEST_INDEX} - explicit check: ${script_rel} exists # FAIL: file missing"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("${script_rel} (file missing)")
    elif [[ ! -x "$script_abs" ]]; then
        echo "not ok ${TEST_INDEX} - explicit check: ${script_rel} executable # FAIL: not executable"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("${script_rel} (not executable)")
    elif bash -n "$script_abs" 2>"$TMP_DIR/err.log"; then
        echo "ok ${TEST_INDEX} - explicit check: bash -n ${script_rel} (v1.5.0 power tool)"
        PASSED=$((PASSED + 1))
    else
        err_msg="$(head -n 1 "$TMP_DIR/err.log" 2>/dev/null || echo "Syntax error")"
        echo "not ok ${TEST_INDEX} - explicit check: bash -n ${script_rel} # FAIL: ${err_msg}"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("${script_rel} (${err_msg})")
    fi
done

# Output Summary Table
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}Syntax & JSON Integrity Summary${NC}"
echo -e "${BOLD}======================================================${NC}"
echo -e "Total Files Checked: ${TOTAL_TESTS} (${TOTAL_SH} Shell scripts, ${TOTAL_JSON} JSON/JSONC configs, ${TOTAL_V15} Explicit v1.5.0 checks)"
echo -e "Passed:              ${GREEN}${PASSED}${NC}"
if [[ $FAILED -gt 0 ]]; then
    echo -e "Failed:              ${RED}${FAILED}${NC}"
    echo -e "\n${RED}Failed files:${NC}"
    for f in "${FAILED_LIST[@]}"; do
        echo -e "  - ${RED}${f}${NC}"
    done
    echo -e "${BOLD}======================================================${NC}"
    exit 1
else
    echo -e "Failed:              0"
    echo -e "${GREEN}${BOLD}Status: ALL SYNTAX CHECKS PASSED${NC}"
    echo -e "${BOLD}======================================================${NC}"
    exit 0
fi
