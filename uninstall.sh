#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Curses Dialog & CLI Uninstaller and System Restoration Module
# ==============================================================================
# Features:
#   - Reads install-state.env & nvidia-state.env to safely revert only installer changes
#   - Restores PRE_INSTALL_BACKUP or oldest yusei-hypr-backup-* snapshot
#   - Reverts recorded NVIDIA mkinitcpio/GRUB/systemd-boot/modprobe changes cleanly
#   - Removes yusei-hypr binaries (verified via cmp -s / symlink), libs, share dir,
#     desktop entry, and injected ~/.bashrc / ~/.zshrc blocks (keeping .bak)
#   - Whiptail / Dialog TUI & Pure-Bash CLI fallback (--cli / --fallback)
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
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$STATE_HOME/yusei-hypr"
INSTALL_STATE_FILE="$STATE_DIR/install-state.env"
NVIDIA_STATE_FILE="$STATE_DIR/nvidia-state.env"
SHARE_DIR="$DATA_HOME/yusei-hypr"
LOCAL_BIN_DIR="$HOME/.local/bin"
LOCAL_LIB_DIR="$HOME/.local/lib"
APPS_DIR="$DATA_HOME/applications"

MKINITCPIO_CONF="${MKINITCPIO_CONF:-/etc/mkinitcpio.conf}"
GRUB_DEFAULT_FILE="${GRUB_DEFAULT_FILE:-/etc/default/grub}"
MODPROBE_NVIDIA_CONF="${MODPROBE_NVIDIA_CONF:-/etc/modprobe.d/nvidia.conf}"
SDDM_THEME_CONF="${SDDM_THEME_CONF:-/etc/sddm.conf.d/10-theme.conf}"

needs_sudo_for_path() {
    local p="$1"
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        return 1
    fi
    if [ -e "$p" ]; then
        [ ! -w "$p" ]
        return $?
    fi
    local parent
    parent="$(dirname "$p")"
    while [ "$parent" != "/" ] && [ ! -e "$parent" ]; do
        parent="$(dirname "$parent")"
    done
    [ ! -w "$parent" ]
}

run_for_path() {
    local p="$1"
    shift
    if needs_sudo_for_path "$p"; then
        sudo "$@"
    else
        "$@"
    fi
}

write_file_content() {
    local target="$1"
    local src="$2"
    local parent
    parent="$(dirname "$target")"
    if [ ! -d "$parent" ]; then
        run_for_path "$parent" mkdir -p "$parent"
    fi
    if needs_sudo_for_path "$target"; then
        sudo tee "$target" >/dev/null < "$src"
    else
        cat "$src" > "$target"
    fi
}

# ------------------------------------------------------------------------------
# 0. Load Recorded Installation & NVIDIA State Files (if present)
# ------------------------------------------------------------------------------
PRE_SDDM_ENABLED=""
PRE_BLUETOOTH_ENABLED=""
PRE_SUPERGFXD_ENABLED=""
PRE_DISPLAY_MANAGER=""
PRE_INSTALL_BACKUP=""
INSTALLER_ENABLED_SDDM=""
INSTALLER_ENABLED_BLUETOOTH=""
INSTALLER_ENABLED_SUPERGFXD=""

if [[ -f "$INSTALL_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$INSTALL_STATE_FILE"
fi

ADDED_MKINITCPIO_MODULES=""
GRUB_MODESET_ADDED="false"
LOADER_ENTRIES_MODIFIED=""
MODPROBE_CREATED="false"

if [[ -f "$NVIDIA_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$NVIDIA_STATE_FILE"
fi

DEFAULT_DO_SDDM="false"
[[ "${INSTALLER_ENABLED_SDDM:-false}" == "true" ]] && DEFAULT_DO_SDDM="true"

DEFAULT_DO_BLUETOOTH="false"
[[ "${INSTALLER_ENABLED_BLUETOOTH:-false}" == "true" ]] && DEFAULT_DO_BLUETOOTH="true"

DEFAULT_DO_SUPERGFXD="false"
[[ "${INSTALLER_ENABLED_SUPERGFXD:-false}" == "true" ]] && DEFAULT_DO_SUPERGFXD="true"

DEFAULT_DO_NVIDIA_MODPROBE="false"
[[ "${MODPROBE_CREATED:-false}" == "true" ]] && DEFAULT_DO_NVIDIA_MODPROBE="true"

HAS_RECORDED_NVIDIA_BOOT="false"
if [[ -n "${ADDED_MKINITCPIO_MODULES:-}" || "${GRUB_MODESET_ADDED:-false}" == "true" || -n "${LOADER_ENTRIES_MODIFIED:-}" ]]; then
    HAS_RECORDED_NVIDIA_BOOT="true"
fi
DEFAULT_DO_NVIDIA_BOOT="$HAS_RECORDED_NVIDIA_BOOT"

DEFAULT_DO_SDDM_THEME="false"
if [[ "${INSTALLER_ENABLED_SDDM:-false}" == "true" ]] || { [[ -f "$SDDM_THEME_CONF" ]] && grep -q "simple-sddm-2" "$SDDM_THEME_CONF" 2>/dev/null; }; then
    DEFAULT_DO_SDDM_THEME="true"
fi

# ------------------------------------------------------------------------------
# 1. Snapshot Discovery (PRE_INSTALL_BACKUP first, else oldest yusei-hypr-backup-*)
# ------------------------------------------------------------------------------
SNAPSHOT_DIRS=()

append_unique_snapshot() {
    local cand="$1"
    [[ -n "$cand" && -d "$cand" ]] || return 0
    local cand_real
    cand_real="$(readlink -f "$cand" 2>/dev/null || echo "$cand")"
    local existing
    for existing in "${SNAPSHOT_DIRS[@]:-}"; do
        local ex_real
        ex_real="$(readlink -f "$existing" 2>/dev/null || echo "$existing")"
        if [[ "$ex_real" == "$cand_real" ]]; then
            return 0
        fi
    done
    SNAPSHOT_DIRS+=("$cand")
}

if [[ -n "${PRE_INSTALL_BACKUP:-}" && -d "${PRE_INSTALL_BACKUP}" ]]; then
    append_unique_snapshot "$PRE_INSTALL_BACKUP"
fi

if [[ -d "$CONFIG_HOME" ]]; then
    while IFS= read -r snap_dir; do
        if [[ -n "$snap_dir" && -d "$snap_dir" && "$snap_dir" != *"yusei-hypr-backup-latest" ]]; then
            append_unique_snapshot "$snap_dir"
        fi
    done < <(find "$CONFIG_HOME" -maxdepth 1 -type d -name "yusei-hypr-backup-*" 2>/dev/null | LC_ALL=C sort)

    if [[ -d "$CONFIG_HOME/yusei-hypr-backups" ]]; then
        while IFS= read -r leg_dir; do
            if [[ -n "$leg_dir" && -d "$leg_dir" && "$leg_dir" != *"latest" ]]; then
                append_unique_snapshot "$leg_dir"
            fi
        done < <(find "$CONFIG_HOME/yusei-hypr-backups" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | LC_ALL=C sort)
    fi
fi

DEFAULT_SNAP="skip"
if [[ ${#SNAPSHOT_DIRS[@]} -gt 0 ]]; then
    DEFAULT_SNAP="${SNAPSHOT_DIRS[0]}"
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
# 3. NVIDIA Boot & Shell Hook Cleanup Helpers
# ------------------------------------------------------------------------------
cleanup_nvidia_boot_changes() {
    local mkinit_rebuilt=false
    local grub_modified=false

    # 3a. Gỡ ADDED_MKINITCPIO_MODULES khỏi mkinitcpio.conf
    if [[ -n "${ADDED_MKINITCPIO_MODULES:-}" && -f "$MKINITCPIO_CONF" ]]; then
        local tmp_mkinit
        tmp_mkinit="$(mktemp)"
        local mkinit_changed
        mkinit_changed="$(python3 - "$MKINITCPIO_CONF" "$tmp_mkinit" "$ADDED_MKINITCPIO_MODULES" << 'PYEOF'
import re
import sys

src_path, out_path, rem_raw = sys.argv[1], sys.argv[2], sys.argv[3]
to_remove = set(rem_raw.split())
if not to_remove:
    print("false")
    sys.exit(0)

with open(src_path, "r", encoding="utf-8") as f:
    text = f.read()

lines = text.splitlines(keepends=True)

def split_code_comment(s, in_sq=False, in_dq=False):
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and not in_sq and i + 1 < len(s):
            i += 2
            continue
        if c == "'" and not in_dq:
            in_sq = not in_sq
        elif c == '"' and not in_sq:
            in_dq = not in_dq
        elif c == "#" and not in_sq and not in_dq:
            return s[:i], s[i:], in_sq, in_dq
        i += 1
    return s, "", in_sq, in_dq

def filter_tokens(code_str):
    removed = False
    kept = []
    for raw in code_str.split():
        clean = raw.strip().strip('"').strip("'")
        if clean in to_remove:
            removed = True
        else:
            kept.append(raw)
    return kept, removed

found_mode = None
start_idx = -1
end_idx = -1
close_pos = -1

for idx, line in enumerate(lines):
    m_arr = re.match(r'^([ \t]*MODULES=\()(.*)$', line, re.DOTALL)
    if m_arr:
        found_mode = "array"
        start_idx = idx
        in_sq = False
        in_dq = False
        j = idx
        pos = len(m_arr.group(1))
        while j < len(lines):
            cur = lines[j]
            k = pos
            while k < len(cur):
                ch = cur[k]
                if ch == "\\" and not in_sq and k + 1 < len(cur):
                    k += 2
                    continue
                if ch == "'" and not in_dq:
                    in_sq = not in_sq
                elif ch == '"' and not in_sq:
                    in_dq = not in_dq
                elif ch == "#" and not in_sq and not in_dq:
                    break
                elif ch == ")" and not in_sq and not in_dq:
                    end_idx = j
                    close_pos = k
                    break
                k += 1
            if end_idx != -1:
                break
            j += 1
            pos = 0
        if end_idx != -1:
            break
        found_mode = None
        start_idx = -1

if found_mode is None:
    for idx, line in enumerate(lines):
        m_str = re.match(r'^([ \t]*MODULES=)(["\'])(.*)$', line, re.DOTALL)
        if m_str:
            q = m_str.group(2)
            rest = m_str.group(3)
            k = 0
            closed = -1
            while k < len(rest):
                if rest[k] == "\\" and q == '"' and k + 1 < len(rest):
                    k += 2
                    continue
                if rest[k] == q:
                    closed = k
                    break
                k += 1
            if closed != -1:
                found_mode = "string"
                start_idx = idx
                end_idx = idx
                close_pos = len(m_str.group(1)) + 1 + closed
                break

changed = False
if found_mode == "array":
    if start_idx == end_idx:
        line = lines[start_idx]
        prefix = re.match(r'^[ \t]*MODULES=\(', line).group(0)
        inner = line[len(prefix):close_pos]
        suffix = line[close_pos:]
        kept, rem = filter_tokens(inner)
        if rem:
            changed = True
            lines[start_idx] = prefix + " ".join(kept) + suffix
    else:
        in_sq = False
        in_dq = False
        new_block = []
        for j in range(start_idx, end_idx + 1):
            cur = lines[j]
            nl = "\r\n" if cur.endswith("\r\n") else ("\n" if cur.endswith("\n") else "")
            body = cur[:-len(nl)] if nl else cur
            if j == start_idx:
                prefix = re.match(r'^[ \t]*MODULES=\(', body).group(0)
                seg = body[len(prefix):]
                code, comment, in_sq, in_dq = split_code_comment(seg, in_sq, in_dq)
                kept, rem = filter_tokens(code)
                if rem:
                    changed = True
                    rebuilt = prefix + " ".join(kept)
                    if comment:
                        rebuilt += (" " if kept else "") + comment
                    new_block.append(rebuilt + nl)
                else:
                    new_block.append(cur)
            elif j == end_idx:
                before_close = body[:close_pos]
                after_close = body[close_pos:]
                code, comment, in_sq, in_dq = split_code_comment(before_close, in_sq, in_dq)
                kept, rem = filter_tokens(code)
                if rem:
                    changed = True
                    indent_m = re.match(r'^([ \t]*)', before_close)
                    indent = indent_m.group(1) if indent_m else ""
                    new_before = (indent + " ".join(kept)) if kept else indent
                    if comment:
                        new_before += (" " if kept else "") + comment
                    new_block.append(new_before + after_close + nl)
                else:
                    new_block.append(cur)
            else:
                indent_m = re.match(r'^([ \t]*)', body)
                indent = indent_m.group(1) if indent_m else ""
                code, comment, in_sq, in_dq = split_code_comment(body, in_sq, in_dq)
                kept, rem = filter_tokens(code)
                if rem:
                    changed = True
                    if not kept and not comment:
                        continue
                    rebuilt = (indent + " ".join(kept)) if kept else indent
                    if comment:
                        rebuilt += (" " if kept else "") + comment
                    new_block.append(rebuilt + nl)
                else:
                    new_block.append(cur)
        if changed:
            lines[start_idx:end_idx + 1] = new_block
elif found_mode == "string":
    line = lines[start_idx]
    m_str = re.match(r'^([ \t]*MODULES=)(["\'])', line)
    prefix = m_str.group(1)
    q = m_str.group(2)
    inner = line[len(prefix) + 1:close_pos]
    suffix = line[close_pos:]
    kept, rem = filter_tokens(inner)
    if rem:
        changed = True
        lines[start_idx] = prefix + q + " ".join(kept) + suffix

with open(out_path, "w", encoding="utf-8") as f:
    f.write("".join(lines))

print("true" if changed else "false")
PYEOF
)"

        if [[ "$mkinit_changed" == "true" ]]; then
            if [ "$DRY_RUN" = "true" ]; then
                echo -e "${YELLOW}[DRY-RUN] Sẽ gỡ các module NVIDIA khỏi ${MKINITCPIO_CONF}: ${ADDED_MKINITCPIO_MODULES}${NC}"
                if [ "$MKINITCPIO_CONF" = "/etc/mkinitcpio.conf" ]; then
                    echo -e "${YELLOW}[DRY-RUN] Sẽ chạy: sudo mkinitcpio -P${NC}"
                fi
            else
                echo -e "${YELLOW}Gỡ các module đã ghi nhận (${ADDED_MKINITCPIO_MODULES}) khỏi ${MKINITCPIO_CONF}...${NC}"
                run_for_path "$MKINITCPIO_CONF" cp -a "$MKINITCPIO_CONF" "${MKINITCPIO_CONF}.bak_uninstall_$(date +%Y%m%d_%H%M%S)"
                write_file_content "$MKINITCPIO_CONF" "$tmp_mkinit"
                echo -e "${GREEN}✓ Đã gỡ module NVIDIA đã ghi nhận khỏi ${MKINITCPIO_CONF}${NC}"
                mkinit_rebuilt=true
            fi
        fi
        rm -f "$tmp_mkinit"
    fi

    if [ "$mkinit_rebuilt" = "true" ] && [ "$DRY_RUN" = "false" ]; then
        if [ "$MKINITCPIO_CONF" = "/etc/mkinitcpio.conf" ] && command -v mkinitcpio &>/dev/null; then
            echo -e "${BLUE}:: Đang biên dịch lại initramfs qua 'sudo mkinitcpio -P'...${NC}"
            if sudo mkinitcpio -P; then
                echo -e "${GREEN}✓ Đã tạo lại initramfs thành công!${NC}"
            else
                echo -e "${YELLOW}⚠️ Không thể chạy mkinitcpio -P tự động. Hãy chạy thủ công: sudo mkinitcpio -P${NC}"
            fi
        else
            echo -e "${YELLOW}ℹ️ Gợi ý: hãy chạy 'sudo mkinitcpio -P' nếu cần cập nhật initramfs.${NC}"
        fi
    fi

    # 3b. Gỡ nvidia_drm.modeset=1 khỏi GRUB nếu đã ghi nhận
    if [[ "${GRUB_MODESET_ADDED:-false}" == "true" && -f "$GRUB_DEFAULT_FILE" ]]; then
        local tmp_grub
        tmp_grub="$(mktemp)"
        local grub_changed
        grub_changed="$(python3 - "$GRUB_DEFAULT_FILE" "$tmp_grub" << 'PYEOF'
import re
import sys

src_path, out_path = sys.argv[1], sys.argv[2]
with open(src_path, "r", encoding="utf-8") as f:
    lines = f.read().splitlines(keepends=True)

changed = False
for idx, line in enumerate(lines):
    m = re.match(r'^([ \t]*GRUB_CMDLINE_LINUX_DEFAULT=)(["\'])(.*)$', line, re.DOTALL)
    if not m:
        continue
    prefix = m.group(1)
    q = m.group(2)
    rest = m.group(3)
    k = 0
    close_idx = -1
    while k < len(rest):
        if rest[k] == "\\" and q == '"' and k + 1 < len(rest):
            k += 2
            continue
        if rest[k] == q:
            close_idx = k
            break
        k += 1
    if close_idx == -1:
        continue
    inner = rest[:close_idx]
    suffix = rest[close_idx:]
    tokens = inner.split()
    kept = [t for t in tokens if t != "nvidia_drm.modeset=1"]
    if len(kept) != len(tokens):
        lines[idx] = prefix + q + " ".join(kept) + suffix
        changed = True
    break

with open(out_path, "w", encoding="utf-8") as f:
    f.write("".join(lines))

print("true" if changed else "false")
PYEOF
)"

        if [[ "$grub_changed" == "true" ]]; then
            if [ "$DRY_RUN" = "true" ]; then
                echo -e "${YELLOW}[DRY-RUN] Sẽ gỡ 'nvidia_drm.modeset=1' khỏi ${GRUB_DEFAULT_FILE}${NC}"
                echo -e "${YELLOW}[DRY-RUN] Gợi ý sau khi gỡ: sudo grub-mkconfig -o /boot/grub/grub.cfg${NC}"
            else
                echo -e "${YELLOW}Gỡ 'nvidia_drm.modeset=1' khỏi ${GRUB_DEFAULT_FILE}...${NC}"
                run_for_path "$GRUB_DEFAULT_FILE" cp -a "$GRUB_DEFAULT_FILE" "${GRUB_DEFAULT_FILE}.bak_uninstall_$(date +%Y%m%d_%H%M%S)"
                write_file_content "$GRUB_DEFAULT_FILE" "$tmp_grub"
                echo -e "${GREEN}✓ Đã gỡ 'nvidia_drm.modeset=1' khỏi ${GRUB_DEFAULT_FILE}${NC}"
                grub_modified=true
            fi
        fi
        rm -f "$tmp_grub"
    fi

    if [ "$grub_modified" = "true" ] && [ "$DRY_RUN" = "false" ]; then
        echo -e "${YELLOW}ℹ️ Gợi ý: hãy chạy 'sudo grub-mkconfig -o /boot/grub/grub.cfg' để cập nhật cấu hình GRUB.${NC}"
    fi

    # 3c. Gỡ nvidia_drm.modeset=1 khỏi các systemd-boot loader entries đã ghi nhận
    if [[ -n "${LOADER_ENTRIES_MODIFIED:-}" ]]; then
        for entry in $LOADER_ENTRIES_MODIFIED; do
            [[ -f "$entry" ]] || continue
            local tmp_entry
            tmp_entry="$(mktemp)"
            local entry_changed
            entry_changed="$(python3 - "$entry" "$tmp_entry" << 'PYEOF'
import re
import sys

src_path, out_path = sys.argv[1], sys.argv[2]
with open(src_path, "r", encoding="utf-8") as f:
    lines = f.read().splitlines(keepends=True)

def split_inline_comment(line_no_nl):
    in_sq = False
    in_dq = False
    i = 0
    while i < len(line_no_nl):
        c = line_no_nl[i]
        if c == "\\" and not in_sq and i + 1 < len(line_no_nl):
            i += 2
            continue
        if c == "'" and not in_dq:
            in_sq = not in_sq
        elif c == '"' and not in_sq:
            in_dq = not in_dq
        elif c == "#" and not in_sq and not in_dq:
            return line_no_nl[:i], line_no_nl[i:]
        i += 1
    return line_no_nl, ""

changed = False
for idx, line in enumerate(lines):
    nl = "\r\n" if line.endswith("\r\n") else ("\n" if line.endswith("\n") else "")
    body = line[:-len(nl)] if nl else line
    if re.match(r'^[ \t]*#', body):
        continue
    m_opt = re.match(r'^([ \t]*options)([ \t]+.*)?$', body)
    if not m_opt:
        continue
    code_part, comment_part = split_inline_comment(body)
    m_head = re.match(r'^([ \t]*options[ \t]*)(.*)$', code_part)
    head = m_head.group(1)
    rest_code = m_head.group(2)
    ws_before_comment = ""
    if comment_part:
        stripped_rest = rest_code.rstrip(" \t")
        ws_before_comment = rest_code[len(stripped_rest):]
        tokens = stripped_rest.split()
    else:
        tokens = rest_code.split()
    kept = [t for t in tokens if t != "nvidia_drm.modeset=1"]
    if len(kept) != len(tokens):
        changed = True
        new_code = head.rstrip(" \t")
        if kept:
            sep = head[len(head.rstrip(" \t")):] or " "
            new_code = head.rstrip(" \t") + sep + " ".join(kept)
        if comment_part:
            ws = ws_before_comment if ws_before_comment else " "
            lines[idx] = new_code + ws + comment_part + nl
        else:
            lines[idx] = new_code + nl

with open(out_path, "w", encoding="utf-8") as f:
    f.write("".join(lines))

print("true" if changed else "false")
PYEOF
)"
            if [[ "$entry_changed" == "true" ]]; then
                if [ "$DRY_RUN" = "true" ]; then
                    echo -e "${YELLOW}[DRY-RUN] Sẽ gỡ 'nvidia_drm.modeset=1' khỏi ${entry}${NC}"
                else
                    echo -e "${YELLOW}Gỡ 'nvidia_drm.modeset=1' khỏi ${entry}...${NC}"
                    run_for_path "$entry" cp -a "$entry" "${entry}.bak_uninstall_$(date +%Y%m%d_%H%M%S)"
                    write_file_content "$entry" "$tmp_entry"
                    echo -e "${GREEN}✓ Đã gỡ 'nvidia_drm.modeset=1' khỏi ${entry}${NC}"
                fi
            fi
            rm -f "$tmp_entry"
        done
    fi
}

cleanup_shell_hooks() {
    local rc
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        [[ -f "$rc" ]] || continue
        local tmp_rc
        tmp_rc="$(mktemp)"
        local rc_changed
        rc_changed="$(python3 - "$rc" "$tmp_rc" << 'PYEOF'
import sys

src_path, out_path = sys.argv[1], sys.argv[2]
with open(src_path, "r", encoding="utf-8") as f:
    lines = f.read().splitlines(keepends=True)

def is_yusei_marker(s):
    return s in (
        "# Pokemon Fastfetch Banner (yusei-hypr)",
        "# Chặn yay/paru tự động thay thế swww bằng awww khi cập nhật",
    )

def is_yusei_hook_line(s):
    if is_yusei_marker(s):
        return True
    if "pokemon-colorscripts" in s and "config-pokemon.jsonc" in s:
        return True
    if s in (
        "alias yay='yay --ignore swww,awww'",
        "alias paru='paru --ignore swww,awww'",
    ):
        return True
    return False

remove_indices = set()
for idx, line in enumerate(lines):
    s = line.strip()
    if is_yusei_hook_line(s):
        remove_indices.add(idx)
        if is_yusei_marker(s) and idx > 0 and lines[idx - 1].strip() == "":
            remove_indices.add(idx - 1)

if not remove_indices:
    print("false")
    sys.exit(0)

new_lines = [line for idx, line in enumerate(lines) if idx not in remove_indices]
with open(out_path, "w", encoding="utf-8") as f:
    f.write("".join(new_lines))
print("true")
PYEOF
)"
        if [[ "$rc_changed" == "true" ]]; then
            if [ "$DRY_RUN" = "true" ]; then
                echo -e "${YELLOW}[DRY-RUN] Sẽ gỡ block hook yusei-hypr khỏi ${rc} (sao lưu thành ${rc}.bak)${NC}"
            else
                cp -a "$rc" "${rc}.bak"
                cat "$tmp_rc" > "$rc"
                echo -e "${GREEN}✓ Đã gỡ block hook yusei-hypr khỏi ${rc} (bản sao lưu: ${rc}.bak)${NC}"
            fi
        fi
        rm -f "$tmp_rc"
    done
}

cleanup_user_artifacts() {
    local bin_names=(
        "swww"
        "swww-daemon"
        "waybar"
        "notify-send"
        "theme-engine.sh"
        "power-optimizer"
        "yusei-settings"
    )

    local name
    for name in "${bin_names[@]}"; do
        local target_bin="$LOCAL_BIN_DIR/$name"
        local ref_bin="$SHARE_DIR/bin/$name"
        local should_remove=false

        if [[ -L "$target_bin" ]]; then
            local raw_link resolved_link
            raw_link="$(readlink "$target_bin" 2>/dev/null || true)"
            resolved_link="$(readlink -f "$target_bin" 2>/dev/null || true)"
            if [[ "$raw_link" == "$SHARE_DIR/"* || "$resolved_link" == "$SHARE_DIR/"* || "$raw_link" == *"/yusei-hypr/bin/"* ]]; then
                should_remove=true
            fi
        elif [[ -f "$target_bin" && -f "$ref_bin" ]]; then
            if cmp -s "$target_bin" "$ref_bin"; then
                should_remove=true
            fi
        fi

        if [ "$should_remove" = "true" ]; then
            if [ "$DRY_RUN" = "true" ]; then
                echo -e "${YELLOW}[DRY-RUN] Sẽ xóa binary của yusei-hypr: ${target_bin}${NC}"
            else
                rm -f "$target_bin"
                echo -e "${GREEN}✓ Đã xóa binary của yusei-hypr: ${target_bin}${NC}"
            fi
        fi
    done

    if [[ -d "$LOCAL_LIB_DIR" ]]; then
        shopt -s nullglob
        local lib_file
        for lib_file in "$LOCAL_LIB_DIR"/libwaybar-hyprland*; do
            if [[ -e "$lib_file" || -L "$lib_file" ]]; then
                if [ "$DRY_RUN" = "true" ]; then
                    echo -e "${YELLOW}[DRY-RUN] Sẽ xóa thư viện: ${lib_file}${NC}"
                else
                    rm -f "$lib_file"
                    echo -e "${GREEN}✓ Đã xóa thư viện: ${lib_file}${NC}"
                fi
            fi
        done
        shopt -u nullglob
    fi

    local desktop_file="$APPS_DIR/yusei-settings.desktop"
    if [[ -e "$desktop_file" || -L "$desktop_file" ]]; then
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "${YELLOW}[DRY-RUN] Sẽ xóa desktop entry: ${desktop_file}${NC}"
        else
            rm -f "$desktop_file"
            update-desktop-database "$APPS_DIR" 2>/dev/null || true
            echo -e "${GREEN}✓ Đã xóa desktop entry: ${desktop_file}${NC}"
        fi
    fi

    cleanup_shell_hooks

    if [[ -d "$SHARE_DIR" || -L "$SHARE_DIR" ]]; then
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "${YELLOW}[DRY-RUN] Sẽ xóa thư mục dữ liệu: ${SHARE_DIR}${NC}"
        else
            rm -rf "$SHARE_DIR"
            echo -e "${GREEN}✓ Đã xóa thư mục dữ liệu: ${SHARE_DIR}${NC}"
        fi
    fi
}

# ------------------------------------------------------------------------------
# 4. Execution of Restoration and Cleanup
# ------------------------------------------------------------------------------
perform_cleanup() {
    local target_snap="$1"
    local do_sddm="$2"
    local do_bluetooth="$3"
    local do_supergfxd="$4"
    local do_nvidia_modprobe="$5"
    local do_sddm_theme="$6"
    local do_nvidia_boot="${7:-$DEFAULT_DO_NVIDIA_BOOT}"

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
        echo -e "\n${BLUE}:: [1/3] Hoàn nguyên cấu hình từ bản sao lưu: $target_snap${NC}"
        local rollback_script=""
        if [[ -f "$DIR/scripts/rollback.sh" ]]; then
            rollback_script="$DIR/scripts/rollback.sh"
        elif [[ -f "$SHARE_DIR/scripts/rollback.sh" ]]; then
            rollback_script="$SHARE_DIR/scripts/rollback.sh"
        fi
        if [[ -n "$rollback_script" ]]; then
            if [ "$DRY_RUN" = "true" ]; then
                bash "$rollback_script" "$target_snap" --dry-run
            else
                bash "$rollback_script" "$target_snap"
            fi
        else
            echo -e "${YELLOW}⚠️ Không tìm thấy scripts/rollback.sh. Bỏ qua hoàn nguyên tự động.${NC}"
        fi
    else
        echo -e "\n${BLUE}:: [1/3] Bỏ qua hoàn nguyên cấu hình ~/.config theo tùy chọn.${NC}"
    fi

    # 2. Dọn dẹp dịch vụ và file hệ thống
    echo -e "\n${BLUE}:: [2/3] Dọn dẹp các dịch vụ và tệp cấu hình hệ thống...${NC}"

    if [ "$do_sddm" = "true" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "${YELLOW}[DRY-RUN] Sẽ thực thi: sudo systemctl disable sddm.service${NC}"
            if [[ -n "${PRE_DISPLAY_MANAGER:-}" && "${PRE_DISPLAY_MANAGER}" != "sddm" && "${PRE_DISPLAY_MANAGER}" != "sddm.service" ]]; then
                echo -e "${YELLOW}[DRY-RUN] Sẽ khôi phục Display Manager trước đó: sudo systemctl enable --force ${PRE_DISPLAY_MANAGER}${NC}"
            fi
        else
            echo -e "${YELLOW}Đang tắt sddm.service...${NC}"
            sudo systemctl disable sddm.service 2>/dev/null || true
            echo -e "${GREEN}✓ Đã vô hiệu hóa sddm.service${NC}"
            if [[ -n "${PRE_DISPLAY_MANAGER:-}" && "${PRE_DISPLAY_MANAGER}" != "sddm" && "${PRE_DISPLAY_MANAGER}" != "sddm.service" ]]; then
                echo -e "${YELLOW}Đang khôi phục Display Manager trước đó (${PRE_DISPLAY_MANAGER})...${NC}"
                sudo systemctl enable --force "$PRE_DISPLAY_MANAGER" 2>/dev/null || true
            fi
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

    if [ "$do_nvidia_boot" = "true" ]; then
        cleanup_nvidia_boot_changes
    fi

    if [ "$do_nvidia_modprobe" = "true" ]; then
        if [ -f "$MODPROBE_NVIDIA_CONF" ]; then
            if [ "$DRY_RUN" = "true" ]; then
                echo -e "${YELLOW}[DRY-RUN] Sẽ xóa tệp: ${MODPROBE_NVIDIA_CONF}${NC}"
            else
                echo -e "${YELLOW}Xóa ${MODPROBE_NVIDIA_CONF}...${NC}"
                run_for_path "$MODPROBE_NVIDIA_CONF" rm -f "$MODPROBE_NVIDIA_CONF" 2>/dev/null || true
                echo -e "${GREEN}✓ Đã dọn dẹp ${MODPROBE_NVIDIA_CONF}${NC}"
            fi
        fi
    fi

    if [ "$do_sddm_theme" = "true" ]; then
        if [ -f "$SDDM_THEME_CONF" ]; then
            if [ "$DRY_RUN" = "true" ]; then
                echo -e "${YELLOW}[DRY-RUN] Sẽ xóa tệp: ${SDDM_THEME_CONF}${NC}"
            else
                echo -e "${YELLOW}Xóa ${SDDM_THEME_CONF}...${NC}"
                run_for_path "$SDDM_THEME_CONF" rm -f "$SDDM_THEME_CONF" 2>/dev/null || true
                echo -e "${GREEN}✓ Đã dọn dẹp ${SDDM_THEME_CONF}${NC}"
            fi
        fi
    fi

    # 3. Dọn dẹp binary, lib, share dir, desktop entry và shell hooks của yusei-hypr
    echo -e "\n${BLUE}:: [3/3] Dọn dẹp tiện ích ~/.local và shell hooks của yusei-hypr...${NC}"
    cleanup_user_artifacts

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
# 5. Fallback Pure-Bash CLI Interactive Menu
# ------------------------------------------------------------------------------
run_cli_fallback_menu() {
    local chosen_snap="$DEFAULT_SNAP"
    local do_sddm="$DEFAULT_DO_SDDM"
    local do_bluetooth="$DEFAULT_DO_BLUETOOTH"
    local do_supergfxd="$DEFAULT_DO_SUPERGFXD"
    local do_nvidia_modprobe="$DEFAULT_DO_NVIDIA_MODPROBE"
    local do_sddm_theme="$DEFAULT_DO_SDDM_THEME"
    local do_nvidia_boot="$DEFAULT_DO_NVIDIA_BOOT"

    local interactive=false
    if [ -t 0 ] && [ -t 1 ]; then
        interactive=true
    fi

    if [ "$interactive" = "false" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            perform_cleanup "$chosen_snap" "$do_sddm" "$do_bluetooth" "$do_supergfxd" "$do_nvidia_modprobe" "$do_sddm_theme" "$do_nvidia_boot"
            exit 0
        elif [ "$AUTO_ACCEPT" = "true" ]; then
            perform_cleanup "$chosen_snap" "$do_sddm" "$do_bluetooth" "$do_supergfxd" "$do_nvidia_modprobe" "$do_sddm_theme" "$do_nvidia_boot"
            exit 0
        else
            echo -e "${YELLOW}Phát hiện môi trường không tương tác (non-interactive / piped stdin).${NC}"
            echo -e "${YELLOW}Để tiến hành gỡ cài đặt không tương tác, vui lòng sử dụng cờ -y hoặc --yes (hoặc --dry-run để mô phỏng).${NC}"
            echo -e "${YELLOW}Thoát an toàn mà không thực hiện thay đổi nào.${NC}"
            exit 0
        fi
    fi

    if [ "$AUTO_ACCEPT" = "true" ]; then
        perform_cleanup "$chosen_snap" "$do_sddm" "$do_bluetooth" "$do_supergfxd" "$do_nvidia_modprobe" "$do_sddm_theme" "$do_nvidia_boot"
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
        local label
        label="$(basename "$snap")"
        if [[ -n "${PRE_INSTALL_BACKUP:-}" && "$snap" == "$PRE_INSTALL_BACKUP" ]]; then
            label="$label (Bản gốc trước cài đặt)"
        elif [[ "$s_idx" -eq 1 ]]; then
            label="$label (Cũ nhất)"
        fi
        echo -e " [$s_idx] $label"
        ((s_idx++))
    done
    echo ""

    local snap_choice=""
    if ! read -rp "👉 Chọn bản sao lưu muốn khôi phục [mặc định: 1 nếu có, hoặc 0 để bỏ qua]: " snap_choice; then
        snap_choice="EOF"
    fi

    if [ "$snap_choice" = "EOF" ]; then
        if [ "$DRY_RUN" = "true" ] || [ "$AUTO_ACCEPT" = "true" ]; then
            perform_cleanup "$chosen_snap" "$do_sddm" "$do_bluetooth" "$do_supergfxd" "$do_nvidia_modprobe" "$do_sddm_theme" "$do_nvidia_boot"
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
        echo -e " Nhập số [1-6] để BẬT / TẮT [X] từng mục. Nhập 'c' hoặc Enter để xác nhận, 'q' để hủy."
        echo ""
        printf "  [1] [%s] Tắt sddm.service\n" "$([ "$do_sddm" = "true" ] && echo "X" || echo " ")"
        printf "  [2] [%s] Tắt bluetooth.service\n" "$([ "$do_bluetooth" = "true" ] && echo "X" || echo " ")"
        printf "  [3] [%s] Tắt supergfxd.service\n" "$([ "$do_supergfxd" = "true" ] && echo "X" || echo " ")"
        printf "  [4] [%s] Xóa %s\n" "$([ "$do_nvidia_modprobe" = "true" ] && echo "X" || echo " ")" "$MODPROBE_NVIDIA_CONF"
        printf "  [5] [%s] Xóa %s\n" "$([ "$do_sddm_theme" = "true" ] && echo "X" || echo " ")" "$SDDM_THEME_CONF"
        printf "  [6] [%s] Hoàn nguyên NVIDIA mkinitcpio/GRUB/loader đã ghi nhận\n" "$([ "$do_nvidia_boot" = "true" ] && echo "X" || echo " ")"
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
                4) [ "$do_nvidia_modprobe" = "true" ] && do_nvidia_modprobe=false || do_nvidia_modprobe=true ;;
                5) [ "$do_sddm_theme" = "true" ] && do_sddm_theme=false || do_sddm_theme=true ;;
                6) [ "$do_nvidia_boot" = "true" ] && do_nvidia_boot=false || do_nvidia_boot=true ;;
            esac
        done
    done

    perform_cleanup "$chosen_snap" "$do_sddm" "$do_bluetooth" "$do_supergfxd" "$do_nvidia_modprobe" "$do_sddm_theme" "$do_nvidia_boot"
}

# ------------------------------------------------------------------------------
# 6. Curses Dialog Workflow (Whiptail / Dialog)
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
                if [[ -n "${PRE_INSTALL_BACKUP:-}" && "$snap" == "$PRE_INSTALL_BACKUP" ]]; then
                    radio_args+=("$snap" "$base (Gốc trước cài đặt)" "ON")
                else
                    radio_args+=("$snap" "$base (Cũ nhất)" "ON")
                fi
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

    # 2. Checklist for Services Cleanup (defaults from recorded state files)
    local sddm_state="OFF" bluetooth_state="OFF" supergfxd_state="OFF"
    local nvidia_modprobe_state="OFF" sddm_theme_state="OFF" nvidia_boot_state="OFF"
    [ "$DEFAULT_DO_SDDM" = "true" ] && sddm_state="ON"
    [ "$DEFAULT_DO_BLUETOOTH" = "true" ] && bluetooth_state="ON"
    [ "$DEFAULT_DO_SUPERGFXD" = "true" ] && supergfxd_state="ON"
    [ "$DEFAULT_DO_NVIDIA_MODPROBE" = "true" ] && nvidia_modprobe_state="ON"
    [ "$DEFAULT_DO_SDDM_THEME" = "true" ] && sddm_theme_state="ON"
    [ "$DEFAULT_DO_NVIDIA_BOOT" = "true" ] && nvidia_boot_state="ON"

    local check_args=(
        "sddm" "Tắt dịch vụ sddm.service (Display Manager)" "$sddm_state"
        "bluetooth" "Tắt dịch vụ bluetooth.service" "$bluetooth_state"
        "supergfxd" "Tắt dịch vụ supergfxd.service (ASUS ROG Graphics)" "$supergfxd_state"
        "nvidia" "Xóa cấu hình ${MODPROBE_NVIDIA_CONF}" "$nvidia_modprobe_state"
        "sddm_theme" "Xóa cấu hình ${SDDM_THEME_CONF}" "$sddm_theme_state"
        "nvidia_boot" "Hoàn nguyên NVIDIA mkinitcpio/GRUB/loader đã ghi nhận" "$nvidia_boot_state"
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
    local do_nvidia_modprobe=false
    local do_sddm_theme=false
    local do_nvidia_boot=false

    for choice in $service_choices; do
        case "$choice" in
            sddm) do_sddm=true ;;
            bluetooth) do_bluetooth=true ;;
            supergfxd) do_supergfxd=true ;;
            nvidia) do_nvidia_modprobe=true ;;
            sddm_theme) do_sddm_theme=true ;;
            nvidia_boot) do_nvidia_boot=true ;;
        esac
    done

    perform_cleanup "$chosen_snap" "$do_sddm" "$do_bluetooth" "$do_supergfxd" "$do_nvidia_modprobe" "$do_sddm_theme" "$do_nvidia_boot"
}

# ------------------------------------------------------------------------------
# 7. Main Flow
# ------------------------------------------------------------------------------
if [ "$AUTO_ACCEPT" = "true" ]; then
    perform_cleanup \
        "$DEFAULT_SNAP" \
        "$DEFAULT_DO_SDDM" \
        "$DEFAULT_DO_BLUETOOTH" \
        "$DEFAULT_DO_SUPERGFXD" \
        "$DEFAULT_DO_NVIDIA_MODPROBE" \
        "$DEFAULT_DO_SDDM_THEME" \
        "$DEFAULT_DO_NVIDIA_BOOT"
    exit 0
fi

if is_terminal_capable; then
    run_curses_dialog
else
    run_cli_fallback_menu
fi
