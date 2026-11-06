#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Display Manager (SDDM) Provisioning Module
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}:: [SDDM Setup] Cấu hình trình quản lý đăng nhập (Display Manager)...${NC}"

AUTO_ACCEPT=false
for arg in "$@"; do
    if [[ "$arg" == "-y" || "$arg" == "--yes" ]]; then
        AUTO_ACCEPT=true
        break
    fi
done

if [ "$AUTO_ACCEPT" = "false" ]; then
    read -rp "Bạn có muốn cài đặt và kích hoạt SDDM làm màn hình đăng nhập mặc định? [Y/n]: " CONFIRM_SDDM
    if [[ "$CONFIRM_SDDM" =~ ^[nN] ]]; then
        echo -e "${YELLOW}:: Bỏ qua cài đặt SDDM theo yêu cầu của người dùng.${NC}\n"
        exit 0
    fi
fi

# 1. Tìm AUR helper hoặc Pacman
AUR_HELPER=""
if command -v yay &> /dev/null; then
    AUR_HELPER="yay"
elif command -v paru &> /dev/null; then
    AUR_HELPER="paru"
else
    AUR_HELPER="sudo pacman"
fi

# 2. Vô hiệu hóa các Display Manager cạnh tranh để tránh xung đột
echo -e "${BLUE}:: [1/4] Vô hiệu hóa các Display Manager khác (GDM, LightDM, LXDM)...${NC}"
for dm in gdm lightdm lxdm; do
    if systemctl is-enabled "${dm}.service" &> /dev/null; then
        echo -e "${YELLOW}Phát hiện ${dm}.service đang bật. Đang tắt...${NC}"
        sudo systemctl disable "${dm}.service" 2>/dev/null || true
    fi
done

# 3. Cài đặt SDDM và các thư viện đồ họa Qt6
echo -e "${BLUE}:: [2/4] Cài đặt SDDM và thư viện Qt6 (qt6-declarative, qt6-svg)...${NC}"
SDDM_PKGS=(sddm qt6-declarative qt6-svg qt6-virtualkeyboard)
SDDM_TO_INSTALL=()
for pkg in "${SDDM_PKGS[@]}"; do
    if ! pacman -Qi "$pkg" &> /dev/null; then
        SDDM_TO_INSTALL+=("$pkg")
    fi
done

if [ ${#SDDM_TO_INSTALL[@]} -gt 0 ]; then
    echo -e "${YELLOW}Đang cài đặt các gói SDDM: ${SDDM_TO_INSTALL[*]}${NC}"
    $AUR_HELPER -S --needed --noconfirm "${SDDM_TO_INSTALL[@]}"
fi
echo -e "${GREEN}✓ SDDM và các gói phụ thuộc đã sẵn sàng!${NC}"

# 4. Tải và cài đặt Theme simple-sddm-2 (Chuẩn JaKooLit)
echo -e "${BLUE}:: [3/4] Cài đặt giao diện SDDM (simple-sddm-2)...${NC}"
THEME_DIR="/usr/share/sddm/themes/simple-sddm-2"
if [ ! -d "$THEME_DIR" ]; then
    TMP_THEME_DIR="/tmp/simple-sddm-2-clone"
    rm -rf "$TMP_THEME_DIR"
    echo -e "${YELLOW}Đang clone theme simple-sddm-2 từ GitHub...${NC}"
    if git clone --depth=1 https://github.com/JaKooLit/simple-sddm-2.git "$TMP_THEME_DIR" 2>/dev/null || \
       git clone --depth=1 https://github.com/koenvervloesem/simple-sddm-2.git "$TMP_THEME_DIR" 2>/dev/null; then
        sudo mkdir -p /usr/share/sddm/themes
        sudo cp -r "$TMP_THEME_DIR" "$THEME_DIR"
        rm -rf "$TMP_THEME_DIR"
        echo -e "${GREEN}✓ Đã triển khai theme simple-sddm-2 vào $THEME_DIR${NC}"
    else
        echo -e "${YELLOW}⚠️ Không thể tải theme từ internet. Sử dụng theme mặc định của SDDM.${NC}"
    fi
else
    echo -e "${GREEN}✓ Theme simple-sddm-2 đã có sẵn tại $THEME_DIR.${NC}"
fi

# 5. Cấu hình SDDM (/etc/sddm.conf.d/10-theme.conf & /etc/sddm.conf)
echo -e "${BLUE}:: [4/4] Ghi cấu hình SDDM...${NC}"
sudo mkdir -p /etc/sddm.conf.d

SELECTED_THEME="simple-sddm-2"
if [ ! -d "$THEME_DIR" ]; then
    SELECTED_THEME="maldives"
fi

cat << EOF | sudo tee /etc/sddm.conf.d/10-theme.conf > /dev/null
[Theme]
Current=$SELECTED_THEME

[General]
InputMethod=qtvirtualkeyboard
EOF

echo -e "${GREEN}✓ Đã ghi cấu hình theme ($SELECTED_THEME) vào /etc/sddm.conf.d/10-theme.conf${NC}"

# 6. Kích hoạt sddm.service
echo -e "${BLUE}:: Kích hoạt dịch vụ sddm.service...${NC}"
sudo systemctl enable sddm.service
echo -e "${GREEN}✓ Đã kích hoạt sddm.service thành công!${NC}\n"
