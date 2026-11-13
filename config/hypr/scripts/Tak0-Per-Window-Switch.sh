#!/usr/bin/env bash
##################################################################
#                                                                #
#                                                                #
#                  TAK_0'S Per-Window-Switch                     #
#                                                                #
#                                                                #
#                                                                #
#  Just a little script that I made to switch keyboard layouts   #
#       per-window instead of global switching for the more      #
#                 smooth and comfortable workflow.               #
#                                                                #
##################################################################
# This is for changing kb_layouts. Set kb_layout in hyprland.lua or config files.

MAP_FILE="$HOME/.cache/kb_layout_per_window"
ICON="$HOME/.config/swaync/images/ja.png"
SCRIPT_NAME="$(basename "$0")"
PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/tak0-per-window.pid"

# Ensure map file directory and file exist
mkdir -p "$(dirname "$MAP_FILE")"
touch "$MAP_FILE"

# Read layouts via hyprctl first, then hyprland.lua, then .conf files, fallback to "us"
raw_layouts=""
if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  raw_layouts="$(hyprctl getoption input:kb_layout -j 2>/dev/null | jq -r '.str // empty' 2>/dev/null || true)"
fi

if [[ -z "$raw_layouts" && -f "$HOME/.config/hypr/hyprland.lua" ]]; then
  raw_layouts="$(grep -E '^[[:space:]]*kb_layout[[:space:]]*=' "$HOME/.config/hypr/hyprland.lua" 2>/dev/null \
    | head -n1 \
    | sed -E 's/^[^=]*=//; s/--.*$//; s/["'"'"'[:space:]]//g; s/,+$//' || true)"
fi

if [[ -z "$raw_layouts" ]]; then
  for f in "$HOME/.config/hypr/UserConfigs/UserSettings.conf" \
           "$HOME/.config/hypr/hyprland.conf" \
           "$HOME/.config/hypr/configs/SystemSettings.conf" \
           "$HOME/.config/hypr/SystemSettings.conf" \
           "$HOME/.config/hypr/env.conf"; do
    if [[ -f "$f" ]]; then
      raw_layouts="$(grep -E '^[[:space:]]*kb_layout[[:space:]]*=' "$f" 2>/dev/null \
        | head -n1 \
        | sed -E 's/^[^=]*=//; s/#.*$//; s/[[:space:]]//g' || true)"
      [[ -n "$raw_layouts" ]] && break
    fi
  done
fi

kb_layouts=()
if [[ -n "$raw_layouts" ]]; then
  IFS=',' read -ra _parsed_layouts <<< "${raw_layouts//[[:space:]]/}"
  for _layout in "${_parsed_layouts[@]}"; do
    [[ -n "$_layout" ]] && kb_layouts+=("$_layout")
  done
fi
if (( ${#kb_layouts[@]} == 0 )); then
  kb_layouts=("us")
fi
count=${#kb_layouts[@]}

# Get current active window ID
get_win() {
  hyprctl activewindow -j 2>/dev/null | jq -r '.address // .id // empty' 2>/dev/null || true
}

# Get available keyboards
get_keyboards() {
  hyprctl devices -j 2>/dev/null | jq -r '.keyboards[].name // empty' 2>/dev/null || true
}

# Save window-specific layout
save_map() {
  local W=$1 L=$2
  grep -v "^${W}:" "$MAP_FILE" > "$MAP_FILE.tmp" 2>/dev/null || true
  echo "${W}:${L}" >> "$MAP_FILE.tmp"
  mv "$MAP_FILE.tmp" "$MAP_FILE"
}

# Load layout for window (fallback to default)
load_map() {
  local W=$1
  local E
  E=$(grep "^${W}:" "$MAP_FILE" 2>/dev/null | head -n1 || true)
  [[ -n "$E" ]] && echo "${E#*:}" || echo "${kb_layouts[0]}"
}

# Switch layout for all keyboards to layout index
do_switch() {
  local IDX=$1
  while IFS= read -r kb; do
    [[ -n "$kb" ]] && hyprctl switchxkblayout "$kb" "$IDX" >/dev/null 2>&1 || true
  done < <(get_keyboards)
}

# Toggle layout for current window only
cmd_toggle() {
  local W=$(get_win)
  [[ -z "$W" || "$W" == "null" ]] && return
  local CUR=$(load_map "$W")
  local i=0 NEXT
  for idx in "${!kb_layouts[@]}"; do
    if [[ "${kb_layouts[idx]}" == "$CUR" ]]; then
      i=$idx
      break
    fi
  done
  NEXT=$(( (i+1) % count ))
  do_switch "$NEXT"
  save_map "$W" "${kb_layouts[NEXT]}"
  notify-send -u low -i "$ICON" "kb_layout: ${kb_layouts[NEXT]}"
}

# Restore layout on focus
cmd_restore() {
  local W=$(get_win)
  [[ -z "$W" || "$W" == "null" ]] && return
  local LAY=$(load_map "$W")
  for idx in "${!kb_layouts[@]}"; do
    if [[ "${kb_layouts[idx]}" == "$LAY" ]]; then
      do_switch "$idx"
      break
    fi
  done
}

# Verify singleton listener process via PID file + /proc/$pid/cmdline
is_listener_running() {
  local pid="" cmdline=""
  if [[ -f "$PID_FILE" ]]; then
    pid="$(tr -d '[:space:]' < "$PID_FILE" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ && "$pid" != "$$" ]] && kill -0 "$pid" 2>/dev/null; then
      cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
      if [[ "$cmdline" == *"$SCRIPT_NAME"* && "$cmdline" == *"--listener"* ]]; then
        return 0
      fi
    fi
  fi
  return 1
}

# Listen to focus events and restore window-specific layouts
subscribe() {
  local SOCKET2="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
  [[ -S "$SOCKET2" ]] || { echo "Error: Hyprland socket not found." >&2; exit 1; }

  socat -u UNIX-CONNECT:"$SOCKET2" - | while read -r line; do
    [[ "$line" =~ ^activewindow ]] && cmd_restore
  done
}

# CLI
case "${1:-}" in
  --listener)
    if is_listener_running; then
      exit 0
    fi
    if command -v flock >/dev/null 2>&1; then
      exec 9>"${PID_FILE}.lock"
      flock -n 9 || exit 0
    fi
    printf '%s\n' "$$" > "$PID_FILE"
    trap '[[ "$(tr -d "[:space:]" < "$PID_FILE" 2>/dev/null || true)" == "$$" ]] && rm -f "$PID_FILE"' EXIT INT TERM
    subscribe
    ;;
  toggle|"")
    if ! is_listener_running; then
      setsid "$0" --listener >/dev/null 2>&1 &
    fi
    cmd_toggle
    ;;
  *)
    echo "Usage: $SCRIPT_NAME [toggle|--listener]" >&2
    exit 1
    ;;
esac
