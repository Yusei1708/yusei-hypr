#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Optional Applications & System Management Module
# Step: [5/5]
#
# Interactive TUI Checklist (Whiptail/Dialog) with Pure-Bash CLI Fallback.
# Curated catalog: Browsers, System Tools, SDDM + Themes, Dev Tools, Aesthetics.
# ==============================================================================

set -uo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}:: [5/5] Gợi ý cài đặt ứng dụng tùy chọn và công cụ quản trị hệ thống...${NC}"

# ------------------------------------------------------------------------------
# 1. Parsing Arguments
# ------------------------------------------------------------------------------
DRY_RUN=false
FORCE_CLI=false
LIST_APPS=false
PRESELECTED=()

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=true
            ;;
        --list-apps)
            LIST_APPS=true
            ;;
        --cli|--fallback|--text)
            FORCE_CLI=true
            ;;
        --select=*)
            IFS=',' read -ra PRESELECTED <<< "${arg#*=}"
            ;;
        -h|--help)
            echo -e "${CYAN}${BOLD}yusei-hypr: Module gợi ý cài đặt ứng dụng tùy chọn${NC}"
            echo -e "Cách dùng: $0 [TÙY CHỌN]"
            echo ""
            echo "Tùy chọn:"
            echo "  --dry-run          Mô phỏng cài đặt mà không thay đổi cấu hình hay gọi lệnh hệ thống"
            echo "  --list-apps        In danh sách toàn bộ các ứng dụng trong catalog rồi thoát"
            echo "  --cli, --fallback  Bắt buộc sử dụng Menu dòng lệnh thuần Bash (bỏ qua Whiptail/Dialog)"
            echo "  --select=ID1,ID2   Chọn sẵn các ứng dụng theo mã ID (hoặc --select=all / --select=none)"
            echo "  -h, --help         Hiển thị hướng dẫn này"
            echo ""
            echo "Lưu ý: Cờ -y / --yes vẫn luôn hiển thị hộp thoại gợi ý để người dùng chủ động lựa chọn."
            exit 0
            ;;
        -y|--yes)
            # Yêu cầu R1: cờ -y vẫn luôn hiển thị hộp thoại gợi ý này
            ;;
        *)
            ;;
    esac
done

# ------------------------------------------------------------------------------
# 2. Curated Application Catalog Definition
# ------------------------------------------------------------------------------
APP_IDS=(
    "chrome"
    "brave"
    "chromium"
    "mission-center"
    "gparted"
    "timeshift"
    "ufw"
    "sddm"
    "git"
    "vscode"
    "btop"
    "pokemon-colorscripts"
    "cava"
)

declare -A APP_NAMES
declare -A APP_CATEGORIES
declare -A APP_PACKAGES
declare -A APP_DESCRIPTIONS
declare -A APP_TRIGGERS

# 🌐 Trình duyệt Web
APP_CATEGORIES["chrome"]="🌐 Trình duyệt Web"
APP_NAMES["chrome"]="Google Chrome"
APP_PACKAGES["chrome"]="google-chrome"
APP_DESCRIPTIONS["chrome"]="Trình duyệt Web phổ biến nhất thế giới"
APP_TRIGGERS["chrome"]="none"

APP_CATEGORIES["brave"]="🌐 Trình duyệt Web"
APP_NAMES["brave"]="Brave Browser"
APP_PACKAGES["brave"]="brave-bin"
APP_DESCRIPTIONS["brave"]="Trình duyệt bảo mật cao & chặn quảng cáo"
APP_TRIGGERS["brave"]="none"

APP_CATEGORIES["chromium"]="🌐 Trình duyệt Web"
APP_NAMES["chromium"]="Chromium"
APP_PACKAGES["chromium"]="chromium"
APP_DESCRIPTIONS["chromium"]="Trình duyệt mã nguồn mở nền tảng Chrome"
APP_TRIGGERS["chromium"]="none"

# 🛠️ Quản lý máy & Hệ thống
APP_CATEGORIES["mission-center"]="🛠️ Quản lý máy & Hệ thống"
APP_NAMES["mission-center"]="Mission Center"
APP_PACKAGES["mission-center"]="mission-center"
APP_DESCRIPTIONS["mission-center"]="Task Manager trực quan phong cách Windows 11"
APP_TRIGGERS["mission-center"]="none"

APP_CATEGORIES["gparted"]="🛠️ Quản lý máy & Hệ thống"
APP_NAMES["gparted"]="GParted"
APP_PACKAGES["gparted"]="gparted"
APP_DESCRIPTIONS["gparted"]="Công cụ phân vùng & quản lý ổ đĩa GUI"
APP_TRIGGERS["gparted"]="none"

APP_CATEGORIES["timeshift"]="🛠️ Quản lý máy & Hệ thống"
APP_NAMES["timeshift"]="Timeshift"
APP_PACKAGES["timeshift"]="timeshift"
APP_DESCRIPTIONS["timeshift"]="Sao lưu & khôi phục snapshot hệ thống"
APP_TRIGGERS["timeshift"]="none"

APP_CATEGORIES["ufw"]="🛠️ Quản lý máy & Hệ thống"
APP_NAMES["ufw"]="UFW Firewall & GUFW"
APP_PACKAGES["ufw"]="ufw gufw"
APP_DESCRIPTIONS["ufw"]="Tường lửa bảo vệ hệ thống & GUI quản trị"
APP_TRIGGERS["ufw"]="ufw"

# 🔐 Màn hình đăng nhập
APP_CATEGORIES["sddm"]="🔐 Màn hình đăng nhập"
APP_NAMES["sddm"]="SDDM & Sugar Candy Theme"
APP_PACKAGES["sddm"]="sddm sddm-sugar-candy-git"
APP_DESCRIPTIONS["sddm"]="Màn hình đăng nhập hiện đại + Theme Sugar Candy"
APP_TRIGGERS["sddm"]="sddm"

# 💻 Lập trình & Dev
APP_CATEGORIES["git"]="💻 Lập trình & Dev"
APP_NAMES["git"]="Git & Git-LFS"
APP_PACKAGES["git"]="git git-lfs"
APP_DESCRIPTIONS["git"]="Quản lý phiên bản mã nguồn & Large File Storage"
APP_TRIGGERS["git"]="none"

APP_CATEGORIES["vscode"]="💻 Lập trình & Dev"
APP_NAMES["vscode"]="Visual Studio Code"
APP_PACKAGES["vscode"]="visual-studio-code-bin"
APP_DESCRIPTIONS["vscode"]="Trình biên tập mã nguồn phổ biến hàng đầu"
APP_TRIGGERS["vscode"]="none"

# 📊 Giám sát & Hiệu ứng
APP_CATEGORIES["btop"]="📊 Giám sát & Hiệu ứng"
APP_NAMES["btop"]="Btop++"
APP_PACKAGES["btop"]="btop"
APP_DESCRIPTIONS["btop"]="Trình theo dõi tài nguyên hệ thống TUI đẹp mắt"
APP_TRIGGERS["btop"]="none"

APP_CATEGORIES["pokemon-colorscripts"]="📊 Giám sát & Hiệu ứng"
APP_NAMES["pokemon-colorscripts"]="Pokemon Colorscripts"
APP_PACKAGES["pokemon-colorscripts"]="pokemon-colorscripts-git"
APP_DESCRIPTIONS["pokemon-colorscripts"]="Hiển thị Pokemon ngẫu nhiên phong cách pixel art"
APP_TRIGGERS["pokemon-colorscripts"]="none"

APP_CATEGORIES["cava"]="📊 Giám sát & Hiệu ứng"
APP_NAMES["cava"]="Cava Audio Visualizer"
APP_PACKAGES["cava"]="cava"
APP_DESCRIPTIONS["cava"]="Trình diễn sóng âm thanh qua Terminal"
APP_TRIGGERS["cava"]="none"

# ------------------------------------------------------------------------------
# 3. Status Checking Helper
# ------------------------------------------------------------------------------
declare -A INSTALLED_MAP

check_installed_status() {
    for id in "${APP_IDS[@]}"; do
        local all_installed=true
        local pkgs=(${APP_PACKAGES[$id]})
        for pkg in "${pkgs[@]}"; do
            if ! pacman -Qi "$pkg" &>/dev/null; then
                all_installed=false
                break
            fi
        done
        if [ "$all_installed" = "true" ]; then
            INSTALLED_MAP[$id]="true"
        else
            INSTALLED_MAP[$id]="false"
        fi
    done
}

check_installed_status

# ------------------------------------------------------------------------------
# 4. Handle --list-apps
# ------------------------------------------------------------------------------
if [ "$LIST_APPS" = "true" ]; then
    echo -e "${CYAN}${BOLD}========================================================================================================${NC}"
    echo -e "${CYAN}${BOLD}                 📦 DANH SÁCH ỨNG DỤNG TÙY CHỌN TRONG CATALOG (yusei-hypr)                              ${NC}"
    echo -e "${CYAN}${BOLD}========================================================================================================${NC}"
    printf "%-4s %-22s %-26s %-12s %-26s %s\n" "STT" "MÃ (ID)" "TÊN ỨNG DỤNG" "TRẠNG THÁI" "CÁC GÓI CÀI ĐẶT" "NHÓM"
    echo -e "--------------------------------------------------------------------------------------------------------"
    local_idx=1
    for id in "${APP_IDS[@]}"; do
        status_label="${YELLOW}[Chưa cài]${NC}"
        if [ "${INSTALLED_MAP[$id]}" = "true" ]; then
            status_label="${GREEN}[Đã có]   ${NC}"
        fi
        printf "%-4d %-22s %-26s %b %-26s %s\n" \
            "$local_idx" \
            "$id" \
            "${APP_NAMES[$id]}" \
            "$status_label" \
            "${APP_PACKAGES[$id]}" \
            "${APP_CATEGORIES[$id]}"
        ((local_idx++))
    done
    echo -e "${CYAN}${BOLD}========================================================================================================${NC}"
    exit 0
fi

# ------------------------------------------------------------------------------
# 5. Helpers for Detection & Execution
# ------------------------------------------------------------------------------
detect_aur_helper() {
    if command -v yay &> /dev/null; then
        echo "yay"
    elif command -v paru &> /dev/null; then
        echo "paru"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    else
        echo ""
    fi
}

is_terminal_capable() {
    if [ "$FORCE_CLI" = "true" ]; then
        return 1
    fi
    # Must have an interactive terminal on stdin and stdout
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        return 1
    fi
    if ! command -v whiptail &>/dev/null && ! command -v dialog &>/dev/null; then
        return 1
    fi
    if [[ -z "${TERM:-}" || "$TERM" == "dumb" ]]; then
        return 1
    fi
    # Terminal must support cursor positioning
    if ! tput cup 0 0 &>/dev/null; then
        return 1
    fi
    # Terminal geometry check: require at least 16 lines and 65 columns
    local term_lines term_cols
    term_lines=$(tput lines 2>/dev/null || echo 0)
    term_cols=$(tput cols 2>/dev/null || echo 0)
    [[ "${term_lines:-0}" =~ ^[0-9]+$ ]] || term_lines=0
    [[ "${term_cols:-0}" =~ ^[0-9]+$ ]] || term_cols=0
    if [ "${term_lines:-0}" -lt 16 ] || [ "${term_cols:-0}" -lt 65 ]; then
        return 1
    fi
    return 0
}

run_post_triggers() {
    local trigger="$1"
    local dry_run="$2"

    case "$trigger" in
        sddm)
            echo -e "${BLUE}:: [SDDM Trigger] Thiết lập giao diện SDDM Sugar Candy Theme...${NC}"
            local theme_name="sugar-candy"
            if [ -d "/usr/share/sddm/themes/Sugar-Candy" ]; then
                theme_name="Sugar-Candy"
            fi
            if [ "$dry_run" = "true" ]; then
                echo -e "${YELLOW}[DRY-RUN] Sẽ tạo file cấu hình /etc/sddm.conf.d/10-theme.conf với nội dung:${NC}"
                echo -e "         [Theme]\n         Current=$theme_name"
                echo -e "${YELLOW}[DRY-RUN] Sẽ kích hoạt dịch vụ: sudo systemctl enable --force sddm.service${NC}"
            else
                sudo mkdir -p /etc/sddm.conf.d
                cat << EOF | sudo tee /etc/sddm.conf.d/10-theme.conf > /dev/null
[Theme]
Current=$theme_name
EOF
                echo -e "${GREEN}✓ Đã ghi cấu hình theme vào /etc/sddm.conf.d/10-theme.conf${NC}"
                echo -e "${BLUE}:: Kích hoạt dịch vụ sddm.service...${NC}"
                if sudo systemctl enable --force sddm.service 2>&1; then
                    echo -e "${GREEN}✓ Đã kích hoạt sddm.service thành công!${NC}"
                else
                    echo -e "${YELLOW}⚠️ Không thể kích hoạt sddm.service tự động (vui lòng kiểm tra quyền hạn hệ thống).${NC}"
                fi
            fi
            ;;
        ufw)
            echo -e "${BLUE}:: [UFW Trigger] Kích hoạt tường lửa UFW...${NC}"
            if [ "$dry_run" = "true" ]; then
                echo -e "${YELLOW}[DRY-RUN] Sẽ kích hoạt dịch vụ: sudo systemctl enable ufw.service${NC}"
            else
                if sudo systemctl enable ufw.service 2>&1; then
                    echo -e "${GREEN}✓ Đã kích hoạt ufw.service thành công!${NC}"
                else
                    echo -e "${YELLOW}⚠️ Không thể kích hoạt ufw.service tự động (vui lòng kiểm tra quyền hạn hệ thống).${NC}"
                fi
            fi
            ;;
        *)
            ;;
    esac
}

install_selected_apps() {
    local selected=("$@")
    if [ ${#selected[@]} -eq 0 ]; then
        echo -e "${YELLOW}:: Không có ứng dụng nào được chọn. Bỏ qua bước cài đặt.${NC}"
        return 0
    fi

    echo ""
    echo -e "${CYAN}${BOLD}================================================================================${NC}"
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}${BOLD}🔍 MÔ PHỎNG QUY TRÌNH CÀI ĐẶT ỨNG DỤNG TÙY CHỌN (--dry-run)${NC}"
    else
        echo -e "${GREEN}${BOLD}🚀 TIẾN HÀNH CÀI ĐẶT CÁC ỨNG DỤNG TÙY CHỌN ĐÃ CHỌN${NC}"
    fi
    echo -e "${CYAN}${BOLD}================================================================================${NC}"

    echo -e "${BLUE}Danh sách ứng dụng được chọn (${#selected[@]} ứng dụng):${NC}"
    local all_pkgs=()
    local triggers=()
    for id in "${selected[@]}"; do
        echo -e "  • ${BOLD}${APP_NAMES[$id]}${NC} (${APP_PACKAGES[$id]})"
        for p in ${APP_PACKAGES[$id]}; do
            all_pkgs+=("$p")
        done
        local trig="${APP_TRIGGERS[$id]}"
        if [[ "$trig" != "none" ]]; then
            triggers+=("$trig")
        fi
    done

    # Loại bỏ gói trùng lặp
    local unique_pkgs=()
    for p in "${all_pkgs[@]}"; do
        local exists=false
        for u in "${unique_pkgs[@]}"; do
            if [ "$u" = "$p" ]; then
                exists=true
                break
            fi
        done
        if [ "$exists" = "false" ]; then
            unique_pkgs+=("$p")
        fi
    done

    # Lọc các gói chưa cài đặt
    local missing_pkgs=()
    for p in "${unique_pkgs[@]}"; do
        if ! pacman -Qi "$p" &>/dev/null; then
            missing_pkgs+=("$p")
        fi
    done

    local helper
    helper=$(detect_aur_helper)
    if [ -z "$helper" ]; then
        echo -e "${RED}[ERROR] Không tìm thấy yay, paru hoặc pacman trên hệ thống!${NC}"
        exit 1
    fi

    echo ""
    if [ ${#missing_pkgs[@]} -eq 0 ]; then
        echo -e "${GREEN}✓ Tất cả các gói phần mềm cho ứng dụng đã chọn đều đã có sẵn trên máy!${NC}"
    else
        echo -e "${BLUE}Tổng số gói cần cài đặt:${NC} ${#missing_pkgs[@]} gói (${missing_pkgs[*]})"
        echo -e "${BLUE}Trình quản lý gói được sử dụng:${NC} ${BOLD}$helper${NC}"

        if [ "$helper" = "pacman" ]; then
            local aur_missing=()
            for p in "${missing_pkgs[@]}"; do
                if ! pacman -Si "$p" &>/dev/null; then
                    aur_missing+=("$p")
                fi
            done
            if [ ${#aur_missing[@]} -gt 0 ]; then
                echo -e "${YELLOW}⚠️ Chú ý: Các gói sau thuộc AUR và không có sẵn trong kho pacman chính thức: ${aur_missing[*]}${NC}"
                echo -e "${YELLOW}   (Khuyên dùng 'yay' hoặc 'paru' để cài đặt tự động từ AUR)${NC}"
            fi
        fi

        if [ "$DRY_RUN" = "true" ]; then
            if [ "$helper" = "pacman" ]; then
                echo -e "${YELLOW}[DRY-RUN] Lệnh cài đặt:${NC} sudo pacman -S --needed --noconfirm ${missing_pkgs[*]}"
            else
                echo -e "${YELLOW}[DRY-RUN] Lệnh cài đặt:${NC} $helper -S --needed --noconfirm ${missing_pkgs[*]}"
            fi
        else
            echo -e "${BLUE}:: Đang tiến hành cài đặt gói...${NC}"
            if [ "$helper" = "pacman" ]; then
                sudo pacman -S --needed --noconfirm "${missing_pkgs[@]}"
            else
                $helper -S --needed --noconfirm "${missing_pkgs[@]}"
            fi
            echo -e "${GREEN}✓ Cài đặt gói hoàn tất thành công!${NC}"
        fi
    fi

    # Thực thi các post-install triggers
    if [ ${#triggers[@]} -gt 0 ]; then
        echo ""
        echo -e "${BLUE}:: Thực hiện các tác vụ cấu hình hệ thống bổ sung (Post-install triggers)...${NC}"
        local unique_triggers=()
        for t in "${triggers[@]}"; do
            local texists=false
            for ut in "${unique_triggers[@]}"; do
                if [ "$ut" = "$t" ]; then
                    texists=true
                    break
                fi
            done
            if [ "$texists" = "false" ]; then
                unique_triggers+=("$t")
            fi
        done

        for t in "${unique_triggers[@]}"; do
            run_post_triggers "$t" "$DRY_RUN"
        done
    fi

    echo ""
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${GREEN}${BOLD}✓ Mô phỏng hoàn tất an toàn! Không có thay đổi nào được thực hiện trên hệ thống.${NC}"
    else
        echo -e "${GREEN}${BOLD}✓ Hoàn tất cài đặt và cấu hình toàn bộ ứng dụng tùy chọn!${NC}"
    fi
    echo ""
}

# ------------------------------------------------------------------------------
# 6. Fallback Pure-Bash CLI Interactive Menu
# ------------------------------------------------------------------------------
run_cli_fallback_menu() {
    declare -A SELECTED_STATE
    for id in "${APP_IDS[@]}"; do
        SELECTED_STATE[$id]=0
    done

    while true; do
        clear 2>/dev/null || echo "--------------------------------------------------------------------------------"
        echo -e "${CYAN}${BOLD}================================================================================${NC}"
        echo -e "${CYAN}${BOLD}        📦 DANH MỤC GỢI Ý CÀI ĐẶT ỨNG DỤNG TÙY CHỌN (yusei-hypr)         ${NC}"
        echo -e "${CYAN}${BOLD}================================================================================${NC}"
        echo -e " Hướng dẫn thao tác:"
        echo -e "   • Nhập số (ví dụ: ${BOLD}1${NC} hoặc ${BOLD}1 4 8${NC}) để ${BOLD}BẬT / TẮT [X]${NC} từng ứng dụng."
        echo -e "   • Nhập ${BOLD}'a'${NC} để chọn tất cả  |  ${BOLD}'n'${NC} để bỏ chọn tất cả."
        echo -e "   • Nhập ${BOLD}'c'${NC} hoặc ${BOLD}'install'${NC} để TIẾP TỤC cài đặt các ứng dụng đã chọn."
        echo -e "   • Nhập ${BOLD}'q'${NC} hoặc ${BOLD}'skip'${NC} hoặc ${BOLD}'0'${NC} để BỎ QUA và hoàn tất."
        echo -e "${CYAN}--------------------------------------------------------------------------------${NC}"

        local current_cat=""
        local idx=1
        for id in "${APP_IDS[@]}"; do
            local cat="${APP_CATEGORIES[$id]}"
            if [ "$cat" != "$current_cat" ]; then
                echo ""
                echo -e "${BLUE}${BOLD}[ $cat ]${NC}"
                current_cat="$cat"
            fi

            local mark=" "
            if [ "${SELECTED_STATE[$id]}" -eq 1 ]; then
                mark="X"
            fi

            local status_str=""
            if [ "${INSTALLED_MAP[$id]}" = "true" ]; then
                status_str="${GREEN}[Đã có]${NC} "
            fi

            printf "  %b[%2d]%b [%b%s%b] %-26s %b%s\n" \
                "${YELLOW}" "$idx" "${NC}" \
                "${BOLD}" "$mark" "${NC}" \
                "${APP_NAMES[$id]}" \
                "$status_str" \
                "${APP_DESCRIPTIONS[$id]}"
            ((idx++))
        done
        echo ""
        echo -e "${CYAN}--------------------------------------------------------------------------------${NC}"

        local user_input=""
        if [ -t 0 ]; then
            # Interactive terminal: allow the user full time to interact
            if ! read -rp "👉 Lựa chọn của bạn (nhập số, Enter/'c' để tiếp tục, 'q' để bỏ qua): " user_input; then
                user_input="EOF"
            fi
        else
            # Non-interactive / piped / EOF
            if ! read -r user_input; then
                user_input="EOF"
            fi
        fi

        # Xử lý trường hợp EOF (non-interactive hoặc đường ống kết thúc)
        if [ "$user_input" = "EOF" ]; then
            local count=0
            for id in "${APP_IDS[@]}"; do
                if [ "${SELECTED_STATE[$id]}" -eq 1 ]; then
                    ((count++))
                fi
            done
            if [ "$count" -gt 0 ]; then
                break
            fi
            if [ "$DRY_RUN" = "true" ]; then
                echo -e "${YELLOW}[DRY-RUN] Phát hiện môi trường non-interactive (EOF). Tự động mô phỏng các ứng dụng mẫu: Google Chrome, SDDM, UFW.${NC}"
                SELECTED_STATE["chrome"]=1
                SELECTED_STATE["sddm"]=1
                SELECTED_STATE["ufw"]=1
                break
            else
                echo -e "${YELLOW}:: Bạn đã chọn bỏ qua cài đặt ứng dụng tùy chọn.${NC}"
                exit 0
            fi
        fi

        # Chuẩn hóa chuỗi nhập: chuyển chữ thường và loại bỏ khoảng trắng an toàn thuần Bash (không dùng xargs)
        user_input="${user_input#"${user_input%%[![:space:]]*}"}"
        user_input="${user_input%"${user_input##*[![:space:]]}"}"
        user_input="${user_input,,}"

        if [[ "$user_input" =~ ^(q|skip|cancel|0)$ ]]; then
            echo -e "${YELLOW}:: Bạn đã chọn bỏ qua cài đặt ứng dụng tùy chọn.${NC}"
            exit 0
        fi

        if [[ "$user_input" =~ ^(c|confirm|install|continue|ok)$ ]] || [ -z "$user_input" ]; then
            break
        fi

        if [[ "$user_input" == "a" || "$user_input" == "all" ]]; then
            for id in "${APP_IDS[@]}"; do
                SELECTED_STATE[$id]=1
            done
            continue
        fi

        if [[ "$user_input" == "n" || "$user_input" == "none" ]]; then
            for id in "${APP_IDS[@]}"; do
                SELECTED_STATE[$id]=0
            done
            continue
        fi

        # Phân tích các số được gõ
        user_input="${user_input//,/ }"
        local valid_num=false
        for token in $user_input; do
            if [[ "$token" =~ ^[0-9]+$ ]]; then
                local num=$((10#$token))
                if [ "$num" -ge 1 ] && [ "$num" -le ${#APP_IDS[@]} ]; then
                    local target_id="${APP_IDS[$((num-1))]}"
                    SELECTED_STATE[$target_id]=$(( 1 - SELECTED_STATE[$target_id] ))
                    valid_num=true
                fi
            fi
        done

        if [ "$valid_num" = "false" ]; then
            echo -e "${RED}Lựa chọn không hợp lệ! Vui lòng nhập số từ 1 đến ${#APP_IDS[@]}, 'c' để tiếp tục hoặc 'q' để bỏ qua.${NC}"
            sleep 1 2>/dev/null || true
        fi
    done

    local final_selected=()
    for id in "${APP_IDS[@]}"; do
        if [ "${SELECTED_STATE[$id]}" -eq 1 ]; then
            final_selected+=("$id")
        fi
    done

    install_selected_apps "${final_selected[@]}"
}

# ------------------------------------------------------------------------------
# 7. Main Workflow Execution
# ------------------------------------------------------------------------------
main_workflow() {
    # Trường hợp 1: Có cờ --select được truyền từ trước
    if [ ${#PRESELECTED[@]} -gt 0 ]; then
        local resolved_ids=()
        if [[ "${PRESELECTED[0]}" == "all" ]]; then
            resolved_ids=("${APP_IDS[@]}")
        elif [[ "${PRESELECTED[0]}" == "none" ]]; then
            resolved_ids=()
        else
            for req in "${PRESELECTED[@]}"; do
                # Chuẩn hóa khoảng trắng an toàn thuần Bash (không dùng xargs)
                req="${req#"${req%%[![:space:]]*}"}"
                req="${req%"${req##*[![:space:]]}"}"
                [ -z "$req" ] && continue
                local found=false
                for id in "${APP_IDS[@]}"; do
                    if [ "$id" = "$req" ]; then
                        resolved_ids+=("$id")
                        found=true
                        break
                    fi
                done
                if [ "$found" = "false" ]; then
                    echo -e "${YELLOW}⚠️ Cảnh báo: Mã ứng dụng không hợp lệ '$req' trong --select (bỏ qua).${NC}"
                fi
            done
        fi
        install_selected_apps "${resolved_ids[@]}"
        exit 0
    fi

    # Trường hợp 2: Khởi chạy TUI Checklist (Whiptail hoặc Dialog)
    if is_terminal_capable; then
        # Tính toán kích thước giao diện động phù hợp chuẩn với mọi terminal (kể cả console 80x24)
        local term_lines term_cols
        term_lines=$(tput lines 2>/dev/null || echo 24)
        term_cols=$(tput cols 2>/dev/null || echo 80)
        [[ "${term_lines:-0}" =~ ^[0-9]+$ ]] || term_lines=24
        [[ "${term_cols:-0}" =~ ^[0-9]+$ ]] || term_cols=80

        local box_h=$(( term_lines > 24 ? 24 : term_lines - 2 ))
        [ "$box_h" -lt 16 ] && box_h=16

        local box_w=$(( term_cols > 80 ? 78 : term_cols - 4 ))
        [ "$box_w" -lt 60 ] && box_w=60

        local list_h=$(( box_h - 8 ))
        [ "$list_h" -lt 6 ] && list_h=6

        local tui_args=()
        for id in "${APP_IDS[@]}"; do
            local label="${APP_NAMES[$id]}"
            if [ "${INSTALLED_MAP[$id]}" = "true" ]; then
                label="$label [Đã có] - ${APP_DESCRIPTIONS[$id]}"
            else
                label="$label - ${APP_DESCRIPTIONS[$id]}"
            fi
            tui_args+=("$id" "$label" "OFF")
        done

        local choices=""
        local ret=0

        # Ưu tiên Whiptail nếu có
        if command -v whiptail &>/dev/null; then
            choices=$(whiptail --title "yusei-hypr: Cài đặt ứng dụng tùy chọn (5/5)" \
                --checklist "Dùng Phím Cách (Space) để chọn/bỏ chọn, Mũi Tên để di chuyển, Tab để chọn nút.\n(Các ứng dụng [Đã có] mặc định tắt checkbox để tránh trùng lặp):" \
                "$box_h" "$box_w" "$list_h" \
                --ok-button "Cài đặt" \
                --cancel-button "Bỏ qua" \
                "${tui_args[@]}" \
                3>&1 1>&2 2>&3) || ret=$?
        elif command -v dialog &>/dev/null; then
            local dialog_err
            dialog_err=$(mktemp 2>/dev/null || echo "/tmp/dialog_err_$$")
            choices=$(dialog --stdout --title "yusei-hypr: Cài đặt ứng dụng tùy chọn (5/5)" \
                --checklist "Dùng Phím Cách (Space) để chọn/bỏ chọn, Mũi Tên để di chuyển, Tab để chọn nút.\n(Các ứng dụng [Đã có] mặc định tắt checkbox để tránh trùng lặp):" \
                "$box_h" "$box_w" "$list_h" \
                --ok-label "Cài đặt" \
                --cancel-label "Bỏ qua" \
                "${tui_args[@]}" 2>"$dialog_err") || ret=$?
            if [ "$ret" -ne 0 ] && [ -s "$dialog_err" ]; then
                choices=$(cat "$dialog_err" 2>/dev/null || true)
            fi
            rm -f "$dialog_err" 2>/dev/null || true
        fi

        if [ "$ret" -eq 0 ]; then
            local choices_clean="${choices//\"/}"
            local selected_ids=()
            read -ra selected_ids <<< "$choices_clean"
            install_selected_apps "${selected_ids[@]}"
            exit 0
        elif [ "$ret" -eq 1 ] || [ "$ret" -eq 255 ]; then
            # Kiểm tra xem đây là hành động chủ động bấm Cancel (không có lỗi ở stderr) hay là lỗi khởi tạo TUI
            local trimmed_choices
            trimmed_choices=$(echo "$choices" | tr -d '[:space:]')
            if [ -z "$trimmed_choices" ]; then
                # Người dùng chọn Cancel / Bỏ qua hoặc nhấn ESC
                echo -e "${YELLOW}:: Bạn đã chọn bỏ qua cài đặt ứng dụng tùy chọn.${NC}"
                exit 0
            fi
            # Nếu choices chứa chuỗi lỗi từ TUI, tự động trôi xuống Fallback CLI bên dưới
        fi
        # Nếu TUI bị lỗi khởi tạo hoặc trả về lỗi, tự động trôi xuống Fallback CLI
    fi

    # Trường hợp 3: Fallback hiển thị Menu dòng lệnh thuần Bash
    run_cli_fallback_menu
}

main_workflow
