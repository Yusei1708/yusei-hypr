#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Core Power Optimizer Engine (scripts/power-optimizer.sh)
# ==============================================================================
# Comprehensive battery and performance management system for laptops:
# - Manages 3 energy profiles: eco (power-saver), balanced, turbo (performance)
#   via powerprofilesctl or sysfs scaling governors.
# - Automatically detects monitor parameters via hyprctl monitors -j (internal panel prioritized).
# - Dynamically adjusts refresh rate (down to 60Hz on battery / eco,
#   up to maximum 120/144/165Hz on AC / turbo).
# - Supports background daemon mode listening to AC plug/unplug events.
# - Interactive quick power menu via Rofi (--menu).
# - CLI flags: --status, --json, --notify, --menu, --set-profile=<eco|balanced|turbo>,
#              --toggle-hz, --auto, --daemon, --dry-run, -h/--help.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ANSI color codes
CYAN='\033[0;36m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# Defaults and State Paths
DRY_RUN="${DRY_RUN:-false}"
OUTPUT_JSON=false
NOTIFY_STATUS=false
ACTION=""
TARGET_PROFILE=""
SYSFS_POWER_DIR="${SYSFS_POWER_DIR:-/sys/class/power_supply}"
SYSFS_CPU_DIR="${SYSFS_CPU_DIR:-/sys/devices/system/cpu}"
CONFIG_FILE="${POWER_CONFIG_FILE:-$HOME/.config/hypr/power.json}"
STATE_FILE="${POWER_STATE_FILE:-$HOME/.config/hypr/.power-optimizer.state}"
PID_FILE="${POWER_PID_FILE:-/tmp/yusei-power-optimizer.pid}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

yusei-hypr Core Power Optimizer & Dynamic Refresh Rate Engine.

Options:
  --status                    Display current battery, profile, and screen refresh rate status
  --json                      Format status output as JSON (used with --status)
  --notify                    Send desktop notification with power and battery status
  --menu                      Open interactive Rofi power & refresh rate settings menu
  --set-profile=<profile>     Set power profile: eco, balanced, or turbo
  --cycle-profile, --next-profile  Cycle to next power profile (eco -> balanced -> turbo -> eco)
  --toggle-hz                 Toggle display refresh rate between 60Hz and max native rate
  --auto                      Automatically optimize profile & refresh rate based on power source
  --daemon                    Run as a background listener responding to AC plug/unplug events
  --dry-run                   Simulate actions without modifying hardware or display settings
  -h, --help                  Display this help message and exit

Profiles:
  eco       Power-saver profile: energy-saving CPU governor & 60Hz screen rate
  balanced  Balanced profile: default power and standard maximum refresh rate
  turbo     High-performance profile: maximum CPU clock & highest screen refresh rate

Examples:
  $(basename "$0") --status
  $(basename "$0") --status --json
  $(basename "$0") --status --notify
  $(basename "$0") --menu
  $(basename "$0") --set-profile=eco
  $(basename "$0") --toggle-hz
  $(basename "$0") --auto
  $(basename "$0") --daemon
  $(basename "$0") --dry-run --auto
EOF
}

# ------------------------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --status)
            ACTION="status"
            shift
            ;;
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --notify)
            NOTIFY_STATUS=true
            shift
            ;;
        --menu)
            ACTION="menu"
            shift
            ;;
        --set-profile=*)
            ACTION="set-profile"
            TARGET_PROFILE="${1#*=}"
            shift
            ;;
        --set-profile)
            ACTION="set-profile"
            if [[ -n "${2:-}" && "${2:-}" != --* ]]; then
                TARGET_PROFILE="$2"
                shift 2
            else
                echo -e "${RED}[ERROR] --set-profile requires a value: eco, balanced, or turbo.${NC}" >&2
                exit 1
            fi
            ;;
        --cycle-profile|--next-profile)
            ACTION="cycle-profile"
            shift
            ;;
        --toggle-hz)
            ACTION="toggle-hz"
            shift
            ;;
        --auto)
            ACTION="auto"
            shift
            ;;
        --daemon)
            ACTION="daemon"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR] Unknown option: $1${NC}" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$ACTION" ]]; then
    ACTION="status"
fi

# ------------------------------------------------------------------------------
# Helper Functions: State and Config Management
# ------------------------------------------------------------------------------
get_config_power_daemon() {
    # 1. Environment variable override
    if [[ -n "${YUSEI_POWER_DAEMON:-}" ]]; then
        if [[ "$YUSEI_POWER_DAEMON" == "0" || "$YUSEI_POWER_DAEMON" == "false" ]]; then
            echo "false"
            return
        elif [[ "$YUSEI_POWER_DAEMON" == "1" || "$YUSEI_POWER_DAEMON" == "true" ]]; then
            echo "true"
            return
        fi
    fi

    # 2. Config file
    if [[ -f "$CONFIG_FILE" ]]; then
        local val
        val="$(jq -r '.power_daemon // empty' "$CONFIG_FILE" 2>/dev/null || true)"
        if [[ "$val" == "true" || "$val" == "false" ]]; then
            echo "$val"
            return
        fi
    fi

    # 3. Check userprefs.conf
    local userprefs="${TARGET_USERPREFS:-$HOME/.config/hypr/userprefs.conf}"
    if [[ -f "$userprefs" ]]; then
        local up_val
        up_val="$(grep -E '^[[:space:]]*env[[:space:]]*=[[:space:]]*YUSEI_POWER_DAEMON' "$userprefs" | tail -n1 | awk -F',' '{print $2}' | sed -e 's/#.*//' | tr -d ' \t\r\n' || true)"
        if [[ "$up_val" == "0" || "$up_val" == "false" ]]; then
            echo "false"
            return
        elif [[ "$up_val" == "1" || "$up_val" == "true" ]]; then
            echo "true"
            return
        fi
    fi

    # Default: true on laptops
    echo "true"
}

get_config_auto_60hz() {
    # 1. Environment variable override
    if [[ -n "${YUSEI_AUTO_60HZ:-}" ]]; then
        if [[ "$YUSEI_AUTO_60HZ" == "1" || "$YUSEI_AUTO_60HZ" == "true" ]]; then
            echo "true"
            return
        else
            echo "false"
            return
        fi
    fi

    # 2. Config file
    if [[ -f "$CONFIG_FILE" ]]; then
        local val
        val="$(jq -r '.auto_60hz // empty' "$CONFIG_FILE" 2>/dev/null || true)"
        if [[ "$val" == "true" || "$val" == "false" ]]; then
            echo "$val"
            return
        fi
    fi

    # 3. Check userprefs.conf
    local userprefs="${TARGET_USERPREFS:-$HOME/.config/hypr/userprefs.conf}"
    if [[ -f "$userprefs" ]]; then
        local up_val
        up_val="$(grep -E '^[[:space:]]*env[[:space:]]*=[[:space:]]*YUSEI_AUTO_60HZ' "$userprefs" | tail -n1 | awk -F',' '{print $2}' | sed -e 's/#.*//' | tr -d ' \t\r\n' || true)"
        if [[ "$up_val" == "0" || "$up_val" == "false" ]]; then
            echo "false"
            return
        elif [[ "$up_val" == "1" || "$up_val" == "true" ]]; then
            echo "true"
            return
        fi
    fi

    # Default: true on laptops
    echo "true"
}

get_config_ac_profile() {
    # 1. Environment variable override
    if [[ -n "${YUSEI_AC_PROFILE:-}" ]]; then
        case "$YUSEI_AC_PROFILE" in
            eco|balanced|turbo) echo "$YUSEI_AC_PROFILE" ; return ;;
        esac
    fi

    # 2. Config file
    if [[ -f "$CONFIG_FILE" ]]; then
        local val
        val="$(jq -r '.ac_profile // empty' "$CONFIG_FILE" 2>/dev/null || true)"
        case "$val" in
            eco|balanced|turbo) echo "$val" ; return ;;
        esac
    fi

    # 3. Check userprefs.conf
    local userprefs="${TARGET_USERPREFS:-$HOME/.config/hypr/userprefs.conf}"
    if [[ -f "$userprefs" ]]; then
        local up_val
        up_val="$(grep -E '^[[:space:]]*env[[:space:]]*=[[:space:]]*YUSEI_AC_PROFILE' "$userprefs" | tail -n1 | awk -F',' '{print $2}' | sed -e 's/#.*//' | tr -d ' \t\r\n' || true)"
        case "$up_val" in
            eco|balanced|turbo) echo "$up_val" ; return ;;
        esac
    fi

    echo "balanced"
}

get_config_bat_profile() {
    # 1. Environment variable override
    if [[ -n "${YUSEI_BAT_PROFILE:-}" ]]; then
        case "$YUSEI_BAT_PROFILE" in
            eco|balanced|turbo) echo "$YUSEI_BAT_PROFILE" ; return ;;
        esac
    fi

    # 2. Config file
    if [[ -f "$CONFIG_FILE" ]]; then
        local val
        val="$(jq -r '.bat_profile // empty' "$CONFIG_FILE" 2>/dev/null || true)"
        case "$val" in
            eco|balanced|turbo) echo "$val" ; return ;;
        esac
    fi

    # 3. Check userprefs.conf
    local userprefs="${TARGET_USERPREFS:-$HOME/.config/hypr/userprefs.conf}"
    if [[ -f "$userprefs" ]]; then
        local up_val
        up_val="$(grep -E '^[[:space:]]*env[[:space:]]*=[[:space:]]*YUSEI_BAT_PROFILE' "$userprefs" | tail -n1 | awk -F',' '{print $2}' | sed -e 's/#.*//' | tr -d ' \t\r\n' || true)"
        case "$up_val" in
            eco|balanced|turbo) echo "$up_val" ; return ;;
        esac
    fi

    echo "eco"
}

get_cached_max_hz() {
    if [[ -f "$STATE_FILE" ]]; then
        jq -r '.max_hz // empty' "$STATE_FILE" 2>/dev/null || true
    fi
}

get_cached_current_hz() {
    if [[ -f "$STATE_FILE" ]]; then
        jq -r '.current_hz // empty' "$STATE_FILE" 2>/dev/null || true
    fi
}

save_state() {
    local key="$1"
    local value="$2"
    if [[ "$DRY_RUN" = "true" ]]; then
        return
    fi
    mkdir -p "$(dirname "$STATE_FILE")"
    local cur="{}"
    if [[ -f "$STATE_FILE" ]]; then
        cur="$(cat "$STATE_FILE" 2>/dev/null || true)"
        [[ -z "$cur" || "$cur" == "null" ]] && cur="{}"
    fi
    echo "$cur" | jq --arg k "$key" --arg v "$value" '.[$k] = $v' > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# ------------------------------------------------------------------------------
# Notification Helper
# ------------------------------------------------------------------------------
send_notification() {
    local title="$1"
    local message="$2"
    local icon="${3:-preferences-system-power}"

    if [[ "$DRY_RUN" = "true" ]]; then
        if [[ "$OUTPUT_JSON" = "false" ]]; then
            echo -e "${YELLOW}[DRY-RUN Notify] ${title} - ${message}${NC}"
        fi
        return
    fi

    if command -v notify-send >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-${DISPLAY:-}}" ]]; then
        notify-send -a "yusei-power" -i "$icon" -u normal "$title" "$message" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------------------
# Power & Battery Probing (Supports Multi-Battery & Modern USB-C/AC Supplies)
# ------------------------------------------------------------------------------
detect_power_status() {
    HAS_BATTERY=false
    AC_ONLINE=true
    BATTERY_PERCENT=100
    BATTERY_STATUS="AC Only"
    POWER_WATTS=0.0
    TIME_REMAINING="N/A"

    # Check AC / Mains power supply (supports multiple AC/USB-C PD adapters)
    local ac_found=false
    local any_ac_online=false
    for ac_path in "$SYSFS_POWER_DIR"/*; do
        [[ -d "$ac_path" ]] || continue
        local ptype=""
        if [[ -f "$ac_path/type" ]]; then
            ptype="$(cat "$ac_path/type" 2>/dev/null || true)"
        fi
        local bname="$(basename "$ac_path")"
        if [[ "$ptype" == "Mains" || "$ptype" == "USB"* || "$bname" == AC* || "$bname" == ADP* || "$bname" == Mains* ]]; then
            if [[ -f "$ac_path/online" ]]; then
                ac_found=true
                local val
                val="$(cat "$ac_path/online" 2>/dev/null || echo "0")"
                if [[ "$val" == "1" ]]; then
                    any_ac_online=true
                    break
                fi
            fi
        fi
    done

    if [[ "$ac_found" = "true" ]]; then
        AC_ONLINE="$any_ac_online"
    fi

    # Check Battery (supports multiple batteries: BAT0, BAT1, etc.)
    local bat_count=0
    local total_pct=0
    local total_energy_now=0
    local total_energy_full=0
    local total_charge_now=0
    local total_charge_full=0
    local total_microwatts=0
    local total_current_now=0
    local any_charging=false
    local any_discharging=false
    local all_full=true

    for bat_path in "$SYSFS_POWER_DIR"/BAT* "$SYSFS_POWER_DIR"/battery*; do
        if [[ -d "$bat_path" ]]; then
            HAS_BATTERY=true
            bat_count=$((bat_count + 1))

            local st="Unknown"
            if [[ -f "$bat_path/status" ]]; then
                st="$(cat "$bat_path/status" 2>/dev/null || echo "Unknown")"
            fi

            if [[ "$st" == "Charging" ]]; then
                any_charging=true
                all_full=false
            elif [[ "$st" == "Discharging" ]]; then
                any_discharging=true
                all_full=false
            elif [[ "$st" != "Full" ]]; then
                all_full=false
            fi

            if [[ -f "$bat_path/capacity" ]]; then
                local cap
                cap="$(cat "$bat_path/capacity" 2>/dev/null || echo "100")"
                total_pct=$((total_pct + cap))
            fi

            if [[ -f "$bat_path/energy_now" ]]; then
                local en
                en="$(cat "$bat_path/energy_now" 2>/dev/null || echo "0")"
                en="${en#-}"
                total_energy_now=$((total_energy_now + en))
            fi
            if [[ -f "$bat_path/energy_full" ]]; then
                local ef
                ef="$(cat "$bat_path/energy_full" 2>/dev/null || echo "0")"
                ef="${ef#-}"
                total_energy_full=$((total_energy_full + ef))
            fi

            if [[ -f "$bat_path/charge_now" ]]; then
                local cn
                cn="$(cat "$bat_path/charge_now" 2>/dev/null || echo "0")"
                cn="${cn#-}"
                total_charge_now=$((total_charge_now + cn))
            fi
            if [[ -f "$bat_path/charge_full" ]]; then
                local cf
                cf="$(cat "$bat_path/charge_full" 2>/dev/null || echo "0")"
                cf="${cf#-}"
                total_charge_full=$((total_charge_full + cf))
            fi

            # Power draw & Current (strip negative sign if reported by driver)
            if [[ -f "$bat_path/power_now" ]]; then
                local p_now
                p_now="$(cat "$bat_path/power_now" 2>/dev/null || echo "0")"
                p_now="${p_now#-}"
                total_microwatts=$((total_microwatts + p_now))
            elif [[ -f "$bat_path/current_now" && -f "$bat_path/voltage_now" ]]; then
                local c_now v_now
                c_now="$(cat "$bat_path/current_now" 2>/dev/null || echo "0")"
                v_now="$(cat "$bat_path/voltage_now" 2>/dev/null || echo "0")"
                c_now="${c_now#-}"
                v_now="${v_now#-}"
                local uW=$(( (c_now * v_now) / 1000000 ))
                total_microwatts=$((total_microwatts + uW))
            fi

            if [[ -f "$bat_path/current_now" ]]; then
                local cur_val
                cur_val="$(cat "$bat_path/current_now" 2>/dev/null || echo "0")"
                cur_val="${cur_val#-}"
                total_current_now=$((total_current_now + cur_val))
            fi
        fi
    done

    if [[ "$HAS_BATTERY" = "true" && "$bat_count" -gt 0 ]]; then
        # Consolidated Battery Status
        if [[ "$any_charging" = "true" ]]; then
            BATTERY_STATUS="Charging"
        elif [[ "$any_discharging" = "true" ]]; then
            BATTERY_STATUS="Discharging"
        elif [[ "$all_full" = "true" ]]; then
            BATTERY_STATUS="Full"
        else
            BATTERY_STATUS="Not Charging"
        fi

        # If any battery is charging, the laptop must be on AC power
        if [[ "$any_charging" = "true" ]]; then
            AC_ONLINE=true
        elif [[ "$ac_found" = "false" ]]; then
            if [[ "$BATTERY_STATUS" == "Full" ]]; then
                AC_ONLINE=true
            else
                AC_ONLINE=false
            fi
        fi

        # Compute percentage: preferred from energy or charge ratio if available
        if [[ "$total_energy_full" -gt 0 ]]; then
            BATTERY_PERCENT=$(( (total_energy_now * 100) / total_energy_full ))
        elif [[ "$total_charge_full" -gt 0 ]]; then
            BATTERY_PERCENT=$(( (total_charge_now * 100) / total_charge_full ))
        else
            BATTERY_PERCENT=$(( total_pct / bat_count ))
        fi

        # Power draw in Watts
        POWER_WATTS="$(awk -v p="$total_microwatts" 'BEGIN { printf "%.1f", p / 1000000 }' 2>/dev/null || echo "0.0")"

        # Estimate remaining time
        if [[ "$BATTERY_STATUS" == "Discharging" ]]; then
            if [[ "$total_energy_now" -gt 0 && "$total_microwatts" -gt 0 ]]; then
                local mins=$(( (total_energy_now * 60) / total_microwatts ))
                local h=$(( mins / 60 ))
                local m=$(( mins % 60 ))
                TIME_REMAINING="${h}h ${m}min"
            elif [[ "$total_charge_now" -gt 0 && "$total_current_now" -gt 0 ]]; then
                local mins=$(( (total_charge_now * 60) / total_current_now ))
                local h=$(( mins / 60 ))
                local m=$(( mins % 60 ))
                TIME_REMAINING="${h}h ${m}min"
            fi
        elif [[ "$BATTERY_STATUS" == "Charging" ]]; then
            local chg_mins=0
            if [[ "$total_energy_full" -gt "$total_energy_now" && "$total_microwatts" -gt 0 ]]; then
                chg_mins=$(( ((total_energy_full - total_energy_now) * 60) / total_microwatts ))
            elif [[ "$total_charge_full" -gt "$total_charge_now" && "$total_current_now" -gt 0 ]]; then
                chg_mins=$(( ((total_charge_full - total_charge_now) * 60) / total_current_now ))
            fi
            if [[ "$chg_mins" -gt 0 ]]; then
                local ch=$(( chg_mins / 60 ))
                local cm=$(( chg_mins % 60 ))
                TIME_REMAINING="Charging (${ch}h ${cm}min)"
            else
                TIME_REMAINING="Charging"
            fi
        elif [[ "$BATTERY_STATUS" == "Full" ]]; then
            TIME_REMAINING="Full (AC)"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Monitor Detection & Parse Logic (Safe Array Filtering for External & Internal Displays)
# ------------------------------------------------------------------------------
detect_monitor() {
    MONITOR_NAME="eDP-1"
    MONITOR_WIDTH=1920
    MONITOR_HEIGHT=1080
    MONITOR_X=0
    MONITOR_Y=0
    MONITOR_SCALE=1
    CURRENT_HZ=60
    MAX_HZ=60
    MIN_HZ=60

    local raw_json=""
    if [[ "${HYPRCTL_MONITORS_DATA:-}" == "none" || "${HYPRCTL_MONITORS_DATA:-}" == "[]" ]]; then
        raw_json=""
    elif [[ -n "${HYPRCTL_MONITORS_DATA:-}" ]]; then
        if [[ -f "$HYPRCTL_MONITORS_DATA" ]]; then
            raw_json="$(cat "$HYPRCTL_MONITORS_DATA")"
        else
            raw_json="$HYPRCTL_MONITORS_DATA"
        fi
    elif command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-${WAYLAND_DISPLAY:-}}" ]]; then
        raw_json="$(hyprctl monitors -j 2>/dev/null || true)"
    fi

    if [[ -n "$raw_json" && "$raw_json" != "[]" && "$raw_json" != "null" ]]; then
        # Parse using jq safely with array subselection
        local parsed
        parsed="$(echo "$raw_json" | jq -r '
            (([.[] | select(.name | test("^(eDP|LVDS|DSI)"))][0] // .[0])) as $mon |
            ($mon.width // 1920) as $w |
            ($mon.height // 1080) as $h |
            ([$mon.availableModes[]? | capture("(?<mw>\\d+)x(?<mh>\\d+)@(?<hz>[0-9.]+)Hz") | select(.mw == ($w|tostring) and .mh == ($h|tostring)) | .hz | tonumber | round] | sort) as $modes |
            {
              name: ($mon.name // "eDP-1"),
              width: $w,
              height: $h,
              x: ($mon.x // 0),
              y: ($mon.y // 0),
              scale: ($mon.scale // 1),
              current_hz: (($mon.refreshRate // 60) | round),
              max_hz: (if ($modes | length) > 0 then ($modes | max) else ([(($mon.refreshRate // 60) | round), 60] | max) end),
              min_hz: 60
            }
        ' 2>/dev/null || true)"

        if [[ -n "$parsed" && "$parsed" != "null" ]]; then
            MONITOR_NAME="$(echo "$parsed" | jq -r '.name')"
            MONITOR_WIDTH="$(echo "$parsed" | jq -r '.width')"
            MONITOR_HEIGHT="$(echo "$parsed" | jq -r '.height')"
            MONITOR_X="$(echo "$parsed" | jq -r '.x')"
            MONITOR_Y="$(echo "$parsed" | jq -r '.y')"
            MONITOR_SCALE="$(echo "$parsed" | jq -r '.scale')"
            CURRENT_HZ="$(echo "$parsed" | jq -r '.current_hz')"
            MAX_HZ="$(echo "$parsed" | jq -r '.max_hz')"
            MIN_HZ="$(echo "$parsed" | jq -r '.min_hz')"
        fi
    fi

    # Check cached current_hz in state file
    local cached_cur
    cached_cur="$(get_cached_current_hz)"
    if [[ -n "$cached_cur" && "$cached_cur" =~ ^[0-9]+$ ]]; then
        if [[ -z "$raw_json" || "$raw_json" == "[]" || "$raw_json" == "null" || "$DRY_RUN" = "true" ]]; then
            CURRENT_HZ="$cached_cur"
        fi
    fi

    # Check cached max_hz in state file
    local cached
    cached="$(get_cached_max_hz)"
    if [[ -n "$cached" && "$cached" =~ ^[0-9]+$ && "$cached" -gt "$MAX_HZ" ]]; then
        MAX_HZ="$cached"
    elif [[ "$MAX_HZ" -gt 60 ]]; then
        save_state "max_hz" "$MAX_HZ"
    fi
}

# ------------------------------------------------------------------------------
# Power Profile Probing & Switching
# ------------------------------------------------------------------------------
get_current_profile() {
    # In dry-run mode, prioritize state file to isolate simulations from host daemons
    if [[ "$DRY_RUN" = "true" && -f "$STATE_FILE" ]]; then
        local st
        st="$(jq -r '.profile // empty' "$STATE_FILE" 2>/dev/null || true)"
        case "$st" in
            eco|balanced|turbo) echo "$st" ; return ;;
        esac
    fi

    # 1. powerprofilesctl
    if command -v powerprofilesctl >/dev/null 2>&1; then
        local p
        p="$(powerprofilesctl get 2>/dev/null || true)"
        case "$p" in
            power-saver) echo "eco" ; return ;;
            balanced)    echo "balanced" ; return ;;
            performance) echo "turbo" ; return ;;
        esac
    fi

    # 2. State cache check if explicitly configured
    if [[ -f "$STATE_FILE" ]]; then
        local st
        st="$(jq -r '.profile // empty' "$STATE_FILE" 2>/dev/null || true)"
        case "$st" in
            eco|balanced|turbo) echo "$st" ; return ;;
        esac
    fi

    # 3. Sysfs energy_performance_preference check (modern Intel / AMD drivers)
    local epp_path=""
    if [[ -f "$SYSFS_CPU_DIR/cpu0/cpufreq/energy_performance_preference" ]]; then
        epp_path="$SYSFS_CPU_DIR/cpu0/cpufreq/energy_performance_preference"
    elif [[ -f "$SYSFS_CPU_DIR/cpufreq/policy0/energy_performance_preference" ]]; then
        epp_path="$SYSFS_CPU_DIR/cpufreq/policy0/energy_performance_preference"
    fi

    if [[ -n "$epp_path" ]]; then
        local epp
        epp="$(cat "$epp_path" 2>/dev/null || true)"
        case "$epp" in
            power)
                echo "eco"
                return
                ;;
            performance)
                echo "turbo"
                return
                ;;
            balance_performance|balance_power|default)
                echo "balanced"
                return
                ;;
        esac
    fi

    # 4. Sysfs scaling governor check
    if [[ -f "$SYSFS_CPU_DIR/cpu0/cpufreq/scaling_governor" ]]; then
        local gov
        gov="$(cat "$SYSFS_CPU_DIR/cpu0/cpufreq/scaling_governor" 2>/dev/null || true)"
        if [[ "$gov" == "performance" ]]; then
            echo "turbo"
            return
        elif [[ "$gov" == "powersave" ]]; then
            echo "balanced"
            return
        fi
    fi

    echo "balanced"
}

set_display_refresh_rate() {
    local target_hz="$1"
    detect_monitor

    if [[ "$CURRENT_HZ" -eq "$target_hz" ]]; then
        return
    fi

    local mon_rule="${MONITOR_NAME},${MONITOR_WIDTH}x${MONITOR_HEIGHT}@${target_hz},${MONITOR_X}x${MONITOR_Y},${MONITOR_SCALE}"

    if [[ "$DRY_RUN" = "true" ]]; then
        if [[ "$OUTPUT_JSON" = "false" ]]; then
            echo -e "${YELLOW}[DRY-RUN] hyprctl keyword monitor \"${mon_rule}\"${NC}"
        fi
    else
        if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-${WAYLAND_DISPLAY:-}}" ]]; then
            hyprctl keyword monitor "$mon_rule" >/dev/null 2>&1 || true
        fi
        CURRENT_HZ="$target_hz"
        save_state "current_hz" "$target_hz"
    fi
}

apply_power_profile() {
    local profile="$1"
    local auto_hz="${2:-true}"

    case "$profile" in
        eco)
            local ppd_target="power-saver"
            local sys_gov="powersave"
            local epp="power"
            local icon="battery-low"
            local title="Chế độ Tiết kiệm Pin (Eco)"
            local msg="Đã kích hoạt profile Eco. Giảm tiêu thụ năng lượng."
            ;;
        balanced)
            local ppd_target="balanced"
            local sys_gov="powersave"
            local epp="balance_performance"
            local icon="preferences-system-power"
            local title="Chế độ Cân bằng (Balanced)"
            local msg="Đã kích hoạt profile Balanced. Hiệu năng & tiêu thụ cân đối."
            ;;
        turbo)
            local ppd_target="performance"
            local sys_gov="performance"
            local epp="performance"
            local icon="battery-charging"
            local title="Chế độ Hiệu năng Cao (Turbo)"
            local msg="Đã kích hoạt profile Turbo. Xung nhịp và hiệu năng tối đa."
            ;;
        *)
            echo -e "${RED}[ERROR] Profile không hợp lệ: $profile (Chọn eco, balanced, hoặc turbo)${NC}" >&2
            exit 1
            ;;
    esac

    if [[ "$DRY_RUN" = "true" ]]; then
        if [[ "$OUTPUT_JSON" = "false" ]]; then
            echo -e "${YELLOW}[DRY-RUN] powerprofilesctl set ${ppd_target}${NC}"
            echo -e "${YELLOW}[DRY-RUN] sysfs scaling_governor -> ${sys_gov}, epp -> ${epp}${NC}"
        fi
    else
        local ppd_ok=false
        if command -v powerprofilesctl >/dev/null 2>&1; then
            if powerprofilesctl set "$ppd_target" 2>/dev/null; then
                ppd_ok=true
            fi
        fi
        if [[ "$ppd_ok" = "false" ]]; then
            for gov in "$SYSFS_CPU_DIR"/cpu*/cpufreq/scaling_governor; do
                if [[ -w "$gov" ]]; then
                    echo "$sys_gov" > "$gov" 2>/dev/null || true
                fi
            done
            for ep in "$SYSFS_CPU_DIR"/cpu*/cpufreq/energy_performance_preference \
                      "$SYSFS_CPU_DIR"/cpufreq/policy*/energy_performance_preference; do
                if [[ -w "$ep" ]]; then
                    echo "$epp" > "$ep" 2>/dev/null || true
                fi
            done
        fi
        save_state "profile" "$profile"
    fi

    # Adjust refresh rate based on profile if auto_hz enabled
    if [[ "$auto_hz" = "true" ]]; then
        detect_monitor
        if [[ "$profile" == "eco" ]]; then
            set_display_refresh_rate 60
            msg="${msg} Tần số quét: 60Hz."
        elif [[ "$profile" == "turbo" ]]; then
            if [[ "$MAX_HZ" -gt 60 ]]; then
                set_display_refresh_rate "$MAX_HZ"
                msg="${msg} Tần số quét: ${MAX_HZ}Hz."
            fi
        elif [[ "$profile" == "balanced" ]]; then
            detect_power_status
            if [[ "$AC_ONLINE" = "true" && "$MAX_HZ" -gt 60 ]]; then
                set_display_refresh_rate "$MAX_HZ"
                msg="${msg} Tần số quét: ${MAX_HZ}Hz (Nguồn AC)."
            elif [[ "$AC_ONLINE" = "false" ]]; then
                set_display_refresh_rate 60
                msg="${msg} Tần số quét: 60Hz (Nguồn Pin)."
            fi
        fi
    fi

    send_notification "$title" "$msg" "$icon"
    if [[ "$OUTPUT_JSON" = "false" && "$DRY_RUN" = "false" ]]; then
        echo -e "${GREEN}✓ ${title}: ${msg}${NC}"
    fi
}

# ------------------------------------------------------------------------------
# Action: Notification Status Summary
# ------------------------------------------------------------------------------
send_status_notification() {
    detect_power_status
    detect_monitor
    local profile
    profile="$(get_current_profile)"
    local auto_60hz
    auto_60hz="$(get_config_auto_60hz)"

    local msg="Nguồn điện: $([ "$AC_ONLINE" = "true" ] && echo "🔌 Cắm sạc AC" || echo "🔋 Đang dùng Pin")"
    if [[ "$HAS_BATTERY" = "true" ]]; then
        msg="${msg}\nMức pin: ${BATTERY_PERCENT}% (${BATTERY_STATUS})"
        msg="${msg}\nCông suất: ${POWER_WATTS}W | Ước tính: ${TIME_REMAINING}"
    fi
    msg="${msg}\nProfile: ${profile} | Màn hình: ${CURRENT_HZ}Hz (Max: ${MAX_HZ}Hz)"
    msg="${msg}\nTự động 60Hz: $([ "$auto_60hz" = "true" ] && echo "Bật" || echo "Tắt")"

    send_notification "⚡ yusei-power: Trạng thái Nguồn & Pin" "$msg" "preferences-system-power"
}

# ------------------------------------------------------------------------------
# Action: Status
# ------------------------------------------------------------------------------
action_status() {
    detect_power_status
    detect_monitor
    local profile
    profile="$(get_current_profile)"
    local auto_60hz
    auto_60hz="$(get_config_auto_60hz)"
    local daemon_enabled
    daemon_enabled="$(get_config_power_daemon)"

    if [[ "$NOTIFY_STATUS" = "true" ]]; then
        send_status_notification
    fi

    if [[ "$OUTPUT_JSON" = "true" ]]; then
        cat <<EOF
{
  "has_battery": $HAS_BATTERY,
  "ac_online": $AC_ONLINE,
  "battery_percent": $BATTERY_PERCENT,
  "battery_status": "$BATTERY_STATUS",
  "power_watts": $POWER_WATTS,
  "time_remaining": "$TIME_REMAINING",
  "profile": "$profile",
  "monitor_name": "$MONITOR_NAME",
  "current_hz": $CURRENT_HZ,
  "max_hz": $MAX_HZ,
  "min_hz": $MIN_HZ,
  "auto_60hz": $auto_60hz,
  "power_daemon": $daemon_enabled,
  "dry_run": $DRY_RUN
}
EOF
    else
        echo -e "${CYAN}${BOLD}================================================================================${NC}"
        echo -e "${CYAN}${BOLD}   ⚡ yusei-hypr: BỘ ĐIỀU PHỐI NĂNG LƯỢNG & TẦN SỐ QUÉT (Power Optimizer)       ${NC}"
        echo -e "${CYAN}${BOLD}================================================================================${NC}"
        echo -e " ${BOLD}Nguồn điện:${NC}         $([ "$AC_ONLINE" = "true" ] && echo -e "${GREEN}🔌 Cắm sạc AC (Mains Online)${NC}" || echo -e "${YELLOW}🔋 Đang dùng Pin (Battery Discharging)${NC}")"
        if [[ "$HAS_BATTERY" = "true" ]]; then
            echo -e " ${BOLD}Mức pin hiện tại:${NC}   ${GREEN}${BATTERY_PERCENT}%${NC} (${BATTERY_STATUS})"
            echo -e " ${BOLD}Công suất tiêu thụ:${NC} ${POWER_WATTS} W"
            echo -e " ${BOLD}Thời gian sử dụng:${NC}  ${TIME_REMAINING}"
        else
            echo -e " ${BOLD}Pin (Battery):${NC}      Không phát hiện pin (Desktop Workstation)"
        fi
        echo -e " ${BOLD}Profile hiện tại:${NC}   ${BOLD}${profile}${NC} $([ "$profile" = "eco" ] && echo "( Tiết kiệm điện)" || ([ "$profile" = "turbo" ] && echo "( Hiệu năng cao)" || echo "( Cân bằng)"))"
        echo -e " ${BOLD}Màn hình chính:${NC}     ${MONITOR_NAME} (${MONITOR_WIDTH}x${MONITOR_HEIGHT})"
        echo -e " ${BOLD}Tần số quét:${NC}        ${GREEN}${CURRENT_HZ} Hz${NC} (Tối đa: ${MAX_HZ} Hz, Tối thiểu: ${MIN_HZ} Hz)"
        echo -e " ${BOLD}Tự động 60Hz khi pin:${NC}$([ "$auto_60hz" = "true" ] && echo -e "${GREEN}Bật (Enabled)${NC}" || echo -e "${YELLOW}Tắt (Disabled)${NC}")"
        echo -e " ${BOLD}Power daemon autostart:${NC}$([ "$daemon_enabled" = "true" ] && echo -e "${GREEN}Bật (Enabled)${NC}" || echo -e "${YELLOW}Tắt (Disabled)${NC}")"
        echo -e "${CYAN}--------------------------------------------------------------------------------${NC}"
    fi
}

# ------------------------------------------------------------------------------
# Action: Toggle Refresh Rate
# ------------------------------------------------------------------------------
action_toggle_hz() {
    detect_monitor
    local target_hz
    if [[ "$CURRENT_HZ" -le 60 ]]; then
        if [[ "$MAX_HZ" -gt 60 ]]; then
            target_hz="$MAX_HZ"
        else
            target_hz=60
        fi
    else
        target_hz=60
    fi

    set_display_refresh_rate "$target_hz"
    send_notification "Tần số quét màn hình" "Đã chuyển đổi sang ${target_hz}Hz (${MONITOR_NAME})" "video-display"
    if [[ "$OUTPUT_JSON" = "false" && "$DRY_RUN" = "false" ]]; then
        echo -e "${GREEN}✓ Đã chuyển đổi tần số quét màn hình ${MONITOR_NAME} sang: ${target_hz}Hz${NC}"
    fi
}

# ------------------------------------------------------------------------------
# Action: Auto Optimize (Respects userprefs.conf & power.json overrides)
# ------------------------------------------------------------------------------
action_auto() {
    detect_power_status
    detect_monitor
    local auto_60hz
    auto_60hz="$(get_config_auto_60hz)"

    if [[ "$AC_ONLINE" = "true" ]]; then
        local target_prof
        target_prof="$(get_config_ac_profile)"
        apply_power_profile "$target_prof" "$auto_60hz"
    else
        local target_prof
        target_prof="$(get_config_bat_profile)"
        apply_power_profile "$target_prof" "$auto_60hz"
    fi
}

# ------------------------------------------------------------------------------
# Action: Cycle Power Profile (eco -> balanced -> turbo -> eco)
# ------------------------------------------------------------------------------
action_cycle_profile() {
    local cur
    cur="$(get_current_profile)"
    local next="balanced"
    case "$cur" in
        eco) next="balanced" ;;
        balanced) next="turbo" ;;
        turbo) next="eco" ;;
        *) next="balanced" ;;
    esac

    local auto_60hz
    auto_60hz="$(get_config_auto_60hz)"
    apply_power_profile "$next" "$auto_60hz"
}

# ------------------------------------------------------------------------------
# Action: Interactive Power Menu (Rofi / Notification Fallback)
# ------------------------------------------------------------------------------
action_menu() {
    detect_power_status
    detect_monitor
    local cur_prof
    cur_prof="$(get_current_profile)"
    local auto_60hz
    auto_60hz="$(get_config_auto_60hz)"

    if [[ "$DRY_RUN" = "true" ]]; then
        if [[ "$OUTPUT_JSON" = "false" ]]; then
            echo -e "${YELLOW}[DRY-RUN] Mở menu cài đặt nguồn điện (rofi / desktop notification)${NC}"
        fi
        return 0
    fi

    if command -v rofi >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-${DISPLAY:-}}" ]]; then
        local next_toggle_hz=60
        if [[ "$CURRENT_HZ" -le 60 && "$MAX_HZ" -gt 60 ]]; then
            next_toggle_hz="$MAX_HZ"
        fi

        local auto_label="BẬT"
        [[ "$auto_60hz" != "true" ]] && auto_label="TẮT"

        local options="  Tiết Kiệm Pin (Eco • 60Hz)\n  Cân Bằng (Balanced • Dynamic Hz)\n  Hiệu Năng Cao (Turbo • ${MAX_HZ}Hz)\n🔄  Chuyển đổi tần số quét (${CURRENT_HZ}Hz ➜ ${next_toggle_hz}Hz)\n⚡  Tự động hạ 60Hz khi dùng pin [${auto_label}]\n⚙️  Mở Bảng điều khiển yusei_settings\n📊  Thông báo trạng thái nguồn & pin"

        local chosen
        chosen="$(echo -e "$options" | rofi -dmenu -i -p "⚡ Nguồn điện & Pin" 2>/dev/null || true)"
        case "$chosen" in
            *"Tiết Kiệm Pin"*)
                apply_power_profile "eco" "$auto_60hz"
                ;;
            *"Cân Bằng"*)
                apply_power_profile "balanced" "$auto_60hz"
                ;;
            *"Hiệu Năng Cao"*)
                apply_power_profile "turbo" "$auto_60hz"
                ;;
            *"Chuyển đổi tần số quét"*)
                action_toggle_hz
                ;;
            *"Tự động hạ 60Hz"*)
                local new_auto="true"
                [[ "$auto_60hz" == "true" ]] && new_auto="false"
                mkdir -p "$(dirname "$CONFIG_FILE")"
                local cur="{}"
                if [[ -f "$CONFIG_FILE" ]]; then
                    cur="$(cat "$CONFIG_FILE" 2>/dev/null || true)"
                    [[ -z "$cur" || "$cur" == "null" ]] && cur="{}"
                fi
                echo "$cur" | jq --argjson v "$new_auto" '.auto_60hz = $v' > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                send_notification "Nguồn điện & Pin" "Đã $([ "$new_auto" = "true" ] && echo "BẬT" || echo "TẮT") tự động hạ 60Hz khi dùng pin"
                ;;
            *"yusei_settings"*)
                if command -v yusei-settings >/dev/null 2>&1; then
                    yusei-settings &
                elif [[ -x "$REPO_ROOT/bin/yusei-settings" ]]; then
                    "$REPO_ROOT/bin/yusei-settings" &
                fi
                ;;
            *"Thông báo trạng thái"*)
                send_status_notification
                ;;
        esac
    else
        send_status_notification
    fi
}

# ------------------------------------------------------------------------------
# Action: Daemon / Listener Mode
# ------------------------------------------------------------------------------
action_daemon() {
    detect_power_status
    if [[ "$HAS_BATTERY" = "false" ]]; then
        if [[ "$OUTPUT_JSON" = "false" ]]; then
            echo -e "${BLUE}:: [Daemon] Không phát hiện pin trên hệ thống. Dừng daemon nguồn điện.${NC}"
        fi
        exit 0
    fi

    local daemon_enabled
    daemon_enabled="$(get_config_power_daemon)"
    if [[ "$daemon_enabled" = "false" ]]; then
        if [[ "$OUTPUT_JSON" = "false" ]]; then
            echo -e "${YELLOW}:: [Daemon] Dịch vụ power-optimizer daemon đã bị vô hiệu hóa qua cấu hình userprefs.conf / power.json.${NC}"
        fi
        exit 0
    fi

    # Terminate any stale or duplicate daemon process
    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ -n "$old_pid" && "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
            if [[ "$old_pid" != "$$" ]]; then
                kill "$old_pid" 2>/dev/null || true
                sleep 0.2
            fi
        fi
    fi

    echo "$$" > "$PID_FILE"
    cleanup_daemon() {
        rm -f "$PID_FILE"
        exit 0
    }
    trap cleanup_daemon SIGINT SIGTERM EXIT

    if [[ "$OUTPUT_JSON" = "false" ]]; then
        echo -e "${GREEN}✓ [Daemon] Khởi chạy power-optimizer daemon (PID: $$)...${NC}"
    fi

    # Run auto optimization on startup
    action_auto

    local last_ac="$AC_ONLINE"
    local last_prof
    last_prof="$(get_current_profile)"
    while true; do
        sleep 3
        detect_power_status
        local cur_prof
        cur_prof="$(get_current_profile)"
        if [[ "$AC_ONLINE" != "$last_ac" ]]; then
            last_ac="$AC_ONLINE"
            action_auto
            last_prof="$(get_current_profile)"
        elif [[ "$cur_prof" != "$last_prof" ]]; then
            last_prof="$cur_prof"
            local auto_60hz
            auto_60hz="$(get_config_auto_60hz)"
            if [[ "$auto_60hz" = "true" ]]; then
                detect_monitor
                if [[ "$cur_prof" == "eco" ]]; then
                    set_display_refresh_rate 60
                elif [[ "$cur_prof" == "turbo" ]]; then
                    if [[ "$MAX_HZ" -gt 60 ]]; then
                        set_display_refresh_rate "$MAX_HZ"
                    fi
                elif [[ "$cur_prof" == "balanced" ]]; then
                    if [[ "$AC_ONLINE" = "true" && "$MAX_HZ" -gt 60 ]]; then
                        set_display_refresh_rate "$MAX_HZ"
                    elif [[ "$AC_ONLINE" = "false" ]]; then
                        set_display_refresh_rate 60
                    fi
                fi
            fi
        fi
    done
}

# ------------------------------------------------------------------------------
# Dispatch Actions
# ------------------------------------------------------------------------------
case "$ACTION" in
    status)
        action_status
        ;;
    set-profile)
        auto_60hz="$(get_config_auto_60hz)"
        apply_power_profile "$TARGET_PROFILE" "$auto_60hz"
        ;;
    cycle-profile)
        action_cycle_profile
        ;;
    toggle-hz)
        action_toggle_hz
        ;;
    auto)
        action_auto
        ;;
    menu)
        action_menu
        ;;
    daemon)
        action_daemon
        ;;
    *)
        echo -e "${RED}[ERROR] Lệnh không hợp lệ: $ACTION${NC}" >&2
        usage >&2
        exit 1
        ;;
esac

exit 0
