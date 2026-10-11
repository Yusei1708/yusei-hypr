#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Config Deployer Module
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}:: [4/4] Đang cài đặt các file cấu hình yusei-hypr vào ~/.config...${NC}"

# Nạp thông tin phần cứng
HAS_NVIDIA="false"
if [ -f /tmp/yusei-hypr/detected.env ]; then
    . /tmp/yusei-hypr/detected.env
fi

# 1. Tạo thư mục .config nếu chưa có
mkdir -p "$HOME/.config"

# 2. Sao chép các thư mục cấu hình
CONFIG_DIRS=("hypr" "waybar" "rofi" "kitty" "swaync" "wlogout" "fastfetch" "btop" "cava" "swappy" "wallust" "Kvantum" "qt5ct" "qt6ct")

for dir in "${CONFIG_DIRS[@]}"; do
    if [[ -d "$SCRIPT_DIR/config/$dir" ]]; then
        rm -rf "$HOME/.config/$dir"
        cp -a "$SCRIPT_DIR/config/$dir" "$HOME/.config/"
        echo -e "${GREEN}✓ Đã triển khai: ~/.config/$dir${NC}"
    fi
done

# Ensure executable permissions for all copied scripts
find "$HOME/.config/hypr/scripts" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
if [[ -d "$HOME/.config/hypr/UserScripts" ]]; then
    find "$HOME/.config/hypr/UserScripts" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
fi

# 3. Kích hoạt NVIDIA nếu được phát hiện
if [ "${HAS_NVIDIA:-false}" = "true" ]; then
    echo -e "${YELLOW}:: Đang kích hoạt nạp nvidia.conf trong hyprland.conf...${NC}"
    if [[ -f "$HOME/.config/hypr/hyprland.conf" ]]; then
        sed -i 's|# source = ~/.config/hypr/nvidia.conf|source = ~/.config/hypr/nvidia.conf|g' "$HOME/.config/hypr/hyprland.conf"
        echo -e "${GREEN}✓ Đã kích hoạt cấu hình tối ưu card đồ họa NVIDIA!${NC}"
    fi
fi

# 4. Sao chép bộ sưu tập hình nền vào ~/Pictures/wallpapers
PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
mkdir -p "$PICTURES_DIR/wallpapers"
if [[ -d "$SCRIPT_DIR/assets/wallpapers" ]]; then
    echo -e "${BLUE}:: Đang đồng bộ bộ sưu tập hình nền vào $PICTURES_DIR/wallpapers...${NC}"
    cp -n "$SCRIPT_DIR/assets/wallpapers"/* "$PICTURES_DIR/wallpapers/" 2>/dev/null || true
    echo -e "${GREEN}✓ Đã cập nhật 20 hình nền nghệ thuật vào $PICTURES_DIR/wallpapers${NC}"
fi

# Thiết lập hình nền mặc định
DEFAULT_WALL="$PICTURES_DIR/wallpapers/16-balcony-twilight.png"
if [[ ! -f "$DEFAULT_WALL" && -f "$SCRIPT_DIR/assets/wallpapers/default.jpg" ]]; then
    DEFAULT_WALL="$SCRIPT_DIR/assets/wallpapers/default.jpg"
fi
if [[ -f "$DEFAULT_WALL" ]]; then
    cp -f "$DEFAULT_WALL" "$HOME/.config/hypr/wallpaper.jpg"
fi

# 5. Cấu hình Pokemon Fastfetch cho Shell Terminal (Zsh & Bash)
POKEMON_BANNER='pokemon-colorscripts --no-title -s -r | fastfetch -c $HOME/.config/fastfetch/config-pokemon.jsonc --logo-type file-raw --logo-height 10 --logo-width 5 --logo -'
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [[ -f "$rc" ]]; then
        if ! grep -q "config-pokemon.jsonc" "$rc"; then
            echo "" >> "$rc"
            echo "# Pokemon Fastfetch Banner (yusei-hypr)" >> "$rc"
            echo "$POKEMON_BANNER" >> "$rc"
            echo -e "${GREEN}✓ Đã tích hợp Pokemon Fastfetch vào $(basename "$rc")${NC}"
        fi
    fi
done

echo -e "${GREEN}✓ Triển khai cấu hình hoàn tất thành công!${NC}\n"
