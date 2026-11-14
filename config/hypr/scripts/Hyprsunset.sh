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

STATE_FILE="${HYPRSUNSET_STATE_FILE:-$HOME/.cache/.hyprsunset_state}"
TARGET_TEMP="${HYPRSUNSET_TEMP:-4500}"
if [[ ! "$TARGET_TEMP" =~ ^[0-9]+$ ]] || (( 10#$TARGET_TEMP < 1000 || 10#$TARGET_TEMP > 25000 )); then
  TARGET_TEMP="4500"
fi
ICON_MODE="${HYPRSUNSET_ICON_MODE:-sunset}"

runtime_dir() {
  local dir="${XDG_RUNTIME_DIR:-/tmp}"
  if [[ -d "$dir" && -w "$dir" ]]; then
    printf '%s' "$dir"
  else
    printf '%s' "/tmp"
  fi
}

RUNTIME_LOG="$(runtime_dir)/hyprsunset-${UID:-$(id -u)}.log"

ensure_state() {
  mkdir -p "$(dirname "$STATE_FILE")"
  [[ -f "$STATE_FILE" ]] || echo "off" > "$STATE_FILE"
}

is_running() {
  pgrep -x hyprsunset >/dev/null 2>&1
}

refresh_waybar() {
  pkill -x -RTMIN+8 waybar >/dev/null 2>&1 || true
}

acquire_lock() {
  command -v flock >/dev/null 2>&1 || return 0
  local lock_file
  lock_file="$(runtime_dir)/hyprsunset-${UID:-$(id -u)}.lock"
  if exec 9>"$lock_file" 2>/dev/null; then
    flock -w 2 9 || return 1
  fi
  return 0
}

release_lock() {
  flock -u 9 2>/dev/null || true
  exec 9>&- 2>/dev/null || true
}

stop_hyprsunset() {
  if is_running; then
    pkill -x hyprsunset >/dev/null 2>&1 || true
    local i=0
    while is_running && [[ $i -lt 20 ]]; do
      sleep 0.05
      i=$((i + 1))
    done
    if is_running; then
      pkill -9 -x hyprsunset >/dev/null 2>&1 || true
      sleep 0.05
    fi
  fi
}

start_hyprsunset() {
  local log_target="$RUNTIME_LOG"
  if ! { : > "$log_target"; } 2>/dev/null; then
    log_target="/dev/null"
  fi
  local pid=""
  nohup hyprsunset -t "$TARGET_TEMP" >"$log_target" 2>&1 9>&- &
  pid=$!
  sleep 0.2
  if kill -0 "$pid" 2>/dev/null || is_running; then
    return 0
  fi
  wait "$pid" 2>/dev/null || true
  return 1
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
    refresh_waybar
    notify-send -u normal "Hyprsunset: Not Installed" "hyprsunset is not installed. Run: sudo pacman -S --needed hyprsunset" || true
    return 1
  fi

  acquire_lock || return 1
  trap release_lock EXIT

  local was_on=false
  if is_running; then
    was_on=true
  fi

  # Always stop any running hyprsunset first to avoid CTM manager conflicts
  stop_hyprsunset

  if [[ "$was_on" == "true" ]]; then
    # Turning OFF: briefly apply identity matrix, then terminate cleanly
    nohup hyprsunset -i >/dev/null 2>&1 9>&- &
    sleep 0.25
    stop_hyprsunset
    echo off > "$STATE_FILE"
    refresh_waybar
    release_lock
    notify-send -u low "Hyprsunset: Disabled" || true
  else
    # Turning ON: start hyprsunset at target temp and verify it stayed active
    if start_hyprsunset; then
      echo on > "$STATE_FILE"
      refresh_waybar
      release_lock
      notify-send -u low "Hyprsunset: Enabled" "${TARGET_TEMP}K" || true
    else
      local err_line=""
      if [[ -s "$RUNTIME_LOG" ]]; then
        err_line="$(head -n 1 "$RUNTIME_LOG" 2>/dev/null | tr -d '\r' | cut -c 1-140 || true)"
      fi
      echo off > "$STATE_FILE"
      refresh_waybar
      release_lock
      notify-send -u normal "Hyprsunset: Failed" "${err_line:-Failed to start hyprsunset (${TARGET_TEMP}K)}" || true
      return 1
    fi
  fi
}

cmd_status() {
  ensure_state
  local onoff="off"
  local tip="Night light off"

  if ! command -v hyprsunset >/dev/null 2>&1; then
    onoff="off"
    tip="Night light unavailable (hyprsunset not installed)"
  elif is_running; then
    onoff="on"
    tip="Night light on @ ${TARGET_TEMP}K"
  else
    onoff="off"
    tip="Night light off"
  fi

  if [[ "$onoff" == "on" ]]; then
    local icon_size="115%"
    [[ "$ICON_MODE" == "sunset" ]] && icon_size="80%"
    txt="<span size='${icon_size}'>$(icon_on)</span>"
    cls="on"
  else
    txt="<span size='115%'>$(icon_off)</span>"
    cls="off"
  fi
  printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$txt" "$cls" "$tip"
}

cmd_init() {
  ensure_state
  local state
  state="$(cat "$STATE_FILE" 2>/dev/null || echo off)"

  if [[ "$state" == "on" ]]; then
    if ! command -v hyprsunset >/dev/null 2>&1; then
      echo off > "$STATE_FILE"
      refresh_waybar
      return 0
    fi
    acquire_lock || return 0
    trap release_lock EXIT
    if ! is_running; then
      if ! start_hyprsunset; then
        echo off > "$STATE_FILE"
      fi
    fi
    refresh_waybar
    release_lock
  fi
}

case "${1:-}" in
  toggle) cmd_toggle ;;
  status) cmd_status ;;
  init) cmd_init ;;
  *) echo "usage: $0 [toggle|status|init]" >&2; exit 2 ;;
esac
