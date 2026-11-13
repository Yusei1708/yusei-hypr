#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */
# This script for selecting wallpapers (SUPER W)

export PATH="$HOME/.local/bin:$PATH"

# WALLPAPERS PATH
terminal=kitty
PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
wallDIR="$PICTURES_DIR/wallpapers"
SCRIPTSDIR="$HOME/.config/hypr/scripts"
wallpaper_current="$HOME/.config/hypr/wallpaper_effects/.wallpaper_current"

# Directory for swaync
iDIR="$HOME/.config/swaync/images"
iDIRi="$HOME/.config/swaync/icons"

# swww transition config
FPS=60
TYPE="any"
DURATION=2
BEZIER=".43,1.19,1,.4"
SWWW_PARAMS="--transition-fps $FPS --transition-type $TYPE --transition-duration $DURATION --transition-bezier $BEZIER"

# Check if package bc exists
if ! command -v bc &>/dev/null; then
  notify-send -i "$iDIR/error.png" "bc missing" "Install package bc first"
  exit 1
fi

# Variables
rofi_theme="$HOME/.config/rofi/config-wallpaper.rasi"
read -r focused_monitor scale_factor monitor_height < <(
  hyprctl monitors -j | jq -r '(.[] | select(.focused)) // .[0] | "\(.name) \(.scale) \(.height)"'
)

# Ensure focused_monitor is detected
if [[ -z "$focused_monitor" ]]; then
  notify-send -i "$iDIR/error.png" "E-R-R-O-R" "Could not detect focused monitor"
  exit 1
fi

icon_size=$(echo "scale=1; ($monitor_height * 3) / ($scale_factor * 150)" | bc)
adjusted_icon_size=$(echo "$icon_size" | awk '{if ($1 < 15) $1 = 20; if ($1 > 25) $1 = 25; print $1}')
rofi_override="element-icon{size:${adjusted_icon_size}%;}"

# Kill existing wallpaper daemons for video
kill_wallpaper_for_video() {
  swww kill 2>/dev/null
  pkill mpvpaper 2>/dev/null
  pkill swaybg 2>/dev/null
  pkill hyprpaper 2>/dev/null
}

# Kill existing wallpaper daemons for image
kill_wallpaper_for_image() {
  pkill mpvpaper 2>/dev/null
  pkill swaybg 2>/dev/null
  pkill hyprpaper 2>/dev/null
}

# Retrieve wallpapers (both images & videos)
mapfile -d '' PICS < <(find -L "${wallDIR}" -type f \( \
  -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o \
  -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.webp" -o \
  -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.webm" \) -print0 2>/dev/null)

if [[ ${#PICS[@]} -eq 0 ]]; then
  notify-send -i "$iDIR/error.png" "No Wallpapers Found" "No wallpapers found in $wallDIR" || true
  exit 1
fi

RANDOM_PIC="${PICS[$((RANDOM % ${#PICS[@]}))]}"
RANDOM_PIC_NAME=". random"

# Rofi command
rofi_command="rofi -i -show -dmenu -config $rofi_theme -theme-str $rofi_override"

# Sorting Wallpapers
menu() {
  mapfile -d '' sorted_options < <(printf '%s\0' "${PICS[@]}" | sort -z)

  printf "%s\x00icon\x1f%s\n" "$RANDOM_PIC_NAME" "$RANDOM_PIC"

  for pic_path in "${sorted_options[@]}"; do
    pic_name=$(basename "$pic_path")
    if [[ "${pic_name,,}" =~ \.gif$ ]]; then
      cache_gif_image="$HOME/.cache/gif_preview/${pic_name}.png"
      if [[ ! -f "$cache_gif_image" ]]; then
        mkdir -p "$HOME/.cache/gif_preview"
        magick "$pic_path[0]" -resize 1920x1080 "$cache_gif_image"
      fi
      printf "%s\x00icon\x1f%s\n" "$pic_name" "$cache_gif_image"
    elif [[ "$pic_name" =~ \.(mp4|mkv|mov|webm|MP4|MKV|MOV|WEBM)$ ]]; then
      cache_preview_image="$HOME/.cache/video_preview/${pic_name}.png"
      if [[ ! -f "$cache_preview_image" ]]; then
        mkdir -p "$HOME/.cache/video_preview"
        ffmpeg -v error -y -i "$pic_path" -ss 00:00:01.000 -vframes 1 "$cache_preview_image"
      fi
      printf "%s\x00icon\x1f%s\n" "$pic_name" "$cache_preview_image"
    else
      printf "%s\x00icon\x1f%s\n" "$pic_name" "$pic_path"
    fi
  done
}

# Apply Image Wallpaper across all outputs
apply_image_wallpaper() {
  local image_path="$1"

  kill_wallpaper_for_image

  if ! pgrep -x "swww-daemon" >/dev/null; then
    echo "Starting swww-daemon..."
    swww-daemon --format xrgb &
    for _ in {1..20}; do
      swww query >/dev/null 2>&1 && break
      sleep 0.1
    done
  fi

  swww img "$image_path" $SWWW_PARAMS

  # Run WallustSwww.sh synchronously (handles theme-engine + live reload signals)
  "$SCRIPTSDIR/WallustSwww.sh" "$image_path"
}

apply_video_wallpaper() {
  local video_path="$1"

  # Check if mpvpaper is installed
  if ! command -v mpvpaper &>/dev/null; then
    notify-send -i "$iDIR/error.png" "E-R-R-O-R" "mpvpaper not found"
    return 1
  fi
  kill_wallpaper_for_video

  # Apply video wallpaper using mpvpaper
  mpvpaper '*' -o "load-scripts=no no-audio --loop" "$video_path" &
}

# Main function
main() {
  choice=$(menu | $rofi_command)
  choice="${choice#"${choice%%[![:space:]]*}"}"
  choice="${choice%"${choice##*[![:space:]]}"}"
  RANDOM_PIC_NAME="${RANDOM_PIC_NAME#"${RANDOM_PIC_NAME%%[![:space:]]*}"}"
  RANDOM_PIC_NAME="${RANDOM_PIC_NAME%"${RANDOM_PIC_NAME##*[![:space:]]}"}"

  if [[ -z "$choice" ]]; then
    echo "No choice selected. Exiting."
    exit 0
  fi

  # Handle random or exact full-filename selection
  local selected_file=""
  if [[ "$choice" == "$RANDOM_PIC_NAME" ]]; then
    selected_file="$RANDOM_PIC"
  else
    for pic_path in "${PICS[@]}"; do
      if [[ "$(basename "$pic_path")" == "$choice" ]]; then
        selected_file="$pic_path"
        break
      fi
    done
  fi

  if [[ -z "$selected_file" ]]; then
    echo "File not found. Selected choice: $choice"
    exit 1
  fi

  # **CHECK FIRST** if it's a video or an image **before calling any function**
  if [[ "$selected_file" =~ \.(mp4|mkv|mov|webm|MP4|MKV|MOV|WEBM)$ ]]; then
    apply_video_wallpaper "$selected_file"
  else
    apply_image_wallpaper "$selected_file"
  fi
}

# Check if rofi is already running
if pidof rofi >/dev/null; then
  pkill rofi
fi

main