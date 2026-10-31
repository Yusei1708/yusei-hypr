#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Screen Recording Subsystem (ScreenRecord.sh)
# Version: 1.5.0 | Architecture: Universal Wayland
# Backends: wf-recorder, wl-screenrec | Output: $HOME/Videos/Recordings/
# Supported flags: --toggle, --region, --fullscreen, --audio, --status
# ==============================================================================

sDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
iDIR="$HOME/.config/swaync/icons"
iDoR="$HOME/.config/swaync/images"

# Fallback icons if swaync icons directory does not exist in ~/.config
[ -d "$iDIR" ] || iDIR="$(cd "$sDIR/../../swaync/icons" 2>/dev/null && pwd || echo "")"
[ -d "$iDoR" ] || iDoR="$(cd "$sDIR/../../swaync/images" 2>/dev/null && pwd || echo "")"

PID_FILE="/tmp/yusei_screenrecord.pid"
META_FILE="/tmp/yusei_screenrecord.file"

# Check if active recording process exists
get_active_pid() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if kill -0 "$pid" 2>/dev/null && grep -Eq "wf-recorder|wl-screenrec" "/proc/$pid/cmdline" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi

    # Fallback process search
    local p
    p=$(pgrep -x wf-recorder 2>/dev/null | head -n 1)
    if [ -n "$p" ]; then
        echo "$p"
        return 0
    fi
    p=$(pgrep -x wl-screenrec 2>/dev/null | head -n 1)
    if [ -n "$p" ]; then
        echo "$p"
        return 0
    fi

    return 1
}

is_recording() {
    get_active_pid >/dev/null 2>&1
}

# Stop active recording cleanly
stop_recording() {
    local pid
    pid=$(get_active_pid 2>/dev/null)
    local rec_file=""
    if [ -f "$META_FILE" ]; then
        rec_file=$(cat "$META_FILE" 2>/dev/null)
    fi

    if [ -n "$pid" ]; then
        # Send SIGINT so recorder finalizes container (moov atom)
        kill -INT "$pid" 2>/dev/null
        local count=0
        while kill -0 "$pid" 2>/dev/null && [ $count -lt 30 ]; do
            sleep 0.1
            count=$((count + 1))
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
        fi
    fi

    rm -f "$PID_FILE" "$META_FILE"

    # Audio feedback
    "$sDIR/Sounds.sh" --screenshot 2>/dev/null || true

    # Notification with SwayNC actions
    local notify_icon="${iDIR}/picture.png"
    [ -f "$notify_icon" ] || notify_icon="video-x-generic"

    if [ -n "$rec_file" ] && [ -f "$rec_file" ]; then
        local filename
        filename=$(basename "$rec_file")
        local notify_cmd=(
            notify-send -t 10000
            -A "action1=Open"
            -A "action2=Directory"
            -i "${iDIR}/picture.png"
            "Screen Recording"
            "Recording saved to ${filename}"
        )
        resp=$(timeout 10 "${notify_cmd[@]}" 2>/dev/null || true)
        case "$resp" in
            action1)
                xdg-open "$rec_file" >/dev/null 2>&1 &
                ;;
            action2)
                xdg-open "$(dirname "$rec_file")" >/dev/null 2>&1 &
                ;;
        esac
    else
        notify-send -t 4000 -i "$notify_icon" "Screen Recording" "Recording stopped."
    fi
}

# Detect recorder binary (wf-recorder > wl-screenrec)
detect_recorder() {
    if command -v wf-recorder >/dev/null 2>&1; then
        echo "wf-recorder"
    elif command -v wl-screenrec >/dev/null 2>&1; then
        echo "wl-screenrec"
    else
        echo ""
    fi
}

# Parse CLI flags
ACTION="toggle"
AUDIO=false

for arg in "$@"; do
    case "$arg" in
        --status)
            if is_recording; then
                exit 0
            else
                exit 1
            fi
            ;;
        --toggle)
            ACTION="toggle"
            ;;
        --region)
            ACTION="region"
            ;;
        --fullscreen)
            ACTION="fullscreen"
            ;;
        --audio)
            AUDIO=true
            ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--toggle|--region|--fullscreen] [--audio] [--status]"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            echo "Usage: $(basename "$0") [--toggle|--region|--fullscreen] [--audio] [--status]" >&2
            exit 1
            ;;
    esac
done

# If currently recording, any trigger stops it cleanly
if is_recording; then
    stop_recording
    exit 0
fi

# Region selection
GEOMETRY=""
if [ "$ACTION" = "region" ]; then
    if ! command -v slurp >/dev/null 2>&1; then
        err_icon="${iDIR}/error.png"
        [ -f "$err_icon" ] || err_icon="dialog-error"
        notify-send -u critical -i "$err_icon" "Screen Recording" "slurp is not installed."
        "$sDIR/Sounds.sh" --error 2>/dev/null || true
        exit 1
    fi
    GEOMETRY=$(slurp 2>/dev/null)
    slurp_rc=$?
    if [ $slurp_rc -ne 0 ] || [ -z "$GEOMETRY" ]; then
        # Canceled by user (e.g. Esc)
        exit 0
    fi
fi

# Check available recorder
RECORDER=$(detect_recorder)
if [ -z "$RECORDER" ]; then
    err_icon="${iDIR}/error.png"
    [ -f "$err_icon" ] || err_icon="dialog-error"
    notify-send -u critical -i "$err_icon" "Screen Recording" "Neither 'wf-recorder' nor 'wl-screenrec' is installed.\nPlease install wf-recorder or wl-screenrec."
    "$sDIR/Sounds.sh" --error 2>/dev/null || true
    exit 1
fi

# Prepare output directory and path
RECORD_DIR="$HOME/Videos/Recordings"
mkdir -p "$RECORD_DIR"
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
FILENAME="Recording_${TIMESTAMP}.mp4"
OUTPUT_FILE="${RECORD_DIR}/${FILENAME}"

# Assemble command arguments
cmd=("$RECORDER")
if [ "$AUDIO" = true ]; then
    if [ "$RECORDER" = "wf-recorder" ]; then
        cmd+=("-a")
    else
        cmd+=("--audio")
    fi
fi
if [ -n "$GEOMETRY" ]; then
    cmd+=("-g" "$GEOMETRY")
fi
cmd+=("-f" "$OUTPUT_FILE")

# Audio feedback on start
"$sDIR/Sounds.sh" --screenshot 2>/dev/null || true

# Notification on start
notify_icon="${iDIR}/timer.png"
[ -f "$notify_icon" ] || notify_icon="media-record"

if [ -n "$GEOMETRY" ]; then
    notify-send -t 3000 -i "$notify_icon" "Screen Recording" "Region recording started..."
else
    notify-send -t 3000 -i "$notify_icon" "Screen Recording" "Fullscreen recording started..."
fi

# Launch recorder process in background
"${cmd[@]}" >/dev/null 2>&1 &
REC_PID=$!

echo "$REC_PID" > "$PID_FILE"
echo "$OUTPUT_FILE" > "$META_FILE"

exit 0
