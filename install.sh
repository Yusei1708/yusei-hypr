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
#  Target: Arch Linux (JaKooLit Stability Parity)
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

clear 2>/dev/null || true
echo -e "${CYAN}${BOLD}"
cat << "EOF"
  __   __ _   _ ____  _____ ___       _   _ __   ______  ____  
  \ \ / /| | | / ___|| ____|_ _|     | | | |\ \ / /  _ \|  _ \ 
   \ V / | | | \___ \|  _|  | | _____| |_| | \ V /| |_) | |_) |
    | |  | |_| |___) | |___ | ||_____|  _  |  | | |  __/|  _ < 
    |_|   \___/|____/|_____|___|     |_| |_|  |_| |_|   |_| \_\

   ✨ Universal Hyprland Suite for Arch Linux (End-4 Style) ✨
      🛡️ Battle-tested Hardware Stability Parity Edition 🛡️
EOF
echo -e "${NC}"

echo -e "${BLUE}Chào mừng bạn đến với bộ cài đặt tự động ${BOLD}yusei-hypr${NC}!"
echo -e "Bộ cài đặt này sẽ:"
echo -e "  1. Tự động nhận diện phần cứng (NVIDIA/Intel/AMD, Kernel headers, Laptop, ASUS ROG)."
echo -e "  2. Cài đặt các gói phụ thuộc, loại bỏ xung đột PulseAudio sang PipeWire hoàn chỉnh."
echo -e "  3. Cấu hình chuyên sâu tầng Kernel (Early KMS, Modprobe DRM, GRUB) nếu có card NVIDIA."
echo -e "  4. Kích hoạt toàn bộ các dịch vụ hệ thống (Bluetooth, PipeWire, WirePlumber)."
echo -e "  5. Cài đặt và cấu hình Display Manager SDDM kèm theme simple-sddm-2 chuẩn mực."
echo -e "  6. Sao lưu bảo toàn các cấu hình cũ trong ~/.config."
echo -e "  7. Triển khai giao diện bo góc & animations phong cách Material 3 (End-4)."
echo -e "  8. Kiểm định toàn diện sức khỏe hệ thống sau khi cài đặt (05-verify.sh)."
echo -e "  9. Gợi ý cài đặt ứng dụng tùy chọn và công cụ quản trị hệ thống (05-optional-apps.sh)."
echo ""

# Xác nhận người dùng (Hỗ trợ cờ -y hoặc --yes)
AUTO_ACCEPT=false
for arg in "$@"; do
    if [[ "$arg" == "-y" || "$arg" == "--yes" ]]; then
        AUTO_ACCEPT=true
        break
    fi
done

if [ "$AUTO_ACCEPT" = "false" ]; then
    read -rp "Bạn có muốn tiếp tục tiến hành cài đặt ngay bây giờ? [Y/n]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[nN] ]]; then
        echo -e "${RED}Đã hủy cài đặt.${NC}"
        exit 0
    fi
fi

echo ""
chmod +x "$DIR"/scripts/*.sh 2>/dev/null || true

# ------------------------------------------------------------------------------
# Chạy tuần tự quy trình cài đặt chuẩn hóa
# ------------------------------------------------------------------------------

# Bước 1: Nhận diện phần cứng & Kernel
"$DIR/scripts/01-detect.sh"

# Bước 2: Cài đặt phần mềm & Phụ thuộc
"$DIR/scripts/02-packages.sh"

# Bước 3: Cấu hình Kernel NVIDIA (nếu có card NVIDIA)
HAS_NVIDIA="false"
if [ -f /tmp/yusei-hypr/detected.env ]; then
    # shellcheck disable=SC1091
    . /tmp/yusei-hypr/detected.env
fi
if [ "$HAS_NVIDIA" = "true" ]; then
    "$DIR/scripts/setup-nvidia.sh" "$@"
fi

# Bước 4: Kích hoạt dịch vụ hệ thống nền (Bluetooth, Audio, ASUS ROG)
"$DIR/scripts/setup-services.sh"

# Bước 5: Cấu hình Trình quản lý đăng nhập SDDM
"$DIR/scripts/setup-sddm.sh" "$@"

# Bước 6: Sao lưu cấu hình hiện tại
"$DIR/scripts/03-backup.sh"

# Bước 7: Cài đặt cấu hình End-4 Material 3 (Bảo vệ UserConfigs & UserScripts)
"$DIR/scripts/04-install-configs.sh"

# Bước 8: Kiểm định hệ thống sau cài đặt
"$DIR/scripts/05-verify.sh"

# Bước 9 (Tùy chọn): Gợi ý cài đặt ứng dụng catalog
if [ -f "$DIR/scripts/05-optional-apps.sh" ]; then
    "$DIR/scripts/05-optional-apps.sh" "$@" || true
elif [ -f "$DIR/scripts/06-optional-apps.sh" ]; then
    "$DIR/scripts/06-optional-apps.sh" "$@" || true
fi

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
echo -e "${BLUE}ℹ️ Khi cần hoàn nguyên hoặc gỡ cài đặt, bạn có thể chạy: ${BOLD}./scripts/uninstall.sh${NC}"
echo -e "${BLUE}👉 Hãy khởi động lại máy tính (Reboot) để các module kernel và SDDM có hiệu lực trọn vẹn!${NC}\n"
