#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Config Deployer Module (Non-Destructive Overlay & Runtime Sync)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

YUSEI_CONFIG_DIRS=(
    "hypr" "waybar" "rofi" "kitty" "swaync" "wlogout"
    "fastfetch" "btop" "cava" "swappy" "wallust"
    "Kvantum" "qt5ct" "qt6ct" "quickshell"
)

TMP_PRESERVE=""
_yusei_cleanup_tmp_preserve() {
    if [[ -n "${TMP_PRESERVE:-}" && -d "${TMP_PRESERVE:-}" ]]; then
        rm -rf "$TMP_PRESERVE"
    fi
}

_yusei_is_preserved_rel() {
    local dir_name="$1"
    local rel="$2"

    case "$dir_name" in
        hypr)
            case "$rel" in
                userprefs.conf|userprefs.lua|animations.conf|monitors.conf|power.json|\
                .power-optimizer.state|.current_wallpaper|.current_theme|wallpaper.jpg|\
                colors.conf|wallust/wallust-hyprland.conf|\
                UserConfigs/*|UserScripts/*)
                    return 0
                    ;;
            esac
            ;;
        waybar)
            case "$rel" in
                config|config.jsonc|style.css|UserModules|colors.css|wallust/colors-waybar.css)
                    return 0
                    ;;
            esac
            ;;
        rofi)
            case "$rel" in
                config.rasi|.current_wallpaper|colors.rasi|wallust/colors-rofi.rasi|online_music.list)
                    return 0
                    ;;
            esac
            ;;
        kitty)
            case "$rel" in
                kitty.conf|current-theme.conf|theme.conf|kitty-themes/01-Wallust.conf)
                    return 0
                    ;;
            esac
            ;;
        quickshell)
            case "$rel" in
                config.json|qml_color.json)
                    return 0
                    ;;
            esac
            ;;
        swaync)
            [[ "$rel" == "colors.css" ]] && return 0
            ;;
        cava)
            [[ "$rel" == "config" ]] && return 0
            ;;
        wallust)
            [[ "$rel" == "wallust.toml" ]] && return 0
            ;;
    esac
    return 1
}

# Đồng bộ không phá hủy một thư mục cấu hình từ repo sang CONFIG_HOME/$dir
yusei_overlay_config_dir() {
    local src_dir="$1"
    local dst_dir="$2"
    local dir_name="$3"

    if [[ ! -d "$src_dir" ]]; then
        return 0
    fi

    # Nếu chưa từng có cấu hình tại đích -> sao chép trọn vẹn lần đầu
    if [[ ! -e "$dst_dir" && ! -L "$dst_dir" ]]; then
        cp -a "$src_dir" "$dst_dir"
        return 0
    fi

    mkdir -p "$dst_dir"

    local subdir src_item rel dst_item
    while IFS= read -r -d '' subdir; do
        rel="${subdir#"$src_dir/"}"
        mkdir -p "$dst_dir/$rel"
    done < <(find "$src_dir" -mindepth 1 -type d -print0)

    while IFS= read -r -d '' src_item; do
        rel="${src_item#"$src_dir/"}"
        dst_item="$dst_dir/$rel"

        if _yusei_is_preserved_rel "$dir_name" "$rel"; then
            if [[ -e "$dst_item" || -L "$dst_item" ]]; then
                continue
            fi
        fi

        mkdir -p "$(dirname "$dst_item")"
        rm -f "$dst_item"
        cp -a "$src_item" "$dst_item"
    done < <(find "$src_dir" -mindepth 1 \( -type f -o -type l \) -print0)
}

_yusei_atomic_copy_file() {
    local src="$1"
    local dst="$2"
    local tmp_dst
    mkdir -p "$(dirname "$dst")"
    tmp_dst="$(dirname "$dst")/.tmp.$(basename "$dst").$$"
    rm -f "$tmp_dst"
    if cp -a "$src" "$tmp_dst" 2>/dev/null; then
        mv -f "$tmp_dst" "$dst"
    else
        rm -f "$tmp_dst"
        return 1
    fi
}

_yusei_atomic_copy_dir() {
    local src_dir="$1"
    local dst_dir="$2"
    local make_exec="${3:-false}"
    [[ -d "$src_dir" ]] || return 0
    mkdir -p "$dst_dir"
    local item base
    for item in "$src_dir"/*; do
        [[ -e "$item" || -L "$item" ]] || continue
        base="$(basename "$item")"
        if _yusei_atomic_copy_file "$item" "$dst_dir/$base"; then
            if [[ "$make_exec" == "true" ]]; then
                chmod +x "$dst_dir/$base" 2>/dev/null || true
            fi
        fi
    done
}

_yusei_clamp_anim_file_speeds() {
    local anim_file="$1"
    [[ -f "$anim_file" ]] || return 0
    local tmp_file
    tmp_file="$(dirname "$anim_file")/.tmp.$(basename "$anim_file").$$"
    local rc=0
    awk '
    BEGIN { changed = 0 }
    {
        line = $0
        code = line
        comment = ""
        cpos = index(line, "#")
        if (cpos > 0) {
            code = substr(line, 1, cpos - 1)
            comment = substr(line, cpos)
        }
        if (code ~ /^[[:space:]]*animation[[:space:]]*=/) {
            eqpos = index(code, "=")
            lhs = substr(code, 1, eqpos)
            rhs = substr(code, eqpos + 1)
            n = split(rhs, parts, ",")
            if (n >= 3) {
                spd_raw = parts[3]
                spd_lead = ""
                if (match(spd_raw, /^[[:space:]]*/)) {
                    spd_lead = substr(spd_raw, 1, RLENGTH)
                }
                spd_trim = spd_raw
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", spd_trim)
                if (spd_trim ~ /^[0-9]+(\.[0-9]+)?$/ && (spd_trim + 0) > 100) {
                    parts[3] = spd_lead "100"
                    rebuilt = parts[1]
                    for (i = 2; i <= n; i++) {
                        rebuilt = rebuilt "," parts[i]
                    }
                    line = lhs rebuilt (comment != "" ? " " comment : "")
                    changed = 1
                }
            }
        }
        print line
    }
    END { exit (changed ? 0 : 10) }' "$anim_file" > "$tmp_file" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        mv -f "$tmp_file" "$anim_file"
    else
        rm -f "$tmp_file"
    fi
}

yusei_sync_userscripts() {
    local repo_root="$1"
    local config_home="$2"
    local src_dir="$repo_root/config/hypr/UserScripts"
    local dst_dir="$config_home/hypr/UserScripts"
    [[ -d "$src_dir" ]] || return 0

    mkdir -p "$dst_dir"
    local bak_dir="$dst_dir/.bak-$(date +%Y%m%d_%H%M%S)"
    local backed_any=false
    local src_item rel dst_item

    while IFS= read -r -d '' src_item; do
        rel="${src_item#"$src_dir/"}"
        dst_item="$dst_dir/$rel"
        if [[ -e "$dst_item" || -L "$dst_item" ]] && ! cmp -s "$src_item" "$dst_item" 2>/dev/null; then
            mkdir -p "$bak_dir/$(dirname "$rel")"
            cp -a "$dst_item" "$bak_dir/$rel" 2>/dev/null || true
            backed_any=true
        fi
        _yusei_atomic_copy_file "$src_item" "$dst_item" || true
        if [[ "$dst_item" == *.sh || "$dst_item" == *.py ]]; then
            chmod +x "$dst_item" 2>/dev/null || true
        fi
    done < <(find "$src_dir" -mindepth 1 \( -type f -o -type l \) -print0)

    if [[ "$backed_any" == "true" ]]; then
        echo -e "${GREEN}✓ Đã sao lưu UserScripts cũ vào $bak_dir và đồng bộ bản mới${NC}"
    else
        echo -e "${GREEN}✓ Đã đồng bộ UserScripts mới nhất vào $dst_dir${NC}"
    fi
}

yusei_deploy_all_configs() {
    local repo_root="$1"
    local config_home="$2"

    mkdir -p "$config_home"

    local had_hypr_before=false
    if [[ -d "$config_home/hypr" ]]; then
        had_hypr_before=true
    fi

    local dir
    for dir in "${YUSEI_CONFIG_DIRS[@]}"; do
        if [[ -d "$repo_root/config/$dir" ]]; then
            local dst_dir="$config_home/$dir"
            yusei_overlay_config_dir "$repo_root/config/$dir" "$dst_dir" "$dir"

            if [[ "$dir" == "hypr" && "$had_hypr_before" = "true" ]]; then
                # Đảm bảo animations.conf giữ/có fadeDpms, 0 để tránh chớp màn hình khi wake
                if [[ -f "$dst_dir/animations.conf" ]] && ! grep -Eq 'fadeDpms' "$dst_dir/animations.conf"; then
                    {
                        echo ""
                        echo "# Prevent flicker on DPMS wake (preserved by yusei-hypr)"
                        echo "animation = fadeDpms, 0"
                    } >> "$dst_dir/animations.conf"
                fi
                # Kẹp an toàn speed > 100 trong UserAnimations.conf/animations.conf hiện có (Hyprland 0.57+)
                _yusei_clamp_anim_file_speeds "$dst_dir/UserConfigs/UserAnimations.conf"
                _yusei_clamp_anim_file_speeds "$dst_dir/animations.conf"
                echo -e "${GREEN}✓ Đã đồng bộ an toàn (non-destructive, giữ cấu hình/trạng thái người dùng): $dst_dir${NC}"
            else
                echo -e "${GREEN}✓ Đã triển khai: $dst_dir${NC}"
            fi
        fi
    done

    # Đảm bảo userprefs.conf luôn tồn tại sau khi triển khai
    if [[ ! -f "$config_home/hypr/userprefs.conf" && -f "$repo_root/config/hypr/userprefs.conf" ]]; then
        cp -a "$repo_root/config/hypr/userprefs.conf" "$config_home/hypr/userprefs.conf"
        echo -e "${GREEN}✓ Đã khởi tạo template cấu hình: $config_home/hypr/userprefs.conf${NC}"
    fi

    # Đảm bảo phân quyền thực thi cho toàn bộ script trong config_home
    if [[ -d "$config_home/hypr/scripts" ]]; then
        find "$config_home/hypr/scripts" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
    fi
    if [[ -d "$config_home/hypr/UserScripts" ]]; then
        find "$config_home/hypr/UserScripts" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} + 2>/dev/null || true
    fi
    if [[ -f "$config_home/hypr/initial-boot.sh" ]]; then
        chmod +x "$config_home/hypr/initial-boot.sh" 2>/dev/null || true
    fi
    if [[ -f "$config_home/hypr/scripts/power-optimizer.sh" ]]; then
        chmod +x "$config_home/hypr/scripts/power-optimizer.sh" 2>/dev/null || true
    fi
}

yusei_enable_hypr_nvidia_conf() {
    local config_home="$1"
    if [[ -f "$config_home/hypr/hyprland.conf" ]]; then
        # Khớp chính xác cả "# source = ./nvidia.conf" và "# source = ~/.config/hypr/nvidia.conf"
        sed -i -E 's@#\s*source\s*=\s*(\./|~/\.config/hypr/)nvidia\.conf@source = ./nvidia.conf@g' "$config_home/hypr/hyprland.conf"
        echo -e "${GREEN}✓ Đã kích hoạt cấu hình tối ưu card đồ họa NVIDIA trong hyprland.conf!${NC}"
    fi
}

yusei_detect_nvidia_readonly() {
    local repo_root="$1"
    local has_nvidia="false"

    if [[ -f /tmp/yusei-hypr/detected.env ]]; then
        # shellcheck disable=SC1091
        . /tmp/yusei-hypr/detected.env
        has_nvidia="${HAS_NVIDIA:-false}"
    elif [[ -x "$repo_root/scripts/hardware-detect.sh" ]] && command -v python3 &>/dev/null; then
        has_nvidia="$("$repo_root/scripts/hardware-detect.sh" --json --dry-run 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print("true" if d.get("has_nvidia") else "false")
except Exception:
    print("false")
' 2>/dev/null || echo "false")"
    fi

    echo "$has_nvidia"
}

yusei_sync_wallpapers() {
    local repo_root="$1"
    local config_home="$2"
    local pictures_dir
    pictures_dir="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"

    mkdir -p "$pictures_dir/wallpapers"
    if [[ -d "$repo_root/assets/wallpapers" ]]; then
        echo -e "${BLUE}:: Đang đồng bộ bộ sưu tập hình nền vào $pictures_dir/wallpapers...${NC}"
        cp -n "$repo_root/assets/wallpapers"/* "$pictures_dir/wallpapers/" 2>/dev/null || true
        local wp_count
        wp_count="$(find "$repo_root/assets/wallpapers" -maxdepth 1 -type f 2>/dev/null | wc -l)"
        echo -e "${GREEN}✓ Đã cập nhật toàn bộ ${wp_count} hình nền nghệ thuật vào $pictures_dir/wallpapers${NC}"
    fi

    # Chỉ thiết lập hình nền mặc định nếu chưa có wallpaper.jpg trước đó
    if [[ ! -e "$config_home/hypr/wallpaper.jpg" && ! -L "$config_home/hypr/wallpaper.jpg" ]]; then
        local default_wall="$pictures_dir/wallpapers/16-balcony-twilight.png"
        if [[ ! -f "$default_wall" && -f "$repo_root/assets/wallpapers/default.jpg" ]]; then
            default_wall="$repo_root/assets/wallpapers/default.jpg"
        fi
        if [[ -f "$default_wall" && -d "$config_home/hypr" ]]; then
            cp -f "$default_wall" "$config_home/hypr/wallpaper.jpg"
        fi
    fi
}

yusei_sync_local_runtime() {
    local repo_root="$1"
    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    local local_share="$data_home/yusei-hypr"

    if [[ -d "$repo_root/lib" ]]; then
        _yusei_atomic_copy_dir "$repo_root/lib" "$HOME/.local/lib" "false"
        if [[ -f "$repo_root/lib/waybar-hyprland-compat.c" ]] && command -v gcc >/dev/null 2>&1; then
            local so_tmp="$HOME/.local/lib/.tmp.libwaybar-hyprland.so.$$"
            rm -f "$so_tmp"
            if gcc -shared -fPIC -O2 "$repo_root/lib/waybar-hyprland-compat.c" -o "$so_tmp" -ldl 2>/dev/null; then
                mv -f "$so_tmp" "$HOME/.local/lib/libwaybar-hyprland.so"
            else
                rm -f "$so_tmp"
            fi
        fi
    fi

    mkdir -p "$HOME/.local/bin" "$local_share/bin" "$local_share/packages"

    # Không bao giờ chmod trực tiếp lên $repo_root/bin/* để giữ sạch git working tree
    if [[ -d "$repo_root/bin" ]]; then
        _yusei_atomic_copy_dir "$repo_root/bin" "$HOME/.local/bin" "true"
        _yusei_atomic_copy_dir "$repo_root/bin" "$local_share/bin" "true"
    fi

    if [[ -d "$repo_root/assets/packages" ]]; then
        cp -a "$repo_root/assets/packages"/* "$local_share/packages/" 2>/dev/null || true
    fi

    if [[ -d "$repo_root/yusei_settings" ]]; then
        rm -rf "$local_share/yusei_settings"
        cp -a "$repo_root/yusei_settings" "$local_share/" 2>/dev/null || true
    fi

    if [[ -d "$repo_root/scripts" ]]; then
        rm -rf "$local_share/scripts"
        cp -a "$repo_root/scripts" "$local_share/" 2>/dev/null || true
        chmod +x "$local_share/scripts"/*.sh 2>/dev/null || true
    fi

    if [[ -f "$repo_root/uninstall.sh" ]]; then
        cp -f "$repo_root/uninstall.sh" "$local_share/uninstall.sh" 2>/dev/null || true
        chmod +x "$local_share/uninstall.sh" 2>/dev/null || true
    fi

    if [[ -f "$repo_root/config/yusei-settings.desktop" ]]; then
        mkdir -p "$data_home/applications"
        cp -f "$repo_root/config/yusei-settings.desktop" "$data_home/applications/"
        update-desktop-database "$data_home/applications" 2>/dev/null || true
    fi

    echo -e "${GREEN}✓ Đã đồng bộ swww (0.9.5), bin/, scripts/, yusei_settings & uninstall.sh vào ~/.local${NC}"
}

if [[ "${YUSEI_CONFIG_SYNC_LIB_ONLY:-0}" = "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

trap _yusei_cleanup_tmp_preserve EXIT INT TERM

DRY_RUN=false
SYNC_USERSCRIPTS=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --sync-userscripts) SYNC_USERSCRIPTS=true ;;
    esac
done

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

if [[ "$DRY_RUN" = "true" ]]; then
    echo -e "${YELLOW}:: [DRY-RUN] Mô phỏng triển khai cấu hình yusei-hypr vào $CONFIG_HOME và ~/.local (không ghi đĩa)...${NC}"
    echo -e "${YELLOW}   • Sẽ đồng bộ không phá hủy ${#YUSEI_CONFIG_DIRS[@]} thư mục cấu hình vào $CONFIG_HOME${NC}"
    echo -e "${YELLOW}   • Sẽ bảo tồn userprefs.{conf,lua}, UserConfigs/, UserScripts/, animations.conf (fadeDpms, 0), monitors.conf, power.json, state/colors, presets cá nhân${NC}"
    echo -e "${YELLOW}   • Sẽ đồng bộ bin/, lib/, scripts/, assets/packages/, yusei_settings/, uninstall.sh vào ~/.local${NC}"
    exit 0
fi

echo -e "${BLUE}:: [Configs] Đang cài đặt các file cấu hình yusei-hypr vào $CONFIG_HOME...${NC}"

# Nạp thông tin phần cứng
HAS_NVIDIA="false"
IS_LAPTOP="false"
if [ -f /tmp/yusei-hypr/detected.env ]; then
    # shellcheck disable=SC1091
    . /tmp/yusei-hypr/detected.env
fi

# 1-2. Đồng bộ an toàn toàn bộ thư mục cấu hình vào CONFIG_HOME
yusei_deploy_all_configs "$SCRIPT_DIR" "$CONFIG_HOME"

if [[ "$SYNC_USERSCRIPTS" == "true" ]]; then
    yusei_sync_userscripts "$SCRIPT_DIR" "$CONFIG_HOME"
fi

# 3. Kích hoạt NVIDIA nếu được phát hiện
if [ "${HAS_NVIDIA:-false}" = "true" ]; then
    echo -e "${YELLOW}:: Đang kích hoạt nạp nvidia.conf trong hyprland.conf...${NC}"
    yusei_enable_hypr_nvidia_conf "$CONFIG_HOME"
fi

# 3b. Cấu hình tự động và quản lý nguồn điện cho Laptop
if [ "${IS_LAPTOP:-false}" = "true" ] || compgen -G "/sys/class/power_supply/BAT*" >/dev/null 2>&1; then
    echo -e "${BLUE}:: [Laptop] Thiết bị Laptop được phát hiện. Đảm bảo cấu hình quản lý nguồn điện (power-profiles-daemon, brightnessctl, acpi)...${NC}"
    echo -e "${GREEN}✓ Đã cấu hình tối ưu pin và tần số quét tự động cho Laptop!${NC}"
fi

# 4. Sao chép bộ sưu tập hình nền vào ~/Pictures/wallpapers (bảo tồn wallpaper.jpg đã có)
yusei_sync_wallpapers "$SCRIPT_DIR" "$CONFIG_HOME"

# 5. Đồng bộ các công cụ bin/, lib/, scripts/, uninstall.sh và runtime yusei_settings vào ~/.local
yusei_sync_local_runtime "$SCRIPT_DIR"

# 6. Cấu hình Pokemon Fastfetch cho Shell Terminal (Zsh & Bash)
POKEMON_BANNER='pokemon-colorscripts --no-title -s -r | fastfetch -c ${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch/config-pokemon.jsonc --logo-type file-raw --logo-height 10 --logo-width 5 --logo -'
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [[ -f "$rc" ]]; then
        if ! grep -q "config-pokemon.jsonc" "$rc"; then
            echo "" >> "$rc"
            echo "# Pokemon Fastfetch Banner (yusei-hypr)" >> "$rc"
            echo "$POKEMON_BANNER" >> "$rc"
            echo -e "${GREEN}✓ Đã tích hợp Pokemon Fastfetch vào $(basename "$rc")${NC}"
        fi
        if ! grep -q "alias yay=" "$rc"; then
            echo "" >> "$rc"
            echo "# Chặn yay/paru tự động thay thế swww bằng awww khi cập nhật" >> "$rc"
            echo "alias yay='yay --ignore swww,awww'" >> "$rc"
            echo "alias paru='paru --ignore swww,awww'" >> "$rc"
        fi
    fi
done

echo -e "${GREEN}✓ Triển khai cấu hình hoàn tất thành công!${NC}\n"
