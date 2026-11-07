#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Game Mode Switcher (GameMode.sh)
# Dual-Compatible: Hyprland 0.57+ Lua API (hl.config) & Legacy batch keyword
# ==============================================================================

set -euo pipefail

notif="$HOME/.config/swaync/images/ja.png"
SCRIPTSDIR="$HOME/.config/hypr/scripts"

HYPRGAMEMODE=$(hyprctl getoption animations:enabled -j 2>/dev/null | jq -r '.int // empty' || true)
if [[ -z "$HYPRGAMEMODE" || "$HYPRGAMEMODE" == "null" ]]; then
    HYPRGAMEMODE=$(hyprctl getoption animations:enabled 2>/dev/null | awk 'NR==1{print $2}' || echo "1")
fi

if [ "$HYPRGAMEMODE" = "1" ] || [ "$HYPRGAMEMODE" = "true" ]; then
    # Disable eye-candy and transparency for gaming latency
    if ! hyprctl eval "hl.config({ animations = { enabled = false }, decoration = { shadow = { enabled = false }, blur = { enabled = false }, rounding = 0 }, general = { gaps_in = 0, gaps_out = 0, border_size = 1 } }); hl.window_rule({ name = 'global-opacity-override', match = { class = '.*' }, opacity = '1.0 override 1.0 override 1.0 override' })" >/dev/null 2>&1; then
        hyprctl --batch "\
            keyword animations:enabled 0;\
            keyword decoration:shadow:enabled 0;\
            keyword decoration:blur:enabled 0;\
            keyword general:gaps_in 0;\
            keyword general:gaps_out 0;\
            keyword general:border_size 1;\
            keyword decoration:rounding 0" >/dev/null 2>&1 || true
    fi

    swww kill 2>/dev/null || true
    notify-send -e -u low -i "$notif" " Gamemode:" " enabled" 2>/dev/null || true
    exit 0
else
    # Restore normal settings via config reload
    swww-daemon --format xrgb >/dev/null 2>&1 &
    sleep 0.1
    if [[ -f "$HOME/.config/rofi/.current_wallpaper" ]]; then
        swww img "$HOME/.config/rofi/.current_wallpaper" >/dev/null 2>&1 || true
    fi
    if [[ -x "${SCRIPTSDIR}/WallustSwww.sh" ]]; then
        "${SCRIPTSDIR}/WallustSwww.sh" >/dev/null 2>&1 &
    fi
    sleep 0.2
    hyprctl reload config-only >/dev/null 2>&1 || hyprctl reload >/dev/null 2>&1 || true
    if [[ -x "${SCRIPTSDIR}/Refresh.sh" ]]; then
        "${SCRIPTSDIR}/Refresh.sh" >/dev/null 2>&1 &
    fi
    notify-send -e -u normal -i "$notif" " Gamemode:" " disabled" 2>/dev/null || true
    exit 0
fi
