#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: OCR Text Grabber Subsystem (OcrGrab.sh)
# Version: 1.5.0 | Architecture: Universal Wayland
# Pipeline: slurp (region) -> grim (capture) -> tesseract (OCR) -> wl-copy
# Supported languages: eng (English), vie (Vietnamese)
# ==============================================================================

sDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
iDIR="$HOME/.config/swaync/icons"
iDoR="$HOME/.config/swaync/images"

# Fallback icons if swaync icons directory does not exist in ~/.config
[ -d "$iDIR" ] || iDIR="$(cd "$sDIR/../../swaync/icons" 2>/dev/null && pwd || echo "")"
[ -d "$iDoR" ] || iDoR="$(cd "$sDIR/../../swaync/images" 2>/dev/null && pwd || echo "")"

tmp_img="/tmp/ocr_snap.png"
cleanup() {
    rm -f "$tmp_img"
}
trap cleanup EXIT INT TERM

# Check required screenshot & clipboard tools
if ! command -v grim >/dev/null 2>&1 || ! command -v slurp >/dev/null 2>&1; then
    notify-send -u critical "OCR Text Grabber" "grim or slurp is not installed."
    "$sDIR/Sounds.sh" --error 2>/dev/null || true
    exit 1
fi

if ! command -v wl-copy >/dev/null 2>&1 || ! command -v wl-paste >/dev/null 2>&1; then
    notify-send -u critical "OCR Text Grabber" "wl-clipboard (wl-copy/wl-paste) is not installed."
    "$sDIR/Sounds.sh" --error 2>/dev/null || true
    exit 1
fi

# Prompt user for region selection via slurp
GEOM=$(slurp 2>/dev/null)
slurp_rc=$?
if [ $slurp_rc -ne 0 ] || [ -z "$GEOM" ]; then
    # Canceled by user (e.g. Esc)
    exit 0
fi

# Take region screenshot
if ! grim -g "$GEOM" "$tmp_img" 2>/dev/null; then
    exit 0
fi

if [ ! -s "$tmp_img" ]; then
    exit 0
fi

# Check tesseract optical character recognition tool
if ! command -v tesseract >/dev/null 2>&1; then
    err_icon="${iDIR}/error.png"
    [ -f "$err_icon" ] || err_icon="dialog-error"
    notify-send -u critical -i "$err_icon" "OCR Text Grabber" "tesseract is not installed.\nPlease install tesseract and language packs (e.g. tesseract-data-eng tesseract-data-vie)."
    "$sDIR/Sounds.sh" --error 2>/dev/null || true
    exit 1
fi

# Run OCR with eng+vie language pack; fall back to default if eng+vie is missing or fails
if (set -o pipefail; tesseract "$tmp_img" stdout -l eng+vie 2>/dev/null | wl-copy) 2>/dev/null; then
    :
else
    tesseract "$tmp_img" stdout 2>/dev/null | wl-copy
fi

# Retrieve copied text from clipboard
COPIED_TEXT=$(wl-paste 2>/dev/null)
TRIMMED_TEXT=$(echo "$COPIED_TEXT" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

# Check result and provide user feedback
if [ -n "$TRIMMED_TEXT" ]; then
    TEXT_PREVIEW=$(echo "$TRIMMED_TEXT" | head -n 3 | cut -c 1-100)
    [ "${#TRIMMED_TEXT}" -gt 100 ] && TEXT_PREVIEW="${TEXT_PREVIEW}..."

    notify-send -t 4000 "OCR Text Grabber" "Copied to clipboard: $TEXT_PREVIEW"
    "$sDIR/Sounds.sh" --screenshot 2>/dev/null || true
else
    notify-send -t 3000 -u low "OCR Text Grabber" "No text recognized."
fi

# Clean up temporary snapshot
rm -f "$tmp_img"
exit 0
