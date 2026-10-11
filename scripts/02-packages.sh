#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Package Installation Module
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}:: [2/4] Kiểm tra và cài đặt phần mềm phụ thuộc (Dependencies)...${NC}"

# Nạp thông tin phần cứng đã quét
if [ -f /tmp/yusei-hypr/detected.env ]; then
    . /tmp/yusei-hypr/detected.env
fi

# 1. Tìm kiếm AUR helper (yay hoặc paru)
AUR_HELPER=""
if command -v yay &> /dev/null; then
    AUR_HELPER="yay"
elif command -v paru &> /dev/null; then
    AUR_HELPER="paru"
else
    echo -e "${YELLOW}Chưa tìm thấy yay hoặc paru. Đang tiến hành cài đặt 'yay'...${NC}"
    sudo pacman -S --needed --noconfirm base-devel git
    git clone https://aur.archlinux.org/yay.git /tmp/yay-install
    (cd /tmp/yay-install && makepkg -si --noconfirm)
    rm -rf /tmp/yay-install
    AUR_HELPER="yay"
fi
echo -e "${GREEN}✓ Sử dụng AUR helper: $AUR_HELPER${NC}"

# 2. Danh sách các gói cần thiết
PACKAGES=(
    # Core Hyprland
    hyprland
    hypridle
    hyprlock
    xdg-desktop-portal-hyprland
    polkit-gnome

    # Desktop Components (End-4 Material UI)
    waybar
    rofi-wayland
    swaync
    swww
    kitty
    ttf-jetbrains-mono-nerd

    # Audio & Media
    pipewire
    wireplumber
    pipewire-audio
    pipewire-pulse
    pavucontrol
    playerctl

    # System Controls & Utilities
    brightnessctl
    grim
    slurp
    wl-clipboard
    cliphist
    thunar
    bc
    jq
    socat
    curl
    libnotify
    imagemagick
    mpv

    # JaKooLit Desktop Enhancements & Utilities
    wlogout
    fastfetch
    btop
    cava
    swappy
    pokemon-colorscripts-git

    # Vietnamese Input Method (Fcitx5)
    fcitx5
    fcitx5-unikey
    fcitx5-gtk
    fcitx5-qt
    fcitx5-configtool
)

# Thêm driver nếu có card NVIDIA
if [ "$HAS_NVIDIA" = "true" ]; then
    PACKAGES+=(nvidia-dkms nvidia-utils libva-nvidia-driver)
fi

# 3. Lọc ra các gói chưa cài đặt để cài bổ sung
TO_INSTALL=()
for pkg in "${PACKAGES[@]}"; do
    if ! pacman -Qi "$pkg" &> /dev/null; then
        TO_INSTALL+=("$pkg")
    fi
done

if [ ${#TO_INSTALL[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ Tất cả các gói phần mềm cần thiết đã được cài đặt sẵn!${NC}\n"
else
    echo -e "${YELLOW}Đang cài đặt các gói còn thiếu: ${TO_INSTALL[*]}${NC}"
    $AUR_HELPER -S --needed --noconfirm "${TO_INSTALL[@]}"
    echo -e "${GREEN}✓ Cài đặt phần mềm hoàn tất!${NC}\n"
fi
