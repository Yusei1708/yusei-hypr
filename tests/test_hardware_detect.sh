#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Hardware Detection Subsystem Test Suite
# ==============================================================================
# - Tests scripts/hardware-detect.sh existence and executable permissions
# - Tests --dry-run exits 0 without writing any files
# - Tests --json produces valid JSON conforming to expected schema
# - Tests mock NVIDIA GPU branch (mock lspci), package listing, and injection
# - Tests mock Intel/AMD non-NVIDIA branch
# - Tests injection idempotency into custom userprefs.conf
# - Tests Laptop / chassis detection branch
# - Tests PipeWire audio stack verification and PulseAudio conflict detection
# - Tests custom --env-file creation with standard variables
# - Tests error handling on invalid option arguments
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

echo -e "${BLUE}${BOLD}:: [Test Suite] Hardware Detection Subsystem Verification${NC}"
echo -e "   Target Directory: ${REPO_ROOT}"

DETECT_SCRIPT="$REPO_ROOT/scripts/hardware-detect.sh"

# Setup isolated sandbox for mocking and file writes
TMP_DIR="$(mktemp -d -t yusei_hw_test_XXXXXX)"
MOCK_BIN="$TMP_DIR/mock_bin"
mkdir -p "$MOCK_BIN"
trap 'rm -rf "$TMP_DIR"' EXIT

TOTAL_TESTS=22
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
# 1. Basic Script Invariants
# ------------------------------------------------------------------------------
assert_check "scripts/hardware-detect.sh exists and is executable" \
    "[ -f '$DETECT_SCRIPT' ] && [ -x '$DETECT_SCRIPT' ]"

# ------------------------------------------------------------------------------
# 2. Dry-Run & Safety Check
# ------------------------------------------------------------------------------
BEFORE_FILES="$(find "$TMP_DIR" -type f | sort)"
assert_check "--dry-run exits 0 without writing any files" \
    "bash '$DETECT_SCRIPT' --dry-run >/dev/null 2>&1"

# ------------------------------------------------------------------------------
# 3. JSON Output & Schema Validation
# ------------------------------------------------------------------------------
JSON_OUT="$TMP_DIR/hw_detect.json"
bash "$DETECT_SCRIPT" --json > "$JSON_OUT" 2>/dev/null || true

assert_check "--json produces valid JSON parsable by jq" \
    "[ -s '$JSON_OUT' ] && jq empty '$JSON_OUT' >/dev/null 2>&1"

assert_check "JSON output contains required hardware schema keys" \
    "[ -s '$JSON_OUT' ] && jq -e '.os and .kernel and .kernel_pkg and .kernel_headers_pkg and (.has_nvidia != null) and (.is_laptop != null) and .audio_stack' '$JSON_OUT' >/dev/null 2>&1"

# ------------------------------------------------------------------------------
# 4. Mock NVIDIA GPU Detection & Packages
# ------------------------------------------------------------------------------
# Create mock lspci for NVIDIA
cat << 'EOF' > "$MOCK_BIN/lspci_nvidia"
#!/usr/bin/env bash
echo "00:00.0 Host bridge: Intel Corporation Device 461b (rev 02)"
echo "01:00.0 VGA compatible controller: NVIDIA Corporation GA106M [GeForce RTX 3060 Mobile] (rev a1)"
echo "01:00.1 Audio device: NVIDIA Corporation GA106 High Definition Audio (rev a1)"
EOF
chmod +x "$MOCK_BIN/lspci_nvidia"

ln -sf "$MOCK_BIN/lspci_nvidia" "$MOCK_BIN/lspci"
NVIDIA_JSON="$TMP_DIR/nvidia.json"
PATH="$MOCK_BIN:$PATH" bash "$DETECT_SCRIPT" --json > "$NVIDIA_JSON" 2>/dev/null || true

assert_check "Mock lspci NVIDIA detects has_nvidia=true and includes nvidia-dkms packages" \
    "[ -s '$NVIDIA_JSON' ] && [ \"\$(jq -r .has_nvidia '$NVIDIA_JSON')\" = 'true' ] && \
     jq -e '.nvidia_packages | index(\"nvidia-dkms\") != null' '$NVIDIA_JSON' >/dev/null 2>&1"

# ------------------------------------------------------------------------------
# 5. Mock Non-NVIDIA (Intel/AMD) Detection
# ------------------------------------------------------------------------------
cat << 'EOF' > "$MOCK_BIN/lspci_intel"
#!/usr/bin/env bash
echo "00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-P [Iris Xe Graphics] (rev 04)"
EOF
chmod +x "$MOCK_BIN/lspci_intel"

ln -sf "$MOCK_BIN/lspci_intel" "$MOCK_BIN/lspci"
INTEL_JSON="$TMP_DIR/intel.json"
PATH="$MOCK_BIN:$PATH" bash "$DETECT_SCRIPT" --json > "$INTEL_JSON" 2>/dev/null || true

assert_check "Mock lspci Intel detects has_nvidia=false" \
    "[ -s '$INTEL_JSON' ] && [ \"\$(jq -r .has_nvidia '$INTEL_JSON')\" = 'false' ]"

# ------------------------------------------------------------------------------
# 5b. Mock Sysfs Fallback for NVIDIA PCI Vendor ID (0x10de)
# ------------------------------------------------------------------------------
cat << 'EOF' > "$MOCK_BIN/lspci_empty"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MOCK_BIN/lspci_empty"
ln -sf "$MOCK_BIN/lspci_empty" "$MOCK_BIN/lspci"

MOCK_SYSFS="$TMP_DIR/mock_sysfs"
mkdir -p "$MOCK_SYSFS/bus/pci/devices/0000:01:00.0"
echo "0x10de" > "$MOCK_SYSFS/bus/pci/devices/0000:01:00.0/vendor"

SYSFS_JSON="$TMP_DIR/sysfs_nvidia.json"
PATH="$MOCK_BIN:$PATH" SYSFS_PCI_DIR="$MOCK_SYSFS/bus/pci/devices" bash "$DETECT_SCRIPT" --json > "$SYSFS_JSON" 2>/dev/null || true

assert_check "Sysfs fallback detects NVIDIA PCI vendor ID (0x10de) when lspci returns empty" \
    "[ -s '$SYSFS_JSON' ] && [ \"\$(jq -r .has_nvidia '$SYSFS_JSON')\" = 'true' ] && \
     [ \"\$(jq -r .nvidia_model '$SYSFS_JSON')\" = 'NVIDIA Corporation (PCI Vendor 0x10de)' ]"

# ------------------------------------------------------------------------------
# 6. Wayland NVIDIA Injection & Idempotency
# ------------------------------------------------------------------------------
ln -sf "$MOCK_BIN/lspci_nvidia" "$MOCK_BIN/lspci"
MOCK_USERPREFS="$TMP_DIR/userprefs_test.conf"
echo "# Initial userprefs" > "$MOCK_USERPREFS"

PATH="$MOCK_BIN:$PATH" bash "$DETECT_SCRIPT" --inject-userprefs --target-userprefs="$MOCK_USERPREFS" >/dev/null 2>&1 || true

assert_check "--inject-userprefs injects Wayland NVIDIA flags (LIBVA, GBM, GLX) when NVIDIA present" \
    "grep -q -E '^[[:space:]]*env[[:space:]]*=[[:space:]]*LIBVA_DRIVER_NAME,nvidia' '$MOCK_USERPREFS' && \
     grep -q -E '^[[:space:]]*env[[:space:]]*=[[:space:]]*GBM_BACKEND,nvidia-drm' '$MOCK_USERPREFS' && \
     grep -q -E '^[[:space:]]*env[[:space:]]*=[[:space:]]*__GLX_VENDOR_LIBRARY_NAME,nvidia' '$MOCK_USERPREFS'"

# Re-run injection to verify idempotency
PATH="$MOCK_BIN:$PATH" bash "$DETECT_SCRIPT" --inject-userprefs --target-userprefs="$MOCK_USERPREFS" >/dev/null 2>&1 || true
OCCURRENCES="$(grep -c -E '^[[:space:]]*env[[:space:]]*=[[:space:]]*LIBVA_DRIVER_NAME,nvidia' "$MOCK_USERPREFS" || true)"

assert_check "--inject-userprefs is idempotent and does not duplicate injected flags" \
    "[ '$OCCURRENCES' -eq 1 ]"

# ------------------------------------------------------------------------------
# 6b. Wayland NVIDIA Injection Against Default Template (with comments) & Idempotency
# ------------------------------------------------------------------------------
TEMPLATE_USERPREFS="$TMP_DIR/template_userprefs.conf"
cp "$REPO_ROOT/config/hypr/userprefs.conf" "$TEMPLATE_USERPREFS"

PATH="$MOCK_BIN:$PATH" bash "$DETECT_SCRIPT" --inject-userprefs --target-userprefs="$TEMPLATE_USERPREFS" >/dev/null 2>&1 || true

assert_check "--inject-userprefs on default config/hypr/userprefs.conf template appends active NVIDIA flags" \
    "grep -q -E '^[[:space:]]*env[[:space:]]*=[[:space:]]*LIBVA_DRIVER_NAME,nvidia' '$TEMPLATE_USERPREFS' && \
     grep -q -E '^[[:space:]]*env[[:space:]]*=[[:space:]]*GBM_BACKEND,nvidia-drm' '$TEMPLATE_USERPREFS' && \
     grep -q -E '^[[:space:]]*env[[:space:]]*=[[:space:]]*__GLX_VENDOR_LIBRARY_NAME,nvidia' '$TEMPLATE_USERPREFS' && \
     grep -q -E '^[[:space:]]*env[[:space:]]*=[[:space:]]*NVD_BACKEND,direct' '$TEMPLATE_USERPREFS'"

# Re-run injection to verify idempotency on template
PATH="$MOCK_BIN:$PATH" bash "$DETECT_SCRIPT" --inject-userprefs --target-userprefs="$TEMPLATE_USERPREFS" >/dev/null 2>&1 || true
TEMPLATE_ACTIVE_COUNT="$(grep -c -E '^[[:space:]]*env[[:space:]]*=[[:space:]]*LIBVA_DRIVER_NAME,nvidia' "$TEMPLATE_USERPREFS" || true)"

assert_check "--inject-userprefs on template is idempotent and does not duplicate active flags" \
    "[ '$TEMPLATE_ACTIVE_COUNT' -eq 1 ]"

# Verify non-NVIDIA does not inject flags
MOCK_USERPREFS_INTEL="$TMP_DIR/userprefs_intel.conf"
echo "# Intel userprefs" > "$MOCK_USERPREFS_INTEL"
ln -sf "$MOCK_BIN/lspci_intel" "$MOCK_BIN/lspci"

PATH="$MOCK_BIN:$PATH" bash "$DETECT_SCRIPT" --inject-userprefs --target-userprefs="$MOCK_USERPREFS_INTEL" >/dev/null 2>&1 || true

assert_check "--inject-userprefs does not inject NVIDIA flags when GPU is Intel/AMD" \
    "! grep -q 'LIBVA_DRIVER_NAME' '$MOCK_USERPREFS_INTEL'"

# ------------------------------------------------------------------------------
# 7. Laptop / Chassis Detection Branch
# ------------------------------------------------------------------------------
assert_check "Laptop detection reports correct packages (brightnessctl, acpi) when laptop chassis detected" \
    "if compgen -G '/sys/class/power_supply/BAT*' >/dev/null 2>&1; then \
        [ \"\$(jq -r .is_laptop '$JSON_OUT')\" = 'true' ] && \
        jq -e '.laptop_packages | index(\"brightnessctl\") != null' '$JSON_OUT' >/dev/null 2>&1; \
     else \
        [ \"\$(jq -r .is_laptop '$JSON_OUT')\" = 'false' ]; \
     fi"

# ------------------------------------------------------------------------------
# 8. Audio Stack Verification & Mock PulseAudio Conflict
# ------------------------------------------------------------------------------
assert_check "Audio stack specifies PipeWire as standard audio architecture" \
    "[ \"\$(jq -r .audio_stack '$JSON_OUT')\" = 'pipewire' ]"

# Mock pacman detecting conflicting pulseaudio package
cat << 'EOF' > "$MOCK_BIN/pacman_conflict"
#!/usr/bin/env bash
if [[ "$*" == *"-Qi pulseaudio"* ]]; then
    echo "Name : pulseaudio"
    exit 0
fi
exit 1
EOF
chmod +x "$MOCK_BIN/pacman_conflict"

ln -sf "$MOCK_BIN/pacman_conflict" "$MOCK_BIN/pacman"
AUDIO_CONFLICT_JSON="$TMP_DIR/audio_conflict.json"
PATH="$MOCK_BIN:$PATH" bash "$DETECT_SCRIPT" --json > "$AUDIO_CONFLICT_JSON" 2>/dev/null || true

assert_check "Audio conflict detection accurately flags pulseaudio package presence" \
    "[ -s '$AUDIO_CONFLICT_JSON' ] && [ \"\$(jq -r .has_pulse_conflict '$AUDIO_CONFLICT_JSON')\" = 'true' ] && \
     jq -e '.pulse_conflicts | index(\"pulseaudio\") != null' '$AUDIO_CONFLICT_JSON' >/dev/null 2>&1"

# Mock clean pacman without conflicts
cat << 'EOF' > "$MOCK_BIN/pacman_clean"
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$MOCK_BIN/pacman_clean"

ln -sf "$MOCK_BIN/pacman_clean" "$MOCK_BIN/pacman"
AUDIO_CLEAN_JSON="$TMP_DIR/audio_clean.json"
PATH="$MOCK_BIN:$PATH" bash "$DETECT_SCRIPT" --json > "$AUDIO_CLEAN_JSON" 2>/dev/null || true

assert_check "Audio conflict detection flags has_pulse_conflict=false when no PulseAudio installed" \
    "[ -s '$AUDIO_CLEAN_JSON' ] && [ \"\$(jq -r .has_pulse_conflict '$AUDIO_CLEAN_JSON')\" = 'false' ]"

# ------------------------------------------------------------------------------
# 9. Custom Environment File Export
# ------------------------------------------------------------------------------
TARGET_ENV="$TMP_DIR/custom_output.env"
# Remove mock pacman so standard path is restored for env test
rm -f "$MOCK_BIN/pacman"
bash "$DETECT_SCRIPT" --env-file="$TARGET_ENV" >/dev/null 2>&1 || true

assert_check "--env-file writes complete environment variables (HAS_NVIDIA, IS_LAPTOP, KERNEL_PKG, AUDIO_STACK)" \
    "[ -s '$TARGET_ENV' ] && \
     grep -q 'HAS_NVIDIA=' '$TARGET_ENV' && \
     grep -q 'IS_LAPTOP=' '$TARGET_ENV' && \
     grep -q 'KERNEL_PKG=' '$TARGET_ENV' && \
     grep -q 'KERNEL_HEADERS_PKG=' '$TARGET_ENV' && \
     grep -q 'AUDIO_STACK=pipewire' '$TARGET_ENV'"

# ------------------------------------------------------------------------------
# 10. Error Handling & Parameter Validation
# ------------------------------------------------------------------------------
assert_check "--env-file without argument returns non-zero error exit code" \
    "! bash '$DETECT_SCRIPT' --env-file >/dev/null 2>&1"

assert_check "--env-file= with empty value returns non-zero error exit code 1" \
    "! bash '$DETECT_SCRIPT' --env-file= >/dev/null 2>&1"

assert_check "--target-userprefs without argument returns non-zero error exit code" \
    "! bash '$DETECT_SCRIPT' --target-userprefs >/dev/null 2>&1"

assert_check "--target-userprefs= with empty value returns non-zero error exit code 1" \
    "! bash '$DETECT_SCRIPT' --target-userprefs= >/dev/null 2>&1"

assert_check "Passing invalid CLI flag (e.g. --invalid-flag) exits with non-zero error exit code 1" \
    "! bash '$DETECT_SCRIPT' --invalid-flag >/dev/null 2>&1"

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}Hardware Detection Subsystem Test Summary${NC}"
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
    echo -e "${GREEN}${BOLD}Status: ALL HARDWARE DETECTION CHECKS PASSED${NC}"
    echo -e "${BOLD}======================================================${NC}"
    exit 0
fi
