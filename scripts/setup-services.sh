#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: System & User Services Orchestration Module
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}:: [Services Setup] Kích hoạt các dịch vụ hệ thống và dịch vụ người dùng...${NC}"

# Nạp thông tin phần cứng
IS_ASUS_ROG="false"
IS_LAPTOP="false"
if [ -f /tmp/yusei-hypr/detected.env ]; then
    # shellcheck disable=SC1091
    . /tmp/yusei-hypr/detected.env
fi

# 1. Kích hoạt Bluetooth Service
echo -e "${BLUE}:: [1/4] Kích hoạt Bluetooth (bluetooth.service)...${NC}"
if command -v bluetoothctl &>/dev/null; then
    sudo systemctl enable --now bluetooth.service 2>&1 || true
    echo -e "${GREEN}✓ Đã kích hoạt bluetooth.service!${NC}"
else
    echo -e "${YELLOW}⚠️ Gói bluez chưa được cài đặt. Bỏ qua bật bluetooth.service.${NC}"
fi

# 2. Kích hoạt dịch vụ quản lý phần cứng ASUS ROG (nếu có)
if [ "$IS_ASUS_ROG" = "true" ]; then
    echo -e "${BLUE}:: [2/4] Kích hoạt dịch vụ ASUS ROG (supergfxd.service)...${NC}"
    if systemctl list-unit-files supergfxd.service &>/dev/null; then
        sudo systemctl enable --now supergfxd.service 2>&1 || true
        echo -e "${GREEN}✓ Đã kích hoạt supergfxd.service!${NC}"
    fi
else
    echo -e "${GREEN}✓ [2/4] Bỏ qua dịch vụ ASUS ROG (thiết bị tiêu chuẩn).${NC}"
fi

# 3. Kích hoạt dịch vụ quản lý nguồn điện cho Laptop (power-profiles-daemon)
if [ "${IS_LAPTOP:-false}" = "true" ]; then
    echo -e "${BLUE}:: [3/4] Kích hoạt dịch vụ nguồn điện Laptop (power-profiles-daemon.service)...${NC}"
    if command -v powerprofilesctl &>/dev/null || systemctl list-unit-files power-profiles-daemon.service &>/dev/null; then
        sudo systemctl enable --now power-profiles-daemon.service 2>&1 || true
        echo -e "${GREEN}✓ Đã kích hoạt power-profiles-daemon.service!${NC}"
    else
        echo -e "${YELLOW}⚠️ Gói power-profiles-daemon chưa được cài đặt. Bỏ qua.${NC}"
    fi
else
    echo -e "${GREEN}✓ [3/4] Bỏ qua dịch vụ nguồn điện Laptop (thiết bị tiêu chuẩn Desktop).${NC}"
fi

# 4. Kích hoạt PipeWire & WirePlumber Audio User Services
echo -e "${BLUE}:: [4/4] Kích hoạt dịch vụ âm thanh người dùng (PipeWire & WirePlumber)...${NC}"
# Chỉ kích hoạt user service nếu không chạy trực tiếp dưới quyền root hoàn toàn (sudo không có UID người dùng)
if [ "${EUID:-0}" -ne 0 ] || [ -n "${SUDO_USER:-}" ]; then
    RUN_AS_USER="${SUDO_USER:-$USER}"
    if [ "${EUID:-0}" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        # Gọi dưới quyền người dùng thực tế nếu đang trong sudo
        sudo -u "$RUN_AS_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$RUN_AS_USER")" systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null || true
    else
        systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null || true
    fi
    echo -e "${GREEN}✓ Đã kích hoạt PipeWire, PipeWire-Pulse và WirePlumber user services!${NC}"
else
    echo -e "${YELLOW}ℹ️ Chạy dưới quyền root trực tiếp, dịch vụ user sẽ tự kích hoạt khi đăng nhập vào Desktop.${NC}"
fi

echo -e "${GREEN}✓ Hoàn tất thiết lập các dịch vụ hệ thống!${NC}\n"
