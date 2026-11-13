#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: SwayNC Single Popup Enforcer (SwayncSinglePopup.sh)
# Invoked by SwayNC on notification receive. Closes any previous active popup ID
# if a new transient notification arrives within the 4-second window, while
# preserving notifications with actions or critical urgency.
# ==============================================================================

STATE_FILE="${SWAYNC_SINGLE_POPUP_STATE:-/tmp/.yusei_swaync_active_id}"
ACTION_MARKER="${XDG_RUNTIME_DIR:-/tmp}/.yusei_swaync_action_pending"
CUR_ID="${SWAYNC_ID:-}"

if [[ -z "$CUR_ID" ]]; then
    exit 0
fi

NOW=$(date +%s)

# Do not auto-close or be auto-closed if notification is critical or has actions
CUR_PROTECTED=0
if [[ "${SWAYNC_URGENCY,,}" == "critical" || "${SWAYNC_URGENCY:-}" == "2" ]]; then
    CUR_PROTECTED=1
fi
if [[ -n "${SWAYNC_HAS_ACTION:-}" && "${SWAYNC_HAS_ACTION}" != "0" && "${SWAYNC_HAS_ACTION,,}" != "false" ]]; then
    CUR_PROTECTED=1
fi
if [[ -n "${SWAYNC_ACTIONS:-}" && "${SWAYNC_ACTIONS}" != "[]" && "${SWAYNC_ACTIONS}" != "0" ]]; then
    CUR_PROTECTED=1
fi
if [[ -f "$ACTION_MARKER" ]]; then
    ACTION_TS="$(tr -d '[:space:]' < "$ACTION_MARKER" 2>/dev/null || true)"
    rm -f "$ACTION_MARKER" 2>/dev/null || true
    if [[ "$ACTION_TS" =~ ^[0-9]+$ ]] && (( NOW - ACTION_TS <= 3 )); then
        CUR_PROTECTED=1
    fi
fi

if [[ -f "$STATE_FILE" ]]; then
    read -r PREV_ID PREV_TS PREV_PROTECTED < "$STATE_FILE" 2>/dev/null || true
    PREV_PROTECTED="${PREV_PROTECTED:-0}"
    if [[ "$CUR_PROTECTED" != "1" && "$PREV_PROTECTED" != "1" ]]; then
        if [[ -n "${PREV_ID:-}" && "$PREV_ID" =~ ^[0-9]+$ && "$PREV_ID" != "$CUR_ID" ]]; then
            if [[ -z "${PREV_TS:-}" ]] || (( NOW - PREV_TS <= 4 )); then
                busctl --user call org.freedesktop.Notifications \
                    /org/freedesktop/Notifications \
                    org.freedesktop.Notifications \
                    CloseNotification u "$PREV_ID" >/dev/null 2>&1 || true
            fi
        fi
    fi
fi

printf '%s %s %s\n' "$CUR_ID" "$NOW" "$CUR_PROTECTED" > "$STATE_FILE"
exit 0
