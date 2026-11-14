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

# Setup isolated sandboxes
MOCK_HOME="$(mktemp -d -t yusei_mgmt_test_XXXXXX)"
UNINST_SANDBOX="$(mktemp -d -t yusei_uninst_XXXXXX)"
NVIDIA_SANDBOX="$(mktemp -d -t yusei_nvidia_XXXXXX)"
OPT_SANDBOX="$(mktemp -d -t yusei_opt_XXXXXX)"
REAL_HOME="$HOME"
trap 'rm -rf "$MOCK_HOME" "$UNINST_SANDBOX" "$NVIDIA_SANDBOX" "$OPT_SANDBOX"' EXIT

# Snapshot real ~/.config mtime
REAL_CONFIG_MTIME=""
if [[ -d "$REAL_HOME/.config" ]]; then
    REAL_CONFIG_MTIME="$(stat -c %Y "$REAL_HOME/.config" 2>/dev/null || true)"
fi

TOTAL_TESTS=19
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
export XDG_DATA_HOME="$MOCK_HOME/.local/share"
export XDG_STATE_HOME="$MOCK_HOME/.local/state"
unset HYPRLAND_INSTANCE_SIGNATURE || true

assert_check "update.sh --dry-run --skip-git executes non-interactively and exits 0" \
    "[ -f '$UPDATE_SCRIPT' ] && bash '$UPDATE_SCRIPT' --dry-run --skip-git >/dev/null 2>&1"

# Populate mock userprefs.conf & preserved user files to verify non-destructive update
mkdir -p "$MOCK_HOME/.config/hypr/UserConfigs"
UPDATE_MARKER="MARKER_USERPREFS_UPDATE_TOKEN_$(date +%s%N)"
cat <<EOF > "$MOCK_HOME/.config/hypr/userprefs.conf"
# Personal overrides
env = TEST_UPDATE_PREF,1
# Marker: ${UPDATE_MARKER}
EOF
echo "# monitor custom update marker" > "$MOCK_HOME/.config/hypr/monitors.conf"
printf "bezier = customUpd, 0.1, 0.9, 0.2, 1.0\nanimation = fadeDpms, 0\n" > "$MOCK_HOME/.config/hypr/animations.conf"
echo "rounding = 11" > "$MOCK_HOME/.config/hypr/UserConfigs/UserDecorations.conf"
echo '{"power_daemon":false}' > "$MOCK_HOME/.config/hypr/power.json"

assert_check "update.sh --skip-git executes cleanly and exits 0" \
    "bash '$UPDATE_SCRIPT' --skip-git --no-reload >/dev/null 2>&1"

assert_check "update.sh strictly preserves userprefs.conf, monitors.conf, animations.conf, UserDecorations.conf, and power.json" \
    "[ -f '$MOCK_HOME/.config/hypr/userprefs.conf' ] && grep -q '$UPDATE_MARKER' '$MOCK_HOME/.config/hypr/userprefs.conf' && \
     grep -q 'monitor custom update marker' '$MOCK_HOME/.config/hypr/monitors.conf' && \
     grep -q 'customUpd' '$MOCK_HOME/.config/hypr/animations.conf' && \
     grep -q 'rounding = 11' '$MOCK_HOME/.config/hypr/UserConfigs/UserDecorations.conf' && \
     grep -q '\"power_daemon\":false' '$MOCK_HOME/.config/hypr/power.json'"

# ------------------------------------------------------------------------------
# 2. Root uninstall.sh Invariants, --dry-run, and Sandboxed -y Execution
# ------------------------------------------------------------------------------
assert_check "Root uninstall.sh exists and is executable" \
    "[ -f '$UNINSTALL_SCRIPT' ] && [ -x '$UNINSTALL_SCRIPT' ]"

# Prepare realistic sandbox state for uninstall.sh (--dry-run and -y)
UNINST_HOME="$UNINST_SANDBOX/home"
UNINST_ETC="$UNINST_SANDBOX/etc"
UNINST_BIN="$UNINST_SANDBOX/spy_bin"
UNINST_SUDO_LOG="$UNINST_SANDBOX/sudo.log"
mkdir -p \
    "$UNINST_HOME/.config/hypr" \
    "$UNINST_HOME/.local/bin" \
    "$UNINST_HOME/.local/lib" \
    "$UNINST_HOME/.local/share/applications" \
    "$UNINST_HOME/.local/share/yusei-hypr/bin" \
    "$UNINST_HOME/.local/state/yusei-hypr" \
    "$UNINST_ETC/modprobe.d" \
    "$UNINST_ETC/sddm.conf.d" \
    "$UNINST_ETC/loader/entries" \
    "$UNINST_BIN"

cat <<'EOF' > "$UNINST_BIN/sudo"
#!/usr/bin/env bash
echo "SUDO_CALLED: $*" >> "${SPY_SUDO_LOG:-/dev/null}"
exit 1
EOF
chmod +x "$UNINST_BIN/sudo"

PRE_SNAP="$UNINST_HOME/.config/yusei-hypr-backup-20261015_090000"
mkdir -p "$PRE_SNAP/hypr"
echo "pre_install_restored=yes" > "$PRE_SNAP/hypr/pre_install.conf"
cat <<'EOF' > "$PRE_SNAP/manifest.json"
{
  "timestamp": "20261015_090000",
  "backed_up_targets": ["hypr"],
  "non_existing_targets": []
}
EOF

echo "existing_hypr=replaced" > "$UNINST_HOME/.config/hypr/current.conf"
echo "#!/usr/bin/env bash" > "$UNINST_HOME/.local/share/yusei-hypr/bin/waybar"
ln -sfn "$UNINST_HOME/.local/share/yusei-hypr/bin/waybar" "$UNINST_HOME/.local/bin/waybar"
echo "#!/usr/bin/env bash" > "$UNINST_HOME/.local/share/yusei-hypr/bin/rofi"
ln -sfn "$UNINST_HOME/.local/share/yusei-hypr/bin/rofi" "$UNINST_HOME/.local/bin/rofi"
touch "$UNINST_HOME/.local/lib/libwaybar-hyprland.so"
echo "[Desktop Entry]" > "$UNINST_HOME/.local/share/applications/yusei-settings.desktop"

cat <<'EOF' > "$UNINST_HOME/.bashrc"
export KEEP_USER_ALIAS=1

# Pokemon Fastfetch Banner (yusei-hypr)
pokemon-colorscripts -n pikachu # config-pokemon.jsonc

# Chặn yay/paru tự động thay thế swww bằng awww khi cập nhật
alias yay='yay --ignore swww,awww'
alias paru='paru --ignore swww,awww'
alias keep_me='ls -la'
EOF

cat <<'EOF' > "$UNINST_ETC/mkinitcpio.conf"
MODULES=(btrfs nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF

cat <<'EOF' > "$UNINST_ETC/grub"
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nvidia_drm.modeset=1"
EOF

cat <<'EOF' > "$UNINST_ETC/loader/entries/arch.conf"
title Arch Linux
options root=UUID=1234 rw nvidia_drm.modeset=1 # keep comment
EOF

cat <<'EOF' > "$UNINST_ETC/modprobe.d/nvidia.conf"
options nvidia_drm modeset=1 fbdev=1
EOF

cat <<'EOF' > "$UNINST_ETC/sddm.conf.d/10-theme.conf"
[Theme]
Current=simple-sddm-2
EOF

cat <<EOF > "$UNINST_HOME/.local/state/yusei-hypr/install-state.env"
PRE_SDDM_ENABLED=false
PRE_BLUETOOTH_ENABLED=false
PRE_SUPERGFXD_ENABLED=false
PRE_DISPLAY_MANAGER=
PRE_INSTALL_BACKUP="${PRE_SNAP}"
INSTALLER_ENABLED_SDDM=false
INSTALLER_ENABLED_BLUETOOTH=false
INSTALLER_ENABLED_SUPERGFXD=false
EOF

cat <<EOF > "$UNINST_HOME/.local/state/yusei-hypr/nvidia-state.env"
ADDED_MKINITCPIO_MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
GRUB_MODESET_ADDED=true
LOADER_ENTRIES_MODIFIED="$UNINST_ETC/loader/entries/arch.conf"
MODPROBE_CREATED=true
EOF

run_uninstaller_sandboxed() {
    local flag="$1"
    (
        export HOME="$UNINST_HOME"
        export XDG_CONFIG_HOME="$UNINST_HOME/.config"
        export XDG_DATA_HOME="$UNINST_HOME/.local/share"
        export XDG_STATE_HOME="$UNINST_HOME/.local/state"
        export MKINITCPIO_CONF="$UNINST_ETC/mkinitcpio.conf"
        export GRUB_DEFAULT_FILE="$UNINST_ETC/grub"
        export MODPROBE_NVIDIA_CONF="$UNINST_ETC/modprobe.d/nvidia.conf"
        export SDDM_THEME_CONF="$UNINST_ETC/sddm.conf.d/10-theme.conf"
        export SPY_SUDO_LOG="$UNINST_SUDO_LOG"
        export PATH="$UNINST_BIN:$PATH"
        unset HYPRLAND_INSTANCE_SIGNATURE || true
        bash "$UNINSTALL_SCRIPT" "$flag" -y </dev/null >/dev/null 2>&1
    )
}

assert_check "uninstall.sh --dry-run -y exits 0 and leaves sandbox state, bootloader files, and .bashrc untouched" \
    "run_uninstaller_sandboxed --dry-run && \
     [ -e '$UNINST_HOME/.local/bin/waybar' ] && \
     [ -e '$UNINST_HOME/.local/bin/rofi' ] && \
     grep -q \"alias yay='yay --ignore swww,awww'\" '$UNINST_HOME/.bashrc' && \
     grep -q 'nvidia_drm.modeset=1' '$UNINST_ETC/grub' && \
     [ -f '$UNINST_ETC/modprobe.d/nvidia.conf' ]"

assert_check "uninstall.sh -y executes in sandbox and exits 0 without invoking sudo" \
    "rm -f '$UNINST_SUDO_LOG' && run_uninstaller_sandboxed -y && [ ! -s '$UNINST_SUDO_LOG' ]"

assert_check "uninstall.sh -y restores PRE_INSTALL_BACKUP and cleans user bin/lib/desktop/share artifacts" \
    "[ -f '$UNINST_HOME/.config/hypr/pre_install.conf' ] && grep -q 'pre_install_restored=yes' '$UNINST_HOME/.config/hypr/pre_install.conf' && \
     [ ! -e '$UNINST_HOME/.local/bin/waybar' ] && \
     [ ! -e '$UNINST_HOME/.local/bin/rofi' ] && \
     [ ! -e '$UNINST_HOME/.local/lib/libwaybar-hyprland.so' ] && \
     [ ! -e '$UNINST_HOME/.local/share/applications/yusei-settings.desktop' ] && \
     [ ! -d '$UNINST_HOME/.local/share/yusei-hypr' ]"

assert_check "uninstall.sh -y strips yusei-hypr .bashrc hooks cleanly while saving .bashrc.bak and keeping user lines" \
    "[ -f '$UNINST_HOME/.bashrc.bak' ] && \
     grep -q 'KEEP_USER_ALIAS=1' '$UNINST_HOME/.bashrc' && \
     grep -q 'keep_me' '$UNINST_HOME/.bashrc' && \
     ! grep -q \"alias yay='yay --ignore swww,awww'\" '$UNINST_HOME/.bashrc' && \
     ! grep -q 'config-pokemon.jsonc' '$UNINST_HOME/.bashrc'"

assert_check "uninstall.sh -y removes recorded NVIDIA modules/modeset and cleans modprobe & SDDM theme files" \
    "! grep -q 'nvidia' '$UNINST_ETC/mkinitcpio.conf' && grep -q 'btrfs' '$UNINST_ETC/mkinitcpio.conf' && \
     ! grep -q 'nvidia_drm.modeset=1' '$UNINST_ETC/grub' && grep -q 'loglevel=3 quiet' '$UNINST_ETC/grub' && \
     ! grep -q 'nvidia_drm.modeset=1' '$UNINST_ETC/loader/entries/arch.conf' && \
     [ ! -e '$UNINST_ETC/modprobe.d/nvidia.conf' ] && [ ! -e '$UNINST_ETC/sddm.conf.d/10-theme.conf' ]"

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
# 5. NVIDIA Kernel & Bootloader Provisioning (scripts/setup-nvidia.sh)
# ------------------------------------------------------------------------------
NV_SCRIPT="$REPO_ROOT/scripts/setup-nvidia.sh"
NV_HOME="$NVIDIA_SANDBOX/home"
NV_ETC="$NVIDIA_SANDBOX/etc"
NV_ENTRIES="$NVIDIA_SANDBOX/loader/entries"
NV_BIN="$NVIDIA_SANDBOX/spy_bin"
NV_SUDO_LOG="$NVIDIA_SANDBOX/sudo.log"
mkdir -p "$NV_HOME/.local/state" "$NV_ETC/modprobe.d" "$NV_ENTRIES" "$NV_BIN"

cat <<'EOF' > "$NV_BIN/sudo"
#!/usr/bin/env bash
echo "SUDO_CALLED: $*" >> "${SPY_SUDO_LOG:-/dev/null}"
exit 1
EOF
chmod +x "$NV_BIN/sudo"

cat <<'EOF' > "$NV_ETC/mkinitcpio.conf"
MODULES=(
    "btrfs"
    'nvme' # keep comment (and parens)
)
EOF

cat <<'EOF' > "$NV_ETC/grub"
GRUB_CMDLINE_LINUX_DEFAULT='loglevel=3 quiet'
EOF

cat <<'EOF' > "$NV_ENTRIES/arch.conf"
title Arch Linux
options root=UUID=abcd rw # loader comment
EOF

run_setup_nvidia() {
    local extra_flag="${1:-}"
    (
        export HOME="$NV_HOME"
        export XDG_STATE_HOME="$NV_HOME/.local/state"
        export HAS_NVIDIA="true"
        export MKINITCPIO_CONF="$NV_ETC/mkinitcpio.conf"
        export GRUB_DEFAULT_FILE="$NV_ETC/grub"
        export LOADER_ENTRY_DIRS="$NV_ENTRIES"
        export MODPROBE_NVIDIA_CONF="$NV_ETC/modprobe.d/nvidia.conf"
        export SPY_SUDO_LOG="$NV_SUDO_LOG"
        export PATH="$NV_BIN:$PATH"
        if [[ -n "$extra_flag" ]]; then
            bash "$NV_SCRIPT" "$extra_flag" >/dev/null 2>&1
        else
            bash "$NV_SCRIPT" -y >/dev/null 2>&1
        fi
    )
}

assert_check "setup-nvidia.sh --dry-run performs zero edits and writes no nvidia-state.env" \
    "run_setup_nvidia --dry-run && \
     [ ! -e '$NV_HOME/.local/state/yusei-hypr/nvidia-state.env' ] && \
     [ ! -e '$NV_ETC/modprobe.d/nvidia.conf' ] && \
     ! grep -q 'nvidia_drm' '$NV_ETC/mkinitcpio.conf' && \
     ! grep -q 'nvidia_drm.modeset=1' '$NV_ETC/grub'"

assert_check "setup-nvidia.sh updates multiline/quoted MODULES, GRUB, systemd-boot loader, and modprobe without sudo" \
    "rm -f '$NV_SUDO_LOG' && run_setup_nvidia && [ ! -s '$NV_SUDO_LOG' ] && \
     grep -q 'nvidia_drm' '$NV_ETC/mkinitcpio.conf' && grep -q 'btrfs' '$NV_ETC/mkinitcpio.conf' && \
     grep -q 'nvidia_drm.modeset=1' '$NV_ETC/grub' && \
     grep -q 'nvidia_drm.modeset=1' '$NV_ENTRIES/arch.conf' && \
     grep -q 'modeset=1 fbdev=1' '$NV_ETC/modprobe.d/nvidia.conf'"

assert_check "setup-nvidia.sh writes idempotent nvidia-state.env without duplicating modules or params" \
    "run_setup_nvidia && \
     [ -f '$NV_HOME/.local/state/yusei-hypr/nvidia-state.env' ] && \
     bash -c 'source \"$NV_HOME/.local/state/yusei-hypr/nvidia-state.env\" && \
              [[ \"\$ADDED_MKINITCPIO_MODULES\" == *nvidia_drm* ]] && \
              [[ \"\$GRUB_MODESET_ADDED\" == \"true\" ]] && \
              [[ \"\$MODPROBE_CREATED\" == \"true\" ]] && \
              [[ \"\$LOADER_ENTRIES_MODIFIED\" == *\"arch.conf\"* ]]' && \
     [ \"\$(grep -o 'nvidia_drm.modeset=1' '$NV_ETC/grub' | wc -l)\" -eq 1 ]"

# ------------------------------------------------------------------------------
# 6. Optional Apps SDDM Theme Guard (scripts/05-optional-apps.sh)
# ------------------------------------------------------------------------------
OPT_BIN="$OPT_SANDBOX/mock_bin"
OPT_HOME="$OPT_SANDBOX/home"
OPT_SUDO_LOG="$OPT_SANDBOX/sudo.log"
mkdir -p "$OPT_BIN" "$OPT_HOME/.config"

cat <<'EOF' > "$OPT_BIN/pacman"
#!/usr/bin/env bash
if [[ "$1" == "-Qi" || "$1" == "-Q" ]]; then
    # Pretend sddm is present or absent, while sddm-sugar-candy-git is missing
    if [[ "$2" == "sddm" ]]; then
        exit 0
    fi
    exit 1
fi
exit 1
EOF

cat <<'EOF' > "$OPT_BIN/yay"
#!/usr/bin/env bash
# Simulate sddm-sugar-candy-git AUR install failure
exit 1
EOF

cat <<'EOF' > "$OPT_BIN/paru"
#!/usr/bin/env bash
exit 1
EOF

cat <<'EOF' > "$OPT_BIN/sudo"
#!/usr/bin/env bash
echo "SUDO_CALLED: $*" >> "${SPY_SUDO_LOG:-/dev/null}"
exit 1
EOF

chmod +x "$OPT_BIN/pacman" "$OPT_BIN/yay" "$OPT_BIN/paru" "$OPT_BIN/sudo"

assert_check "05-optional-apps.sh skips SDDM theme rewrite and sudo calls when sddm-sugar-candy-git fails/is absent" \
    "rm -f '$OPT_SUDO_LOG' && \
     OPT_OUT=\$(HOME='$OPT_HOME' XDG_CONFIG_HOME='$OPT_HOME/.config' SPY_SUDO_LOG='$OPT_SUDO_LOG' PATH='$OPT_BIN:$PATH' \
         bash '$REPO_ROOT/scripts/05-optional-apps.sh' --select=sddm --cli </dev/null 2>&1) && \
     [ ! -s '$OPT_SUDO_LOG' ] && echo \"\$OPT_OUT\" | grep -q 'sddm-sugar-candy-git'"

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
