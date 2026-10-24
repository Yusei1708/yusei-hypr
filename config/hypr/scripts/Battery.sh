#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Battery Status & Telemetry Script (Battery.sh)
# Architecture: Universal Sysfs Power Supply Reader | Nerd Font Iconography
# ==============================================================================

set -euo pipefail

get_icon() {
  local capacity="$1"
  local status="$2"

  if [[ "$status" == "Charging" ]]; then
    echo "󰂄"
  elif [[ "$capacity" -ge 90 ]]; then
    echo "󰁹"
  elif [[ "$capacity" -ge 60 ]]; then
    echo "󰁿"
  elif [[ "$capacity" -ge 30 ]]; then
    echo "󰁼"
  elif [[ "$capacity" -ge 15 ]]; then
    echo "󰁺"
  else
    echo "󰂎"
  fi
}

found=0
for i in {0..3}; do
  bat_path="/sys/class/power_supply/BAT$i"
  if [[ -f "$bat_path/capacity" ]] && [[ -f "$bat_path/status" ]]; then
    status=$(cat "$bat_path/status" 2>/dev/null || echo "Unknown")
    capacity=$(cat "$bat_path/capacity" 2>/dev/null || echo "0")
    icon=$(get_icon "$capacity" "$status")
    echo "$icon $capacity% ($status)"
    found=1
    break
  fi
done

if [[ "$found" -eq 0 ]]; then
  echo "󰚥 AC Connected (No Battery)"
fi

