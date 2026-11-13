#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##

# Modified version of Refresh.sh but waybar wont refresh
# Used by automatic wallpaper change
# Modified inorder to refresh rofi background, Wallust, SwayNC only

SCRIPTSDIR=$HOME/.config/hypr/scripts
UserScripts=$HOME/.config/hypr/UserScripts
export PATH="$HOME/.local/bin:$PATH"

# Define file_exists function
file_exists() {
    if [ -e "$1" ]; then
        return 0  # File exists
    else
        return 1  # File does not exist
    fi
}

# Kill already running processes
_ps=(rofi)
for _prs in "${_ps[@]}"; do
    if pidof "${_prs}" >/dev/null; then
        pkill "${_prs}"
    fi
done

# quit quickshell & relaunch quickshell overview
if command -v qs >/dev/null 2>&1; then
    pkill qs 2>/dev/null || true
    qs -c overview >/dev/null 2>&1 &
fi

# Wallust refresh (synchronous to ensure colors are ready)
if [ -x "${SCRIPTSDIR}/WallustSwww.sh" ]; then
    "${SCRIPTSDIR}/WallustSwww.sh"
fi

# Reload swaync config
swaync-client --reload-config >/dev/null 2>&1 || true

# Relaunching rainbow borders if the script exists
if file_exists "${UserScripts}/RainbowBorders.sh"; then
    "${UserScripts}/RainbowBorders.sh" &
elif file_exists "${SCRIPTSDIR}/RainbowBorders.sh"; then
    "${SCRIPTSDIR}/RainbowBorders.sh" &
fi

exit 0