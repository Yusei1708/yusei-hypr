#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Hardware & OS Detection Module
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}:: [1/4] Đang quét hệ thống và phần cứng...${NC}"

# 1. Kiểm tra Hệ điều hành
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "arch" && "$ID_LIKE" != *"arch"* ]]; then
        echo -e "${RED}[ERROR] Dự án yusei-hypr hiện được thiết kế tối ưu cho Arch Linux! (Phát hiện: $PRETTY_NAME)${NC}"
        echo -e "${YELLOW}Nếu bạn muốn tiếp tục mạo hiểm trên distro này, hãy chỉnh sửa scripts/01-detect.sh.${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ Hệ điều hành: $PRETTY_NAME (Tương thích tốt)${NC}"
    fi
else
    echo -e "${RED}[ERROR] Không nhận diện được file /etc/os-release!${NC}"
    exit 1
fi

# 2. Kiểm tra GPU
export HAS_NVIDIA=false
if lspci | grep -iE 'vga|3d|display' | grep -iq 'nvidia'; then
    export HAS_NVIDIA=true
    echo -e "${GREEN}✓ Đồ họa: Phát hiện card NVIDIA (Sẽ tự động kích hoạt nvidia.conf)${NC}"
else
    echo -e "${GREEN}✓ Đồ họa: Card Intel / AMD Radeon (Native Wayland)${NC}"
fi

# 3. Kiểm tra Laptop hay Desktop
export IS_LAPTOP=false
if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    export IS_LAPTOP=true
    echo -e "${GREEN}✓ Thiết bị: Laptop (Sẽ kích hoạt phím chỉnh độ sáng & module Pin)${NC}"
else
    echo -e "${GREEN}✓ Thiết bị: Desktop PC${NC}"
fi

# Lưu trạng thái vào file tạm để các script sau dùng
mkdir -p /tmp/yusei-hypr
cat <<EOF > /tmp/yusei-hypr/detected.env
HAS_NVIDIA=$HAS_NVIDIA
IS_LAPTOP=$IS_LAPTOP
EOF

echo -e "${GREEN}✓ Quét phần cứng hoàn tất!${NC}\n"
