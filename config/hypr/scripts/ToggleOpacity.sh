#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Toggle Global Window Opacity / Transparency
# Dual-Compatible: Hyprland 0.57+ Lua API (hl.config) & Legacy keyword fallback
# ==============================================================================

set -euo pipefail

state_file="${XDG_RUNTIME_DIR:-/tmp}/hypr-opacity-disabled"

apply_opacity_mode() {
    local level="$1"
    local rule_expr="$level override $level override $level override"
    local lua_expr="hl.config({ decoration = { active_opacity = $level, inactive_opacity = $level } }); hl.window_rule({ name = 'global-opacity-override', match = { class = '.*' }, opacity = '$rule_expr' })"
    local out="" rc=0
    out=$(hyprctl eval "$lua_expr" 2>&1) || rc=$?
    if [[ $rc -ne 0 || "$out" != ok* ]]; then
        hyprctl keyword "windowrule opacity $rule_expr, ^(.*)$" >/dev/null 2>&1 || true
    fi
}

if [[ -e "$state_file" ]]; then
    # Enable transparency (90% uniform override)
    apply_opacity_mode "0.9"
    rm -f "$state_file"
    notify-send -u low "Window transparency" "Enabled (90%)" 2>/dev/null || true
else
    # Disable transparency (fully opaque 1.0)
    apply_opacity_mode "1.0"
    : > "$state_file"
    notify-send -u low "Window transparency" "Disabled (opaque)" 2>/dev/null || true
fi
