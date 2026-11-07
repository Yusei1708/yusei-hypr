#!/usr/bin/env bash
SOURCE_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SOURCE_PATH")/.." && pwd)"
if [[ -x "$SCRIPT_DIR/scripts/theme-engine.sh" ]]; then
    exec "$SCRIPT_DIR/scripts/theme-engine.sh" "$@"
elif [[ -x "$HOME/.local/share/yusei-hypr/scripts/theme-engine.sh" ]]; then
    exec "$HOME/.local/share/yusei-hypr/scripts/theme-engine.sh" "$@"
fi
echo "Error: theme-engine.sh not found" >&2
exit 1
