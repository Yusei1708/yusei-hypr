#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Automated System Updater & Config Synchronizer
# ==============================================================================
# Usage:
#   ./update.sh [OPTIONS]
#
# Options:
#   --dry-run           Preview actions without making changes
#   -y, --yes           Accept prompts non-interactively
#   --skip-git          Skip Git pull and remote update check
#   --no-reload         Do not reload Hyprland session
#   --install-packages  Install missing packages from scripts/02-packages.sh
#   -h, --help          Show help and usage information
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
INSTALL_PACKAGES=false

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
        --install-packages)
            INSTALL_PACKAGES=true
            ;;
        -h|--help)
            echo -e "${CYAN}${BOLD}yusei-hypr: Trình cập nhật và đồng bộ cấu hình hệ thống${NC}"
            echo ""
            echo "Cú pháp: $0 [TÙY CHỌN]"
            echo ""
            echo "Tùy chọn:"
            echo "  --dry-run           Mô phỏng các bước cập nhật mà không thay đổi hệ thống"
            echo "  -y, --yes           Tự động xác nhận cập nhật (chế độ non-interactive)"
            echo "  --skip-git          Bỏ qua bước git pull từ kho lưu trữ từ xa"
            echo "  --no-reload         Không thực hiện hyprctl reload sau khi cập nhật"
            echo "  --install-packages  Cài bổ sung các gói còn thiếu từ scripts/02-packages.sh"
            echo "  -h, --help          Hiển thị hướng dẫn này và thoát"
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

TMP_PRESERVE=""
_yusei_update_cleanup() {
    if [[ -n "${TMP_PRESERVE:-}" && -d "${TMP_PRESERVE:-}" ]]; then
        rm -rf "$TMP_PRESERVE"
    fi
}
trap _yusei_update_cleanup EXIT INT TERM

CONFIG_SYNC_HELPER="$DIR/scripts/04-install-configs.sh"
if [[ ! -f "$CONFIG_SYNC_HELPER" ]]; then
    echo -e "${RED}[ERROR] Không tìm thấy module đồng bộ cấu hình: $CONFIG_SYNC_HELPER${NC}"
    exit 1
fi
# shellcheck disable=SC1090
YUSEI_CONFIG_SYNC_LIB_ONLY=1 source "$CONFIG_SYNC_HELPER"

if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}[DRY-RUN] Sẽ đồng bộ không phá hủy ${#YUSEI_CONFIG_DIRS[@]} thư mục cấu hình vào $CONFIG_HOME (bảo tồn userprefs.{conf,lua}, UserConfigs, UserScripts, animations.conf, monitors.conf, power.json, state/colors, custom presets)${NC}"
    echo -e "${YELLOW}[DRY-RUN] Sẽ đồng bộ bin/, lib/, assets/packages/, scripts/, yusei_settings/, uninstall.sh vào ~/.local${NC}"
    echo -e "${YELLOW}[DRY-RUN] Sẽ đồng bộ bộ sưu tập hình nền vào ~/Pictures/wallpapers (bảo tồn wallpaper.jpg đã có)${NC}"
    if [[ "$(yusei_detect_nvidia_readonly "$DIR")" = "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Phát hiện GPU NVIDIA: sẽ kích hoạt lại nvidia.conf và kiểm tra userprefs.conf${NC}"
    fi
else
    yusei_deploy_all_configs "$DIR" "$CONFIG_HOME"
    yusei_sync_local_runtime "$DIR"
    yusei_sync_wallpapers "$DIR" "$CONFIG_HOME"

    if [[ "$(yusei_detect_nvidia_readonly "$DIR")" = "true" ]]; then
        echo -e "${YELLOW}:: Phát hiện GPU NVIDIA: đang đồng bộ lại cấu hình NVIDIA...${NC}"
        yusei_enable_hypr_nvidia_conf "$CONFIG_HOME"
        if [[ -x "$DIR/scripts/hardware-detect.sh" ]]; then
            "$DIR/scripts/hardware-detect.sh" --inject-userprefs --target-userprefs="$CONFIG_HOME/hypr/userprefs.conf" || true
        fi
    fi
fi

# Kiểm tra các gói phụ thuộc mới được bổ sung trong scripts/02-packages.sh
PKG_HELPER="$DIR/scripts/02-packages.sh"
if [[ -f "$PKG_HELPER" ]] && command -v pacman &>/dev/null; then
    MISSING_PKGS=()
    mapfile -t MISSING_PKGS < <(bash "$PKG_HELPER" --list-missing 2>/dev/null || true)
    if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}⚠️ Phát hiện ${#MISSING_PKGS[@]} gói phụ thuộc còn thiếu (bao gồm tiện ích runtime nếu chưa cài):${NC}"
        echo -e "${YELLOW}   ${MISSING_PKGS[*]}${NC}"
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "${YELLOW}[DRY-RUN] Sẽ kiểm tra/cài đặt các gói còn thiếu bằng $PKG_HELPER.${NC}"
        elif [ "$INSTALL_PACKAGES" = "true" ]; then
            echo -e "${BLUE}:: Đang chạy 02-packages.sh để cài bổ sung các gói còn thiếu...${NC}"
            bash "$PKG_HELPER"
        elif [ -t 0 ] && [ -t 1 ] && [ "$AUTO_ACCEPT" = "false" ]; then
            read -rp "Bạn có muốn cài đặt các gói còn thiếu ngay bây giờ? [Y/n]: " INSTALL_CONFIRM
            if [[ ! "$INSTALL_CONFIRM" =~ ^[nN] ]]; then
                bash "$PKG_HELPER"
            else
                echo -e "${YELLOW}ℹ️ Bỏ qua cài gói. Bạn có thể cài sau bằng: sudo pacman -S --needed ${MISSING_PKGS[*]}${NC}"
            fi
        else
            echo -e "${YELLOW}ℹ️ Bỏ qua cài gói ở chế độ non-interactive. Chạy './update.sh --install-packages' hoặc: sudo pacman -S --needed ${MISSING_PKGS[*]}${NC}"
        fi
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
