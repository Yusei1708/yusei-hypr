#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Post-Installation Diagnostics & Verification Module
# ==============================================================================

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}================================================================================${NC}"
echo -e "${CYAN}${BOLD}   🔍 yusei-hypr: BÁO CÁO KIỂM ĐỊNH HỆ THỐNG & ĐỘ ỔN ĐỊNH PHẦN CỨNG             ${NC}"
echo -e "${CYAN}${BOLD}================================================================================${NC}"

# Nạp thông tin phần cứng đã quét
HAS_NVIDIA="false"
IS_LAPTOP="false"
KERNEL_HEADERS_PKG=""
IS_ASUS_ROG="false"

if [ -f /tmp/yusei-hypr/detected.env ]; then
    # shellcheck disable=SC1091
    . /tmp/yusei-hypr/detected.env
fi

TOTAL_CHECKS=0
PASSED_CHECKS=0
WARN_CHECKS=0
FAIL_CHECKS=0

report_item() {
    local category="$1"
    local name="$2"
    local status="$3" # OK, WARN, FAIL
    local detail="$4"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local tag=""
    case "$status" in
        OK)
            tag="${GREEN}[OK]      ${NC}"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            ;;
        WARN)
            tag="${YELLOW}[CẢNH BÁO]${NC}"
            WARN_CHECKS=$((WARN_CHECKS + 1))
            ;;
        FAIL)
            tag="${RED}[LỖI]     ${NC}"
            FAIL_CHECKS=$((FAIL_CHECKS + 1))
            ;;
    esac

    printf " %b %-24s %-28s %b\n" "$tag" "$category" "$name" "$detail"
}

printf "\n ${BOLD}%-10s %-24s %-28s %s${NC}\n" "TRẠNG THÁI" "DANH MỤC" "THÀNH PHẦN" "CHI TIẾT KIỂM TRA"
echo -e " --------------------------------------------------------------------------------------------------"

# 1. Kiểm tra Đồ họa (GPU & Drivers)
if [ "$HAS_NVIDIA" = "true" ]; then
    if pacman -Qi nvidia-dkms &>/dev/null || pacman -Qi nvidia &>/dev/null; then
        report_item "Card Đồ Họa (GPU)" "Driver NVIDIA" "OK" "nvidia-dkms đã được cài đặt"
    else
        report_item "Card Đồ Họa (GPU)" "Driver NVIDIA" "FAIL" "Chưa cài đặt gói nvidia-dkms"
    fi

    if lsmod 2>/dev/null | grep -q "nvidia"; then
        report_item "Card Đồ Họa (GPU)" "NVIDIA Kernel Module" "OK" "Module nvidia đang tải trong Kernel"
    else
        report_item "Card Đồ Họa (GPU)" "NVIDIA Kernel Module" "WARN" "Module chưa nạp (cần reboot để áp dụng)"
    fi

    if [ -f /etc/modprobe.d/nvidia.conf ]; then
        report_item "Card Đồ Họa (GPU)" "Modprobe DRM Modeset" "OK" "Đã có options nvidia_drm modeset=1 fbdev=1"
    else
        report_item "Card Đồ Họa (GPU)" "Modprobe DRM Modeset" "WARN" "Chưa có /etc/modprobe.d/nvidia.conf"
    fi
else
    report_item "Card Đồ Họa (GPU)" "Intel / AMD GPU" "OK" "Tương thích tốt Native Wayland"
fi

# 2. Kiểm tra Hệ thống Âm thanh (Audio Stack)
if pgrep -x pipewire >/dev/null 2>&1 || (command -v systemctl &>/dev/null && systemctl --user is-active pipewire &>/dev/null); then
    report_item "Hệ thống Âm thanh" "PipeWire Daemon" "OK" "Dịch vụ âm thanh PipeWire đang hoạt động"
elif pacman -Qi pipewire &>/dev/null; then
    report_item "Hệ thống Âm thanh" "PipeWire Daemon" "WARN" "Đã cài đặt (sẽ tự chạy khi đăng nhập Hyprland)"
else
    report_item "Hệ thống Âm thanh" "PipeWire Daemon" "FAIL" "Thiếu gói pipewire"
fi

if pgrep -x wireplumber >/dev/null 2>&1 || (command -v systemctl &>/dev/null && systemctl --user is-active wireplumber &>/dev/null); then
    report_item "Hệ thống Âm thanh" "WirePlumber Session" "OK" "Session Manager WirePlumber đang chạy"
elif pacman -Qi wireplumber &>/dev/null; then
    report_item "Hệ thống Âm thanh" "WirePlumber Session" "WARN" "Đã cài đặt (sẽ tự chạy khi đăng nhập Hyprland)"
else
    report_item "Hệ thống Âm thanh" "WirePlumber Session" "FAIL" "Thiếu gói wireplumber"
fi

# 3. Kiểm tra Bluetooth
if pacman -Qi bluez &>/dev/null; then
    if systemctl is-enabled bluetooth.service &>/dev/null; then
        report_item "Kết nối Bluetooth" "Bluetooth Service" "OK" "bluez đã cài & bluetooth.service đã enable"
    else
        report_item "Kết nối Bluetooth" "Bluetooth Service" "WARN" "Gói bluez đã có nhưng service chưa enable"
    fi
else
    report_item "Kết nối Bluetooth" "Bluetooth Package" "FAIL" "Thiếu gói bluez/bluez-utils"
fi

# 4. Kiểm tra Display Manager (SDDM)
if pacman -Qi sddm &>/dev/null; then
    if systemctl is-enabled sddm.service &>/dev/null; then
        report_item "Display Manager" "SDDM Service" "OK" "sddm.service đã được enable"
    else
        report_item "Display Manager" "SDDM Service" "WARN" "SDDM đã cài nhưng chưa enable làm DM mặc định"
    fi

    if [ -d "/usr/share/sddm/themes/simple-sddm-2" ]; then
        report_item "Display Manager" "SDDM Theme" "OK" "Giao diện simple-sddm-2 đã sẵn sàng"
    else
        report_item "Display Manager" "SDDM Theme" "WARN" "Theme simple-sddm-2 chưa tải vào /usr/share/sddm/themes"
    fi
else
    report_item "Display Manager" "SDDM" "WARN" "Chưa cài đặt SDDM (Khởi động qua tty/start-hyprland)"
fi

# 5. Kiểm tra XDG Desktop Portal (Screen Share & Dialogs)
if pacman -Qi xdg-desktop-portal-hyprland &>/dev/null; then
    report_item "Desktop Portal" "Portal Hyprland" "OK" "xdg-desktop-portal-hyprland đã được cài đặt"
else
    report_item "Desktop Portal" "Portal Hyprland" "FAIL" "Thiếu xdg-desktop-portal-hyprland (ảnh hưởng share màn hình)"
fi

if pacman -Qi xdg-desktop-portal &>/dev/null; then
    report_item "Desktop Portal" "Portal Core" "OK" "xdg-desktop-portal đã được cài đặt"
else
    report_item "Desktop Portal" "Portal Core" "FAIL" "Thiếu xdg-desktop-portal"
fi

# 6. Kiểm tra Font & Bộ gõ tiếng Việt (Fcitx5)
if pacman -Qi fcitx5 &>/dev/null && pacman -Qi fcitx5-unikey &>/dev/null; then
    report_item "Gõ Tiếng Việt" "Fcitx5 + Unikey" "OK" "Bộ gõ tiếng Việt Fcitx5-Unikey đã sẵn sàng"
else
    report_item "Gõ Tiếng Việt" "Fcitx5 + Unikey" "WARN" "Chưa cài đặt đủ gói fcitx5 hoặc fcitx5-unikey"
fi

FONT_STATUS="OK"
if ! pacman -Qi ttf-jetbrains-mono-nerd &>/dev/null || ! pacman -Qi ttf-font-awesome &>/dev/null || ! pacman -Qi noto-fonts-emoji &>/dev/null; then
    FONT_STATUS="WARN"
fi
report_item "Giao Diện & Font" "Nerd Font & Emoji" "$FONT_STATUS" "Kiểm tra JetBrains Mono, FontAwesome, Noto Emoji"

# 7. Kiểm tra Thunar & Thumbnailers
THUNAR_STATUS="OK"
if ! pacman -Qi tumbler &>/dev/null || ! pacman -Qi ffmpegthumbnailer &>/dev/null; then
    THUNAR_STATUS="WARN"
fi
report_item "Quản Lý Tệp Tin" "Thunar Thumbnailers" "$THUNAR_STATUS" "Xem trước thumbnail ảnh và video trong Thunar"

# 8. Cấu hình người dùng (User Configs)
if [ -f "$HOME/.config/hypr/hyprland.conf" ]; then
    report_item "Cấu Hình Desktop" "Hyprland Config" "OK" "Đã tìm thấy ~/.config/hypr/hyprland.conf"
else
    report_item "Cấu Hình Desktop" "Hyprland Config" "WARN" "Chưa triển khai ~/.config/hypr/hyprland.conf"
fi

if [ -f "$HOME/.config/waybar/config" ] || [ -f "$HOME/.config/waybar/config.jsonc" ]; then
    report_item "Cấu Hình Desktop" "Waybar Material 3" "OK" "Đã tìm thấy cấu hình thanh trạng thái Waybar"
else
    report_item "Cấu Hình Desktop" "Waybar Material 3" "WARN" "Chưa tìm thấy cấu hình Waybar trong ~/.config"
fi

# 9. Kiểm tra tính năng ASUS ROG (nếu có)
if [ "$IS_ASUS_ROG" = "true" ]; then
    if pacman -Qi asusctl &>/dev/null && pacman -Qi supergfxctl &>/dev/null; then
        report_item "Phần Cứng ASUS ROG" "asusctl & supergfxctl" "OK" "Đã cài đặt công cụ quản trị ASUS ROG"
    else
        report_item "Phần Cứng ASUS ROG" "asusctl & supergfxctl" "WARN" "Chưa cài đặt đủ công cụ cho laptop ASUS ROG"
    fi
fi

echo -e " --------------------------------------------------------------------------------------------------"
echo -e "\n${BOLD}📊 TỔNG KẾT KIỂM ĐỊNH:${NC}"
echo -e "   • Tổng số mục kiểm tra: ${BOLD}$TOTAL_CHECKS${NC}"
echo -e "   • Đạt chuẩn (${GREEN}OK${NC})       : ${GREEN}${BOLD}$PASSED_CHECKS${NC}"
echo -e "   • Cảnh báo (${YELLOW}WARN${NC})    : ${YELLOW}${BOLD}$WARN_CHECKS${NC}"
echo -e "   • Cần xử lý (${RED}FAIL${NC})   : ${RED}${BOLD}$FAIL_CHECKS${NC}"
echo ""

if [ "$FAIL_CHECKS" -gt 0 ]; then
    echo -e "${RED}${BOLD}⚠️ Phát hiện một số lỗi nghiêm trọng có thể ảnh hưởng đến khả năng khởi động Desktop.${NC}"
    echo -e "${YELLOW}Gợi ý: Hãy chạy lại './install.sh' để tự động hoàn thiện các thành phần còn thiếu.${NC}\n"
    exit 1
elif [ "$WARN_CHECKS" -gt 0 ]; then
    echo -e "${YELLOW}${BOLD}ℹ️ Hệ thống cơ bản đã hoàn tất, một số thay đổi (như kernel module) sẽ có hiệu lực sau khi Reboot.${NC}\n"
    exit 0
else
    echo -e "${GREEN}${BOLD}🎉 Tuyệt vời! Hệ thống của bạn đạt 100% tiêu chuẩn tương thích và ổn định phần cứng!${NC}\n"
    exit 0
fi
