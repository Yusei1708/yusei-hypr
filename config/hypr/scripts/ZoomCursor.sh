#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Zoom / Magnify Cursor
# Dual-Compatible: Hyprland 0.57+ Lua API (hl.config) & Legacy keyword fallback
# ==============================================================================

set -euo pipefail

mode="${1:-}"
current=$(hyprctl getoption cursor:zoom_factor -j 2>/dev/null | jq -r '.float // empty')
if [[ -z "$current" || "$current" == "null" ]]; then
    current=$(hyprctl getoption cursor:zoom_factor 2>/dev/null | awk 'NR==1 {print $2}')
fi
if [[ -z "$current" ]]; then
    current=1.0
fi

case "$mode" in
    in)
        next=$(awk -v n="$current" 'BEGIN {if (n < 1) n=1; printf "%.3f", n*1.5}')
        ;;
    out)
        next=$(awk -v n="$current" 'BEGIN {if (n < 1) n=1; n=n/1.5; if (n < 1) n=1; printf "%.3f", n}')
        ;;
    *)
        echo "Usage: $0 {in|out}" >&2
        exit 2
        ;;
esac

if ! hyprctl eval "hl.config({ cursor = { zoom_factor = $next } })" >/dev/null 2>&1; then
    hyprctl keyword cursor:zoom_factor "$next" >/dev/null 2>&1 || true
fi
