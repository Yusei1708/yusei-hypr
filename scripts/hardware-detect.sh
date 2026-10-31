#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Hardware & Driver Detection Subsystem
# ==============================================================================
# Comprehensive hardware, chassis, audio, and driver detection engine.
# Supports dry-run inspection, JSON reporting, env file export, and
# userprefs.conf NVIDIA environment variable injection.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ANSI color codes
CYAN='\033[0;36m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# Default configuration flags
DRY_RUN=false
OUTPUT_JSON=false
ENV_FILE="/tmp/yusei-hypr/detected.env"
INJECT_USERPREFS=false
TARGET_USERPREFS="${TARGET_USERPREFS:-$HOME/.config/hypr/userprefs.conf}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

yusei-hypr Hardware & Driver Detection Subsystem. Probes host OS, Kernel,
GPU, chassis, and audio stack to configure optimal Hyprland environment.

Options:
  --dry-run                 Simulate detection; prints summary without writing any files
  --json                    Output hardware detection profile in JSON format
  --env-file=<path>         Path to write detected shell environment variables
                            (default: /tmp/yusei-hypr/detected.env)
  --inject-userprefs        Inject NVIDIA Wayland flags into userprefs.conf if NVIDIA GPU is present
  --target-userprefs=<path> Specify custom userprefs.conf target path
                            (default: ~/.config/hypr/userprefs.conf)
  -h, --help                Display this help message and exit

Examples:
  $(basename "$0") --dry-run
  $(basename "$0") --json
  $(basename "$0") --env-file=/tmp/custom.env
  $(basename "$0") --inject-userprefs
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --env-file=*)
            ENV_FILE="${1#*=}"
            if [[ -z "$ENV_FILE" ]]; then
                echo -e "${RED}[ERROR] --env-file requires a non-empty file path.${NC}" >&2
                exit 1
            fi
            shift
            ;;
        --env-file)
            if [[ -n "${2:-}" && "${2:-}" != --* ]]; then
                ENV_FILE="$2"
                shift 2
            else
                echo -e "${RED}[ERROR] --env-file requires a valid file path.${NC}" >&2
                exit 1
            fi
            ;;
        --inject-userprefs)
            INJECT_USERPREFS=true
            shift
            ;;
        --target-userprefs=*)
            TARGET_USERPREFS="${1#*=}"
            if [[ -z "$TARGET_USERPREFS" ]]; then
                echo -e "${RED}[ERROR] --target-userprefs requires a non-empty file path.${NC}" >&2
                exit 1
            fi
            shift
            ;;
        --target-userprefs)
            if [[ -n "${2:-}" && "${2:-}" != --* ]]; then
                TARGET_USERPREFS="$2"
                shift 2
            else
                echo -e "${RED}[ERROR] --target-userprefs requires a valid file path.${NC}" >&2
                exit 1
            fi
            ;;
        -y|--yes)
            # Accept auto-confirm flag forwarded from callers (e.g. install.sh)
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR] Unknown option: $1${NC}" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# 1. OS & Distro Detection
# ------------------------------------------------------------------------------
IS_ARCH=false
OS_NAME="Unknown Linux"
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_NAME="${PRETTY_NAME:-${NAME:-Arch Linux}}"
    if [[ "${ID:-}" == "arch" || "${ID_LIKE:-}" == *"arch"* || "${ID:-}" == *"arch"* ]]; then
        IS_ARCH=true
    fi
fi

if [ "$IS_ARCH" = "false" ] && [ "$OUTPUT_JSON" = "false" ]; then
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[CẢNH BÁO] Hệ điều hành hiện tại không phải Arch Linux: $OS_NAME${NC}" >&2
    else
        echo -e "${RED}[ERROR] Dự án yusei-hypr được thiết kế tối ưu cho Arch Linux! (Phát hiện: $OS_NAME)${NC}" >&2
        echo -e "${YELLOW}Nếu bạn muốn tiếp tục mạo hiểm trên distro này, hãy sử dụng cờ --dry-run để xem trước.${NC}" >&2
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# 2. Kernel & Headers Detection
# ------------------------------------------------------------------------------
KERNEL_RELEASE="$(uname -r)"
KERNEL_PKG="linux"
if [ -f "/usr/lib/modules/${KERNEL_RELEASE}/pkgbase" ]; then
    KERNEL_PKG=$(cat "/usr/lib/modules/${KERNEL_RELEASE}/pkgbase" 2>/dev/null || true)
fi

if [ -z "$KERNEL_PKG" ]; then
    case "$KERNEL_RELEASE" in
        *zen*)      KERNEL_PKG="linux-zen" ;;
        *lts*)      KERNEL_PKG="linux-lts" ;;
        *hardened*) KERNEL_PKG="linux-hardened" ;;
        *)          KERNEL_PKG="linux" ;;
    esac
fi
KERNEL_HEADERS_PKG="${KERNEL_PKG}-headers"

# ------------------------------------------------------------------------------
# 3. GPU Detection (NVIDIA / Integrated / AMD)
# ------------------------------------------------------------------------------
# Detects dedicated NVIDIA GPUs via lspci or sysfs PCI vendor ID (0x10de).
# When detected, triggers dkms kernel driver recommendations and exports
# optimal Wayland compositor environment variables (GBM_BACKEND, LIBVA).
HAS_NVIDIA=false
NVIDIA_MODEL=""

SYSFS_PCI_DIR="${SYSFS_PCI_DIR:-/sys/bus/pci/devices}"
LSPCI_OUTPUT="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)"
if echo "$LSPCI_OUTPUT" | grep -iq "nvidia"; then
    HAS_NVIDIA=true
    NVIDIA_MODEL="$(echo "$LSPCI_OUTPUT" | grep -i "nvidia" | head -n 1 | sed -E 's/^[0-9a-f:.]+ (VGA compatible controller|3D controller): //' | tr -d '"\n')"
    if [ -z "$NVIDIA_MODEL" ]; then
        NVIDIA_MODEL="NVIDIA Corporation (Generic)"
    fi
elif { ! command -v lspci >/dev/null 2>&1 || [ -z "$LSPCI_OUTPUT" ]; } && grep -qi "0x10de" "$SYSFS_PCI_DIR"/*/vendor /dev/null 2>/dev/null; then
    HAS_NVIDIA=true
    NVIDIA_MODEL="NVIDIA Corporation (PCI Vendor 0x10de)"
fi

# ------------------------------------------------------------------------------
# 4. Laptop / Chassis Detection
# ------------------------------------------------------------------------------
IS_LAPTOP=false
if compgen -G "/sys/class/power_supply/BAT*" >/dev/null 2>&1 || compgen -G "/sys/class/power_supply/battery*" >/dev/null 2>&1; then
    IS_LAPTOP=true
elif [ -f /sys/class/dmi/id/chassis_type ]; then
    CHASSIS_TYPE="$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || true)"
    case "$CHASSIS_TYPE" in
        8|9|10|11|14|30|31|32)
            IS_LAPTOP=true
            ;;
    esac
fi

# ------------------------------------------------------------------------------
# 5. ASUS ROG Detection
# ------------------------------------------------------------------------------
IS_ASUS_ROG=false
DMI_VENDOR="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
DMI_PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
DMI_FAMILY="$(cat /sys/class/dmi/id/product_family 2>/dev/null || true)"
DMI_COMBINED="${DMI_VENDOR} ${DMI_PRODUCT} ${DMI_FAMILY}"
if echo "$DMI_COMBINED" | grep -iq "asus" && echo "$DMI_COMBINED" | grep -iqE "rog|republic of gamers|zephyrus|strix|flow"; then
    IS_ASUS_ROG=true
fi

# ------------------------------------------------------------------------------
# 6. Audio Stack & PulseAudio Conflict Detection
# ------------------------------------------------------------------------------
AUDIO_STACK="pipewire"
PULSE_CONFLICTS=()
for pulse_pkg in pulseaudio pulseaudio-bluetooth pulseaudio-alsa pulseaudio-jack; do
    if pacman -Qi "$pulse_pkg" &>/dev/null; then
        PULSE_CONFLICTS+=("$pulse_pkg")
    fi
done

if [ ${#PULSE_CONFLICTS[@]} -gt 0 ]; then
    HAS_PULSE_CONFLICT=true
else
    HAS_PULSE_CONFLICT=false
fi

# ------------------------------------------------------------------------------
# Output Formats: JSON vs Human-Readable Terminal
# ------------------------------------------------------------------------------
if [ "$OUTPUT_JSON" = "true" ]; then
    PULSE_JSON="["
    first=true
    for p in "${PULSE_CONFLICTS[@]}"; do
        if [ "$first" = true ]; then
            PULSE_JSON="${PULSE_JSON}\"$p\""
            first=false
        else
            PULSE_JSON="${PULSE_JSON}, \"$p\""
        fi
    done
    PULSE_JSON="${PULSE_JSON}]"

    cat <<EOF
{
  "os": "$OS_NAME",
  "is_arch": $IS_ARCH,
  "kernel": "$KERNEL_RELEASE",
  "kernel_pkg": "$KERNEL_PKG",
  "kernel_headers_pkg": "$KERNEL_HEADERS_PKG",
  "has_nvidia": $HAS_NVIDIA,
  "nvidia_model": "$NVIDIA_MODEL",
  "nvidia_packages": [
    "$KERNEL_HEADERS_PKG",
    "nvidia-dkms",
    "nvidia-utils",
    "libva-nvidia-driver"
  ],
  "is_laptop": $IS_LAPTOP,
  "laptop_packages": [
    "brightnessctl",
    "acpi",
    "power-profiles-daemon"
  ],
  "is_asus_rog": $IS_ASUS_ROG,
  "audio_stack": "$AUDIO_STACK",
  "has_pulse_conflict": $HAS_PULSE_CONFLICT,
  "pulse_conflicts": $PULSE_JSON
}
EOF
else
    echo -e "${CYAN}${BOLD}================================================================================${NC}"
    echo -e "${CYAN}${BOLD}   🖥️  yusei-hypr: HỆ THỐNG NHẬN DIỆN PHẦN CỨNG & CẤU HÌNH HỆ THỐNG              ${NC}"
    echo -e "${CYAN}${BOLD}================================================================================${NC}"
    echo -e " ${BOLD}Hệ điều hành:${NC}       ${OS_NAME} $([ "$IS_ARCH" = "true" ] && echo -e "${GREEN}(Arch Linux Compatible)${NC}" || echo -e "${YELLOW}(Non-Arch Warning)${NC}")"
    echo -e " ${BOLD}Kernel Linux:${NC}       ${KERNEL_RELEASE} (${GREEN}${KERNEL_PKG}${NC})"
    echo -e " ${BOLD}Kernel Headers:${NC}     ${GREEN}${KERNEL_HEADERS_PKG}${NC}"

    if [ "$HAS_NVIDIA" = "true" ]; then
        echo -e " ${BOLD}Đồ họa (GPU):${NC}        ${GREEN}NVIDIA Detected${NC} [${NVIDIA_MODEL}]"
        echo -e "                     ${YELLOW}↳ Gói yêu cầu: ${KERNEL_HEADERS_PKG}, nvidia-dkms, nvidia-utils, libva-nvidia-driver${NC}"
    else
        echo -e " ${BOLD}Đồ họa (GPU):${NC}        ${GREEN}Intel / AMD Radeon (Native Wayland Driver)${NC}"
    fi

    if [ "$IS_LAPTOP" = "true" ]; then
        echo -e " ${BOLD}Kiểu thiết bị:${NC}      ${GREEN}Laptop Chassis${NC} (Phát hiện pin / ACPI)"
        echo -e "                     ${YELLOW}↳ Gói khuyến nghị: brightnessctl, acpi, power-profiles-daemon${NC}"
    else
        echo -e " ${BOLD}Kiểu thiết bị:${NC}      ${GREEN}Desktop PC / Fixed Workstation${NC}"
    fi

    if [ "$IS_ASUS_ROG" = "true" ]; then
        echo -e " ${BOLD}Phần cứng đặc thù:${NC}  ${GREEN}ASUS ROG Series Laptop${NC} (Kích hoạt asusctl, supergfxctl)"
    fi

    echo -e " ${BOLD}Hệ thống âm thanh:${NC}  ${GREEN}PipeWire Stack${NC} (wireplumber, pipewire-pulse, pipewire-alsa)"
    if [ "$HAS_PULSE_CONFLICT" = "true" ]; then
        echo -e "                     ${RED}⚠️ Xung đột PulseAudio: ${PULSE_CONFLICTS[*]} (Cần tháo gỡ)${NC}"
    else
        echo -e "                     ${GREEN}✓ Không phát hiện xung đột PulseAudio${NC}"
    fi
    echo -e "${CYAN}--------------------------------------------------------------------------------${NC}"
fi

# ------------------------------------------------------------------------------
# Action: Inject NVIDIA environment variables into userprefs.conf
# ------------------------------------------------------------------------------
if [ "$INJECT_USERPREFS" = "true" ]; then
    if [ "$HAS_NVIDIA" = "true" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            if [ "$OUTPUT_JSON" = "false" ]; then
                echo -e "${YELLOW}:: [DRY-RUN] Sẽ chèn các biến môi trường NVIDIA vào: ${TARGET_USERPREFS}${NC}"
                echo -e "${YELLOW}   • env = LIBVA_DRIVER_NAME,nvidia${NC}"
                echo -e "${YELLOW}   • env = GBM_BACKEND,nvidia-drm${NC}"
                echo -e "${YELLOW}   • env = __GLX_VENDOR_LIBRARY_NAME,nvidia${NC}"
                echo -e "${YELLOW}   • env = NVD_BACKEND,direct${NC}"
            fi
        else
            mkdir -p "$(dirname "$TARGET_USERPREFS")"

            if [[ ! -f "$TARGET_USERPREFS" ]]; then
                if [[ -f "$REPO_ROOT/config/hypr/userprefs.conf" ]]; then
                    cp -a "$REPO_ROOT/config/hypr/userprefs.conf" "$TARGET_USERPREFS"
                else
                    touch "$TARGET_USERPREFS"
                fi
            fi

            if grep -q -E '^[[:space:]]*env[[:space:]]*=[[:space:]]*LIBVA_DRIVER_NAME' "$TARGET_USERPREFS" && \
               grep -q -E '^[[:space:]]*env[[:space:]]*=[[:space:]]*GBM_BACKEND' "$TARGET_USERPREFS"; then
                if [ "$OUTPUT_JSON" = "false" ]; then
                    echo -e "${GREEN}✓ [Userprefs] Biến môi trường NVIDIA đã có sẵn trong: ${TARGET_USERPREFS}${NC}"
                fi
            else
                cat << 'EOF' >> "$TARGET_USERPREFS"

# ------------------------------------------------------------------------------
# NVIDIA Wayland Flags (Auto-injected by hardware-detect.sh)
# ------------------------------------------------------------------------------
env = LIBVA_DRIVER_NAME,nvidia
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = NVD_BACKEND,direct
EOF
                if [ "$OUTPUT_JSON" = "false" ]; then
                    echo -e "${GREEN}✓ [Userprefs] Đã chèn biến môi trường NVIDIA vào: ${TARGET_USERPREFS}${NC}"
                fi
            fi
        fi
    else
        if [ "$OUTPUT_JSON" = "false" ]; then
            echo -e "${BLUE}:: [Userprefs] Không có GPU NVIDIA. Bỏ qua chèn biến môi trường.${NC}"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# Action: Write environment file
# ------------------------------------------------------------------------------
if [ "$DRY_RUN" = "true" ]; then
    if [ "$OUTPUT_JSON" = "false" ]; then
        echo -e "${YELLOW}:: [DRY-RUN] Chế độ chạy thử hoàn tất an toàn. Không có file nào bị ghi đè.${NC}\n"
    fi
    exit 0
else
    mkdir -p "$(dirname "$ENV_FILE")"
    cat <<EOF > "$ENV_FILE"
HAS_NVIDIA=$HAS_NVIDIA
IS_LAPTOP=$IS_LAPTOP
KERNEL_PKG=$KERNEL_PKG
KERNEL_HEADERS_PKG=$KERNEL_HEADERS_PKG
IS_ASUS_ROG=$IS_ASUS_ROG
AUDIO_STACK=$AUDIO_STACK
HAS_PULSE_CONFLICT=$HAS_PULSE_CONFLICT
EOF

    if [ "$OUTPUT_JSON" = "false" ]; then
        echo -e "${GREEN}✓ Đã lưu hồ sơ phần cứng vào: ${ENV_FILE}${NC}\n"
    fi
fi

exit 0
