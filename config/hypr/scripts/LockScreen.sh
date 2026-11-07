#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Lock Screen Trigger (LockScreen.sh)
# Pre-refreshes weather in background and triggers loginctl lock-session / hyprlock
# ==============================================================================

set -euo pipefail

# Refresh weather cache in background if script exists
if [[ -f "$HOME/.config/hypr/UserScripts/WeatherWrap.sh" ]]; then
    bash "$HOME/.config/hypr/UserScripts/WeatherWrap.sh" >/dev/null 2>&1 &
fi

# Lock session cleanly via systemd/loginctl with hyprlock fallback
if ! loginctl lock-session 2>/dev/null; then
    pidof hyprlock >/dev/null 2>&1 || hyprlock --grace 5 -q &
fi
