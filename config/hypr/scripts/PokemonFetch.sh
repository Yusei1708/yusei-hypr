#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Pokemon Fastfetch Banner Generator
# ==============================================================================

CONFIG_FILE="$HOME/.config/fastfetch/config-pokemon.jsonc"

if command -v pokemon-colorscripts &>/dev/null; then
    pokemon-colorscripts --no-title -s -r | fastfetch -c "$CONFIG_FILE" --logo-type file-raw --logo-height 10 --logo-width 5 --logo -
elif command -v fastfetch &>/dev/null; then
    fastfetch -c "$CONFIG_FILE"
fi
