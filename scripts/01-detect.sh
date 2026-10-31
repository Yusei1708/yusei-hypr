#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Hardware & OS Detection Module (Compatibility Wrapper)
# ==============================================================================
# Backwards-compatible wrapper delegating to scripts/hardware-detect.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Delegate to hardware-detect.sh with all supplied arguments
exec "$SCRIPT_DIR/hardware-detect.sh" "$@"

