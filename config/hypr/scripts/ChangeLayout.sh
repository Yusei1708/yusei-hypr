#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Dynamic Tiling Layout Engine Switcher (ChangeLayout.sh)
# Architecture: Hyprland IPC Keyword Controller (Dwindle <-> Master)
# Supported flags: init, -h, --help
# ==============================================================================

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $(basename "$0") [init]"
    echo "Toggles between Dwindle and Master layouts and rebinds navigation keys dynamically."
    exit 0
fi

notif="$HOME/.config/swaync/images/ja.png"


LAYOUT=$(hyprctl -j getoption general:layout | jq '.str' | sed 's/"//g')

# Reverse layout value to reuse toggle logic. So layouts don't get swapped initially.
if [ "$1" = "init" ]; then
  if [ "$LAYOUT" = "master" ]; then
    LAYOUT="dwindle"
  else
    LAYOUT="master"
  fi
fi

case $LAYOUT in
"master")
  hyprctl keyword general:layout dwindle
  hyprctl keyword unbind SUPER,J
  hyprctl keyword unbind SUPER,K
  hyprctl keyword bind SUPER,J,cyclenext
  hyprctl keyword bind SUPER,K,cyclenext,prev
  hyprctl keyword bind SUPER,O,togglesplit
  notify-send -e -u low -i "$notif" " Dwindle Layout"
  ;;
"dwindle")
  hyprctl keyword general:layout master
  hyprctl keyword unbind SUPER,J
  hyprctl keyword unbind SUPER,K
  hyprctl keyword unbind SUPER,O
  hyprctl keyword bind SUPER,J,layoutmsg,cyclenext
  hyprctl keyword bind SUPER,K,layoutmsg,cycleprev
  notify-send -e -u low -i "$notif" " Master Layout"
  ;;
*) ;;

esac
