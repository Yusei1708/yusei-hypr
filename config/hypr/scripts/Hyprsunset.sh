#!/usr/bin/env bash
set -euo pipefail

# Hyprsunset toggle + Waybar status helper
# Phase 1: manual toggle only (no scheduling)
# Icons:
# - Off: bright sun
# - On: sunset icon if available, otherwise a blue sun
#
# Customize via env vars:
#   HYPRSUNSET_TEMP   default 4500 (K)
#   HYPRSUNSET_ICON_MODE  sunset|blue  (default: sunset)

STATE_FILE="$HOME/.cache/.hyprsunset_state"
TARGET_TEMP="${HYPRSUNSET_TEMP:-4500}"
ICON_MODE="${HYPRSUNSET_ICON_MODE:-sunset}"

ensure_state() {
  [[ -f "$STATE_FILE" ]] || echo "off" > "$STATE_FILE"
}

# Render icons using pango markup to allow colorization
icon_off() {
  # universally available sun symbol
  printf "☀"
}

icon_on() {
  case "$ICON_MODE" in
    sunset)
      # sunset emoji (falls back to tofu if no emoji font)
      printf "🌇"
      ;;
    blue)
      # no color in text; rely on CSS .on to style if desired
      printf "☀"
      ;;
    *)
      printf "☀"
      ;;
  esac
}

cmd_toggle() {
  ensure_state

  if ! command -v hyprsunset >/dev/null 2>&1; then
    echo off > "$STATE_FILE"
    notify-send -u normal "Hyprsunset: Not Installed" "hyprsunset is not installed" || true
    return 1
  fi

  state="$(cat "$STATE_FILE" || echo off)"

  # Always stop any running hyprsunset first to avoid CTM manager conflicts
  if pgrep -x hyprsunset >/dev/null 2>&1; then
    pkill -x hyprsunset || true
    # give it a moment to release the CTM manager
    sleep 0.2
  fi

  if [[ "$state" == "on" ]]; then
    # Turning OFF: set identity and exit
    nohup hyprsunset -i >/dev/null 2>&1 &
    # if hyprsunset persists, stop it shortly after applying identity
    sleep 0.3 && pkill -x hyprsunset || true
    echo off > "$STATE_FILE"
    notify-send -u low "Hyprsunset: Disabled" || true
  else
    # Turning ON: start hyprsunset at target temp in background
    nohup hyprsunset -t "$TARGET_TEMP" >/dev/null 2>&1 &
    echo on > "$STATE_FILE"
    notify-send -u low "Hyprsunset: Enabled" "${TARGET_TEMP}K" || true
  fi
}

cmd_status() {
  ensure_state
  # Prefer live process detection; fall back to state file (unless binary missing)
  if ! command -v hyprsunset >/dev/null 2>&1; then
    onoff="off"
    tip="Night light unavailable (hyprsunset not installed)"
  elif pgrep -x hyprsunset >/dev/null 2>&1; then
    onoff="on"
    tip="Night light on @ ${TARGET_TEMP}K"
  else
    onoff="$(cat "$STATE_FILE" || echo off)"
    if [[ "$onoff" == "on" ]]; then
      tip="Night light on @ ${TARGET_TEMP}K"
    else
      tip="Night light off"
    fi
  fi

  if [[ "$onoff" == "on" ]]; then
    txt="<span size='18pt'>$(icon_on)</span>"
    cls="on"
  else
    txt="<span size='16pt'>$(icon_off)</span>"
    cls="off"
  fi
  printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$txt" "$cls" "$tip"
}

cmd_init() {
  ensure_state
  state="$(cat "$STATE_FILE" || echo off)"

  if [[ "$state" == "on" ]]; then
    if command -v hyprsunset >/dev/null 2>&1; then
      nohup hyprsunset -t "$TARGET_TEMP" >/dev/null 2>&1 &
    else
      echo off > "$STATE_FILE"
    fi
  fi
}

case "${1:-}" in
  toggle) cmd_toggle ;;
  status) cmd_status ;;
  init) cmd_init ;;
  *) echo "usage: $0 [toggle|status|init]" >&2; exit 2 ;;
 esac
