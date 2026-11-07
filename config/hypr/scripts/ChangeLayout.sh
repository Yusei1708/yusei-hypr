#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Layout Switcher (Dwindle <-> Master)
# Dual-Compatible: Hyprland 0.57+ Lua API & Legacy hyprctl keyword
# ==============================================================================

set -euo pipefail

notif="$HOME/.config/swaync/images/ja.png"
layout=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str // empty' || true)
if [[ -z "$layout" || "$layout" == "null" ]]; then
    layout=$(hyprctl getoption general:layout 2>/dev/null | awk 'NR==1 {print $2}' || echo "dwindle")
fi

set_layout() {
    local target="$1"
    if ! hyprctl eval "hl.config({ general = { layout = '$target' } })" >/dev/null 2>&1; then
        hyprctl keyword general:layout "$target" >/dev/null 2>&1 || true
    fi
}

set_bind() {
    local key=$1 dispatcher=$2
    if ! hyprctl eval "hl.unbind('SUPER + $key')" >/dev/null 2>&1; then
        hyprctl unbind "SUPER, $key" >/dev/null 2>&1 || true
    fi
    if ! hyprctl eval "hl.bind('SUPER + $key', $dispatcher)" >/dev/null 2>&1; then
        :
    fi
}

set_unbind() {
    local key=$1
    if ! hyprctl eval "hl.unbind('SUPER + $key')" >/dev/null 2>&1; then
        hyprctl unbind "SUPER, $key" >/dev/null 2>&1 || true
    fi
}

# If init is requested on startup or config reload:
# Configure bindings silently for the active layout without switching or sending notifications!
if [[ "${1:-}" == "init" ]]; then
    case "$layout" in
        master)
            set_bind J "hl.dsp.layout('cyclenext')"
            set_bind K "hl.dsp.layout('cycleprev')"
            set_unbind O
            ;;
        dwindle|*)
            set_bind J 'hl.dsp.window.cycle_next()'
            set_bind K 'hl.dsp.window.cycle_next({ next = false })'
            hyprctl eval "hl.unbind('SUPER + O')" >/dev/null 2>&1 || hyprctl unbind "SUPER, O" >/dev/null 2>&1 || true
            hyprctl eval "hl.bind('SUPER + O', hl.dsp.layout('togglesplit'))" >/dev/null 2>&1 || true
            ;;
    esac
    exit 0
fi

# Explicit toggle requested by user (Super + Alt + L)
case "$layout" in
    master)
        set_layout dwindle
        set_bind J 'hl.dsp.window.cycle_next()'
        set_bind K 'hl.dsp.window.cycle_next({ next = false })'
        hyprctl eval "hl.unbind('SUPER + O')" >/dev/null 2>&1 || hyprctl unbind "SUPER, O" >/dev/null 2>&1 || true
        hyprctl eval "hl.bind('SUPER + O', hl.dsp.layout('togglesplit'))" >/dev/null 2>&1 || true
        notify-send -e -u low -i "$notif" " Dwindle Layout" 2>/dev/null || true
        ;;
    dwindle|*)
        set_layout master
        set_bind J "hl.dsp.layout('cyclenext')"
        set_bind K "hl.dsp.layout('cycleprev')"
        set_unbind O
        notify-send -e -u low -i "$notif" " Master Layout" 2>/dev/null || true
        ;;
esac
