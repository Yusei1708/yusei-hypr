#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Script for Random Wallpaper ( CTRL ALT W)

export PATH="$HOME/.local/bin:$PATH"

PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
wallDIR="$PICTURES_DIR/wallpapers"
SCRIPTSDIR="$HOME/.config/hypr/scripts"

focused_monitor=$(hyprctl monitors -j | jq -r '(.[] | select(.focused) | .name) // .[0].name')

mapfile -d '' PICS < <(find -L "${wallDIR}" -type f \( \
  -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.pnm" -o \
  -iname "*.tga" -o -iname "*.tiff" -o -iname "*.webp" -o -iname "*.bmp" -o \
  -iname "*.farbfeld" -o -iname "*.gif" \) -print0)
RANDOMPICS="${PICS[$((RANDOM % ${#PICS[@]}))]}"

# Transition config
FPS=30
TYPE="random"
DURATION=1
BEZIER=".43,1.19,1,.4"
SWWW_PARAMS="--transition-fps $FPS --transition-type $TYPE --transition-duration $DURATION --transition-bezier $BEZIER"

if ! pgrep -x "swww-daemon" >/dev/null; then
  swww-daemon --format xrgb &
fi
swww img -o "$focused_monitor" "$RANDOMPICS" $SWWW_PARAMS

"$SCRIPTSDIR/WallustSwww.sh" "$RANDOMPICS"

