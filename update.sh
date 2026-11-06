#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Automated System Updater & Config Synchronizer
# ==============================================================================
# Usage:
#   ./update.sh [OPTIONS]
#
# Options:
#   --dry-run       Preview actions without making changes
#   -y, --yes       Accept prompts non-interactively
#   --skip-git      Skip Git pull and remote update check
#   --no-reload     Do not reload Hyprland session
#   -h, --help      Show help and usage information
# ==============================================================================

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

AUTO_ACCEPT=false
DRY_RUN=false
SKIP_GIT=false
NO_RELOAD=false

for arg in "$@"; do
    case "$arg" in
        -y|--yes)
            AUTO_ACCEPT=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --skip-git)
            SKIP_GIT=true
            ;;
        --no-reload)
            NO_RELOAD=true
            ;;
        -h|--help)
            echo -e "${CYAN}${BOLD}yusei-hypr: Trình cập nhật và đồng bộ cấu hình hệ thống${NC}"
            echo ""
            echo "Cú pháp: $0 [TÙY CHỌN]"
            echo ""
            echo "Tùy chọn:"
            echo "  --dry-run       Mô phỏng các bước cập nhật mà không thay đổi hệ thống"
            echo "  -y, --yes       Tự động xác nhận cập nhật (chế độ non-interactive)"
            echo "  --skip-git      Bỏ qua bước git pull từ kho lưu trữ từ xa"
            echo "  --no-reload     Không thực hiện hyprctl reload sau khi cập nhật"
            echo "  -h, --help      Hiển thị hướng dẫn này và thoát"
            exit 0
            ;;
        *)
            ;;
    esac
done

echo -e "${CYAN}${BOLD}================================================================================${NC}"
echo -e "${BLUE}${BOLD}             🔄 TRÌNH CẬP NHẬT CẤU HÌNH HỆ THỐNG (yusei-hypr)                   ${NC}"
echo -e "${CYAN}${BOLD}================================================================================${NC}"
echo ""

if [ "$AUTO_ACCEPT" = "false" ] && [ "$DRY_RUN" = "false" ]; then
    if [ -t 0 ] && [ -t 1 ]; then
        read -rp "Bạn có muốn tiếp tục tiến hành cập nhật yusei-hypr? [Y/n]: " CONFIRM
        if [[ "$CONFIRM" =~ ^[nN] ]]; then
            echo -e "${RED}Đã hủy cập nhật.${NC}"
            exit 0
        fi
    fi
fi

# ------------------------------------------------------------------------------
# Stage 1: Git Update Check
# ------------------------------------------------------------------------------
echo -e "${BLUE}:: [Stage 1/4] Kiểm tra mã nguồn kho lưu trữ Git...${NC}"
if [ "$SKIP_GIT" = "true" ]; then
    echo -e "${YELLOW}:: Bỏ qua kiểm tra Git (--skip-git được kích hoạt).${NC}"
else
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[DRY-RUN] Sẽ kiểm tra trạng thái Git và thực thi: git pull --rebase origin main${NC}"
    else
        if git -C "$DIR" rev-parse --is-inside-work-tree &>/dev/null; then
            if [[ -n "$(git -C "$DIR" status --porcelain 2>/dev/null)" ]]; then
                echo -e "${YELLOW}⚠️ Phát hiện thay đổi cục bộ chưa commit trong kho Git. Bỏ qua git pull để tránh xung đột.${NC}"
            else
                if ! git -C "$DIR" pull --rebase origin main 2>&1; then
                    echo -e "${YELLOW}⚠️ Không thể kéo cập nhật từ Git (có thể ngoại tuyến hoặc lỗi mạng). Tiếp tục với mã nguồn hiện tại.${NC}"
                else
                    echo -e "${GREEN}✓ Đã cập nhật mã nguồn Git mới nhất thành công.${NC}"
                fi
            fi
        else
            echo -e "${YELLOW}⚠️ Không phải kho lưu trữ Git. Bỏ qua bước cập nhật Git.${NC}"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# Stage 2: Automatic Pre-update Snapshot
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}:: [Stage 2/4] Tạo bản sao lưu cấu hình trước khi cập nhật...${NC}"
BACKUP_SCRIPT="$DIR/scripts/03-backup.sh"
if [[ -f "$BACKUP_SCRIPT" ]]; then
    if [ "$DRY_RUN" = "true" ]; then
        bash "$BACKUP_SCRIPT" --dry-run
    else
        bash "$BACKUP_SCRIPT"
    fi
else
    echo -e "${YELLOW}⚠️ Không tìm thấy $BACKUP_SCRIPT. Bỏ qua bước tạo bản sao lưu.${NC}"
fi

# ------------------------------------------------------------------------------
# Stage 3: Synchronize Configs, bin/, and Wallpapers
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}:: [Stage 3/4] Đồng bộ cấu hình yusei-hypr, bin/ và wallpapers...${NC}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}[DRY-RUN] Sẽ đồng bộ các thư mục cấu hình vào $CONFIG_HOME (bảo tồn userprefs.conf, UserConfigs, UserScripts)${NC}"
    echo -e "${YELLOW}[DRY-RUN] Sẽ đồng bộ các tiện ích từ bin/ vào ~/.local/bin${NC}"
    echo -e "${YELLOW}[DRY-RUN] Sẽ đồng bộ bộ sưu tập hình nền vào ~/Pictures/wallpapers${NC}"
else
    mkdir -p "$CONFIG_HOME"
    CONFIG_DIRS=("hypr" "waybar" "rofi" "kitty" "swaync" "wlogout" "fastfetch" "btop" "cava" "swappy" "wallust" "Kvantum" "qt5ct" "qt6ct")

    for dir in "${CONFIG_DIRS[@]}"; do
        if [[ -d "$DIR/config/$dir" ]]; then
            if [[ "$dir" == "hypr" && -d "$CONFIG_HOME/hypr" ]]; then
                TMP_PRESERVE="$(mktemp -d /tmp/yusei-update-preserve-XXXXXX)"
                HAS_USER_PREFS=false
                HAS_USER_CONFIGS=false
                HAS_USER_SCRIPTS=false

                if [[ -f "$CONFIG_HOME/hypr/userprefs.conf" ]]; then
                    cp -a "$CONFIG_HOME/hypr/userprefs.conf" "$TMP_PRESERVE/userprefs.conf"
                    HAS_USER_PREFS=true
                fi
                if [[ -d "$CONFIG_HOME/hypr/UserConfigs" ]]; then
                    cp -a "$CONFIG_HOME/hypr/UserConfigs" "$TMP_PRESERVE/"
                    HAS_USER_CONFIGS=true
                fi
                if [[ -d "$CONFIG_HOME/hypr/UserScripts" ]]; then
                    cp -a "$CONFIG_HOME/hypr/UserScripts" "$TMP_PRESERVE/"
                    HAS_USER_SCRIPTS=true
                fi

                rm -rf "$CONFIG_HOME/hypr"
                cp -a "$DIR/config/hypr" "$CONFIG_HOME/"

                if [ "$HAS_USER_PREFS" = "true" ]; then
                    cp -a "$TMP_PRESERVE/userprefs.conf" "$CONFIG_HOME/hypr/userprefs.conf"
                    echo -e "${GREEN}✓ Đã bảo tồn an toàn cấu hình cá nhân: ~/.config/hypr/userprefs.conf${NC}"
                elif [[ -f "$DIR/config/hypr/userprefs.conf" && ! -f "$CONFIG_HOME/hypr/userprefs.conf" ]]; then
                    cp -a "$DIR/config/hypr/userprefs.conf" "$CONFIG_HOME/hypr/userprefs.conf"
                    echo -e "${GREEN}✓ Đã khởi tạo cấu hình cá nhân mẫu: ~/.config/hypr/userprefs.conf${NC}"
                fi

                if [ "$HAS_USER_CONFIGS" = "true" ]; then
                    mkdir -p "$CONFIG_HOME/hypr/UserConfigs"
                    cp -a "$TMP_PRESERVE/UserConfigs/." "$CONFIG_HOME/hypr/UserConfigs/" 2>/dev/null || true
                    echo -e "${GREEN}✓ Đã bảo tồn an toàn tùy biến người dùng tại: ~/.config/hypr/UserConfigs${NC}"
                fi

                if [ "$HAS_USER_SCRIPTS" = "true" ]; then
                    mkdir -p "$CONFIG_HOME/hypr/UserScripts"
                    cp -a "$TMP_PRESERVE/UserScripts/." "$CONFIG_HOME/hypr/UserScripts/" 2>/dev/null || true
                    echo -e "${GREEN}✓ Đã bảo tồn an toàn script cá nhân tại: ~/.config/hypr/UserScripts${NC}"
                fi

                rm -rf "$TMP_PRESERVE"
                echo -e "${GREEN}✓ Đã đồng bộ an toàn: ~/.config/hypr${NC}"
            else
                rm -rf "$CONFIG_HOME/$dir"
                cp -a "$DIR/config/$dir" "$CONFIG_HOME/"
                echo -e "${GREEN}✓ Đã đồng bộ: ~/.config/$dir${NC}"
            fi
        fi
    done

    # Đảm bảo userprefs.conf luôn tồn tại
    if [[ ! -f "$CONFIG_HOME/hypr/userprefs.conf" && -f "$DIR/config/hypr/userprefs.conf" ]]; then
        cp -a "$DIR/config/hypr/userprefs.conf" "$CONFIG_HOME/hypr/userprefs.conf"
    fi

    # Cấp quyền thực thi cho các script
    if [[ -d "$CONFIG_HOME/hypr/scripts" ]]; then
        find "$CONFIG_HOME/hypr/scripts" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
    fi
    if [[ -d "$CONFIG_HOME/hypr/UserScripts" ]]; then
        find "$CONFIG_HOME/hypr/UserScripts" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} + 2>/dev/null || true
    fi
    if [[ -f "$CONFIG_HOME/hypr/initial-boot.sh" ]]; then
        chmod +x "$CONFIG_HOME/hypr/initial-boot.sh" 2>/dev/null || true
    fi

    # Đồng bộ các công cụ bin/
    if [[ -d "$DIR/bin" ]]; then
        mkdir -p "$HOME/.local/bin"
        cp -a "$DIR/bin"/* "$HOME/.local/bin/" 2>/dev/null || true
        chmod +x "$HOME/.local/bin"/* 2>/dev/null || true
        chmod +x "$DIR/bin"/* 2>/dev/null || true
        echo -e "${GREEN}✓ Đã đồng bộ các công cụ bin/ vào ~/.local/bin${NC}"
    fi

    # Đồng bộ hình nền
    PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
    if [[ -d "$DIR/assets/wallpapers" ]]; then
        mkdir -p "$PICTURES_DIR/wallpapers"
        cp -n "$DIR/assets/wallpapers"/* "$PICTURES_DIR/wallpapers/" 2>/dev/null || true
        echo -e "${GREEN}✓ Đã đồng bộ bộ sưu tập hình nền vào $PICTURES_DIR/wallpapers${NC}"
    fi
fi

# ------------------------------------------------------------------------------
# Stage 4: Reload Hyprland Session
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}:: [Stage 4/4] Kiểm tra phiên làm việc Hyprland...${NC}"
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ "$NO_RELOAD" = "false" ]; then
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[DRY-RUN] Phát hiện phiên Hyprland đang hoạt động ($HYPRLAND_INSTANCE_SIGNATURE). Sẽ chạy: hyprctl reload${NC}"
    else
        echo -e "${GREEN}✓ Đang nạp lại cấu hình Hyprland (hyprctl reload)...${NC}"
        hyprctl reload 2>&1 || echo -e "${YELLOW}⚠️ Không thể nạp lại cấu hình Hyprland tự động.${NC}"
    fi
else
    if [ "$NO_RELOAD" = "true" ]; then
        echo -e "${YELLOW}:: Bỏ qua nạp lại Hyprland (--no-reload được kích hoạt).${NC}"
    else
        echo -e "${BLUE}ℹ️ Không nằm trong phiên Hyprland đang chạy. Không cần nạp lại cấu hình.${NC}"
    fi
fi

echo -e "\n${CYAN}${BOLD}================================================================================${NC}"
echo -e "${GREEN}${BOLD}🎉 QUÁ TRÌNH CẬP NHẬT CẤU HÌNH ĐÃ HOÀN TẤT THÀNH CÔNG!${NC}"
echo -e "${CYAN}${BOLD}================================================================================${NC}\n"
exit 0
