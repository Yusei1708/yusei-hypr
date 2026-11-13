#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Lock Screen Trigger (LockScreen.sh)
# Pre-refreshes weather in background and locks cleanly via loginctl / hyprlock
# ==============================================================================

set -euo pipefail

LOCK_AND_WAIT="false"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --lock-and-wait   Wait until hyprlock starts and settles before returning
  -h, --help        Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lock-and-wait)
            LOCK_AND_WAIT="true"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

wait_for_hyprlock() {
    local max_steps="$1"
    local step=0
    while (( step < max_steps )); do
        if pidof hyprlock >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.05
        step=$((step + 1))
    done
    pidof hyprlock >/dev/null 2>&1
}

# Refresh weather cache in background if script exists
if [[ -f "$HOME/.config/hypr/UserScripts/WeatherWrap.sh" ]]; then
    bash "$HOME/.config/hypr/UserScripts/WeatherWrap.sh" >/dev/null 2>&1 &
fi

# Lock session cleanly via loginctl/hypridle when active, with direct hyprlock fallback
if ! pidof hyprlock >/dev/null 2>&1; then
    if pgrep -x hypridle >/dev/null 2>&1; then
        loginctl lock-session >/dev/null 2>&1 || true
        if ! wait_for_hyprlock 12; then
            hyprlock -q >/dev/null 2>&1 &
        fi
    else
        hyprlock -q >/dev/null 2>&1 &
    fi
fi

if [[ "$LOCK_AND_WAIT" == "true" ]]; then
    if ! wait_for_hyprlock 60; then
        echo "Error: hyprlock failed to start; refusing to unlock-bypass wait" >&2
        exit 1
    fi
    sleep "${YUSEI_LOCK_SETTLE_DELAY:-0.25}"
fi
