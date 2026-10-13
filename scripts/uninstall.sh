#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Safe Uninstaller & System Restoration Module
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

echo -e "${CYAN}${BOLD}================================================================================${NC}"
echo -e "${RED}${BOLD}       🗑️  TRÌNH GỠ CÀI ĐẶT VÀ HOÀN NGUYÊN HỆ THỐNG (yusei-hypr)                ${NC}"
echo -e "${CYAN}${BOLD}================================================================================${NC}"
echo ""

AUTO_ACCEPT=false
for arg in "$@"; do
    if [[ "$arg" == "-y" || "$arg" == "--yes" ]]; then
        AUTO_ACCEPT=true
        break
    fi
done

if [ "$AUTO_ACCEPT" = "false" ]; then
    echo -e "${YELLOW}Thao tác này sẽ:${NC}"
    echo -e "  1. Hoàn nguyên toàn bộ cấu hình trong ~/.config về bản sao lưu gần nhất."
    echo -e "  2. Tắt các dịch vụ hệ thống đã kích hoạt (SDDM, Bluetooth, Supergfxd)."
    echo -e "  3. Dọn dẹp cấu hình modprobe và theme SDDM đã tạo."
    echo ""
    read -rp "Bạn có chắc chắn muốn tiếp tục gỡ cài đặt yusei-hypr? [y/N]: " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[yY] ]]; then
        echo -e "${BLUE}Đã hủy thao tác gỡ cài đặt.${NC}"
        exit 0
    fi
fi

# 1. Khôi phục cấu hình ~/.config qua rollback.sh
echo -e "\n${BLUE}:: [1/3] Khôi phục cấu hình ~/.config từ bản snapshot lưu trữ...${NC}"
if [ -f "$DIR/rollback.sh" ]; then
    bash "$DIR/rollback.sh"
else
    echo -e "${YELLOW}⚠️ Không tìm thấy script rollback.sh. Bỏ qua hoàn nguyên tự động.${NC}"
fi

# 2. Dọn dẹp các dịch vụ hệ thống (SDDM, Bluetooth, Supergfxd)
echo -e "\n${BLUE}:: [2/3] Dọn dẹp các dịch vụ hệ thống (Display Manager & Daemons)...${NC}"
DISABLE_SERVICES=false
if [ "$AUTO_ACCEPT" = "true" ]; then
    DISABLE_SERVICES=true
else
    read -rp "Bạn có muốn tắt các dịch vụ hệ thống (sddm, bluetooth, supergfxd)? [Y/n]: " CONFIRM_SVCS
    if [[ ! "$CONFIRM_SVCS" =~ ^[nN] ]]; then
        DISABLE_SERVICES=true
    fi
fi

if [ "$DISABLE_SERVICES" = "true" ]; then
    echo -e "${YELLOW}Đang tắt sddm.service...${NC}"
    sudo systemctl disable sddm.service 2>/dev/null || true

    echo -e "${YELLOW}Đang tắt bluetooth.service...${NC}"
    sudo systemctl disable bluetooth.service 2>/dev/null || true

    if systemctl list-unit-files supergfxd.service &>/dev/null; then
        echo -e "${YELLOW}Đang tắt supergfxd.service...${NC}"
        sudo systemctl disable supergfxd.service 2>/dev/null || true
    fi
    echo -e "${GREEN}✓ Đã vô hiệu hóa các dịch vụ hệ thống liên quan.${NC}"
fi

# 3. Dọn dẹp các file cấu hình hệ thống đã tạo
echo -e "\n${BLUE}:: [3/3] Dọn dẹp các file cấu hình hệ thống...${NC}"
if [ -f /etc/modprobe.d/nvidia.conf ]; then
    echo -e "${YELLOW}Xóa /etc/modprobe.d/nvidia.conf...${NC}"
    sudo rm -f /etc/modprobe.d/nvidia.conf
fi

if [ -f /etc/sddm.conf.d/10-theme.conf ]; then
    echo -e "${YELLOW}Xóa /etc/sddm.conf.d/10-theme.conf...${NC}"
    sudo rm -f /etc/sddm.conf.d/10-theme.conf
fi

# Dọn dẹp thư mục tạm thời
rm -rf /tmp/yusei-hypr

echo -e "\n${CYAN}${BOLD}================================================================================${NC}"
echo -e "${GREEN}${BOLD}🎉 QUÁ TRÌNH GỠ CÀI ĐẶT VÀ HOÀN NGUYÊN ĐÃ HOÀN TẤT THÀNH CÔNG!${NC}"
echo -e "${CYAN}${BOLD}================================================================================${NC}"
echo -e "${YELLOW}Lưu ý: Các gói phần mềm đã tải về qua pacman/yay vẫn được giữ nguyên để bảo đảm an toàn hệ thống.${NC}"
echo -e "${YELLOW}Nếu bạn muốn gỡ các gói không dùng, hãy chạy: 'sudo pacman -Rns <tên_gói>' hoặc 'pacman -Qtdq | sudo pacman -Rns -'${NC}\n"
