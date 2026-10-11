#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# searchable enabled keybinds using rofi (supports bindd descriptions)

# kill yad to not interfere with this binds
pkill yad || true

# check if rofi is already running
if pidof rofi > /dev/null; then
  pkill rofi
fi

# define the config files
keybinds_conf="$HOME/.config/hypr/configs/Keybinds.conf"
user_keybinds_conf="$HOME/.config/hypr/UserConfigs/UserKeybinds.conf"
laptop_conf="$HOME/.config/hypr/UserConfigs/Laptops.conf"
rofi_theme="$HOME/.config/rofi/config-keybinds.rasi"
msg='☣️ NOTE ☣️: Clicking with Mouse or Pressing ENTER will have NO function'

# collect raw bind lines (strip end-of-line comments) from available files
files=()
for kconf in "$HOME/.config/hypr/keybinds.conf" \
             "$HOME/.config/hypr/configs/Keybinds.conf" \
             "$HOME/.config/hypr/UserConfigs/UserKeybinds.conf" \
             "$HOME/.config/hypr/Laptops.conf" \
             "$HOME/.config/hypr/UserConfigs/Laptops.conf"; do
    [[ -f "$kconf" ]] && files+=("$kconf")
done

# Resilient fallback if custom Rofi theme is missing
rofi_args=(-dmenu -i -mesg "$msg")
[[ -f "$rofi_theme" ]] && rofi_args+=(-config "$rofi_theme")

# Parse binds using the python script for speed
parser_script="$(dirname "$0")/keybinds_parser.py"
[[ ! -f "$parser_script" ]] && parser_script="$HOME/.config/hypr/scripts/keybinds_parser.py"

display_keybinds=$("$parser_script" "${files[@]}" 2>/dev/null || true)

# Check for suggestions file created by python script
if [[ -f "/tmp/hypr_keybind_suggestions_file" ]]; then
  suggestions_file=$(cat "/tmp/hypr_keybind_suggestions_file")
  rm "/tmp/hypr_keybind_suggestions_file"
  if [[ -n "$suggestions_file" && -f "$suggestions_file" ]]; then
     count=$(wc -l < "$suggestions_file")
     msg="$msg | Overrides missing unbind: $count (suggestions: $suggestions_file)"
  fi
fi

# use rofi to display the keybinds
printf '%s\n' "$display_keybinds" | rofi "${rofi_args[@]}"
