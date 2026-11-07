#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Toggle Global Window Opacity / Transparency
# Dual-Compatible: Hyprland 0.57+ Lua API (hl.config) & Legacy keyword fallback
# ==============================================================================

set -euo pipefail

state_file="${XDG_RUNTIME_DIR:-/tmp}/hypr-opacity-disabled"

if [[ -e "$state_file" ]]; then
    # Enable transparency (90% uniform override)
    if ! hyprctl eval "hl.config({ decoration = { active_opacity = 0.9, inactive_opacity = 0.9 } }); hl.window_rule({ match = { class = '.*' }, opacity = '0.9 override 0.9 override 0.9 override' })" >/dev/null 2>&1; then
        hyprctl keyword "windowrule opacity 0.9 override 0.9 override 0.9 override, ^(.*)$" >/dev/null 2>&1 || true
    fi
    rm -f "$state_file"
    notify-send -u low "Window transparency" "Enabled (90%)" 2>/dev/null || true
else
    # Disable transparency (fully opaque 1.0)
    if ! hyprctl eval "hl.config({ decoration = { active_opacity = 1.0, inactive_opacity = 1.0 } }); hl.window_rule({ match = { class = '.*' }, opacity = '1.0 override 1.0 override 1.0 override' })" >/dev/null 2>&1; then
        hyprctl keyword "windowrule opacity 1 override 1 override 1 override, ^(.*)$" >/dev/null 2>&1 || true
    fi
    : > "$state_file"
    notify-send -u low "Window transparency" "Disabled (opaque)" 2>/dev/null || true
fi
