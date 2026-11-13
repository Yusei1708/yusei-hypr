#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Safe Uninstaller & System Restoration Wrapper
# ==============================================================================
# Backwards-compatible shim delegating to root uninstall.sh.
# Works both from repo (<repo>/scripts/uninstall.sh) and installed location
# (~/.local/share/yusei-hypr/scripts/uninstall.sh).
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

for candidate in "$ROOT_DIR/uninstall.sh" "$DATA_HOME/yusei-hypr/uninstall.sh"; do
    if [[ -f "$candidate" ]]; then
        if [[ -x "$candidate" ]]; then
            exec "$candidate" "$@"
        else
            exec bash "$candidate" "$@"
        fi
    fi
done

echo "Error: Cannot find root uninstall.sh at $ROOT_DIR/uninstall.sh or $DATA_HOME/yusei-hypr/uninstall.sh" >&2
exit 1
