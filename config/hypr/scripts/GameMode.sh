#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Game Mode. Turning off all animations

notif="$HOME/.config/swaync/images/ja.png"
SCRIPTSDIR="$HOME/.config/hypr/scripts"


HYPRGAMEMODE=$(hyprctl getoption animations:enabled 2>/dev/null | awk 'NR==1{print $2}')
if [ "$HYPRGAMEMODE" = 1 ] ; then
    hyprctl --batch "\
        keyword animations:enabled 0;\
        keyword decoration:shadow:enabled 0;\
        keyword decoration:blur:enabled 0;\
        keyword general:gaps_in 0;\
        keyword general:gaps_out 0;\
        keyword general:border_size 1;\
        keyword decoration:rounding 0;\
        keyword general:allow_tearing 1"
	
    hyprctl keyword "windowrule match:class .*, opacity 1.0 override 1.0 override"
    swww kill 2>/dev/null || true
    notify-send -e -u low -i "$notif" " Gamemode:" " enabled" 2>/dev/null || true
    sleep 0.1
    exit 0
else
    swww-daemon --format xrgb 2>/dev/null && swww img "$HOME/.config/rofi/.current_wallpaper" 2>/dev/null &
    sleep 0.1
    ${SCRIPTSDIR}/WallustSwww.sh 2>/dev/null || true
    sleep 0.5
    hyprctl reload
    ${SCRIPTSDIR}/Refresh.sh 2>/dev/null || true
    notify-send -e -u normal -i "$notif" " Gamemode:" " disabled" 2>/dev/null || true
    exit 0
fi
hyprctl reload

