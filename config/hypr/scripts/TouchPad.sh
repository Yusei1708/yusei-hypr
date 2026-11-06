#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Touchpad Toggle Subsystem (TouchPad.sh)
# Architecture: hyprctl devices Auto-Discovery | Hardware Input Enabler/Disabler
# ==============================================================================

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $(basename "$0")"
    echo "Toggles internal laptop touchpad on/off using hyprctl keyword device:enabled."
    exit 0
fi


notif="$HOME/.config/swaync/images/ja.png"
laptops_conf="$HOME/.config/hypr/UserConfigs/Laptops.conf"

touchpad_device="${TOUCHPAD_DEVICE:-}"
if [[ -z "$touchpad_device" ]]; then
    for conf in "$laptops_conf" "$HOME/.config/hypr/Laptops.conf" "$HOME/.config/hypr/configs/Laptops.conf"; do
        if [[ -f "$conf" ]]; then
            touchpad_device="$(
                awk -F= '/^\$Touchpad_Device/ {
                    gsub(/[[:space:]]*/, "", $1);
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2);
                    print $2;
                    exit
                }' "$conf"
            )"
            [[ -n "$touchpad_device" ]] && break
        fi
    done
fi

if [[ -z "$touchpad_device" ]] && command -v hyprctl >/dev/null 2>&1; then
    touchpad_device="$(hyprctl devices -j 2>/dev/null | jq -r '.mice[]? | select(.name | test("touchpad"; "i")) | .name' 2>/dev/null | head -n1 || true)"
fi

if [[ -z "$touchpad_device" ]]; then
    notify-send -u low -i "$notif" " Touchpad" " Device name not detected or unsupported" 2>/dev/null || true
    exit 0
fi

touchpad_keyword="${TOUCHPAD_KEYWORD:-device:${touchpad_device}:enabled}"
status_file="${XDG_RUNTIME_DIR:-/tmp}/touchpad.status"

enable_touchpad() {
    printf "true" >"$status_file"
    notify-send -u low -i "$notif" " Enabling" " touchpad"
    hyprctl keyword "$touchpad_keyword" true -r
}

disable_touchpad() {
    printf "false" >"$status_file"
    notify-send -u low -i "$notif" " Disabling" " touchpad"
    hyprctl keyword "$touchpad_keyword" false -r
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
