#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Singleton Desktop UI Daemon Supervisor
# ==============================================================================
# Enforces the Single Daemon Principle (R2 & Acceptance Criteria):
# - Terminates conflicting notification daemons (dunst, mako, fnott) before starting swaync
# - Terminates competing bars (eww, ags) before starting waybar
# - Terminates competing wallpaper daemons (hyprpaper, mpvpaper)
# - Prevents duplicate swww-daemon executions
# - Restores active wallpaper and color palette dynamically
# ==============================================================================

set -euo pipefail

WALLPAPER_DIR="$HOME/Pictures/wallpapers"
DEFAULT_WALLPAPER="$HOME/.config/hypr/wallpaper.jpg"
STATE_WALLPAPER="$HOME/.config/hypr/.current_wallpaper"

echo ":: [Supervisor] Initializing yusei-hypr singleton desktop daemons..."

# 1. Terminate competing / conflicting daemons
echo ":: [Supervisor] Terminating conflicting notification & bar daemons..."
killall -q dunst mako fnott 2>/dev/null || true
killall -q eww ags 2>/dev/null || true
killall -q hyprpaper mpvpaper 2>/dev/null || true

# 2. Wallpaper Daemon (swww-daemon) with singleton protection
if ! pidof swww-daemon >/dev/null 2>&1; then
    echo ":: [Supervisor] Starting swww-daemon..."
    swww-daemon --format xrgb &
    
    # Wait for socket to become ready (max 3 seconds)
    for _ in {1..15}; do
        if swww query >/dev/null 2>&1; then
            break
        fi
        sleep 0.2
    done
else
    echo ":: [Supervisor] swww-daemon is already running."
fi

# 3. Restore Wallpaper
TARGET_WALL=""
if [[ -f "$STATE_WALLPAPER" ]] && [[ -s "$STATE_WALLPAPER" ]]; then
    SAVED_WALL="$(cat "$STATE_WALLPAPER")"
    if [[ -f "$SAVED_WALL" ]]; then
        TARGET_WALL="$SAVED_WALL"
    fi
fi

if [[ -z "$TARGET_WALL" ]] && [[ -f "$DEFAULT_WALLPAPER" ]]; then
    TARGET_WALL="$DEFAULT_WALLPAPER"
fi

if [[ -n "$TARGET_WALL" ]] && swww query >/dev/null 2>&1; then
    echo ":: [Supervisor] Applying wallpaper: $TARGET_WALL"
    swww img "$TARGET_WALL" --transition-type wipe --transition-duration 1.5 2>/dev/null || true
fi

# 4. Status Bar (Waybar)
if ! pidof waybar >/dev/null 2>&1; then
    echo ":: [Supervisor] Starting Waybar..."
    waybar &
else
    echo ":: [Supervisor] Waybar is already running."
fi

# 5. Notification & Control Center (SwayNC)
if ! pidof swaync >/dev/null 2>&1; then
    echo ":: [Supervisor] Starting SwayNC..."
    swaync &
else
    echo ":: [Supervisor] SwayNC is already running."
fi

# 6. Idle Listener (Hypridle)
if ! pidof hypridle >/dev/null 2>&1; then
    echo ":: [Supervisor] Starting Hypridle..."
    hypridle &
else
    echo ":: [Supervisor] Hypridle is already running."
fi

echo ":: [Supervisor] Singleton desktop daemons initialized successfully."
