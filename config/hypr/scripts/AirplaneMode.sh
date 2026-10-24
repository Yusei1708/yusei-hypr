#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Airplane Mode Toggle Subsystem (AirplaneMode.sh)
# Architecture: Universal Wayland | rfkill Hardware Interface
# ==============================================================================

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $(basename "$0")"
    echo "Toggles all wireless RF devices (Wi-Fi / Bluetooth) using rfkill."
    exit 0
fi

# Visual icon resolution with fallback
notif="$HOME/.config/swaync/images/ja.png"
if [[ ! -f "$notif" ]]; then
    notif="network-wireless-offline"
fi

# Check if any wireless device is soft-blocked
wifi_blocked=$(rfkill list wifi 2>/dev/null | grep -o "Soft blocked: yes" || true)

if [[ -n "$wifi_blocked" ]]; then
    rfkill unblock wifi
    notify-send -u low -i "$notif" "Airplane Mode" "Wireless enabled (OFF)"
else
    rfkill block wifi
    notify-send -u low -i "$notif" "Airplane Mode" "Wireless disabled (ON)"
fi

