#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Package Installation Module
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}:: [Packages] Kiểm tra và cài đặt phần mềm phụ thuộc (Dependencies)...${NC}"

# Nạp thông tin phần cứng đã quét
HAS_NVIDIA="false"
IS_LAPTOP="false"
KERNEL_PKG="linux"
KERNEL_HEADERS_PKG="linux-headers"
IS_ASUS_ROG="false"

if [ -f /tmp/yusei-hypr/detected.env ]; then
    # shellcheck disable=SC1091
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

# 2. Xử lý xung đột PulseAudio vs PipeWire
echo -e "${BLUE}:: Kiểm tra và loại bỏ các gói PulseAudio gây xung đột...${NC}"
PULSE_CONFLICTS=()
for pulse_pkg in pulseaudio pulseaudio-bluetooth pulseaudio-alsa pulseaudio-jack; do
    if pacman -Qi "$pulse_pkg" &> /dev/null; then
        PULSE_CONFLICTS+=("$pulse_pkg")
    fi
done

if [ ${#PULSE_CONFLICTS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Phát hiện các gói PulseAudio: ${PULSE_CONFLICTS[*]}${NC}"
    echo -e "${YELLOW}Đang tháo gỡ an toàn để kích hoạt hệ thống âm thanh hiện đại PipeWire...${NC}"
    sudo pacman -Rdd --noconfirm "${PULSE_CONFLICTS[@]}"
    echo -e "${GREEN}✓ Đã giải quyết triệt để xung đột âm thanh PulseAudio!${NC}"
else
    echo -e "${GREEN}✓ Không có xung đột âm thanh PulseAudio.${NC}"
fi

# 3. Danh sách các gói cần thiết chuẩn hóa tương đương JaKooLit
PACKAGES=(
    # Core Hyprland & Portals
    hyprland
    hypridle
    hyprlock
    xdg-desktop-portal-hyprland
    xdg-desktop-portal
    polkit-gnome

    # Desktop Components (End-4 Material UI)
    waybar
    rofi-wayland
    swaync
    swww
    kitty

    # Fonts & Icons & Cursors (Aesthetics Parity)
    ttf-jetbrains-mono-nerd
    ttf-font-awesome
    noto-fonts-emoji
    bibata-cursor-theme
    papirus-icon-theme

    # Audio & Media (PipeWire Stack)
    pipewire
    wireplumber
    pipewire-audio
    pipewire-pulse
    pipewire-alsa
    pipewire-jack
    pavucontrol
    playerctl

    # Bluetooth Stack
    bluez
    bluez-utils
    blueman

    # File Manager & Thumbnailers (Thunar Suite)
    thunar
    tumbler
    ffmpegthumbnailer
    thunar-archive-plugin
    gvfs
    xarchiver

    # System Controls & Utilities
    brightnessctl
    grim
    slurp
    wl-clipboard
    cliphist
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

# Thêm driver và kernel headers nếu có card NVIDIA
if [ "$HAS_NVIDIA" = "true" ]; then
    echo -e "${BLUE}:: Bổ sung gói Driver NVIDIA và Kernel Headers: ${KERNEL_HEADERS_PKG}...${NC}"
    PACKAGES+=(
        "$KERNEL_HEADERS_PKG"
        nvidia-dkms
        nvidia-utils
        libva-nvidia-driver
    )
fi

# Thêm tiện ích quản lý phần cứng ASUS ROG nếu phát hiện máy ASUS ROG
if [ "$IS_ASUS_ROG" = "true" ]; then
    echo -e "${BLUE}:: Bổ sung tiện ích điều khiển máy ASUS ROG (asusctl, supergfxctl)...${NC}"
    PACKAGES+=(
        asusctl
        supergfxctl
    )
fi

# 4. Lọc ra các gói chưa cài đặt để cài bổ sung
TO_INSTALL=()
for pkg in "${PACKAGES[@]}"; do
    if ! pacman -Qi "$pkg" &> /dev/null; then
        TO_INSTALL+=("$pkg")
    fi
done

if [ ${#TO_INSTALL[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ Tất cả các gói phần mềm cần thiết đã được cài đặt sẵn!${NC}\n"
else
    echo -e "${YELLOW}Đang cài đặt các gói còn thiếu (${#TO_INSTALL[@]} gói): ${TO_INSTALL[*]}${NC}"
    $AUR_HELPER -S --needed --noconfirm "${TO_INSTALL[@]}"
    echo -e "${GREEN}✓ Cài đặt phần mềm hoàn tất!${NC}\n"
fi
