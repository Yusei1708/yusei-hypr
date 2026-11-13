#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Touchpad Toggle Switcher (TouchPad.sh)
# Dual-Compatible: Hyprland 0.57+ Lua API (hl.device) & Legacy keyword fallback
# Auto-detects Touchpad device via hyprctl devices if not specified in Laptops.conf
# ==============================================================================

set -euo pipefail

notif="$HOME/.config/swaync/images/ja.png"

touchpad_device="${TOUCHPAD_DEVICE:-}"
if [[ -z "$touchpad_device" ]]; then
    for laptops_conf in \
        "$HOME/.config/hypr/UserConfigs/Laptops.conf" \
        "$HOME/.config/hypr/Laptops.conf" \
        "$HOME/.config/hypr/configs/Laptops.conf"; do
        [[ -f "$laptops_conf" ]] || continue
        touchpad_device="$(
            awk -F= '/^[[:space:]]*\$Touchpad_Device[[:space:]]*=/ {
                sub(/#.*$/, "", $2);
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2);
                gsub(/^["'\'']|["'\'']$/, "", $2);
                print $2;
                exit
            }' "$laptops_conf"
        )"
        [[ -n "$touchpad_device" ]] && break
    done
fi

# Fallback auto-discovery from hyprctl devices (first mouse name containing "touchpad")
if [[ -z "$touchpad_device" ]] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    touchpad_device=$(hyprctl devices -j 2>/dev/null | jq -r '.mice[]? | select(.name | test("(?i)touchpad")) | .name' | head -n1 || true)
fi

if [[ -z "$touchpad_device" ]]; then
    notify-send -u low -i "$notif" " Touchpad" " Device name not set or detected" 2>/dev/null || true
    exit 0
fi

status_file="${XDG_RUNTIME_DIR:-/tmp}/touchpad.status"
safe_dev="${touchpad_device//\'/\\\'}"

enable_touchpad() {
    printf "true" >"$status_file"
    notify-send -u low -i "$notif" " Enabling" " touchpad" 2>/dev/null || true
    if ! hyprctl eval "hl.device({ name = '$safe_dev', enabled = true })" >/dev/null 2>&1; then
        hyprctl keyword "device[$touchpad_device]:enabled" true >/dev/null 2>&1 || true
    fi
}

disable_touchpad() {
    printf "false" >"$status_file"
    notify-send -u low -i "$notif" " Disabling" " touchpad" 2>/dev/null || true
    if ! hyprctl eval "hl.device({ name = '$safe_dev', enabled = false })" >/dev/null 2>&1; then
        hyprctl keyword "device[$touchpad_device]:enabled" false >/dev/null 2>&1 || true
    fi
}

# Read initial live enabled state via hyprctl getoption when supported, else fall back to status_file (default true)
current_state=""
if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    if opt_json=$(hyprctl getoption "device[$touchpad_device]:enabled" -j 2>/dev/null); then
        current_state=$(printf '%s' "$opt_json" | jq -r '
            if (.set == false) then empty
            elif has("bool") then (.bool | tostring)
            elif has("int") then (if .int == 0 then "false" else "true" end)
            else empty
            end
        ' 2>/dev/null || true)
    fi
fi

if [[ "$current_state" != "true" && "$current_state" != "false" ]]; then
    if [[ -f "$status_file" ]]; then
        current_state="$(<"$status_file")"
    else
        current_state="true"
    fi
fi

if [[ "$current_state" == "true" ]]; then
    disable_touchpad
else
    enable_touchpad
fi
