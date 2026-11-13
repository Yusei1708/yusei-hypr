#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Dynamic Blur Intensity Switcher (ChangeBlur.sh)
# Dual-Compatible: Hyprland 0.57+ Lua API (hl.config) & Legacy keyword fallback
# ==============================================================================

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $(basename "$0")"
    echo "Toggles between Normal Blur (size 5, passes 2) and Less Blur (size 2, passes 1)."
    exit 0
fi

notif="$HOME/.config/swaync/images"
dec_file="${USER_DECORATIONS_CONF:-$HOME/.config/hypr/UserConfigs/UserDecorations.conf}"

read_blur_passes() {
    local val=""
    if command -v jq >/dev/null 2>&1; then
        val=$(hyprctl -j getoption decoration:blur:passes 2>/dev/null | jq -r '.int // empty' 2>/dev/null || true)
    fi
    if [[ -z "$val" || "$val" == "null" ]]; then
        val=$(hyprctl getoption decoration:blur:passes 2>/dev/null | awk 'NR==1 {print $2}' || true)
    fi
    printf '%s' "${val:-2}"
}

read_blur_enabled() {
    local val=""
    if command -v jq >/dev/null 2>&1; then
        val=$(hyprctl -j getoption decoration:blur:enabled 2>/dev/null | jq -r '
            if has("bool") then (.bool | tostring)
            elif has("int") then (if .int == 0 then "false" else "true" end)
            else empty
            end
        ' 2>/dev/null || true)
    fi
    if [[ "$val" != "true" && "$val" != "false" ]]; then
        val=$(hyprctl getoption decoration:blur:enabled 2>/dev/null | awk '
            NR==1 {
                v = tolower($2)
                if (v == "true" || v == "1" || v == "yes" || v == "on") print "true"
                else if (v == "false" || v == "0" || v == "no" || v == "off") print "false"
            }
        ' || true)
    fi
    printf '%s' "${val:-true}"
}

apply_hypr_blur() {
    local size="$1"
    local passes="$2"
    local lua_expr="hl.config({ decoration = { blur = { enabled = true, size = $size, passes = $passes } } })"
    local eval_out="" eval_rc=0
    eval_out=$(hyprctl eval "$lua_expr" 2>&1) || eval_rc=$?
    if [[ $eval_rc -eq 0 && "$eval_out" == ok* ]]; then
        return 0
    fi
    hyprctl keyword decoration:blur:enabled true >/dev/null 2>&1 || true
    hyprctl keyword decoration:blur:size "$size" >/dev/null 2>&1 || true
    hyprctl keyword decoration:blur:passes "$passes" >/dev/null 2>&1 || true
}

persist_user_decorations() {
    local target="$1"
    local size="$2"
    local passes="$3"
    [[ -f "$target" ]] || return 0

    local tmp_file
    tmp_file=$(mktemp "$(dirname "$target")/.$(basename "$target").XXXXXX")
    if ! awk -v new_size="$size" -v new_passes="$passes" '
    BEGIN {
        depth = 0
        blur_depth = -1
        saw_blur = 0
        seen_enabled = 0
        seen_size = 0
        seen_passes = 0
        child_indent = "    "
        blur_indent = "  "
    }
    function count_ch(str, ch,    i, c, n) {
        n = 0
        for (i = 1; i <= length(str); i++) {
            c = substr(str, i, 1)
            if (c == ch) n++
        }
        return n
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

        if (blur_depth < 0 && code ~ /^[[:space:]]*blur[[:space:]]*\{[[:space:]]*$/) {
            saw_blur = 1
            blur_depth = depth
            match(code, /^[[:space:]]*/)
            blur_indent = substr(code, 1, RLENGTH)
            child_indent = blur_indent "  "
            depth += count_ch(code, "{") - count_ch(code, "}")
            print line
            next
        }

        if (blur_depth >= 0) {
            if (code !~ /^[[:space:]]*(}|$)/) {
                match(code, /^[[:space:]]*/)
                child_indent = substr(code, 1, RLENGTH)
            }
            if (code ~ /^[[:space:]]*enabled[[:space:]]*=/) {
                seen_enabled = 1
                print child_indent "enabled = true" (comment != "" ? " " comment : "")
                depth += count_ch(code, "{") - count_ch(code, "}")
                next
            }
            if (code ~ /^[[:space:]]*size[[:space:]]*=/) {
                seen_size = 1
                print child_indent "size = " new_size (comment != "" ? " " comment : "")
                depth += count_ch(code, "{") - count_ch(code, "}")
                next
            }
            if (code ~ /^[[:space:]]*passes[[:space:]]*=/) {
                seen_passes = 1
                print child_indent "passes = " new_passes (comment != "" ? " " comment : "")
                depth += count_ch(code, "{") - count_ch(code, "}")
                next
            }
            depth += count_ch(code, "{") - count_ch(code, "}")
            if (depth <= blur_depth) {
                if (!seen_enabled) print child_indent "enabled = true"
                if (!seen_size)    print child_indent "size = " new_size
                if (!seen_passes)  print child_indent "passes = " new_passes
                blur_depth = -1
            }
            print line
            next
        }

        depth += count_ch(code, "{") - count_ch(code, "}")
        print line
    }
    END {
        if (!saw_blur) {
            print ""
            print "decoration {"
            print "  blur {"
            print "    enabled = true"
            print "    size = " new_size
            print "    passes = " new_passes
            print "  }"
            print "}"
        }
    }' "$target" > "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi

    chmod --reference="$target" "$tmp_file" 2>/dev/null || chmod 0644 "$tmp_file"
    mv -f "$tmp_file" "$target"
}

blur_enabled=$(read_blur_enabled)
blur_passes=$(read_blur_passes)

if [[ "$blur_enabled" == "false" ]]; then
    size=5
    passes=2
    icon="$notif/ja.png"
    label="Normal Blur"
elif [[ "$blur_passes" == "2" ]]; then
    size=2
    passes=1
    icon="$notif/note.png"
    label="Less Blur"
else
    size=5
    passes=2
    icon="$notif/ja.png"
    label="Normal Blur"
fi

apply_hypr_blur "$size" "$passes"
persist_user_decorations "$dec_file" "$size" "$passes"

notify-send -e -u low -i "$icon" "$label" 2>/dev/null || true
