#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Optional Applications Module Compatibility Shim
# Delegates directly to scripts/05-optional-apps.sh
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/05-optional-apps.sh" "$@"
