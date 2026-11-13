#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Initialize J/K keybinds so they always cycle windows globally (no layout-specific behavior)
# This avoids double-actions when layouts change.

set -euo pipefail

# Always reset and bind SUPER+J/K the same way on startup
if ! hyprctl eval "hl.unbind('SUPER + J'); hl.unbind('SUPER + K'); hl.bind('SUPER + J', hl.dsp.window.cycle_next()); hl.bind('SUPER + K', hl.dsp.window.cycle_next({ next = false }))" >/dev/null 2>&1; then
    hyprctl keyword unbind SUPER,J >/dev/null 2>&1 || true
    hyprctl keyword unbind SUPER,K >/dev/null 2>&1 || true
    hyprctl keyword bind SUPER,J,cyclenext >/dev/null 2>&1 || true
    hyprctl keyword bind SUPER,K,cyclenext,prev >/dev/null 2>&1 || true
fi
