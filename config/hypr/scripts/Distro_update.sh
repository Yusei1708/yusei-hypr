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
  kitty -T update -e bash -c "
    if pacman -Qi awww >/dev/null 2>&1; then
      echo ':: Removing conflicting awww package and locking swww...'
      sudo pacman -Rdd --noconfirm awww || true
      if [ -f \"\$HOME/App/swww/swww-0.9.5-1-x86_64.pkg.tar.zst\" ]; then
        sudo pacman -U --noconfirm \"\$HOME/App/swww/swww-0.9.5-1-x86_64.pkg.tar.zst\" || true
      fi
    fi
    if ! grep -Eq '^IgnorePkg\s*=.*swww' /etc/pacman.conf 2>/dev/null; then
      sudo sed -i 's/^#*\s*IgnorePkg\s*=.*/IgnorePkg = swww awww/' /etc/pacman.conf 2>/dev/null || true
    fi
    $AUR_CMD -Syu --ignore swww,awww
    if [ -d \"\$HOME/App/swww/pkg/swww/usr/bin\" ]; then
      mkdir -p \"\$HOME/.local/bin\"
      cp -f \"\$HOME/App/swww/pkg/swww/usr/bin/swww\" \"\$HOME/.local/bin/swww\"
      cp -f \"\$HOME/App/swww/pkg/swww/usr/bin/swww-daemon\" \"\$HOME/.local/bin/swww-daemon\"
      chmod +x \"\$HOME/.local/bin/swww\" \"\$HOME/.local/bin/swww-daemon\"
    fi
    if ! pgrep -x swww-daemon >/dev/null 2>&1; then
      nohup \"\$HOME/.local/bin/swww-daemon\" --format xrgb >/dev/null 2>&1 &
      sleep 0.3
      [ -e \"\$HOME/.config/hypr/.current_wallpaper\" ] && \"\$HOME/.local/bin/swww\" img \"\$(readlink -f \"\$HOME/.config/hypr/.current_wallpaper\")\" >/dev/null 2>&1 || true
    fi
  "
  notify-send -i "$iDIR/ja.png" -u low 'Arch-based system' 'has been updated (swww protected).'
elif command -v dnf &> /dev/null; then
  # Fedora-based
  kitty -T update -e sudo dnf update --refresh -y
  notify-send -i "$iDIR/ja.png" -u low 'Fedora system' 'has been updated.'
elif command -v apt &> /dev/null; then
  # Debian-based (Debian, Ubuntu, etc.)
  kitty -T update -e bash -c "sudo apt update && sudo apt upgrade -y"
  notify-send -i "$iDIR/ja.png" -u low 'Debian/Ubuntu system' 'has been updated.'
elif command -v zypper &> /dev/null; then
  # openSUSE-based
  kitty -T update -e sudo zypper dup -y
  notify-send -i "$iDIR/ja.png" -u low 'openSUSE system' 'has been updated.'
else
  # Unsupported distro
  notify-send -i "$iDIR/error.png" -u critical "Unsupported system" "This script does not support your distribution."
  exit 1
fi
