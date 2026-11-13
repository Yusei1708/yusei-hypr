#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Weather entrypoint: prefer Python (Open‑Meteo), fallback to legacy Bash (wttr.in)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PY_SCRIPT=""
for py_candidate in \
    "$HOME/.config/hypr/UserScripts/Weather.py" \
    "$HOME/.config/hypr/scripts/Weather.py" \
    "$SCRIPT_DIR/Weather.py" \
    "$SCRIPT_DIR/../UserScripts/Weather.py" \
    "$SCRIPT_DIR/../scripts/Weather.py"; do
    if [ -f "$py_candidate" ]; then
        PY_SCRIPT="$py_candidate"
        break
    fi
done

BASH_FALLBACK=""
for sh_candidate in \
    "$SCRIPT_DIR/Weather.sh" \
    "$HOME/.config/hypr/scripts/Weather.sh" \
    "$HOME/.config/hypr/UserScripts/Weather.sh" \
    "$SCRIPT_DIR/../scripts/Weather.sh" \
    "$SCRIPT_DIR/../UserScripts/Weather.sh"; do
    if [ -f "$sh_candidate" ]; then
        BASH_FALLBACK="$sh_candidate"
        break
    fi
done

# Function to check network connectivity
check_network() {
    # Try multiple methods to check network
    if ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
        return 0
    fi
    
    if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        return 0
    fi
    
    if curl -s --connect-timeout 3 "https://ipinfo.io" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# If no network, return offline status immediately
if ! check_network; then
    echo '{"text":"󰖪", "alt":"Offline", "tooltip":"No network connection"}'
    exit 0
fi

run_fallback() {
    if [ -n "$BASH_FALLBACK" ] && [ -f "$BASH_FALLBACK" ]; then
        # Invoke via bash to avoid requiring +x and ensure consistent shell
        bash "$BASH_FALLBACK" "$@"
        return $?
    else
        echo "Weather fallback not found: $BASH_FALLBACK" >&2
        return 127
    fi
}

if [ -n "$PY_SCRIPT" ] && command -v python3 >/dev/null 2>&1; then
    python3 "$PY_SCRIPT" "$@"
    exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        exit 0
    fi
    echo "Weather.py failed with code $exit_code — falling back to Weather.sh" >&2
    run_fallback "$@"
    exit $?
else
    if [ -z "$PY_SCRIPT" ]; then
        echo "Weather.py not found — falling back to Weather.sh" >&2
    else
        echo "python3 not found in PATH — falling back to Weather.sh" >&2
    fi
    run_fallback "$@"
    exit $?
fi
