#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Dynamic Blur Intensity Switcher (ChangeBlur.sh)
# Dual-Compatible: Hyprland 0.57+ Lua API (hl.config) & Legacy keyword fallback
# ==============================================================================

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $(basename "$0")"
    echo "Toggles between Normal Blur (size 5, passes 2) and Less Blur (size 2, passes 1)."
    exit 0
fi

notif="$HOME/.config/swaync/images"

state=$(hyprctl -j getoption decoration:blur:passes 2>/dev/null | jq -r '.int // empty' || true)
if [[ -z "$state" || "$state" == "null" ]]; then
    state=$(hyprctl getoption decoration:blur:passes 2>/dev/null | awk 'NR==1 {print $2}' || echo "2")
fi

if [[ "$state" == "2" ]]; then
    size=2
    passes=1
    icon="$notif/note.png"
    label="Less Blur"
else
    size=5
    passes=2
    icon="$notif/ja.png"
    label="Normal Blur"
fi

if ! hyprctl eval "hl.config({ decoration = { blur = { size = $size, passes = $passes } } })" >/dev/null 2>&1; then
    hyprctl keyword decoration:blur:size "$size" >/dev/null 2>&1 || true
    hyprctl keyword decoration:blur:passes "$passes" >/dev/null 2>&1 || true
fi

notify-send -e -u low -i "$icon" "$label" 2>/dev/null || true
