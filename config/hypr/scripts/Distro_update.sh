#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Simple bash script to check and will try to update your system

# Local Paths
iDIR="$HOME/.config/swaync/images"

# Check for required tools (kitty)
if ! command -v kitty &> /dev/null; then
  notify-send -i "$iDIR/error.png" "Need Kitty:" "Kitty terminal not found. Please install Kitty terminal."
  exit 1
fi

# Detect distribution and update accordingly
if command -v paru &> /dev/null || command -v yay &> /dev/null; then
  # Arch-based: prevent pacman/yay/paru from replacing swww with awww
  export PATH="$HOME/.local/bin:$PATH"
  AUR_CMD="yay"
  if command -v paru &> /dev/null; then
    AUR_CMD="paru"
  fi
  PACKAGES_LIB="$HOME/.local/share/yusei-hypr/scripts/02-packages.sh"
  if kitty -T update -e bash -c "
    SWWW_PKG=\"\$HOME/.local/share/yusei-hypr/packages/swww-0.9.5-1-x86_64.pkg.tar.zst\"
    SWWW_BIN_DIR=\"\$HOME/.local/share/yusei-hypr/bin\"
    if pacman -Q awww >/dev/null 2>&1; then
      echo ':: Removing conflicting awww package and locking bundled swww...'
      sudo pacman -Rdd --noconfirm awww || true
    fi
    if [ -f \"\$SWWW_PKG\" ] && [ \"\$(pacman -Q swww 2>/dev/null | awk '{print \$1}')\" != 'swww' ]; then
      sudo pacman -U --noconfirm \"\$SWWW_PKG\" || true
    fi
    if [ -f \"$PACKAGES_LIB\" ]; then
      YUSEI_PACKAGES_LIB_ONLY=1 source \"$PACKAGES_LIB\"
      ensure_pacman_ignorepkg /etc/pacman.conf || true
    fi
    UPDATE_RC=0
    $AUR_CMD -Syu --ignore swww,awww || UPDATE_RC=\$?
    if [ -x \"\$SWWW_BIN_DIR/swww\" ] && [ -x \"\$SWWW_BIN_DIR/swww-daemon\" ]; then
      mkdir -p \"\$HOME/.local/bin\"
      cp -f \"\$SWWW_BIN_DIR/swww\" \"\$HOME/.local/bin/swww\"
      cp -f \"\$SWWW_BIN_DIR/swww-daemon\" \"\$HOME/.local/bin/swww-daemon\"
      chmod +x \"\$HOME/.local/bin/swww\" \"\$HOME/.local/bin/swww-daemon\"
    fi
    if ! pgrep -x swww-daemon >/dev/null 2>&1; then
      nohup \"\$HOME/.local/bin/swww-daemon\" --format xrgb >/dev/null 2>&1 &
      sleep 0.3
      [ -e \"\$HOME/.config/hypr/.current_wallpaper\" ] && \"\$HOME/.local/bin/swww\" img \"\$(readlink -f \"\$HOME/.config/hypr/.current_wallpaper\")\" >/dev/null 2>&1 || true
    fi
    exit \"\$UPDATE_RC\"
  "; then
    notify-send -i "$iDIR/ja.png" -u low 'Arch-based system' 'has been updated (swww protected).'
  else
    notify-send -i "$iDIR/error.png" -u normal 'Arch-based system' 'System update failed or was cancelled.'
    exit 1
  fi
elif command -v dnf &> /dev/null; then
  # Fedora-based
  if kitty -T update -e sudo dnf update --refresh -y; then
    notify-send -i "$iDIR/ja.png" -u low 'Fedora system' 'has been updated.'
  else
    notify-send -i "$iDIR/error.png" -u normal 'Fedora system' 'System update failed or was cancelled.'
    exit 1
  fi
elif command -v apt &> /dev/null; then
  # Debian-based (Debian, Ubuntu, etc.)
  if kitty -T update -e bash -c "sudo apt update && sudo apt upgrade -y"; then
    notify-send -i "$iDIR/ja.png" -u low 'Debian/Ubuntu system' 'has been updated.'
  else
    notify-send -i "$iDIR/error.png" -u normal 'Debian/Ubuntu system' 'System update failed or was cancelled.'
    exit 1
  fi
elif command -v zypper &> /dev/null; then
  # openSUSE-based
  if kitty -T update -e sudo zypper dup -y; then
    notify-send -i "$iDIR/ja.png" -u low 'openSUSE system' 'has been updated.'
  else
    notify-send -i "$iDIR/error.png" -u normal 'openSUSE system' 'System update failed or was cancelled.'
    exit 1
  fi
else
  # Unsupported distro
  notify-send -i "$iDIR/error.png" -u critical "Unsupported system" "This script does not support your distribution."
  exit 1
fi
