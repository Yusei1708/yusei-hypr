#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# For applying Animations from different users

# Check if rofi is already running
if pidof rofi > /dev/null; then
  pkill rofi
fi

# Variables
iDIR="$HOME/.config/swaync/images"
SCRIPTSDIR="$HOME/.config/hypr/scripts"
animations_dir="$HOME/.config/hypr/animations"
UserConfigs="$HOME/.config/hypr/UserConfigs"
rofi_theme="$HOME/.config/rofi/config-Animations.rasi"
msg='❗NOTE:❗ This will copy animations into UserAnimations.conf'
# list of animation files, sorted alphabetically with numbers first
animations_list=$(find -L "$animations_dir" -maxdepth 1 -type f | sed 's/.*\///' | sed 's/\.conf$//' | sort -V)

sanitize_user_animations() {
    local src_file="$1"
    local dst_file="$2"

    awk '
    BEGIN {
        saw_fadedpms = 0
        saw_anim_block = 0
    }
    {
        line = $0
        code = line
        comment = ""
        cpos = index(line, "#")
        if (cpos > 0) {
            code = substr(line, 1, cpos - 1)
            comment = substr(line, cpos)
        }

        if (code ~ /^[[:space:]]*animations[[:space:]]*\{/) {
            saw_anim_block = 1
        }

        if (code ~ /^[[:space:]]*animation[[:space:]]*=/) {
            eqpos = index(code, "=")
            lhs = substr(code, 1, eqpos)
            rhs = substr(code, eqpos + 1)
            n = split(rhs, parts, ",")
            leaf = parts[1]
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", leaf)
            if (leaf == "fadeDpms") {
                print "    animation = fadeDpms, 0"
                saw_fadedpms = 1
                next
            }
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
                }
            }
        }

        if (code ~ /^[[:space:]]*\}[[:space:]]*$/) {
            if (!saw_fadedpms) {
                print "    animation = fadeDpms, 0"
                saw_fadedpms = 1
            }
            print line
            next
        }

        print line
    }
    END {
        if (!saw_fadedpms) {
            if (!saw_anim_block) {
                print ""
                print "animations {"
            }
            print "    animation = fadeDpms, 0"
            if (!saw_anim_block) {
                print "}"
            }
        }
    }' "$src_file" > "$dst_file"
}

if [[ "${1:-}" == "--apply" && -n "${2:-}" ]]; then
    chosen_file="${2%.conf}"
else
    # Rofi Menu
    chosen_file=$(echo "$animations_list" | rofi -i -dmenu -config "$rofi_theme" -mesg "$msg")
fi

# Check if a file was selected
if [[ -n "$chosen_file" ]]; then
    full_path="$animations_dir/$chosen_file.conf"
    if [[ ! -f "$full_path" ]]; then
        exit 1
    fi
    mkdir -p "$UserConfigs"
    sanitize_user_animations "$full_path" "$UserConfigs/UserAnimations.conf"
    cat > "$HOME/.config/hypr/animations.conf" <<EOF
source = ./animations/$chosen_file.conf

animations {
    animation = fadeDpms, 0
}
EOF
    hyprctl reload config-only >/dev/null 2>&1 || true
    notify-send -u low -i "$iDIR/ja.png" "$chosen_file" "Hyprland Animation Loaded"
fi

sleep 0.5
if [[ -x "$SCRIPTSDIR/RefreshNoWaybar.sh" ]]; then
    "$SCRIPTSDIR/RefreshNoWaybar.sh"
fi
