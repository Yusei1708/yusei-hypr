#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Refresh Desktop UI Components (Refresh.sh)
# Refreshes Waybar, SwayNC, Rofi, and Quickshell Desktop Overview cleanly
# ==============================================================================

set -euo pipefail

SCRIPTSDIR=$HOME/.config/hypr/scripts
UserScripts=$HOME/.config/hypr/UserScripts

# Kill already running UI processes (preserve waybar so StatusNotifierWatcher stays alive)
_ps=(rofi swaync ags cava)
for _prs in "${_ps[@]}"; do
    if pidof "${_prs}" >/dev/null 2>&1; then
        pkill "${_prs}" 2>/dev/null || true
    fi
done
pkill -f "WaybarCava.sh" 2>/dev/null || true

# Restart quickshell overview cleanly
pkill qs 2>/dev/null || true
if command -v qs >/dev/null 2>&1; then
    qs -c overview >/dev/null 2>&1 &
fi

# Reload Hyprland border colors, window rules & blur cache if running
hyprctl reload >/dev/null 2>&1 || true

# Reload waybar in-place via SIGUSR2 (or start if not running)
sleep 0.1
if pidof waybar >/dev/null 2>&1; then
    killall -SIGUSR2 waybar 2>/dev/null || pkill -SIGUSR2 waybar 2>/dev/null || true
else
    nohup waybar >/dev/null 2>&1 &
fi

# Restart swaync
sleep 0.2
nohup swaync >/dev/null 2>&1 &
swaync-client --reload-config 2>/dev/null || true

# Relaunch rainbow borders if enabled
if [[ -f "${UserScripts}/RainbowBorders.sh" ]]; then
    "${UserScripts}/RainbowBorders.sh" &
fi

exit 0
