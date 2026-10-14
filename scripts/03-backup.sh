#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Hardened Safe Configuration Backup Module
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DRY_RUN=false
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
    fi
done

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BACKUP_DIR="$CONFIG_HOME/yusei-hypr-backup-$TIMESTAMP"
LATEST_LINK="$CONFIG_HOME/yusei-hypr-backup-latest"
LEGACY_ROOT="$CONFIG_HOME/yusei-hypr-backups"

CONFIG_TARGETS=("hypr" "waybar" "rofi" "kitty" "swaync" "wlogout" "fastfetch" "btop" "cava" "swappy" "wallust" "Kvantum" "qt5ct" "qt6ct")

if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}:: [DRY-RUN] Mô phỏng sao lưu cấu hình yusei-hypr...${NC}"
    echo -e "   Thư mục sao lưu dự kiến: ${BACKUP_DIR}"
    echo -e "   Symlink dự kiến:         ${LATEST_LINK} -> ${BACKUP_DIR}"
    for item in "${CONFIG_TARGETS[@]}"; do
        if [[ -e "$CONFIG_HOME/$item" ]]; then
            echo -e "${YELLOW}[DRY-RUN] Sẽ sao lưu: ~/.config/$item${NC}"
        else
            echo -e "${YELLOW}[DRY-RUN] Mục tiêu không tồn tại (sẽ ghi vào manifest): ~/.config/$item${NC}"
        fi
    done
    exit 0
fi

while [[ -e "$BACKUP_DIR" ]]; do
    sleep 1
    TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    BACKUP_DIR="$CONFIG_HOME/yusei-hypr-backup-$TIMESTAMP"
done

echo -e "${BLUE}:: [Backup] Sao lưu các cấu hình hiện tại để đảm bảo an toàn...${NC}"

mkdir -p "$CONFIG_HOME"
mkdir -p "$BACKUP_DIR"

BACKED_UP=()
NON_EXISTING=()

for item in "${CONFIG_TARGETS[@]}"; do
    if [[ -e "$CONFIG_HOME/$item" ]]; then
        cp -a "$CONFIG_HOME/$item" "$BACKUP_DIR/"
        echo -e "${GREEN}✓ Đã sao lưu: ~/.config/$item${NC}"
        BACKED_UP+=("$item")
    else
        NON_EXISTING+=("$item")
    fi
done

# Write manifest.json safely
MANIFEST_TMP="$BACKUP_DIR/manifest.json.tmp"
if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys

timestamp = sys.argv[1]
backup_dir = sys.argv[2]
backed_up = [x for x in sys.argv[3].split(',') if x]
non_existing = [x for x in sys.argv[4].split(',') if x]

manifest = {
    'timestamp': timestamp,
    'backup_dir': backup_dir,
    'backed_up_targets': backed_up,
    'non_existing_targets': non_existing
}

with open(sys.argv[5], 'w', encoding='utf-8') as f:
    json.dump(manifest, f, indent=2)
" "$TIMESTAMP" "$BACKUP_DIR" "$(IFS=,; echo "${BACKED_UP[*]}")" "$(IFS=,; echo "${NON_EXISTING[*]}")" "$MANIFEST_TMP"
    mv "$MANIFEST_TMP" "$BACKUP_DIR/manifest.json"
else
    # Pure-bash valid JSON formatting fallback
    json_backed_up=""
    json_non_existing=""
    b_targets=()
    for t in "${BACKED_UP[@]:-}"; do
        [[ -n "$t" ]] && b_targets+=("$t")
    done
    if [ ${#b_targets[@]} -gt 0 ]; then
        json_backed_up=$(printf '"%s",' "${b_targets[@]}" | sed 's/,$//')
    fi

    ne_targets=()
    for t in "${NON_EXISTING[@]:-}"; do
        [[ -n "$t" ]] && ne_targets+=("$t")
    done
    if [ ${#ne_targets[@]} -gt 0 ]; then
        json_non_existing=$(printf '"%s",' "${ne_targets[@]}" | sed 's/,$//')
    fi

    cat <<EOF > "$BACKUP_DIR/manifest.json"
{
  "timestamp": "$TIMESTAMP",
  "backup_dir": "$BACKUP_DIR",
  "backed_up_targets": [$json_backed_up],
  "non_existing_targets": [$json_non_existing]
}
EOF
fi

# Update symlinks
ln -sfn "$BACKUP_DIR" "$LATEST_LINK"

# Also maintain legacy symlink if legacy folder exists or for compatibility
mkdir -p "$LEGACY_ROOT" 2>/dev/null || true
ln -sfn "$BACKUP_DIR" "$LEGACY_ROOT/latest" 2>/dev/null || true

echo -e "${GREEN}✓ Toàn bộ cấu hình cũ đã được bảo vệ tại: ${BACKUP_DIR}${NC}"
echo -e "${GREEN}✓ Symlink: ${LATEST_LINK} -> ${BACKUP_DIR}${NC}\n"
