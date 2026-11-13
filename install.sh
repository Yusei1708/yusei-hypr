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

AUTO_ACCEPT=false
DRY_RUN=false
HW_ARGS=()
SDDM_NVIDIA_ARGS=()
OPTIONAL_APP_ARGS=()

show_usage() {
    echo -e "${CYAN}${BOLD}yusei-hypr: Bộ cài đặt tự động Universal Hyprland Suite${NC}"
    echo ""
    echo "Cú pháp: $0 [TÙY CHỌN]"
    echo ""
    echo "Tùy chọn:"
    echo "  --dry-run             Mô phỏng toàn bộ quy trình cài đặt (chỉ đọc, không sửa hệ thống)"
    echo "  -y, --yes             Tự động xác nhận tiến hành cài đặt (non-interactive)"
    echo "  --cli, --fallback     Dùng menu dòng lệnh cho bước ứng dụng tùy chọn"
    echo "  --list-apps           Liệt kê catalog ứng dụng tùy chọn ở Bước 9"
    echo "  --select=ID1,ID2      Chọn sẵn ứng dụng tùy chọn (hoặc --select=all / none)"
    echo "  -h, --help            Hiển thị hướng dẫn này và thoát"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            AUTO_ACCEPT=true
            HW_ARGS+=("-y")
            SDDM_NVIDIA_ARGS+=("-y")
            OPTIONAL_APP_ARGS+=("-y")
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            HW_ARGS+=("--dry-run")
            OPTIONAL_APP_ARGS+=("--dry-run")
            shift
            ;;
        --cli|--fallback|--text|--list-apps)
            OPTIONAL_APP_ARGS+=("$1")
            shift
            ;;
        --select=*)
            OPTIONAL_APP_ARGS+=("$1")
            shift
            ;;
        --select)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                echo -e "${RED}[LỖI] --select yêu cầu giá trị (ví dụ: --select=all hoặc --select=none).${NC}" >&2
                exit 1
            fi
            OPTIONAL_APP_ARGS+=("--select=$2")
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${RED}[LỖI] Tùy chọn không hợp lệ: $1${NC}" >&2
            show_usage >&2
            exit 1
            ;;
    esac
done

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

if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}${BOLD}🔍 [DRY-RUN] Chế độ chạy thử chỉ đọc: KHÔNG cài gói, KHÔNG sửa /etc, KHÔNG chạm ~/.config hoặc ~/.local!${NC}\n"
fi

echo -e "${BLUE}Chào mừng bạn đến với bộ cài đặt tự động ${BOLD}yusei-hypr${NC}!"
echo -e "Bộ cài đặt này sẽ:"
echo -e "  1. Tự động nhận diện phần cứng (NVIDIA/Intel/AMD, Kernel headers, Laptop, ASUS ROG)."
echo -e "  2. Cài đặt các gói phụ thuộc, loại bỏ xung đột PulseAudio sang PipeWire hoàn chỉnh."
echo -e "  3. Cấu hình chuyên sâu tầng Kernel (Early KMS, Modprobe DRM, GRUB) nếu có card NVIDIA."
echo -e "  4. Kích hoạt toàn bộ các dịch vụ hệ thống (Bluetooth, PipeWire, WirePlumber)."
echo -e "  5. Cài đặt và cấu hình Display Manager SDDM kèm theme simple-sddm-2 chuẩn mực."
echo -e "  6. Sao lưu bảo toàn các cấu hình cũ trong ~/.config."
echo -e "  7. Triển khai giao diện bo góc & animations Material 3 (Bảo toàn userprefs.conf & tùy biến cá nhân)."
echo -e "  8. Kiểm định toàn diện sức khỏe hệ thống sau khi cài đặt (05-verify.sh)."
echo -e "  9. Gợi ý cài đặt ứng dụng tùy chọn và công cụ quản trị hệ thống (05-optional-apps.sh)."
echo ""

if [ "$AUTO_ACCEPT" = "false" ] && [ "$DRY_RUN" = "false" ]; then
    read -rp "Bạn có muốn tiếp tục tiến hành cài đặt ngay bây giờ? [Y/n]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[nN] ]]; then
        echo -e "${RED}Đã hủy cài đặt.${NC}"
        exit 0
    fi
fi

echo ""

if [ "$DRY_RUN" = "false" ]; then
    for s in "$DIR"/scripts/*.sh; do
        [[ -f "$s" && ! -x "$s" ]] && chmod +x "$s" 2>/dev/null || true
    done
fi

# Helpers ghi nhận trạng thái tiền cài đặt cho uninstall.sh an toàn
detect_current_dm() {
    local dm_unit=""
    if command -v systemctl &>/dev/null && [[ -L /etc/systemd/system/display-manager.service ]]; then
        dm_unit="$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)" .service)"
    fi
    echo "$dm_unit"
}

is_svc_enabled_bool() {
    if command -v systemctl &>/dev/null && systemctl is-enabled "$1" &>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/yusei-hypr"
STATE_FILE="$STATE_DIR/install-state.env"
PRE_SDDM_ENABLED="false"
PRE_BLUETOOTH_ENABLED="false"
PRE_SUPERGFXD_ENABLED="false"
PRE_DISPLAY_MANAGER=""
PRE_INSTALL_BACKUP=""

if [ "$DRY_RUN" = "false" ]; then
    PRE_SDDM_ENABLED="$(is_svc_enabled_bool sddm.service)"
    PRE_BLUETOOTH_ENABLED="$(is_svc_enabled_bool bluetooth.service)"
    PRE_SUPERGFXD_ENABLED="$(is_svc_enabled_bool supergfxd.service)"
    PRE_DISPLAY_MANAGER="$(detect_current_dm)"

    if [[ -f "$STATE_FILE" ]]; then
        EXISTING_PRE_BACKUP=""
        EXISTING_PRE_BACKUP="$(grep -E '^PRE_INSTALL_BACKUP=' "$STATE_FILE" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d "\"'" || true)"
        if [[ -n "$EXISTING_PRE_BACKUP" && -d "$EXISTING_PRE_BACKUP" ]]; then
            PRE_INSTALL_BACKUP="$EXISTING_PRE_BACKUP"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# Chạy tuần tự quy trình cài đặt chuẩn hóa
# ------------------------------------------------------------------------------

# Bước 1: Nhận diện phần cứng & Kernel
"$DIR/scripts/hardware-detect.sh" ${HW_ARGS[@]+"${HW_ARGS[@]}"}

HAS_NVIDIA="false"
if [ "$DRY_RUN" = "true" ]; then
    if command -v python3 &>/dev/null; then
        HAS_NVIDIA="$("$DIR/scripts/hardware-detect.sh" --json --dry-run 2>/dev/null | python3 -c '
import json, sys
try:
    print("true" if json.load(sys.stdin).get("has_nvidia") else "false")
except Exception:
    print("false")
' 2>/dev/null || echo "false")"
    fi
elif [ -f /tmp/yusei-hypr/detected.env ]; then
    # shellcheck disable=SC1091
    . /tmp/yusei-hypr/detected.env
fi

# Bước 2: Cài đặt phần mềm & Phụ thuộc
if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}[DRY-RUN] Bỏ qua Bước 2 (02-packages.sh): sẽ đồng bộ gói, gỡ xung đột PulseAudio/awww, ghi IgnorePkg = swww awww và cài swww 0.9.5.${NC}"
else
    "$DIR/scripts/02-packages.sh"
fi

# Bước 3: Cấu hình Kernel NVIDIA (nếu có card NVIDIA)
if [ "$HAS_NVIDIA" = "true" ]; then
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[DRY-RUN] Phát hiện GPU NVIDIA: sẽ chạy setup-nvidia.sh để cấu hình Early KMS, Modprobe và tham số kernel.${NC}"
    else
        "$DIR/scripts/setup-nvidia.sh" ${SDDM_NVIDIA_ARGS[@]+"${SDDM_NVIDIA_ARGS[@]}"}
    fi
fi

# Bước 4: Kích hoạt dịch vụ hệ thống nền (Bluetooth, Audio, ASUS ROG)
if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}[DRY-RUN] Bỏ qua Bước 4 (setup-services.sh): sẽ kích hoạt PipeWire, WirePlumber, Bluetooth, Power Profiles/ASUS ROG.${NC}"
else
    "$DIR/scripts/setup-services.sh"
fi

# Bước 5: Cấu hình Trình quản lý đăng nhập SDDM
if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}[DRY-RUN] Bỏ qua Bước 5 (setup-sddm.sh): sẽ cấu hình SDDM kèm theme simple-sddm-2.${NC}"
else
    "$DIR/scripts/setup-sddm.sh" ${SDDM_NVIDIA_ARGS[@]+"${SDDM_NVIDIA_ARGS[@]}"}
fi

# Bước 6: Sao lưu cấu hình hiện tại
if [ "$DRY_RUN" = "true" ]; then
    "$DIR/scripts/03-backup.sh" --dry-run
else
    "$DIR/scripts/03-backup.sh"
    CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    if [[ -z "$PRE_INSTALL_BACKUP" && -L "$CONFIG_HOME/yusei-hypr-backup-latest" ]]; then
        LATEST_BACKUP_RESOLVED="$(readlink -f "$CONFIG_HOME/yusei-hypr-backup-latest" 2>/dev/null || true)"
        if [[ -n "$LATEST_BACKUP_RESOLVED" && -d "$LATEST_BACKUP_RESOLVED" ]]; then
            PRE_INSTALL_BACKUP="$LATEST_BACKUP_RESOLVED"
        fi
    fi
fi

# Bước 7: Cài đặt cấu hình End-4 Material 3 (Bảo vệ userprefs.conf, UserConfigs & UserScripts)
if [ "$DRY_RUN" = "true" ]; then
    "$DIR/scripts/04-install-configs.sh" --dry-run
else
    "$DIR/scripts/04-install-configs.sh"
fi

# Bước 7.1: Thiết lập cờ biến môi trường Wayland NVIDIA vào userprefs.conf nếu phát hiện GPU NVIDIA
if [ "$HAS_NVIDIA" = "true" ]; then
    if [ "$DRY_RUN" = "true" ]; then
        "$DIR/scripts/hardware-detect.sh" --dry-run --inject-userprefs --target-userprefs="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/userprefs.conf"
    else
        "$DIR/scripts/hardware-detect.sh" --inject-userprefs --target-userprefs="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/userprefs.conf"
    fi
fi

# Ghi install-state.env (chỉ khi không --dry-run)
if [ "$DRY_RUN" = "false" ]; then
    POST_SDDM_ENABLED="$(is_svc_enabled_bool sddm.service)"
    POST_BLUETOOTH_ENABLED="$(is_svc_enabled_bool bluetooth.service)"
    POST_SUPERGFXD_ENABLED="$(is_svc_enabled_bool supergfxd.service)"

    INSTALLER_ENABLED_SDDM="false"
    [[ "$PRE_SDDM_ENABLED" = "false" && "$POST_SDDM_ENABLED" = "true" ]] && INSTALLER_ENABLED_SDDM="true"

    INSTALLER_ENABLED_BLUETOOTH="false"
    [[ "$PRE_BLUETOOTH_ENABLED" = "false" && "$POST_BLUETOOTH_ENABLED" = "true" ]] && INSTALLER_ENABLED_BLUETOOTH="true"

    INSTALLER_ENABLED_SUPERGFXD="false"
    [[ "$PRE_SUPERGFXD_ENABLED" = "false" && "$POST_SUPERGFXD_ENABLED" = "true" ]] && INSTALLER_ENABLED_SUPERGFXD="true"

    mkdir -p "$STATE_DIR"
    {
        printf 'PRE_SDDM_ENABLED=%q\n' "$PRE_SDDM_ENABLED"
        printf 'PRE_BLUETOOTH_ENABLED=%q\n' "$PRE_BLUETOOTH_ENABLED"
        printf 'PRE_SUPERGFXD_ENABLED=%q\n' "$PRE_SUPERGFXD_ENABLED"
        printf 'PRE_DISPLAY_MANAGER=%q\n' "$PRE_DISPLAY_MANAGER"
        printf 'PRE_INSTALL_BACKUP=%q\n' "$PRE_INSTALL_BACKUP"
        printf 'INSTALLER_ENABLED_SDDM=%q\n' "$INSTALLER_ENABLED_SDDM"
        printf 'INSTALLER_ENABLED_BLUETOOTH=%q\n' "$INSTALLER_ENABLED_BLUETOOTH"
        printf 'INSTALLER_ENABLED_SUPERGFXD=%q\n' "$INSTALLER_ENABLED_SUPERGFXD"
    } > "$STATE_FILE"
fi

# Bước 8: Kiểm định hệ thống sau cài đặt (không làm gián đoạn Bước 9 dưới set -e)
VERIFY_RC=0
if [ "$DRY_RUN" = "true" ]; then
    "$DIR/scripts/05-verify.sh" --dry-run || VERIFY_RC=$?
else
    "$DIR/scripts/05-verify.sh" || VERIFY_RC=$?
    if [ "$VERIFY_RC" -ne 0 ]; then
        echo -e "${YELLOW}⚠️ Kiểm định phát hiện một số hạng mục cần lưu ý (mã $VERIFY_RC); tiếp tục sang Bước 9...${NC}"
    fi
fi

# Bước 9 (Tùy chọn): Gợi ý cài đặt ứng dụng catalog
if [ -f "$DIR/scripts/05-optional-apps.sh" ]; then
    "$DIR/scripts/05-optional-apps.sh" ${OPTIONAL_APP_ARGS[@]+"${OPTIONAL_APP_ARGS[@]}"} || true
elif [ -f "$DIR/scripts/06-optional-apps.sh" ]; then
    "$DIR/scripts/06-optional-apps.sh" ${OPTIONAL_APP_ARGS[@]+"${OPTIONAL_APP_ARGS[@]}"} || true
fi

echo -e "${CYAN}${BOLD}================================================================${NC}"
if [ "$DRY_RUN" = "true" ]; then
    echo -e "${GREEN}${BOLD}🎉 MÔ PHỎNG CÀI ĐẶT (--dry-run) HOÀN TẤT AN TOÀN! (KHÔNG GHI ĐĨA)${NC}"
elif [ "$VERIFY_RC" -ne 0 ]; then
    echo -e "${YELLOW}${BOLD}⚠️ BỘ CÀI ĐẶT ĐÃ HOÀN TẤT VỚI CẢNH BÁO KIỂM ĐỊNH (xem báo cáo Bước 8).${NC}"
else
    echo -e "${GREEN}${BOLD}🎉 CHÚC MỪNG! BỘ CÀI ĐẶT yusei-hypr ĐÃ HOÀN TẤT THÀNH CÔNG!${NC}"
fi
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
echo -e "${BLUE}ℹ️ Khi cần hoàn nguyên hoặc gỡ cài đặt, bạn có thể chạy: ${BOLD}./uninstall.sh${NC} (hoặc ${BOLD}./scripts/uninstall.sh${NC})"
echo -e "${BLUE}👉 Hãy khởi động lại máy tính (Reboot) để các module kernel và SDDM có hiệu lực trọn vẹn!${NC}\n"
