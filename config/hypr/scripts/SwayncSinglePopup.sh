#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: SwayNC Single Popup Enforcer (SwayncSinglePopup.sh)
# Invoked by SwayNC on notification receive. Closes any previous active popup ID
# if a new notification with a different ID arrives within the 3-second window.
# ==============================================================================

STATE_FILE="/tmp/.yusei_swaync_active_id"
CUR_ID="${SWAYNC_ID:-}"

if [[ -z "$CUR_ID" ]]; then
    exit 0
fi

NOW=$(date +%s)

if [[ -f "$STATE_FILE" ]]; then
    read -r PREV_ID PREV_TS < "$STATE_FILE" 2>/dev/null || true
    if [[ -n "${PREV_ID:-}" && "$PREV_ID" =~ ^[0-9]+$ && "$PREV_ID" != "$CUR_ID" ]]; then
        if [[ -z "${PREV_TS:-}" ]] || (( NOW - PREV_TS <= 4 )); then
            busctl --user call org.freedesktop.Notifications \
                /org/freedesktop/Notifications \
                org.freedesktop.Notifications \
                CloseNotification u "$PREV_ID" >/dev/null 2>&1 || true
        fi
    fi
fi

printf '%s %s\n' "$CUR_ID" "$NOW" > "$STATE_FILE"
exit 0
