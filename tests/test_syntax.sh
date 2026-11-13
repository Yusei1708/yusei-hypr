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

# Temporary workdir for preprocessed JSONC and Python bytecode cache
TMP_DIR="$(mktemp -d -t yusei_syntax_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
export PYTHONPYCACHEPREFIX="$TMP_DIR/pycache"

# String-aware JSONC stripper: preserves //, /*...*/, and ,] / ,} inside JSON strings
cat << 'EOF' > "$TMP_DIR/strip_jsonc.py"
import sys


def strip_jsonc(text: str) -> str:
    # Pass 1: strip // and /* ... */ comments outside string literals
    no_comments = []
    in_str = False
    n = len(text)
    i = 0
    while i < n:
        c = text[i]
        if in_str:
            no_comments.append(c)
            if c == "\\" and i + 1 < n:
                no_comments.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue

        if c == '"':
            in_str = True
            no_comments.append(c)
            i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "/":
            i += 2
            while i < n and text[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                if text[i] == "\n":
                    no_comments.append("\n")
                i += 1
            i += 2 if i + 1 < n else 1
        else:
            no_comments.append(c)
            i += 1

    # Pass 2: strip trailing commas before ] or } outside string literals
    clean_text = "".join(no_comments)
    out = []
    in_str = False
    m = len(clean_text)
    j = 0
    while j < m:
        c = clean_text[j]
        if in_str:
            out.append(c)
            if c == "\\" and j + 1 < m:
                out.append(clean_text[j + 1])
                j += 2
                continue
            if c == '"':
                in_str = False
            j += 1
            continue

        if c == '"':
            in_str = True
            out.append(c)
        elif c == ",":
            k = j + 1
            while k < m and clean_text[k].isspace():
                k += 1
            if k < m and clean_text[k] in "]}":
                j += 1
                continue
            out.append(c)
        else:
            out.append(c)
        j += 1

    return "".join(out)


if __name__ == "__main__":
    sys.stdout.write(strip_jsonc(sys.stdin.read()))
EOF

echo -e "${BLUE}${BOLD}:: [Test Suite] Syntax & Structure Validation${NC}"
echo -e "   Target Directory: ${REPO_ROOT}"

# Collect files
mapfile -t SH_FILES < <(find "$REPO_ROOT" -type f -name "*.sh" -not -path "*/.agents/*" -not -path "*/.git/*" | sort)
mapfile -t JSON_FILES < <(find "$REPO_ROOT" -type f \( -name "*.json" -o -name "*.jsonc" \) -not -path "*/.agents/*" -not -path "*/.git/*" | sort)
mapfile -t PY_FILES < <(find "$REPO_ROOT/yusei_settings" -type f -name "*.py" -not -path "*/__pycache__/*" | sort)

TOTAL_SH=${#SH_FILES[@]}
TOTAL_JSON=${#JSON_FILES[@]}
TOTAL_PY=${#PY_FILES[@]}
TOTAL_JSONC_FIXTURE=1
TOTAL_LUA=0
if command -v luac >/dev/null 2>&1 && [[ -f "$REPO_ROOT/config/hypr/hyprland.lua" ]]; then
    TOTAL_LUA=1
fi
TOTAL_C=0
if command -v gcc >/dev/null 2>&1 && [[ -f "$REPO_ROOT/lib/waybar-hyprland-compat.c" ]]; then
    TOTAL_C=1
fi

# Explicitly verified Power Tools & Core Wrappers
MANDATORY_V15_SCRIPTS=(
    "config/hypr/scripts/ScreenRecord.sh"
    "config/hypr/scripts/OcrGrab.sh"
    "config/hypr/scripts/SwayncSinglePopup.sh"
    "bin/notify-send"
    "bin/waybar"
)
TOTAL_V15=${#MANDATORY_V15_SCRIPTS[@]}
TOTAL_TESTS=$((TOTAL_SH + TOTAL_JSON + TOTAL_JSONC_FIXTURE + TOTAL_V15 + TOTAL_PY + TOTAL_LUA + TOTAL_C))

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
        # Strip C/C++ style comments and trailing commas (string-aware) before piping to jq
        if python3 "$TMP_DIR/strip_jsonc.py" < "$json_file" | jq empty 2>"$TMP_DIR/err.log"; then
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

# 3. Regression Check: JSONC Stripper Preserves URLs and Comment Tokens Inside Strings
TEST_INDEX=$((TEST_INDEX + 1))
cat << 'EOF' > "$TMP_DIR/url_comment.jsonc"
{
  // leading line comment
  "url": "https://example.com/path/*keep*/?q=1,]//still-in-string",
  /* block comment */
  "arr": [1, 2,],
}
EOF
if python3 "$TMP_DIR/strip_jsonc.py" < "$TMP_DIR/url_comment.jsonc" | jq -e '.url == "https://example.com/path/*keep*/?q=1,]//still-in-string" and .arr == [1, 2]' >/dev/null 2>"$TMP_DIR/err.log"; then
    echo "ok ${TEST_INDEX} - jsonc string-aware stripper preserves URLs and /* inside strings"
    PASSED=$((PASSED + 1))
else
    err_msg="$(head -n 1 "$TMP_DIR/err.log" 2>/dev/null || echo "JSONC stripper corrupted string literal")"
    echo "not ok ${TEST_INDEX} - jsonc string-aware stripper preserves URLs and /* inside strings # FAIL: ${err_msg}"
    FAILED=$((FAILED + 1))
    FAILED_LIST+=("jsonc-stripper-url (${err_msg})")
fi

# 4. Explicit Verification of Critical v1.5.0 Power Tools (ScreenRecord.sh & OcrGrab.sh)
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
    elif [[ "$script_abs" == *.py ]]; then
        if python3 -m py_compile "$script_abs" 2>"$TMP_DIR/err.log"; then
            echo "ok ${TEST_INDEX} - explicit check: py_compile ${script_rel} (v1.5.0 power tool)"
            PASSED=$((PASSED + 1))
        else
            err_msg="$(head -n 1 "$TMP_DIR/err.log" 2>/dev/null || echo "Python syntax error")"
            echo "not ok ${TEST_INDEX} - explicit check: py_compile ${script_rel} # FAIL: ${err_msg}"
            FAILED=$((FAILED + 1))
            FAILED_LIST+=("${script_rel} (${err_msg})")
        fi
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

# 5. Check Python Files across yusei_settings/
for py_file in "${PY_FILES[@]}"; do
    TEST_INDEX=$((TEST_INDEX + 1))
    rel_path="${py_file#$REPO_ROOT/}"
    if python3 -m py_compile "$py_file" 2>"$TMP_DIR/err.log"; then
        echo "ok ${TEST_INDEX} - python3 -m py_compile ${rel_path}"
        PASSED=$((PASSED + 1))
    else
        err_msg="$(head -n 1 "$TMP_DIR/err.log" 2>/dev/null || echo "Python syntax error")"
        echo "not ok ${TEST_INDEX} - python3 -m py_compile ${rel_path} # FAIL: ${err_msg}"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("${rel_path} (${err_msg})")
    fi
done

# 6. Check Lua Config Syntax (when luac is available)
if [[ $TOTAL_LUA -gt 0 ]]; then
    TEST_INDEX=$((TEST_INDEX + 1))
    if luac -p "$REPO_ROOT/config/hypr/hyprland.lua" 2>"$TMP_DIR/err.log"; then
        echo "ok ${TEST_INDEX} - luac -p config/hypr/hyprland.lua"
        PASSED=$((PASSED + 1))
    else
        err_msg="$(head -n 1 "$TMP_DIR/err.log" 2>/dev/null || echo "Lua syntax error")"
        echo "not ok ${TEST_INDEX} - luac -p config/hypr/hyprland.lua # FAIL: ${err_msg}"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("config/hypr/hyprland.lua (${err_msg})")
    fi
fi

# 7. Check C Shim Syntax (when gcc is available)
if [[ $TOTAL_C -gt 0 ]]; then
    TEST_INDEX=$((TEST_INDEX + 1))
    if gcc -fsyntax-only "$REPO_ROOT/lib/waybar-hyprland-compat.c" 2>"$TMP_DIR/err.log"; then
        echo "ok ${TEST_INDEX} - gcc -fsyntax-only lib/waybar-hyprland-compat.c"
        PASSED=$((PASSED + 1))
    else
        err_msg="$(head -n 1 "$TMP_DIR/err.log" 2>/dev/null || echo "C syntax error")"
        echo "not ok ${TEST_INDEX} - gcc -fsyntax-only lib/waybar-hyprland-compat.c # FAIL: ${err_msg}"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("lib/waybar-hyprland-compat.c (${err_msg})")
    fi
fi

# Output Summary Table
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}Syntax & JSON Integrity Summary${NC}"
echo -e "${BOLD}======================================================${NC}"
echo -e "Total Files Checked: ${TOTAL_TESTS} (${TOTAL_SH} Shell scripts, ${TOTAL_JSON} JSON/JSONC, ${TOTAL_JSONC_FIXTURE} JSONC URL fixture, ${TOTAL_V15} v1.5.0 explicit, ${TOTAL_PY} Python, ${TOTAL_LUA} Lua, ${TOTAL_C} C)"
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
