#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Safe Idempotent DPMS & Idle Brightness Controller (DpmsControl.sh)
# ==============================================================================
# - Prevents DPMS toggle flickering on Hyprland 0.57+ Lua API by enforcing
#   table arguments: hl.dsp.dpms({action = "on"}) / ({action = "off"})
#   instead of bare strings ('on'/'off') which Hyprland treats as a toggle.
# - Checks monitor dpmsStatus beforehand (idempotent: skips redundant calls if
#   Hyprland's key_press_enables_dpms already enabled the display).
# - Supports legacy .conf Hyprland fallback by verifying both exit status and
#   'ok' response from hyprctl dispatch.
# - Handles safe backlight dimming (-c backlight) without overwriting saved
#   brightness on repeated idle/suspend transitions.
# ==============================================================================

set -euo pipefail

DRY_RUN="false"
DIM_PERCENT="${YUSEI_IDLE_DIM_PERCENT:-10}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
DIM_FLAG="${YUSEI_DIM_FLAG_FILE:-${RUNTIME_DIR}/yusei_hypr_dimmed}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <ACTION>

Actions:
  --on                  Safely enable DPMS (no-op if all active displays are ON)
  --off                 Safely disable DPMS (no-op if all active displays are OFF)
  --wake                Post-suspend wake: ensure DPMS ON (with retry) and restore brightness
  --dim                 Save current backlight (once per cycle) and dim to ${DIM_PERCENT}%
  --restore-brightness  Restore previously saved backlight level if dimmed
  --status              Print current monitor DPMS and dim flag status
  -h, --help            Show this help message

Options:
  --dry-run             Print intended commands without modifying hardware/compositor state
EOF
}

log_dry() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] $*"
    fi
}

query_monitors_json() {
    if [[ -n "${HYPRCTL_MONITORS_DATA:-}" ]]; then
        if [[ -f "$HYPRCTL_MONITORS_DATA" ]]; then
            cat "$HYPRCTL_MONITORS_DATA" 2>/dev/null || true
        else
            printf '%s\n' "$HYPRCTL_MONITORS_DATA"
        fi
        return 0
    fi

    if ! command -v hyprctl >/dev/null 2>&1; then
        return 0
    fi

    local raw=""
    raw="$(hyprctl monitors all -j 2>/dev/null || true)"
    if [[ -z "$raw" || "$raw" == "null" || "$raw" != \[* ]]; then
        raw="$(hyprctl monitors -j 2>/dev/null || true)"
    fi
    printf '%s\n' "$raw"
}

# Returns:
#   0 -> should dispatch (at least one active monitor differs, or state unknown)
#   1 -> already in desired state (safe no-op)
needs_dpms_change() {
    local target="$1"
    local raw_json=""
    raw_json="$(query_monitors_json)"

    if [[ -z "$raw_json" || "$raw_json" == "null" ]] || ! command -v jq >/dev/null 2>&1; then
        return 0
    fi

    local counts=""
    counts="$(printf '%s' "$raw_json" | jq -r '
        [.[] | select((.disabled // false) | not)] as $active |
        ($active | length) as $total |
        ([$active[] | select(.dpmsStatus == true)] | length) as $on_count |
        ([$active[] | select(.dpmsStatus == false)] | length) as $off_count |
        "\($total) \($on_count) \($off_count)"
    ' 2>/dev/null || true)"

    if [[ -z "$counts" ]]; then
        return 0
    fi

    local total on_count off_count
    read -r total on_count off_count <<< "$counts"
    if [[ "${total:-0}" -eq 0 ]]; then
        return 0
    fi

    if [[ "$target" == "on" ]]; then
        [[ "${off_count:-0}" -gt 0 ]]
    else
        [[ "${on_count:-0}" -gt 0 ]]
    fi
}

dispatch_dpms() {
    local target="$1"
    local lua_cmd="hl.dsp.dpms({action = \"${target}\"})"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "hyprctl dispatch '${lua_cmd}' (fallback: hyprctl dispatch dpms ${target})"
        return 0
    fi

    if ! command -v hyprctl >/dev/null 2>&1; then
        return 0
    fi

    local out=""
    local rc=0
    out="$(hyprctl dispatch "$lua_cmd" 2>&1)" || rc=$?
    if [[ $rc -eq 0 && "$out" == ok* ]]; then
        return 0
    fi

    # Fallback for legacy non-Lua Hyprland configs
    hyprctl dispatch dpms "$target" >/dev/null 2>&1 || true
}

set_dpms() {
    local target="$1"
    if needs_dpms_change "$target"; then
        dispatch_dpms "$target"
    else
        log_dry "DPMS already '${target}' on all active displays; skipping dispatch."
    fi
}

has_backlight() {
    command -v brightnessctl >/dev/null 2>&1 || return 1
    local info=""
    info="$(brightnessctl -l -c backlight -m 2>/dev/null || true)"
    [[ -n "$info" ]]
}

get_backlight_percent() {
    local line=""
    line="$(brightnessctl -l -c backlight -m 2>/dev/null | head -n 1 || true)"
    if [[ -z "$line" ]]; then
        return 1
    fi
    local pct=""
    pct="$(printf '%s' "$line" | cut -d, -f4 | tr -d '%[:space:]')"
    if [[ "$pct" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$pct"
        return 0
    fi
    return 1
}

action_dim() {
    if ! has_backlight; then
        log_dry "No backlight device detected; skipping dim."
        return 0
    fi

    if [[ -f "$DIM_FLAG" ]]; then
        log_dry "Backlight already dimmed (flag ${DIM_FLAG} present); skipping duplicate save."
        return 0
    fi

    local current_pct=""
    current_pct="$(get_backlight_percent || true)"
    if [[ -n "$current_pct" && "$current_pct" -le "$DIM_PERCENT" ]]; then
        log_dry "Current backlight (${current_pct}%) <= target (${DIM_PERCENT}%); leaving unchanged."
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "brightnessctl -c backlight -s set ${DIM_PERCENT}% && touch '${DIM_FLAG}'"
        return 0
    fi

    mkdir -p "$(dirname "$DIM_FLAG")"
    if brightnessctl -q -c backlight -s set "${DIM_PERCENT}%" 2>/dev/null; then
        : > "$DIM_FLAG"
    fi
}

action_restore_brightness() {
    if ! has_backlight; then
        rm -f "$DIM_FLAG" 2>/dev/null || true
        log_dry "No backlight device detected; skipping brightness restore."
        return 0
    fi

    if [[ ! -f "$DIM_FLAG" ]]; then
        log_dry "Dim flag absent (${DIM_FLAG}); skipping brightness restore."
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "brightnessctl -c backlight -r && rm -f '${DIM_FLAG}'"
        return 0
    fi

    brightnessctl -q -c backlight -r 2>/dev/null || true
    rm -f "$DIM_FLAG" 2>/dev/null || true
}

action_wake() {
    set_dpms "on"

    # After s2idle suspend/resume on hybrid Intel/NVIDIA laptops, DRM connector
    # modesetting can settle a fraction of a second after PrepareForSleep(false).
    if [[ "$DRY_RUN" == "false" && -z "${HYPRCTL_MONITORS_DATA:-}" ]]; then
        sleep "${YUSEI_WAKE_SETTLE_DELAY:-0.25}"
        if needs_dpms_change "on"; then
            dispatch_dpms "on"
        fi
    fi

    action_restore_brightness
}

action_status() {
    local raw_json=""
    raw_json="$(query_monitors_json)"
    local dimmed="false"
    [[ -f "$DIM_FLAG" ]] && dimmed="true"

    if [[ -n "$raw_json" && "$raw_json" != "null" ]] && command -v jq >/dev/null 2>&1; then
        printf '%s' "$raw_json" | jq -c --argjson dimmed "$([[ "$dimmed" == "true" ]] && echo true || echo false)" '{
            dimmed: $dimmed,
            monitors: [.[] | {name: .name, disabled: (.disabled // false), dpmsStatus: .dpmsStatus}]
        }'
    else
        printf '{"dimmed":%s,"monitors":[]}\n' "$dimmed"
    fi
}

ACTION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --on) ACTION="on" ;;
        --off) ACTION="off" ;;
        --wake) ACTION="wake" ;;
        --dim) ACTION="dim" ;;
        --restore-brightness) ACTION="restore-brightness" ;;
        --status) ACTION="status" ;;
        --dry-run) DRY_RUN="true" ;;
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

if [[ -z "$ACTION" ]]; then
    usage >&2
    exit 2
fi

case "$ACTION" in
    on) set_dpms "on" ;;
    off) set_dpms "off" ;;
    wake) action_wake ;;
    dim) action_dim ;;
    restore-brightness) action_restore_brightness ;;
    status) action_status ;;
esac
