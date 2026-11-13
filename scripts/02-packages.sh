#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Package Installation Module
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if genuine swww package is installed (not awww via Provides: swww)
is_real_swww_pkg_installed() {
    local pkg_name
    pkg_name="$(pacman -Q swww 2>/dev/null | awk '{print $1}' || true)"
    [[ "$pkg_name" == "swww" ]]
}

# Safely merge swww and awww into [options] IgnorePkg in pacman.conf without clobbering user entries
ensure_pacman_ignorepkg() {
    local conf_path="${1:-/etc/pacman.conf}"
    [[ -f "$conf_path" ]] || return 1

    local updated_content
    updated_content="$(python3 - "$conf_path" << 'PYEOF'
import re
import sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

req_pkgs = ['swww', 'awww']
in_options = False
options_found = False
options_end_idx = len(lines)
active_ignore_idx = None
commented_empty_ignore_idx = None

for i, line in enumerate(lines):
    stripped = line.strip()
    m_sec = re.match(r'^\[([^\]]+)\]\s*(?:#.*)?$', stripped)
    if m_sec:
        if in_options:
            options_end_idx = i
            break
        if m_sec.group(1) == 'options':
            in_options = True
            options_found = True
        continue
    if in_options:
        if re.match(r'^\s*IgnorePkg\s*=', line):
            if active_ignore_idx is None:
                active_ignore_idx = i
        elif re.match(r'^\s*#\s*IgnorePkg\s*=\s*(?:#.*)?$', line):
            if commented_empty_ignore_idx is None:
                commented_empty_ignore_idx = i

if active_ignore_idx is not None:
    line = lines[active_ignore_idx]
    nl = '\n' if line.endswith('\n') else ''
    body = line.rstrip('\r\n')
    comment = ''
    if '#' in body:
        idx_c = body.index('#')
        comment = ' ' + body[idx_c:].strip()
        body = body[:idx_c]
    lhs, _, rhs = body.partition('=')
    pkgs = rhs.split()
    for p in req_pkgs:
        if p not in pkgs:
            pkgs.append(p)
    lines[active_ignore_idx] = f"IgnorePkg = {' '.join(pkgs)}{comment}{nl}"
elif commented_empty_ignore_idx is not None:
    line = lines[commented_empty_ignore_idx]
    nl = '\n' if line.endswith('\n') else ''
    lines[commented_empty_ignore_idx] = f"IgnorePkg = {' '.join(req_pkgs)}{nl}"
elif options_found:
    insert_at = options_end_idx
    while insert_at > 0 and lines[insert_at - 1].strip() == '':
        insert_at -= 1
    lines.insert(insert_at, f"IgnorePkg = {' '.join(req_pkgs)}\n")
else:
    if lines and not lines[-1].endswith('\n'):
        lines[-1] += '\n'
    lines.append('[options]\n')
    lines.append(f"IgnorePkg = {' '.join(req_pkgs)}\n")

sys.stdout.write(''.join(lines))
PYEOF
)" || return 1

    if [[ -z "$updated_content" ]]; then
        return 1
    fi

    local tmp_conf
    tmp_conf="$(mktemp)"
    printf '%s' "$updated_content" > "$tmp_conf"
    if cmp -s "$tmp_conf" "$conf_path"; then
        rm -f "$tmp_conf"
        return 0
    fi

    if [[ -w "$conf_path" ]]; then
        cp "$tmp_conf" "$conf_path"
    else
        sudo cp "$tmp_conf" "$conf_path"
        sudo chmod 644 "$conf_path"
    fi
    rm -f "$tmp_conf"
}

if [[ "${YUSEI_PACKAGES_LIB_ONLY:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

echo -e "${BLUE}:: [Packages] Kiểm tra và cài đặt phần mềm phụ thuộc (Dependencies)...${NC}"

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo -e "${RED}[ERROR] Không chạy 02-packages.sh trực tiếp bằng root/sudo! AUR helper (yay/paru) và makepkg cấm quyền root.${NC}" >&2
    echo -e "${YELLOW}Vui lòng chạy dưới tài khoản user thường có quyền sudo.${NC}" >&2
    exit 1
fi

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

# 0. Đảm bảo base-devel và git luôn sẵn sàng (kể cả khi yay/paru đã cài sẵn; cần cho gcc biên dịch libwaybar-hyprland.so)
if ! pacman -Qi base-devel &>/dev/null || ! command -v gcc &>/dev/null || ! command -v git &>/dev/null; then
    echo -e "${BLUE}:: Cài đặt base-devel và git...${NC}"
    sudo pacman -S --needed --noconfirm base-devel git
fi

# 1. Tìm kiếm AUR helper (yay hoặc paru)
AUR_HELPER=""
if command -v yay &> /dev/null; then
    AUR_HELPER="yay"
elif command -v paru &> /dev/null; then
    AUR_HELPER="paru"
else
    echo -e "${YELLOW}Chưa tìm thấy yay hoặc paru. Đang tiến hành cài đặt 'yay'...${NC}"
    rm -rf /tmp/yay-install
    trap 'rm -rf /tmp/yay-install' EXIT
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

# 2b. Xử lý xung đột awww vs swww và cài đặt swww cố định đi kèm trong yusei-hypr
if pacman -Q awww &> /dev/null; then
    echo -e "${YELLOW}:: Phát hiện gói 'awww' gây xung đột với swww (Provides: swww). Đang gỡ bỏ awww...${NC}"
    sudo pacman -Rdd --noconfirm awww
fi
ensure_pacman_ignorepkg /etc/pacman.conf || echo -e "${YELLOW}⚠️ Không thể cập nhật IgnorePkg trong /etc/pacman.conf${NC}"
BUNDLED_SWWW_PKG="$SCRIPT_DIR/assets/packages/swww-0.9.5-1-x86_64.pkg.tar.zst"
if [[ -f "$BUNDLED_SWWW_PKG" ]] && ! is_real_swww_pkg_installed; then
    echo -e "${BLUE}:: Cài đặt gói swww (0.9.5) đi kèm trong yusei-hypr...${NC}"
    sudo pacman -U --noconfirm "$BUNDLED_SWWW_PKG"
fi
if [[ -x "$SCRIPT_DIR/bin/swww" && -x "$SCRIPT_DIR/bin/swww-daemon" ]]; then
    mkdir -p "$HOME/.local/bin"
    cp -f "$SCRIPT_DIR/bin/swww" "$HOME/.local/bin/swww"
    cp -f "$SCRIPT_DIR/bin/swww-daemon" "$HOME/.local/bin/swww-daemon"
    chmod +x "$HOME/.local/bin/swww" "$HOME/.local/bin/swww-daemon"
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
    # Lưu ý: swww KHÔNG cài qua pacman/yay vì kho Arch sẽ ép tải awww (Replaces: swww);
    # swww đã được cài trực tiếp từ bản đóng gói bên trong repo (assets/packages/ & bin/)
    waybar
    rofi-wayland
    swaync
    kitty
    wallust
    qt5ct
    qt6ct
    kvantum

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
    pamixer
    playerctl

    # Bluetooth & Network Stack
    bluez
    bluez-utils
    blueman
    network-manager-applet

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
    pacman-contrib
    yad
    hyprpicker
    hyprsunset
    wf-recorder
    tesseract
    tesseract-data-eng

    # Python runtime dependencies (yusei_settings GTK/Web & PIL theme extraction)
    python-gobject
    python-pillow
    python-requests

    # JaKooLit Desktop Enhancements & Utilities (Desktop Overview & Tools)
    wlogout
    fastfetch
    btop
    cava
    swappy
    quickshell
    qt6-5compat
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

# Thêm tiện ích quản lý năng lượng và pin cho Laptop
if [ "$IS_LAPTOP" = "true" ]; then
    echo -e "${BLUE}:: Bổ sung gói quản lý pin và năng lượng cho Laptop (acpi, power-profiles-daemon)...${NC}"
    PACKAGES+=(
        acpi
        power-profiles-daemon
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
