#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Hardware & OS Detection Module
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}:: [Detect] Đang quét hệ thống và phần cứng...${NC}"

# 1. Kiểm tra Hệ điều hành
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "arch" && "${ID_LIKE:-}" != *"arch"* ]]; then
        echo -e "${RED}[ERROR] Dự án yusei-hypr hiện được thiết kế tối ưu cho Arch Linux! (Phát hiện: ${PRETTY_NAME:-Không rõ})${NC}"
        echo -e "${YELLOW}Nếu bạn muốn tiếp tục mạo hiểm trên distro này, hãy chỉnh sửa scripts/01-detect.sh.${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ Hệ điều hành: ${PRETTY_NAME:-Arch Linux} (Tương thích tốt)${NC}"
    fi
else
    echo -e "${RED}[ERROR] Không nhận diện được file /etc/os-release!${NC}"
    exit 1
fi

# 2. Kiểm tra Kernel và Kernel Headers
KERNEL_PKG="linux"
if [ -f "/usr/lib/modules/$(uname -r)/pkgbase" ]; then
    KERNEL_PKG=$(cat "/usr/lib/modules/$(uname -r)/pkgbase" 2>/dev/null || true)
fi

if [ -z "$KERNEL_PKG" ]; then
    CURRENT_UNAME="$(uname -r)"
    case "$CURRENT_UNAME" in
        *zen*)      KERNEL_PKG="linux-zen" ;;
        *lts*)      KERNEL_PKG="linux-lts" ;;
        *hardened*) KERNEL_PKG="linux-hardened" ;;
        *)          KERNEL_PKG="linux" ;;
    esac
fi

KERNEL_HEADERS_PKG="${KERNEL_PKG}-headers"
echo -e "${GREEN}✓ Kernel đang chạy: $(uname -r) -> Gói Headers yêu cầu: ${KERNEL_HEADERS_PKG}${NC}"

# 3. Kiểm tra GPU
HAS_NVIDIA=false
if lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -iq 'nvidia'; then
    HAS_NVIDIA=true
    echo -e "${GREEN}✓ Đồ họa: Phát hiện card NVIDIA (Sẽ kích hoạt nvidia.conf và kernel module)${NC}"
else
    echo -e "${GREEN}✓ Đồ họa: Card Intel / AMD Radeon (Native Wayland)${NC}"
fi

# 4. Kiểm tra Laptop hay Desktop
IS_LAPTOP=false
if compgen -G "/sys/class/power_supply/BAT*" >/dev/null 2>&1; then
    IS_LAPTOP=true
    echo -e "${GREEN}✓ Thiết bị: Laptop (Sẽ kích hoạt phím chỉnh độ sáng & module Pin)${NC}"
else
    echo -e "${GREEN}✓ Thiết bị: Desktop PC${NC}"
fi

# 5. Kiểm tra phần cứng ASUS ROG Laptop
IS_ASUS_ROG=false
DMI_VENDOR="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
DMI_PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
DMI_FAMILY="$(cat /sys/class/dmi/id/product_family 2>/dev/null || true)"
DMI_COMBINED="${DMI_VENDOR} ${DMI_PRODUCT} ${DMI_FAMILY}"

if echo "$DMI_COMBINED" | grep -iq "asus" && echo "$DMI_COMBINED" | grep -iqE "rog|republic of gamers|zephyrus|strix|flow"; then
    IS_ASUS_ROG=true
    echo -e "${GREEN}✓ Thiết bị đặc thù: Phát hiện laptop ASUS ROG (Sẽ cấu hình asusctl & supergfxctl)${NC}"
fi

# Lưu trạng thái vào file tạm để các script sau dùng
mkdir -p /tmp/yusei-hypr
cat <<EOF > /tmp/yusei-hypr/detected.env
HAS_NVIDIA=$HAS_NVIDIA
IS_LAPTOP=$IS_LAPTOP
KERNEL_PKG=$KERNEL_PKG
KERNEL_HEADERS_PKG=$KERNEL_HEADERS_PKG
IS_ASUS_ROG=$IS_ASUS_ROG
EOF

echo -e "${GREEN}✓ Quét phần cứng hoàn tất!${NC}\n"
