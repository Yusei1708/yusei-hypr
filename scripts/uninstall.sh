#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Safe Uninstaller & System Restoration Wrapper
# ==============================================================================
# Backwards-compatible shim delegating to root uninstall.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$SCRIPT_DIR/uninstall.sh" ]]; then
    exec "$SCRIPT_DIR/uninstall.sh" "$@"
else
    echo "Error: Cannot find root uninstall.sh at $SCRIPT_DIR/uninstall.sh" >&2
    exit 1
fi
