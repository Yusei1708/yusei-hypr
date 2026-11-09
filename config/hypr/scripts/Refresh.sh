#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Refresh Desktop UI Components (Refresh.sh)
# Refreshes Waybar, SwayNC, Rofi, and Quickshell Desktop Overview cleanly
# ==============================================================================

set -euo pipefail

SCRIPTSDIR=$HOME/.config/hypr/scripts
UserScripts=$HOME/.config/hypr/UserScripts

# Kill already running UI processes (preserve waybar and swaync so daemons stay alive)
_ps=(rofi ags cava)
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
hyprctl reload config-only >/dev/null 2>&1 || hyprctl reload >/dev/null 2>&1 || true

# Reload waybar in-place via SIGUSR2 (or start if not running)
if pidof waybar >/dev/null 2>&1; then
    killall -SIGUSR2 waybar 2>/dev/null || pkill -SIGUSR2 waybar 2>/dev/null || true
else
    nohup waybar >/dev/null 2>&1 &
fi

# Reload swaync CSS & config in-place without killing the daemon
if pidof swaync >/dev/null 2>&1; then
    swaync-client -rs >/dev/null 2>&1 || true
    swaync-client --reload-config >/dev/null 2>&1 || true
else
    nohup swaync >/dev/null 2>&1 &
fi

# Relaunch rainbow borders if enabled
if [[ -f "${UserScripts}/RainbowBorders.sh" ]]; then
    "${UserScripts}/RainbowBorders.sh" &
fi

exit 0
