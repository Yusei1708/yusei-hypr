#!/usr/bin/env bash
# ==============================================================================
#  _   _ _   _ ____  _____ ___       _   _ __   ______  ____  
# | | | | | | / ___|| ____|_ _|     | | | |\ \ / /  _ \|  _ \ 
# | |_| | | | \___ \|  _|  | | _____| |_| | \ V /| |_) | |_) |
# |  _  | |_| |___) | |___ | ||_____|  _  |  | | |  __/|  _ < 
# |_| |_|\___/|____/|_____|___|     |_| |_|  |_| |_|   |_| \_\
# 
#  yusei-hypr: Universal Hyprland Suite & Auto-Installer
#  Style: End-4 Material 3 (Material You)
#  Target: Arch Linux
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

clear 2>/dev/null || true
echo -e "${CYAN}${BOLD}"
cat << "EOF"
  __   __ _   _ ____  _____ ___       _   _ __   ______  ____  
  \ \ / /| | | / ___|| ____|_ _|     | | | |\ \ / /  _ \|  _ \ 
   \ V / | | | \___ \|  _|  | | _____| |_| | \ V /| |_) | |_) |
    | |  | |_| |___) | |___ | ||_____|  _  |  | | |  __/|  _ < 
    |_|   \___/|____/|_____|___|     |_| |_|  |_| |_|   |_| \_\

   ✨ Universal Hyprland Suite for Arch Linux (End-4 Style) ✨
EOF
echo -e "${NC}"

echo -e "${BLUE}Chào mừng bạn đến với bộ cài đặt tự động ${BOLD}yusei-hypr${NC}!"
echo -e "Bộ cài đặt này sẽ:"
echo -e "  1. Tự động nhận diện phần cứng (NVIDIA/Intel/AMD, Laptop/Desktop)."
echo -e "  2. Tự cài đặt đầy đủ phần mềm phụ thuộc (Hyprland, Waybar, Rofi, Fcitx5...)."
echo -e "  3. Tự động sao lưu toàn bộ cấu hình cũ trong ~/.config."
echo -e "  4. Triển khai giao diện bo góc & animations phong cách Material 3 (End-4)."
echo ""

# Xác nhận người dùng
if [[ "$1" != "-y" && "$1" != "--yes" ]]; then
    read -rp "Bạn có muốn tiếp tục tiến hành cài đặt ngay bây giờ? [Y/n]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[nN] ]]; then
        echo -e "${RED}Đã hủy cài đặt.${NC}"
        exit 0
    fi
fi

echo ""
chmod +x "$DIR"/scripts/*.sh

# Chạy tuần tự các bước
"$DIR/scripts/01-detect.sh"
"$DIR/scripts/02-packages.sh"
"$DIR/scripts/03-backup.sh"
"$DIR/scripts/04-install-configs.sh"

echo -e "${CYAN}${BOLD}================================================================${NC}"
echo -e "${GREEN}${BOLD}🎉 CHÚC MỪNG! BỘ CÀI ĐẶT yusei-hypr ĐÃ HOÀN TẤT THÀNH CÔNG!${NC}"
echo -e "${CYAN}${BOLD}================================================================${NC}"
echo ""
echo -e "${YELLOW}Một số phím tắt cơ bản để bạn làm quen:${NC}"
echo -e "  • ${BOLD}Super + Return${NC} : Mở Terminal (Kitty)"
echo -e "  • ${BOLD}Super + Space${NC}  : Mở Menu ứng dụng (Rofi)"
echo -e "  • ${BOLD}Super + Q${NC}      : Đóng cửa sổ đang chọn"
echo -e "  • ${BOLD}Super + E${NC}      : Mở Quản lý file (Thunar)"
echo -e "  • ${BOLD}Super + N${NC}      : Mở Trung tâm thông báo (SwayNC)"
echo -e "  • ${BOLD}Super + L${NC}      : Khóa màn hình (Hyprlock)"
echo -e "  • ${BOLD}Print / Super+Shift+S${NC} : Chụp toàn màn hình / Chụp vùng chọn"
echo ""
echo -e "${BLUE}👉 Hãy khởi động lại Hyprland hoặc Logout và Login lại để áp dụng trọn vẹn!${NC}"
