#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Curses Dialog & CLI Uninstaller and System Restoration Module
# ==============================================================================
# Features:
#   - Terminal capability detection (interactive, geometry, whiptail/dialog)
#   - Whiptail / Dialog radiolist for backup snapshot selection
#   - Whiptail / Dialog checklist for system services cleanup
#   - Pure-Bash CLI interactive fallback menu (--cli / --fallback or non-curses)
#   - Non-interactive and EOF clean termination handling (</dev/null safety)
#   - Full --dry-run and -y/--yes automation support
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

DRY_RUN=false
AUTO_ACCEPT=false
FORCE_CLI=false

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=true
            ;;
        -y|--yes)
            AUTO_ACCEPT=true
            ;;
        --cli|--fallback)
            FORCE_CLI=true
            ;;
        -h|--help)
            echo -e "${CYAN}${BOLD}yusei-hypr: Trình gỡ cài đặt và hoàn nguyên hệ thống${NC}"
            echo ""
            echo "Cú pháp: $0 [TÙY CHỌN]"
            echo ""
            echo "Tùy chọn:"
            echo "  --dry-run          Mô phỏng thao tác hoàn nguyên mà không sửa đổi hệ thống"
            echo "  -y, --yes          Tự động xác nhận gỡ cài đặt (chế độ non-interactive)"
            echo "  --cli, --fallback  Bắt buộc sử dụng giao diện dòng lệnh thuần Bash"
            echo "  -h, --help         Hiển thị hướng dẫn này và thoát"
            exit 0
            ;;
        *)
            ;;
    esac
done

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# ------------------------------------------------------------------------------
# 1. Snapshot Discovery
# ------------------------------------------------------------------------------
SNAPSHOT_DIRS=()
if [[ -d "$CONFIG_HOME" ]]; then
    while IFS= read -r snap_dir; do
        if [[ -n "$snap_dir" && -d "$snap_dir" && "$snap_dir" != *"yusei-hypr-backup-latest" ]]; then
            SNAPSHOT_DIRS+=("$snap_dir")
        fi
    done < <(find "$CONFIG_HOME" -maxdepth 1 -type d -name "yusei-hypr-backup-*" 2>/dev/null | sort -r)

    if [[ -d "$CONFIG_HOME/yusei-hypr-backups" ]]; then
        while IFS= read -r leg_dir; do
            if [[ -n "$leg_dir" && -d "$leg_dir" && "$leg_dir" != *"latest" ]]; then
                SNAPSHOT_DIRS+=("$leg_dir")
            fi
        done < <(find "$CONFIG_HOME/yusei-hypr-backups" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | sort -r)
    fi
fi

# ------------------------------------------------------------------------------
# 2. Terminal Capability Inspection (from 05-optional-apps.sh)
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# 3. Execution of Restoration and Cleanup
# ------------------------------------------------------------------------------
perform_cleanup() {
    local target_snap="$1"
    local do_sddm="$2"
    local do_bluetooth="$3"
    local do_supergfxd="$4"
    local do_nvidia="$5"
    local do_sddm_theme="$6"

    echo ""
    echo -e "${CYAN}${BOLD}================================================================================${NC}"
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}${BOLD}🔍 MÔ PHỎNG QUY TRÌNH GỠ CÀI ĐẶT VÀ HOÀN NGUYÊN (--dry-run)${NC}"
    else
        echo -e "${GREEN}${BOLD}🚀 TIẾN HÀNH GỠ CÀI ĐẶT VÀ HOÀN NGUYÊN HỆ THỐNG${NC}"
    fi
    echo -e "${CYAN}${BOLD}================================================================================${NC}"

    # 1. Khôi phục cấu hình ~/.config
    if [[ -n "$target_snap" && "$target_snap" != "skip" && "$target_snap" != "none" ]]; then
        echo -e "\n${BLUE}:: [1/2] Hoàn nguyên cấu hình từ bản sao lưu: $target_snap${NC}"
        if [[ -f "$DIR/scripts/rollback.sh" ]]; then
            if [ "$DRY_RUN" = "true" ]; then
                bash "$DIR/scripts/rollback.sh" "$target_snap" --dry-run
            else
                bash "$DIR/scripts/rollback.sh" "$target_snap"
            fi
        else
            echo -e "${YELLOW}⚠️ Không tìm thấy scripts/rollback.sh. Bỏ qua hoàn nguyên tự động.${NC}"
        fi
    else
        echo -e "\n${BLUE}:: [1/2] Bỏ qua hoàn nguyên cấu hình ~/.config theo tùy chọn.${NC}"
    fi

    # 2. Dọn dẹp dịch vụ và file hệ thống
    echo -e "\n${BLUE}:: [2/2] Dọn dẹp các dịch vụ và tệp cấu hình hệ thống...${NC}"

    if [ "$do_sddm" = "true" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "${YELLOW}[DRY-RUN] Sẽ thực thi: sudo systemctl disable sddm.service${NC}"
        else
            echo -e "${YELLOW}Đang tắt sddm.service...${NC}"
            sudo systemctl disable sddm.service 2>/dev/null || true
            echo -e "${GREEN}✓ Đã vô hiệu hóa sddm.service${NC}"
        fi
    fi

    if [ "$do_bluetooth" = "true" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "${YELLOW}[DRY-RUN] Sẽ thực thi: sudo systemctl disable bluetooth.service${NC}"
        else
            echo -e "${YELLOW}Đang tắt bluetooth.service...${NC}"
            sudo systemctl disable bluetooth.service 2>/dev/null || true
            echo -e "${GREEN}✓ Đã vô hiệu hóa bluetooth.service${NC}"
        fi
    fi

    if [ "$do_supergfxd" = "true" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "${YELLOW}[DRY-RUN] Sẽ thực thi: sudo systemctl disable supergfxd.service${NC}"
        else
            if systemctl list-unit-files supergfxd.service &>/dev/null; then
                echo -e "${YELLOW}Đang tắt supergfxd.service...${NC}"
                sudo systemctl disable supergfxd.service 2>/dev/null || true
                echo -e "${GREEN}✓ Đã vô hiệu hóa supergfxd.service${NC}"
            fi
        fi
    fi

    if [ "$do_nvidia" = "true" ]; then
        if [ -f /etc/modprobe.d/nvidia.conf ]; then
            if [ "$DRY_RUN" = "true" ]; then
                echo -e "${YELLOW}[DRY-RUN] Sẽ xóa tệp: /etc/modprobe.d/nvidia.conf${NC}"
            else
                echo -e "${YELLOW}Xóa /etc/modprobe.d/nvidia.conf...${NC}"
                sudo rm -f /etc/modprobe.d/nvidia.conf 2>/dev/null || true
                echo -e "${GREEN}✓ Đã dọn dẹp /etc/modprobe.d/nvidia.conf${NC}"
            fi
        fi
    fi

    if [ "$do_sddm_theme" = "true" ]; then
        if [ -f /etc/sddm.conf.d/10-theme.conf ]; then
            if [ "$DRY_RUN" = "true" ]; then
                echo -e "${YELLOW}[DRY-RUN] Sẽ xóa tệp: /etc/sddm.conf.d/10-theme.conf${NC}"
            else
                echo -e "${YELLOW}Xóa /etc/sddm.conf.d/10-theme.conf...${NC}"
                sudo rm -f /etc/sddm.conf.d/10-theme.conf 2>/dev/null || true
                echo -e "${GREEN}✓ Đã dọn dẹp /etc/sddm.conf.d/10-theme.conf${NC}"
            fi
        fi
    fi

    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[DRY-RUN] Sẽ dọn dẹp thư mục tạm thời: /tmp/yusei-hypr${NC}"
    else
        rm -rf /tmp/yusei-hypr
    fi

    echo -e "\n${CYAN}${BOLD}================================================================================${NC}"
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${GREEN}${BOLD}✓ MÔ PHỎNG GỠ CÀI ĐẶT HOÀN TẤT AN TOÀN!${NC}"
    else
        echo -e "${GREEN}${BOLD}🎉 QUÁ TRÌNH GỠ CÀI ĐẶT VÀ HOÀN NGUYÊN ĐÃ HOÀN TẤT THÀNH CÔNG!${NC}"
        echo -e "${YELLOW}Lưu ý: Các gói phần mềm đã tải về qua pacman/yay vẫn được giữ nguyên để bảo đảm an toàn hệ thống.${NC}"
        echo -e "${YELLOW}Nếu muốn gỡ bỏ hoàn toàn các gói không dùng, hãy chạy: 'pacman -Qtdq | sudo pacman -Rns -'${NC}\n"
    fi
    echo -e "${CYAN}${BOLD}================================================================================${NC}\n"
}

# ------------------------------------------------------------------------------
# 4. Fallback Pure-Bash CLI Interactive Menu
# ------------------------------------------------------------------------------
run_cli_fallback_menu() {
    local chosen_snap="skip"
    local do_sddm=true
    local do_bluetooth=true
    local do_supergfxd=false
    local do_nvidia=true
    local do_sddm_theme=true

    if [ ${#SNAPSHOT_DIRS[@]} -gt 0 ]; then
        chosen_snap="${SNAPSHOT_DIRS[0]}"
    fi

    local interactive=false
    if [ -t 0 ] && [ -t 1 ]; then
        interactive=true
    fi

    if [ "$interactive" = "false" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            # Dry-run preview in non-interactive environment
            perform_cleanup "$chosen_snap" "$do_sddm" "$do_bluetooth" "$do_supergfxd" "$do_nvidia" "$do_sddm_theme"
            exit 0
        elif [ "$AUTO_ACCEPT" = "true" ]; then
            # Non-interactive with explicit confirmation (-y / --yes)
            perform_cleanup "$chosen_snap" "$do_sddm" "$do_bluetooth" "$do_supergfxd" "$do_nvidia" "$do_sddm_theme"
            exit 0
        else
            # Non-interactive / piped environment without -y/--yes: safe guard exit
            echo -e "${YELLOW}Phát hiện môi trường không tương tác (non-interactive / piped stdin).${NC}"
            echo -e "${YELLOW}Để tiến hành gỡ cài đặt không tương tác, vui lòng sử dụng cờ -y hoặc --yes (hoặc --dry-run để mô phỏng).${NC}"
            echo -e "${YELLOW}Thoát an toàn mà không thực hiện thay đổi nào.${NC}"
            exit 0
        fi
    fi

    if [ "$AUTO_ACCEPT" = "true" ]; then
        perform_cleanup "$chosen_snap" "$do_sddm" "$do_bluetooth" "$do_supergfxd" "$do_nvidia" "$do_sddm_theme"
        exit 0
    fi

    # Interactive Menu 1: Snapshot Selection
    echo ""
    echo -e "${CYAN}${BOLD}================================================================================${NC}"
    echo -e "${BLUE}${BOLD}   [1/2] CHỌN BẢN SAO LƯU ĐỂ HOÀN NGUYÊN (yusei-hypr)${NC}"
    echo -e "${CYAN}${BOLD}================================================================================${NC}"
    echo -e " [0] Bỏ qua hoàn nguyên cấu hình ~/.config"
    local s_idx=1
    for snap in "${SNAPSHOT_DIRS[@]}"; do
        echo -e " [$s_idx] $(basename "$snap")"
        ((s_idx++))
    done
    echo ""

    local snap_choice=""
    if ! read -rp "👉 Chọn bản sao lưu muốn khôi phục [mặc định: 1 nếu có, hoặc 0 để bỏ qua]: " snap_choice; then
        snap_choice="EOF"
    fi

    if [ "$snap_choice" = "EOF" ]; then
        if [ "$DRY_RUN" = "true" ] || [ "$AUTO_ACCEPT" = "true" ]; then
            perform_cleanup "$chosen_snap" "$do_sddm" "$do_bluetooth" "$do_supergfxd" "$do_nvidia" "$do_sddm_theme"
            exit 0
        else
            echo -e "\n${YELLOW}Đã hủy bỏ.${NC}"
            exit 0
        fi
    fi

    snap_choice="${snap_choice// /}"
    if [[ "$snap_choice" =~ ^[0-9]+$ ]]; then
        local num=$((10#$snap_choice))
        if [ "$num" -eq 0 ]; then
            chosen_snap="skip"
        elif [ "$num" -ge 1 ] && [ "$num" -le ${#SNAPSHOT_DIRS[@]} ]; then
            chosen_snap="${SNAPSHOT_DIRS[$((num-1))]}"
        fi
    fi

    # Interactive Menu 2: Services Cleanup Checklist
    while true; do
        echo ""
        echo -e "${CYAN}${BOLD}================================================================================${NC}"
        echo -e "${BLUE}${BOLD}   [2/2] DỌN DẸP DỊCH VỤ VÀ FILE CẤU HÌNH HỆ THỐNG${NC}"
        echo -e "${CYAN}${BOLD}================================================================================${NC}"
        echo -e " Nhập số [1-5] để BẬT / TẮT [X] từng mục. Nhập 'c' hoặc Enter để xác nhận, 'q' để hủy."
        echo ""
        printf "  [1] [%s] Tắt sddm.service\n" "$([ "$do_sddm" = "true" ] && echo "X" || echo " ")"
        printf "  [2] [%s] Tắt bluetooth.service\n" "$([ "$do_bluetooth" = "true" ] && echo "X" || echo " ")"
        printf "  [3] [%s] Tắt supergfxd.service\n" "$([ "$do_supergfxd" = "true" ] && echo "X" || echo " ")"
        printf "  [4] [%s] Xóa /etc/modprobe.d/nvidia.conf\n" "$([ "$do_nvidia" = "true" ] && echo "X" || echo " ")"
        printf "  [5] [%s] Xóa /etc/sddm.conf.d/10-theme.conf\n" "$([ "$do_sddm_theme" = "true" ] && echo "X" || echo " ")"
        echo ""

        local clean_input=""
        if ! read -rp "👉 Lựa chọn của bạn (Enter/'c' để tiến hành, 'q' để hủy): " clean_input; then
            clean_input="EOF"
        fi

        if [ "$clean_input" = "EOF" ]; then
            if [ "$DRY_RUN" = "true" ] || [ "$AUTO_ACCEPT" = "true" ]; then
                break
            else
                echo -e "\n${YELLOW}Đã hủy bỏ.${NC}"
                exit 0
            fi
        fi

        clean_input="${clean_input#"${clean_input%%[![:space:]]*}"}"
        clean_input="${clean_input%"${clean_input##*[![:space:]]}"}"
        clean_input="${clean_input,,}"

        if [[ "$clean_input" =~ ^(q|quit|cancel)$ ]]; then
            echo -e "${RED}Đã hủy thao tác gỡ cài đặt.${NC}"
            exit 0
        fi

        if [[ "$clean_input" =~ ^(c|confirm|ok|y|yes)$ ]] || [ -z "$clean_input" ]; then
            break
        fi

        clean_input="${clean_input//,/ }"
        for tok in $clean_input; do
            case "$tok" in
                1) [ "$do_sddm" = "true" ] && do_sddm=false || do_sddm=true ;;
                2) [ "$do_bluetooth" = "true" ] && do_bluetooth=false || do_bluetooth=true ;;
                3) [ "$do_supergfxd" = "true" ] && do_supergfxd=false || do_supergfxd=true ;;
                4) [ "$do_nvidia" = "true" ] && do_nvidia=false || do_nvidia=true ;;
                5) [ "$do_sddm_theme" = "true" ] && do_sddm_theme=false || do_sddm_theme=true ;;
            esac
        done
    done

    perform_cleanup "$chosen_snap" "$do_sddm" "$do_bluetooth" "$do_supergfxd" "$do_nvidia" "$do_sddm_theme"
}

# ------------------------------------------------------------------------------
# 5. Curses Dialog Workflow (Whiptail / Dialog)
# ------------------------------------------------------------------------------
run_curses_dialog() {
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

    # 1. Radiolist for Snapshot Selection
    local radio_args=()
    if [ ${#SNAPSHOT_DIRS[@]} -eq 0 ]; then
        radio_args+=("skip" "Không tìm thấy bản sao lưu nào (Bỏ qua hoàn nguyên)" "ON")
    else
        local is_first=true
        for snap in "${SNAPSHOT_DIRS[@]}"; do
            local base
            base="$(basename "$snap")"
            if [ "$is_first" = "true" ]; then
                radio_args+=("$snap" "$base (Mới nhất)" "ON")
                is_first=false
            else
                radio_args+=("$snap" "$base" "OFF")
            fi
        done
        radio_args+=("skip" "Bỏ qua hoàn nguyên cấu hình ~/.config" "OFF")
    fi

    local chosen_snap=""
    local ret=0
    if command -v whiptail &>/dev/null; then
        chosen_snap=$(whiptail --title "yusei-hypr: Chọn bản sao lưu hoàn nguyên (1/2)" \
            --radiolist "Dùng Phím Mũi Tên để di chuyển, Phím Cách (Space) để chọn, Enter để tiếp tục:" \
            "$box_h" "$box_w" "$list_h" \
            --ok-button "Tiếp tục" \
            --cancel-button "Hủy bỏ" \
            "${radio_args[@]}" \
            3>&1 1>&2 2>&3) || ret=$?
    elif command -v dialog &>/dev/null; then
        chosen_snap=$(dialog --stdout --title "yusei-hypr: Chọn bản sao lưu hoàn nguyên (1/2)" \
            --radiolist "Dùng Phím Mũi Tên để di chuyển, Phím Cách (Space) để chọn, Enter để tiếp tục:" \
            "$box_h" "$box_w" "$list_h" \
            --ok-label "Tiếp tục" \
            --cancel-label "Hủy bỏ" \
            "${radio_args[@]}") || ret=$?
    fi

    if [ "$ret" -ne 0 ]; then
        echo -e "${RED}Đã hủy thao tác gỡ cài đặt.${NC}"
        exit 0
    fi
    chosen_snap="${chosen_snap//\"/}"

    # 2. Checklist for Services Cleanup
    local check_args=(
        "sddm" "Tắt dịch vụ sddm.service (Display Manager)" "ON"
        "bluetooth" "Tắt dịch vụ bluetooth.service" "ON"
        "supergfxd" "Tắt dịch vụ supergfxd.service (ASUS ROG Graphics)" "OFF"
        "nvidia" "Xóa cấu hình /etc/modprobe.d/nvidia.conf" "ON"
        "sddm_theme" "Xóa cấu hình /etc/sddm.conf.d/10-theme.conf" "ON"
    )

    local service_choices=""
    local ret_svc=0
    if command -v whiptail &>/dev/null; then
        service_choices=$(whiptail --title "yusei-hypr: Dọn dẹp dịch vụ và cấu hình hệ thống (2/2)" \
            --checklist "Dùng Phím Cách (Space) để chọn/bỏ chọn, Mũi Tên để di chuyển, Tab để chọn nút:" \
            "$box_h" "$box_w" "$list_h" \
            --ok-button "Thực hiện" \
            --cancel-button "Hủy bỏ" \
            "${check_args[@]}" \
            3>&1 1>&2 2>&3) || ret_svc=$?
    elif command -v dialog &>/dev/null; then
        service_choices=$(dialog --stdout --title "yusei-hypr: Dọn dẹp dịch vụ và cấu hình hệ thống (2/2)" \
            --checklist "Dùng Phím Cách (Space) để chọn/bỏ chọn, Mũi Tên để di chuyển, Tab để chọn nút:" \
            "$box_h" "$box_w" "$list_h" \
            --ok-label "Thực hiện" \
            --cancel-label "Hủy bỏ" \
            "${check_args[@]}") || ret_svc=$?
    fi

    if [ "$ret_svc" -ne 0 ]; then
        echo -e "${RED}Đã hủy thao tác gỡ cài đặt.${NC}"
        exit 0
    fi

    service_choices="${service_choices//\"/}"
    local do_sddm=false
    local do_bluetooth=false
    local do_supergfxd=false
    local do_nvidia=false
    local do_sddm_theme=false

    for choice in $service_choices; do
        case "$choice" in
            sddm) do_sddm=true ;;
            bluetooth) do_bluetooth=true ;;
            supergfxd) do_supergfxd=true ;;
            nvidia) do_nvidia=true ;;
            sddm_theme) do_sddm_theme=true ;;
        esac
    done

    perform_cleanup "$chosen_snap" "$do_sddm" "$do_bluetooth" "$do_supergfxd" "$do_nvidia" "$do_sddm_theme"
}

# ------------------------------------------------------------------------------
# 6. Main Flow
# ------------------------------------------------------------------------------
if [ "$AUTO_ACCEPT" = "true" ]; then
    DEFAULT_SNAP="skip"
    if [ ${#SNAPSHOT_DIRS[@]} -gt 0 ]; then
        DEFAULT_SNAP="${SNAPSHOT_DIRS[0]}"
    fi
    perform_cleanup "$DEFAULT_SNAP" true true false true true
    exit 0
fi

if is_terminal_capable; then
    run_curses_dialog
else
    run_cli_fallback_menu
fi
