#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# For Searching via web browsers

# Set safe default engine
Search_Engine="https://www.google.com/search?q="

# Check optional config file
config_file=$HOME/.config/hypr/UserConfigs/01-UserDefaults.conf
for conf in "$config_file" "$HOME/.config/hypr/01-UserDefaults.conf"; do
    if [[ -f "$conf" ]]; then
        config_content=$(sed 's/\$//g' "$conf" | sed 's/ = /=/')
        eval "$config_content"
        break
    fi
done

# Check if $term is set correctly
if [[ -z "$Search_Engine" ]]; then
    echo "Error: \$Search_Engine is not set in the configuration file!"
    exit 1
fi

# Rofi theme and message
rofi_theme="$HOME/.config/rofi/config-search.rasi"
msg='‼️ **note** ‼️ search via default web browser'

# Kill Rofi if already running before execution
if pgrep -x "rofi" >/dev/null; then
    pkill rofi
fi

# Open Rofi and pass the selected query to xdg-open for the configured search engine
query=$(printf '' | rofi -dmenu -config "$rofi_theme" -mesg "$msg")

if [[ -z "$query" ]]; then
    exit 0
fi

encoded_query=$(printf '%s' "$query" | jq -sRr @uri)
xdg-open "${Search_Engine}${encoded_query}" >/dev/null 2>&1 &
