#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Desktop Overview Toggle (Quickshell with AGS fallback)
# ==============================================================================

set -euo pipefail

# 1) Try Quickshell via IPC
if qs ipc -c overview call overview toggle >/dev/null 2>&1; then
    exit 0
fi

# 2) If Quickshell is installed but not started, launch it and retry
if command -v qs >/dev/null 2>&1; then
    qs -c overview >/dev/null 2>&1 &
    sleep 0.6
    if qs ipc -c overview call overview toggle >/dev/null 2>&1; then
        exit 0
    fi
fi

# 3) Fallback to AGS if available
if command -v ags >/dev/null 2>&1; then
    pkill rofi 2>/dev/null || true
    if ags -t 'overview' >/dev/null 2>&1; then
        exit 0
    fi
fi

notify-send "Overview" "Desktop Overview could not be reached (qs / ags)" -u low 2>/dev/null || true
exit 0
