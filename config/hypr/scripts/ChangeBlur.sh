#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Dynamic Blur Intensity Switcher (ChangeBlur.sh)
# Architecture: Hyprland IPC Keyword Controller | Dual-Kawase Optimization
# ==============================================================================

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $(basename "$0")"
    echo "Toggles between Normal Blur (size 5, passes 2) and Less Blur (size 2, passes 1)."
    exit 0
fi

notif="$HOME/.config/swaync/images"


STATE=$(hyprctl -j getoption decoration:blur:passes | jq ".int")

if [ "${STATE}" == "2" ]; then
	hyprctl keyword decoration:blur:size 2
	hyprctl keyword decoration:blur:passes 1
 	notify-send -e -u low -i "$notif/note.png" " Less Blur"
else
	hyprctl keyword decoration:blur:size 5
	hyprctl keyword decoration:blur:passes 2
  	notify-send -e -u low -i "$notif/ja.png" " Normal Blur"
fi
