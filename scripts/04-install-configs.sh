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

echo -e "${BLUE}:: [Configs] Đang cài đặt các file cấu hình yusei-hypr vào ~/.config...${NC}"

# Nạp thông tin phần cứng
HAS_NVIDIA="false"
if [ -f /tmp/yusei-hypr/detected.env ]; then
    # shellcheck disable=SC1091
    . /tmp/yusei-hypr/detected.env
fi

# 1. Tạo thư mục .config nếu chưa có
mkdir -p "$HOME/.config"

# 2. Sao chép các thư mục cấu hình và bảo vệ dữ liệu người dùng
CONFIG_DIRS=("hypr" "waybar" "rofi" "kitty" "swaync" "wlogout" "fastfetch" "btop" "cava" "swappy" "wallust" "Kvantum" "qt5ct" "qt6ct")

for dir in "${CONFIG_DIRS[@]}"; do
    if [[ -d "$SCRIPT_DIR/config/$dir" ]]; then
        if [[ "$dir" == "hypr" && -d "$HOME/.config/hypr" ]]; then
            # Bảo vệ cấu hình cá nhân của người dùng (userprefs.conf, UserConfigs và UserScripts)
            TMP_PRESERVE="/tmp/yusei-hypr/preserve_user_$$"
            mkdir -p "$TMP_PRESERVE"
            HAS_USER_PREFS=false
            HAS_USER_CONFIGS=false
            HAS_USER_SCRIPTS=false

            if [[ -f "$HOME/.config/hypr/userprefs.conf" ]]; then
                cp -a "$HOME/.config/hypr/userprefs.conf" "$TMP_PRESERVE/userprefs.conf"
                HAS_USER_PREFS=true
            fi

            if [[ -d "$HOME/.config/hypr/UserConfigs" ]]; then
                cp -a "$HOME/.config/hypr/UserConfigs" "$TMP_PRESERVE/"
                HAS_USER_CONFIGS=true
            fi

            if [[ -d "$HOME/.config/hypr/UserScripts" ]]; then
                cp -a "$HOME/.config/hypr/UserScripts" "$TMP_PRESERVE/"
                HAS_USER_SCRIPTS=true
            fi

            # Thay thế thư mục hypr
            rm -rf "$HOME/.config/hypr"
            cp -a "$SCRIPT_DIR/config/hypr" "$HOME/.config/"

            # Khôi phục các tùy biến cá nhân của người dùng
            if [ "$HAS_USER_PREFS" = "true" ]; then
                cp -a "$TMP_PRESERVE/userprefs.conf" "$HOME/.config/hypr/userprefs.conf"
                echo -e "${GREEN}✓ Đã bảo tồn an toàn cấu hình cá nhân tại: ~/.config/hypr/userprefs.conf${NC}"
            else
                if [[ ! -f "$HOME/.config/hypr/userprefs.conf" && -f "$SCRIPT_DIR/config/hypr/userprefs.conf" ]]; then
                    cp -a "$SCRIPT_DIR/config/hypr/userprefs.conf" "$HOME/.config/hypr/userprefs.conf"
                    echo -e "${GREEN}✓ Đã khởi tạo cấu hình cá nhân mẫu: ~/.config/hypr/userprefs.conf${NC}"
                fi
            fi

            if [ "$HAS_USER_CONFIGS" = "true" ]; then
                cp -a "$TMP_PRESERVE/UserConfigs"/* "$HOME/.config/hypr/UserConfigs/" 2>/dev/null || true
                echo -e "${GREEN}✓ Đã bảo tồn an toàn tùy biến của người dùng tại: ~/.config/hypr/UserConfigs${NC}"
            fi

            if [ "$HAS_USER_SCRIPTS" = "true" ]; then
                cp -a "$TMP_PRESERVE/UserScripts"/* "$HOME/.config/hypr/UserScripts/" 2>/dev/null || true
                echo -e "${GREEN}✓ Đã bảo tồn an toàn script cá nhân tại: ~/.config/hypr/UserScripts${NC}"
            fi

            rm -rf "$TMP_PRESERVE"
            echo -e "${GREEN}✓ Đã triển khai an toàn (non-destructive): ~/.config/hypr${NC}"
        else
            rm -rf "$HOME/.config/$dir"
            cp -a "$SCRIPT_DIR/config/$dir" "$HOME/.config/"
            echo -e "${GREEN}✓ Đã triển khai: ~/.config/$dir${NC}"
        fi
    fi
done

# Đảm bảo ~/.config/hypr/userprefs.conf luôn tồn tại sau khi cài đặt
if [[ ! -f "$HOME/.config/hypr/userprefs.conf" && -f "$SCRIPT_DIR/config/hypr/userprefs.conf" ]]; then
    cp -a "$SCRIPT_DIR/config/hypr/userprefs.conf" "$HOME/.config/hypr/userprefs.conf"
    echo -e "${GREEN}✓ Đã khởi tạo template cấu hình: ~/.config/hypr/userprefs.conf${NC}"
fi

# Đảm bảo phân quyền thực thi cho toàn bộ script
if [[ -d "$HOME/.config/hypr/scripts" ]]; then
    find "$HOME/.config/hypr/scripts" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
fi
if [[ -d "$HOME/.config/hypr/UserScripts" ]]; then
    find "$HOME/.config/hypr/UserScripts" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} + 2>/dev/null || true
fi
if [[ -f "$HOME/.config/hypr/initial-boot.sh" ]]; then
    chmod +x "$HOME/.config/hypr/initial-boot.sh" 2>/dev/null || true
fi

# 3. Kích hoạt NVIDIA nếu được phát hiện
if [ "${HAS_NVIDIA:-false}" = "true" ]; then
    echo -e "${YELLOW}:: Đang kích hoạt nạp nvidia.conf trong hyprland.conf...${NC}"
    if [[ -f "$HOME/.config/hypr/hyprland.conf" ]]; then
        # Khớp chính xác cả "# source = ./nvidia.conf" và "# source = ~/.config/hypr/nvidia.conf"
        sed -i -E 's@#\s*source\s*=\s*(\./|~/\.config/hypr/)nvidia\.conf@source = ./nvidia.conf@g' "$HOME/.config/hypr/hyprland.conf"
        echo -e "${GREEN}✓ Đã kích hoạt cấu hình tối ưu card đồ họa NVIDIA trong hyprland.conf!${NC}"
    fi
fi

# 4. Sao chép bộ sưu tập hình nền vào ~/Pictures/wallpapers
PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
mkdir -p "$PICTURES_DIR/wallpapers"
if [[ -d "$SCRIPT_DIR/assets/wallpapers" ]]; then
    echo -e "${BLUE}:: Đang đồng bộ bộ sưu tập hình nền vào $PICTURES_DIR/wallpapers...${NC}"
    cp -n "$SCRIPT_DIR/assets/wallpapers"/* "$PICTURES_DIR/wallpapers/" 2>/dev/null || true
    WP_COUNT="$(find "$SCRIPT_DIR/assets/wallpapers" -maxdepth 1 -type f 2>/dev/null | wc -l)"
    echo -e "${GREEN}✓ Đã cập nhật toàn bộ ${WP_COUNT} hình nền nghệ thuật vào $PICTURES_DIR/wallpapers${NC}"
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
