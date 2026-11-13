#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Safe Dotfiles Update Notifier (KooLsDotsUpdate.sh)
# Deprecates upstream JaKooLit/Hyprland-Dots cloning and overwriting.
# Performs read-only status checks against the local yusei-hypr repository
# and directs the user to run update.sh to synchronize updates safely.
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
iDIR="$HOME/.config/swaync/images"
SHARE_DIR="$HOME/.local/share/yusei-hypr"

notify_msg() {
    local urgency="$1"
    local icon_name="$2"
    local title="$3"
    local body="$4"
    local icon="$iDIR/$icon_name"

    [[ -f "$icon" ]] || icon="software-update-available"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" -t 7000 -i "$icon" "$title" "$body" >/dev/null 2>&1 || true
    fi
}

find_yusei_repo() {
    local repo_from_script=""
    repo_from_script="$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd || true)"

    local candidates=(
        "${YUSEI_HYPR_REPO:-}"
        "$repo_from_script"
        "$SHARE_DIR"
        "$HOME/yusei-hypr"
        "$HOME/Documents/yusei-hypr"
        "$HOME/Projects/yusei-hypr"
        "$HOME/src/yusei-hypr"
    )

    local dir
    for dir in "${candidates[@]}"; do
        [[ -n "$dir" && -d "$dir" ]] || continue
        if command -v git >/dev/null 2>&1 \
           && git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
           && [[ -f "$dir/update.sh" ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
    done
    return 1
}

emit_waybar_json() {
    local text=" 󰁈 "
    local tooltip="$1"
    local cls="${2:-yusei-hypr}"

    if command -v jq >/dev/null 2>&1; then
        jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg cls "$cls" \
            '{text: $text, tooltip: $tooltip, class: $cls}'
    else
        local esc_tooltip="${tooltip//\\/\\\\}"
        esc_tooltip="${esc_tooltip//\"/\\\"}"
        esc_tooltip="${esc_tooltip//$'\n'/\\n}"
        printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$text" "$esc_tooltip" "$cls"
    fi
}

cmd_status() {
    local repo_dir="" tooltip="" cls="yusei-hypr"
    if repo_dir="$(find_yusei_repo)"; then
        local branch="" behind=""
        branch="$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
        behind="$(git -C "$repo_dir" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo "")"
        if [[ "$behind" =~ ^[0-9]+$ && "$behind" -gt 0 ]]; then
            cls="updates-available"
            tooltip="yusei-hypr (${branch}): ${behind} update(s) cached\nRepo: ${repo_dir}\nClick to check remote & run update.sh"
        else
            tooltip="yusei-hypr (${branch})\nRepo: ${repo_dir}\nClick to check updates & run update.sh"
        fi
    elif [[ -d "$SHARE_DIR" ]]; then
        tooltip="yusei-hypr installed (${SHARE_DIR})\nClick for update instructions (run update.sh)"
    else
        tooltip="yusei-hypr updates\nClick for update instructions (run update.sh)"
    fi
    emit_waybar_json "$tooltip" "$cls"
}

cmd_check() {
    local repo_dir=""
    if ! repo_dir="$(find_yusei_repo)"; then
        if [[ -d "$SHARE_DIR" ]]; then
            notify_msg "normal" "note.png" "yusei-hypr Updates" \
                "Updates come from yusei-hypr (JaKooLit/Hyprland-Dots clone is deprecated). Runtime assets exist at ${SHARE_DIR}; run update.sh from your yusei-hypr git repository."
        else
            notify_msg "normal" "note.png" "yusei-hypr Updates" \
                "Updates come from yusei-hypr (JaKooLit/Hyprland-Dots clone is deprecated). Run update.sh from your yusei-hypr repository to update."
        fi
        return 0
    fi

    local fetch_ok=false
    if command -v timeout >/dev/null 2>&1; then
        if timeout 10 git -C "$repo_dir" fetch --quiet 2>/dev/null; then
            fetch_ok=true
        fi
    else
        if git -C "$repo_dir" fetch --quiet 2>/dev/null; then
            fetch_ok=true
        fi
    fi

    local status_line="" behind=""
    status_line="$(git -C "$repo_dir" status -sb 2>/dev/null | head -n 1 || true)"
    behind="$(git -C "$repo_dir" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo "")"

    if [[ "$behind" =~ ^[0-9]+$ && "$behind" -gt 0 ]]; then
        notify_msg "normal" "ja.png" "yusei-hypr Update Available" \
            "${behind} commit(s) available (${status_line}). Run ${repo_dir}/update.sh to apply updates."
    elif [[ "$fetch_ok" == "true" ]]; then
        notify_msg "low" "note.png" "yusei-hypr Up to Date" \
            "Up to date (${status_line}). Updates come from yusei-hypr; run ${repo_dir}/update.sh whenever updating."
    else
        notify_msg "normal" "note.png" "yusei-hypr Updates" \
            "Could not fetch remote (${status_line:-local repo}). Updates come from yusei-hypr; run ${repo_dir}/update.sh to synchronize."
    fi
}

case "${1:-check}" in
    --status|status)
        cmd_status
        ;;
    --check|check|"")
        cmd_check
        ;;
    -h|--help)
        echo "Usage: $(basename "$0") [--status|--check]"
        echo "Read-only yusei-hypr repository update checker (replaces deprecated KooL Dots upgrader)."
        ;;
    *)
        echo "Usage: $(basename "$0") [--status|--check]" >&2
        exit 2
        ;;
esac
