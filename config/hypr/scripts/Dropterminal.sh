#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Dropdown Scratchpad Terminal (Dropterminal.sh)
# Optimized for Hyprland 0.57+ Lua API with smooth easing animation
# ==============================================================================

set -euo pipefail

DEBUG=0
if [[ "${1:-}" == "-d" ]]; then DEBUG=1; shift; fi
TERMINAL=${1:-kitty}
if [[ -z "$TERMINAL" ]]; then TERMINAL=kitty; fi
SLIDE_STEPS=20
SLIDE_DELAY=0.008

log() { (( DEBUG )) && printf '[dropdown] %s\n' "$*" >&2 || true; }
dispatch() {
    if ! hyprctl dispatch "$1" >/dev/null 2>&1; then
        :
    fi
}

slide_window() {
    local addr=$1 x=$2 from_y=$3 to_y=$4
    local delta=$((to_y - from_y))
    local i progress eased frame_y
    for ((i = 1; i <= SLIDE_STEPS; i++)); do
        progress=$((i * 1000 / SLIDE_STEPS))
        eased=$((1000 - (1000 - progress) * (1000 - progress) * (1000 - progress) / 1000000))
        frame_y=$((from_y + delta * eased / 1000))
        dispatch "hl.dsp.window.move({ window = 'address:$addr', x = $x, y = $frame_y, relative = false })"
        sleep "$SLIDE_DELAY"
    done
    dispatch "hl.dsp.window.move({ window = 'address:$addr', x = $x, y = $to_y, relative = false })"
}

find_terminal() {
    local clients addr
    clients=$(hyprctl clients -j 2>/dev/null || echo "[]")
    if [[ -s /tmp/dropdown_terminal_addr ]]; then
        addr=$(cut -d' ' -f1 /tmp/dropdown_terminal_addr)
        if jq -e --arg a "$addr" 'any(.[]; .address == $a and ((.class // "" | ascii_downcase) == "kitty-dropterm" or (.class // "" | ascii_downcase) == "kitty"))' <<<"$clients" >/dev/null 2>&1; then
            printf '%s' "$addr"
            return 0
        fi
    fi
    jq -r 'map(select((.class // "" | ascii_downcase) == "kitty-dropterm")) | sort_by(.focusHistoryID) | last | .address // empty' <<<"$clients"
}

active_ws=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty' || true)
monitor=$(hyprctl monitors -j 2>/dev/null | jq -c 'first(.[] | select(.focused == true))' || true)
[[ -n "$active_ws" && -n "$monitor" && "$monitor" != "null" ]] || { echo 'Không đọc được workspace/monitor đang dùng.' >&2; exit 0; }

read -r mon_x mon_y mon_w mon_h mon_scale mon_name < <(jq -r '[.x,.y,.width,.height,.scale,.name] | @tsv' <<<"$monitor")
read -r x y width height < <(awk -v x="$mon_x" -v y="$mon_y" -v w="$mon_w" -v h="$mon_h" -v s="$mon_scale" 'BEGIN { if (s <= 0) s=1; w=int(w/s); h=int(h/s); W=int(w*.65); H=int(h*.65); printf "%d %d %d %d\n", int(x+(w-W)/2), int(y+h*.10), W, H }')
start_y=$((y - height - 50))

LAUNCH_CMD="$TERMINAL"
if [[ "$TERMINAL" == "kitty" ]]; then
    LAUNCH_CMD="kitty --class kitty-dropterm"
fi

addr=$(find_terminal || true)
if [[ -z "$addr" ]]; then
    log "Starting $LAUNCH_CMD silently in hidden scratchpad"
    dispatch "hl.dsp.exec_cmd('$LAUNCH_CMD', { workspace = 'special:scratchpad silent', float = true, size = '$width $height', move = '$x $start_y', no_anim = true })"
    for _ in {1..40}; do
        sleep 0.05
        addr=$(find_terminal || true)
        [[ -n "$addr" ]] && break
    done
    [[ -n "$addr" ]] || { echo 'Terminal chưa xuất hiện sau 2 giây.' >&2; exit 0; }
    printf '%s %s\n' "$addr" "$mon_name" > /tmp/dropdown_terminal_addr
fi

client=$(hyprctl clients -j 2>/dev/null | jq -c --arg a "$addr" '.[] | select(.address == $a)' || true)
[[ -n "$client" ]] || { rm -f /tmp/dropdown_terminal_addr; exit 0; }
ws_name=$(jq -r '.workspace.name // ""' <<<"$client")
window="address:$addr"

if [[ "$ws_name" == "special:scratchpad" ]]; then
    log "Showing Kitty on workspace $active_ws"
    dispatch "hl.dsp.window.resize({ window = '$window', x = $width, y = $height, relative = false })"
    dispatch "hl.dsp.window.move({ window = '$window', x = $x, y = $start_y, relative = false })"
    dispatch "hl.dsp.window.move({ window = '$window', workspace = '$active_ws', follow = true })"
    dispatch "hl.dsp.window.pin({ window = '$window', action = 'on' })"
    slide_window "$addr" "$x" "$start_y" "$y"
else
    log 'Hiding Kitty in the scratchpad'
    geometry=$(hyprctl clients -j 2>/dev/null | jq -r --arg a "$addr" '.[] | select(.address == $a) | "\(.at[0]) \(.at[1]) \(.size[1])"')
    read -r current_x current_y current_height <<<"$geometry"
    end_y=$((current_y - current_height - 50))
    slide_window "$addr" "$current_x" "$current_y" "$end_y"
    dispatch "hl.dsp.window.pin({ window = '$window', action = 'off' })"
    dispatch "hl.dsp.window.move({ window = '$window', workspace = 'special:scratchpad', follow = false })"
fi
printf '%s %s\n' "$addr" "$mon_name" > /tmp/dropdown_terminal_addr
