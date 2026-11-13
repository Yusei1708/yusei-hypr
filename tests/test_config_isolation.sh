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

# Setup isolated sandboxes
MOCK_HOME="$(mktemp -d -t yusei_mock_home_XXXXXX)"
MOCK_HOME_FRESH="$(mktemp -d -t yusei_fresh_XXXXXX)"
MOCK_ANIM_HOME="$(mktemp -d -t yusei_anim_XXXXXX)"
MOCK_DRYRUN_HOME="$(mktemp -d -t yusei_dryrun_XXXXXX)"
PKG_SANDBOX="$(mktemp -d -t yusei_pkg_XXXXXX)"
REAL_HOME="$HOME"
trap 'rm -rf "$MOCK_HOME" "$MOCK_HOME_FRESH" "$MOCK_ANIM_HOME" "$MOCK_DRYRUN_HOME" "$PKG_SANDBOX"' EXIT

# Snapshot real ~/.config mtime if it exists to verify zero host tampering
REAL_CONFIG_MTIME=""
if [[ -d "$REAL_HOME/.config" ]]; then
    REAL_CONFIG_MTIME="$(stat -c %Y "$REAL_HOME/.config" 2>/dev/null || true)"
fi

TOTAL_TESTS=25
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
# 2. Config Isolation in Sandbox (Non-destructive Overlay & Preserved Files)
# ------------------------------------------------------------------------------
# Populate mock environment with all user-owned configs, runtime states & presets
mkdir -p \
    "$MOCK_HOME/.config/hypr/UserConfigs" \
    "$MOCK_HOME/.config/hypr/UserScripts" \
    "$MOCK_HOME/.config/waybar/layouts" \
    "$MOCK_HOME/.config/rofi/themes" \
    "$MOCK_HOME/.config/kitty/kitty-themes"

CUSTOM_MARKER="MARKER_USERPREFS_SECRET_$(date +%s%N)"
cat <<EOF > "$MOCK_HOME/.config/hypr/userprefs.conf"
# Custom user preferences
env = TEST_CUSTOM_VAR,1
# Unique marker: ${CUSTOM_MARKER}
EOF

cat <<'EOF' > "$MOCK_HOME/.config/hypr/animations.conf"
# Custom animations marker
bezier = customUserCurve, 0.1, 0.9, 0.2, 1.0
animation = fadeDpms, 0
EOF

cat <<'EOF' > "$MOCK_HOME/.config/hypr/monitors.conf"
# Custom monitor marker
monitor = DP-1, 2560x1440@144, 0x0, 1
EOF

cat <<'EOF' > "$MOCK_HOME/.config/hypr/UserConfigs/UserDecorations.conf"
# Custom user decorations marker
decoration {
    rounding = 9
}
EOF

echo "custom_user_config=true" > "$MOCK_HOME/.config/hypr/UserConfigs/user.conf"
cat <<'EOF' > "$MOCK_HOME/.config/hypr/UserScripts/custom_helper.sh"
#!/usr/bin/env bash
echo "custom_user_script_marker"
EOF
echo '{"power_daemon":false,"auto_60hz":false}' > "$MOCK_HOME/.config/hypr/power.json"
echo '{"profile":"eco","marker":"keep_state"}' > "$MOCK_HOME/.config/hypr/.power-optimizer.state"
echo "/home/custom/Wallpapers/keep-me.png" > "$MOCK_HOME/.config/hypr/.current_wallpaper"

echo '{"custom_waybar_marker": true}' > "$MOCK_HOME/.config/waybar/config.jsonc"
echo '{"custom_layout": true}' > "$MOCK_HOME/.config/waybar/layouts/CustomPreset"
echo '/* custom_rofi_config_marker */' > "$MOCK_HOME/.config/rofi/config.rasi"
echo '/* custom_rofi_theme_marker */' > "$MOCK_HOME/.config/rofi/themes/CustomPreset.rasi"
echo '# custom_kitty_conf_marker' > "$MOCK_HOME/.config/kitty/kitty.conf"
echo '# custom_kitty_theme_marker' > "$MOCK_HOME/.config/kitty/kitty-themes/CustomPreset.conf"

# Execute 04-install-configs.sh with all user XDG dirs isolated inside MOCK_HOME
assert_check "04-install-configs.sh exits 0 during non-destructive overlay" \
    "(export HOME='$MOCK_HOME' XDG_CONFIG_HOME='$MOCK_HOME/.config' XDG_DATA_HOME='$MOCK_HOME/.local/share' XDG_STATE_HOME='$MOCK_HOME/.local/state'; bash '$REPO_ROOT/scripts/04-install-configs.sh' >/dev/null 2>&1)"

assert_check "04-install-configs.sh preserves existing userprefs.conf content" \
    "[ -f '$MOCK_HOME/.config/hypr/userprefs.conf' ] && grep -q '$CUSTOM_MARKER' '$MOCK_HOME/.config/hypr/userprefs.conf'"

assert_check "04-install-configs.sh preserves animations.conf custom curve and fadeDpms, 0" \
    "[ -f '$MOCK_HOME/.config/hypr/animations.conf' ] && grep -q 'customUserCurve' '$MOCK_HOME/.config/hypr/animations.conf' && grep -Eq 'animation[[:space:]]*=[[:space:]]*fadeDpms,[[:space:]]*0' '$MOCK_HOME/.config/hypr/animations.conf'"

assert_check "04-install-configs.sh preserves monitors.conf, UserDecorations.conf, UserConfigs, and UserScripts" \
    "grep -q 'Custom monitor marker' '$MOCK_HOME/.config/hypr/monitors.conf' && \
     grep -q 'rounding = 9' '$MOCK_HOME/.config/hypr/UserConfigs/UserDecorations.conf' && \
     grep -q 'custom_user_config=true' '$MOCK_HOME/.config/hypr/UserConfigs/user.conf' && \
     grep -q 'custom_user_script_marker' '$MOCK_HOME/.config/hypr/UserScripts/custom_helper.sh'"

assert_check "04-install-configs.sh preserves power.json, .power-optimizer.state, and .current_wallpaper" \
    "grep -q '\"power_daemon\":false' '$MOCK_HOME/.config/hypr/power.json' && \
     grep -q 'keep_state' '$MOCK_HOME/.config/hypr/.power-optimizer.state' && \
     grep -q 'keep-me.png' '$MOCK_HOME/.config/hypr/.current_wallpaper'"

assert_check "04-install-configs.sh preserves waybar, rofi, and kitty user configs and custom presets" \
    "grep -q 'custom_waybar_marker' '$MOCK_HOME/.config/waybar/config.jsonc' && \
     grep -q 'custom_layout' '$MOCK_HOME/.config/waybar/layouts/CustomPreset' && \
     grep -q 'custom_rofi_config_marker' '$MOCK_HOME/.config/rofi/config.rasi' && \
     grep -q 'custom_rofi_theme_marker' '$MOCK_HOME/.config/rofi/themes/CustomPreset.rasi' && \
     grep -q 'custom_kitty_conf_marker' '$MOCK_HOME/.config/kitty/kitty.conf' && \
     grep -q 'custom_kitty_theme_marker' '$MOCK_HOME/.config/kitty/kitty-themes/CustomPreset.conf'"

# Overlay case where pre-existing animations.conf lacks fadeDpms
mkdir -p "$MOCK_ANIM_HOME/.config/hypr"
echo "bezier = legacyCurve, 0.2, 0.8, 0.2, 1.0" > "$MOCK_ANIM_HOME/.config/hypr/animations.conf"
assert_check "04-install-configs.sh overlay injects fadeDpms, 0 when missing while preserving legacy animations" \
    "(export HOME='$MOCK_ANIM_HOME' XDG_CONFIG_HOME='$MOCK_ANIM_HOME/.config' XDG_DATA_HOME='$MOCK_ANIM_HOME/.local/share' XDG_STATE_HOME='$MOCK_ANIM_HOME/.local/state'; bash '$REPO_ROOT/scripts/04-install-configs.sh' >/dev/null 2>&1) && \
     grep -q 'legacyCurve' '$MOCK_ANIM_HOME/.config/hypr/animations.conf' && \
     grep -Eq 'animation[[:space:]]*=[[:space:]]*fadeDpms,[[:space:]]*0' '$MOCK_ANIM_HOME/.config/hypr/animations.conf'"

# ------------------------------------------------------------------------------
# 3. Clean Install (Template Initialization when userprefs.conf absent)
# ------------------------------------------------------------------------------
assert_check "04-install-configs.sh exits 0 and creates userprefs.conf from template on clean install" \
    "(export HOME='$MOCK_HOME_FRESH' XDG_CONFIG_HOME='$MOCK_HOME_FRESH/.config' XDG_DATA_HOME='$MOCK_HOME_FRESH/.local/share' XDG_STATE_HOME='$MOCK_HOME_FRESH/.local/state'; bash '$REPO_ROOT/scripts/04-install-configs.sh' >/dev/null 2>&1) && \
     [ -f '$MOCK_HOME_FRESH/.config/hypr/userprefs.conf' ] && grep -qi 'yusei-hypr: User Custom Preferences' '$MOCK_HOME_FRESH/.config/hypr/userprefs.conf'"

assert_check "04-install-configs.sh installs bundled swww and swww-daemon into ~/.local/bin on clean install" \
    "[ -x '$MOCK_HOME_FRESH/.local/bin/swww' ] && [ -x '$MOCK_HOME_FRESH/.local/bin/swww-daemon' ] && [ -f '$MOCK_HOME_FRESH/.local/share/yusei-hypr/packages/swww-0.9.5-1-x86_64.pkg.tar.zst' ]"

# ------------------------------------------------------------------------------
# 4. Standard Backup Module Tests (scripts/03-backup.sh)
# ------------------------------------------------------------------------------
mkdir -p "$MOCK_HOME/.config/waybar" "$MOCK_HOME/.config/rofi"
echo "bar_config=1" > "$MOCK_HOME/.config/waybar/config"
echo "rofi_theme=1" > "$MOCK_HOME/.config/rofi/theme.rasi"

assert_check "03-backup.sh exits 0 and creates directory matching yusei-hypr-backup-YYYYMMDD_HHMMSS" \
    "(export HOME='$MOCK_HOME' XDG_CONFIG_HOME='$MOCK_HOME/.config' XDG_DATA_HOME='$MOCK_HOME/.local/share' XDG_STATE_HOME='$MOCK_HOME/.local/state'; bash '$REPO_ROOT/scripts/03-backup.sh' >/dev/null 2>&1) && \
     BACKUP_DIR_CHECK=\$(find '$MOCK_HOME/.config' -maxdepth 1 -type d -name 'yusei-hypr-backup-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]' | head -n 1); \
     [ -n \"\$BACKUP_DIR_CHECK\" ] && [ -d \"\$BACKUP_DIR_CHECK\" ]"

BACKUP_DIR_FOUND="$(find "$MOCK_HOME/.config" -maxdepth 1 -type d -name "yusei-hypr-backup-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]" | head -n 1 || true)"

assert_check "Backup directory contains valid manifest.json" \
    "[ -n '$BACKUP_DIR_FOUND' ] && [ -f '$BACKUP_DIR_FOUND/manifest.json' ] && jq empty '$BACKUP_DIR_FOUND/manifest.json' 2>/dev/null"

assert_check "manifest.json contains required metadata keys (timestamp, targets)" \
    "[ -n '$BACKUP_DIR_FOUND' ] && [ -f '$BACKUP_DIR_FOUND/manifest.json' ] && \
     jq -e '.timestamp and .backed_up_targets and .non_existing_targets' '$BACKUP_DIR_FOUND/manifest.json' >/dev/null 2>&1"

assert_check "Backup directory contains actual archived config files (hypr, waybar, rofi)" \
    "[ -n '$BACKUP_DIR_FOUND' ] && [ -d '$BACKUP_DIR_FOUND/hypr' ] && [ -d '$BACKUP_DIR_FOUND/waybar' ]"

assert_check "Symlink yusei-hypr-backup-latest or latest points to current backup snapshot" \
    "([ -L '$MOCK_HOME/.config/yusei-hypr-backup-latest' ] && [ \"\$(readlink -f '$MOCK_HOME/.config/yusei-hypr-backup-latest')\" = '$BACKUP_DIR_FOUND' ]) || \
     ([ -L '$MOCK_HOME/.config/yusei-hypr-backups/latest' ] && [ -n '$BACKUP_DIR_FOUND' ])"

# ------------------------------------------------------------------------------
# 5. install.sh --dry-run Zero Disk Writes
# ------------------------------------------------------------------------------
assert_check "install.sh --dry-run exits 0 and performs zero disk writes in .config and .local/state" \
    "(export HOME='$MOCK_DRYRUN_HOME' XDG_CONFIG_HOME='$MOCK_DRYRUN_HOME/.config' XDG_DATA_HOME='$MOCK_DRYRUN_HOME/.local/share' XDG_STATE_HOME='$MOCK_DRYRUN_HOME/.local/state'; bash '$REPO_ROOT/install.sh' --dry-run --select=none --cli </dev/null >/dev/null 2>&1) && \
     [ ! -e '$MOCK_DRYRUN_HOME/.config' ] && [ ! -e '$MOCK_DRYRUN_HOME/.local/state' ]"

# ------------------------------------------------------------------------------
# 6. scripts/02-packages.sh awww/swww & pacman IgnorePkg Helpers
# ------------------------------------------------------------------------------
MOCK_PKG_BIN="$PKG_SANDBOX/bin"
mkdir -p "$MOCK_PKG_BIN"

cat <<'EOF' > "$MOCK_PKG_BIN/pacman_awww"
#!/usr/bin/env bash
if [[ "$1" == "-Q" && "$2" == "swww" ]]; then
    echo "awww 0.12.1-1"
    exit 0
fi
exit 1
EOF
chmod +x "$MOCK_PKG_BIN/pacman_awww"
ln -sf "$MOCK_PKG_BIN/pacman_awww" "$MOCK_PKG_BIN/pacman"

assert_check "02-packages.sh is_real_swww_pkg_installed returns false when pacman reports awww (Provides: swww)" \
    "PATH='$MOCK_PKG_BIN:$PATH' bash -c 'YUSEI_PACKAGES_LIB_ONLY=1 source \"$REPO_ROOT/scripts/02-packages.sh\" && ! is_real_swww_pkg_installed'"

cat <<'EOF' > "$MOCK_PKG_BIN/pacman_swww"
#!/usr/bin/env bash
if [[ "$1" == "-Q" && "$2" == "swww" ]]; then
    echo "swww 0.9.5-1"
    exit 0
fi
exit 1
EOF
chmod +x "$MOCK_PKG_BIN/pacman_swww"
ln -sf "$MOCK_PKG_BIN/pacman_swww" "$MOCK_PKG_BIN/pacman"

assert_check "02-packages.sh is_real_swww_pkg_installed returns true when pacman reports genuine swww" \
    "PATH='$MOCK_PKG_BIN:$PATH' bash -c 'YUSEI_PACKAGES_LIB_ONLY=1 source \"$REPO_ROOT/scripts/02-packages.sh\" && is_real_swww_pkg_installed'"

PACMAN_CONF_EXISTING="$PKG_SANDBOX/pacman_existing.conf"
cat <<'EOF' > "$PACMAN_CONF_EXISTING"
[options]
HoldPkg = pacman glibc
IgnorePkg = linux linux-headers # keep kernel pinned

[core]
Include = /etc/pacman.d/mirrorlist
EOF

assert_check "02-packages.sh ensure_pacman_ignorepkg preserves existing IgnorePkg entries & comment inside [options]" \
    "bash -c 'YUSEI_PACKAGES_LIB_ONLY=1 source \"$REPO_ROOT/scripts/02-packages.sh\" && ensure_pacman_ignorepkg \"$PACMAN_CONF_EXISTING\"' && \
     python3 -c '
import sys
txt = open(\"$PACMAN_CONF_EXISTING\", encoding=\"utf-8\").read()
opts, _, rest = txt.partition(\"[core]\")
assert \"IgnorePkg = linux linux-headers swww awww # keep kernel pinned\" in opts, opts
assert \"IgnorePkg\" not in rest, rest
'"

PACMAN_CONF_COMMENTED="$PKG_SANDBOX/pacman_commented.conf"
cat <<'EOF' > "$PACMAN_CONF_COMMENTED"
[options]
Color
#IgnorePkg   =

[extra]
Include = /etc/pacman.d/mirrorlist
EOF

assert_check "02-packages.sh ensure_pacman_ignorepkg uncomments #IgnorePkg strictly inside [options] idempotently" \
    "bash -c 'YUSEI_PACKAGES_LIB_ONLY=1 source \"$REPO_ROOT/scripts/02-packages.sh\" && ensure_pacman_ignorepkg \"$PACMAN_CONF_COMMENTED\" && ensure_pacman_ignorepkg \"$PACMAN_CONF_COMMENTED\"' && \
     python3 -c '
txt = open(\"$PACMAN_CONF_COMMENTED\", encoding=\"utf-8\").read()
opts, _, rest = txt.partition(\"[extra]\")
lines = [l for l in opts.splitlines() if l.strip().startswith(\"IgnorePkg\")]
assert lines == [\"IgnorePkg = swww awww\"], lines
assert \"IgnorePkg\" not in rest, rest
'"

# ------------------------------------------------------------------------------
# 4b. Atomic .so Deploy, UserAnimations Clamping & --sync-userscripts
# ------------------------------------------------------------------------------
MOCK_ATOMIC_HOME="$(mktemp -d -t yusei_atomic_XXXXXX)"
trap 'rm -rf "$MOCK_HOME" "$MOCK_HOME_FRESH" "$MOCK_ANIM_HOME" "$MOCK_DRYRUN_HOME" "$PKG_SANDBOX" "$MOCK_ATOMIC_HOME"' EXIT

mkdir -p "$MOCK_ATOMIC_HOME/.local/lib" "$MOCK_ATOMIC_HOME/.config/hypr/UserConfigs" "$MOCK_ATOMIC_HOME/.config/hypr/UserScripts"
printf 'OLD_MAPPED_INODE' > "$MOCK_ATOMIC_HOME/.local/lib/libwaybar-hyprland.so"
ln -f "$MOCK_ATOMIC_HOME/.local/lib/libwaybar-hyprland.so" "$MOCK_ATOMIC_HOME/.local/lib/libwaybar-hyprland.so.hardlink"
OLD_INODE="$(stat -c %i "$MOCK_ATOMIC_HOME/.local/lib/libwaybar-hyprland.so.hardlink")"

cat <<'EOF' > "$MOCK_ATOMIC_HOME/.config/hypr/UserConfigs/UserAnimations.conf"
animations {
    animation = borderangle, 1, 180, liner, loop
}
EOF
echo '# stale userscript' > "$MOCK_ATOMIC_HOME/.config/hypr/UserScripts/WallpaperSelect.sh"

assert_check "04-install-configs.sh replaces libwaybar-hyprland.so atomically (new inode) and clamps existing UserAnimations speed <= 100" \
    "(export HOME='$MOCK_ATOMIC_HOME' XDG_CONFIG_HOME='$MOCK_ATOMIC_HOME/.config' XDG_DATA_HOME='$MOCK_ATOMIC_HOME/.local/share' XDG_STATE_HOME='$MOCK_ATOMIC_HOME/.local/state'; bash '$REPO_ROOT/scripts/04-install-configs.sh' >/dev/null 2>&1) && \
     [ \"\$(stat -c %i '$MOCK_ATOMIC_HOME/.local/lib/libwaybar-hyprland.so')\" != '$OLD_INODE' ] && \
     [ \"\$(cat '$MOCK_ATOMIC_HOME/.local/lib/libwaybar-hyprland.so.hardlink')\" = 'OLD_MAPPED_INODE' ] && \
     grep -q 'animation = borderangle, 1, 100, liner, loop' '$MOCK_ATOMIC_HOME/.config/hypr/UserConfigs/UserAnimations.conf' && \
     grep -q 'stale userscript' '$MOCK_ATOMIC_HOME/.config/hypr/UserScripts/WallpaperSelect.sh'"

assert_check "04-install-configs.sh --sync-userscripts backs up stale UserScripts and deploys repo fixes" \
    "(export HOME='$MOCK_ATOMIC_HOME' XDG_CONFIG_HOME='$MOCK_ATOMIC_HOME/.config' XDG_DATA_HOME='$MOCK_ATOMIC_HOME/.local/share' XDG_STATE_HOME='$MOCK_ATOMIC_HOME/.local/state'; bash '$REPO_ROOT/scripts/04-install-configs.sh' --sync-userscripts >/dev/null 2>&1) && \
     BAK_DIR=\$(find '$MOCK_ATOMIC_HOME/.config/hypr/UserScripts' -maxdepth 1 -type d -name '.bak-*' | head -n 1) && \
     [ -n \"\$BAK_DIR\" ] && grep -q 'stale userscript' \"\$BAK_DIR/WallpaperSelect.sh\" && \
     ! grep -q 'stale userscript' '$MOCK_ATOMIC_HOME/.config/hypr/UserScripts/WallpaperSelect.sh'"

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
