#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Touchpad Toggle Switcher (TouchPad.sh)
# Dual-Compatible: Hyprland 0.57+ Lua API (hl.device) & Legacy keyword fallback
# Auto-detects Touchpad device via hyprctl devices if not specified in Laptops.conf
# ==============================================================================

set -euo pipefail

notif="$HOME/.config/swaync/images/ja.png"
laptops_conf="$HOME/.config/hypr/configs/Laptops.conf"
[ -f "$HOME/.config/hypr/Laptops.conf" ] && laptops_conf="$HOME/.config/hypr/Laptops.conf"

touchpad_device="${TOUCHPAD_DEVICE:-}"
if [[ -z "$touchpad_device" && -f "$laptops_conf" ]]; then
    touchpad_device="$(
        awk -F= '/^\$Touchpad_Device/ {
            gsub(/[[:space:]]*/, "", $1);
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2);
            print $2;
            exit
        }' "$laptops_conf"
    )"
fi

# Fallback auto-discovery from hyprctl devices
if [[ -z "$touchpad_device" ]] && command -v hyprctl >/dev/null 2>&1; then
    touchpad_device=$(hyprctl devices -j 2>/dev/null | jq -r '.mice[]? | select(.name | test("(?i)touchpad")) | .name' | head -1 || true)
fi

if [[ -z "$touchpad_device" ]]; then
    notify-send -u low -i "$notif" " Touchpad" " Device name not set or detected" 2>/dev/null || true
    exit 0
fi

status_file="${XDG_RUNTIME_DIR:-/tmp}/touchpad.status"

enable_touchpad() {
    printf "true" >"$status_file"
    notify-send -u low -i "$notif" " Enabling" " touchpad" 2>/dev/null || true
    if ! hyprctl eval "hl.device({ name = '$touchpad_device', enabled = true })" >/dev/null 2>&1; then
        hyprctl keyword "device[$touchpad_device]:enabled" true >/dev/null 2>&1 || true
    fi
}

disable_touchpad() {
    printf "false" >"$status_file"
    notify-send -u low -i "$notif" " Disabling" " touchpad" 2>/dev/null || true
    if ! hyprctl eval "hl.device({ name = '$touchpad_device', enabled = false })" >/dev/null 2>&1; then
        hyprctl keyword "device[$touchpad_device]:enabled" false >/dev/null 2>&1 || true
    fi
}

current_state="false"
if [[ -f "$status_file" ]]; then
    current_state="$(<"$status_file")"
fi

if [[ "$current_state" == "true" ]]; then
    disable_touchpad
else
    enable_touchpad
fi
