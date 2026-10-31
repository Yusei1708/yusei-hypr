#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Force Terminate Active Window Process (KillActiveProcess.sh)
# Architecture: hyprctl IPC Active Window Inspector | Process Terminator
# ==============================================================================

set -euo pipefail



# Get id of an active window
active_pid=$(hyprctl activewindow | grep -o 'pid: [0-9]*' | cut -d' ' -f2)

if [[ -z "$active_pid" || ! "$active_pid" =~ ^[0-9]+$ ]]; then
  notify-send -u low -i "$HOME/.config/swaync/images/error.png" "Kill Active Window" "No active window PID found."
  exit 1
fi

# Close active window
kill "$active_pid"
