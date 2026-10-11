#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Hardened Safe Configuration Backup Module
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}:: [3/4] Sao lưu các cấu hình hiện tại để đảm bảo an toàn...${NC}"

BACKUP_ROOT="$HOME/.config/yusei-hypr-backups"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/backup_$TIMESTAMP"
CONFIG_TARGETS=("hypr" "waybar" "rofi" "kitty" "swaync" "wlogout" "fastfetch" "btop" "cava" "swappy" "wallust" "Kvantum" "qt5ct" "qt6ct")

mkdir -p "$BACKUP_DIR"

BACKED_UP=()
NON_EXISTING=()

for item in "${CONFIG_TARGETS[@]}"; do
    if [[ -d "$HOME/.config/$item" || -f "$HOME/.config/$item" ]]; then
        cp -a "$HOME/.config/$item" "$BACKUP_DIR/"
        echo -e "${GREEN}✓ Đã sao lưu: ~/.config/$item${NC}"
        BACKED_UP+=("$item")
    else
        NON_EXISTING+=("$item")
    fi
done

# Write manifest.json
cat <<EOF > "$BACKUP_DIR/manifest.json"
{
  "timestamp": "$TIMESTAMP",
  "backed_up_targets": [$(printf '"%s",' "${BACKED_UP[@]:-}" | sed 's/,$//')],
  "non_existing_targets": [$(printf '"%s",' "${NON_EXISTING[@]:-}" | sed 's/,$//')]
}
EOF

# Update 'latest' symlink
rm -f "$BACKUP_ROOT/latest"
ln -s "$BACKUP_DIR" "$BACKUP_ROOT/latest"

echo -e "${GREEN}✓ Toàn bộ cấu hình cũ đã được bảo vệ tại: ${BACKUP_DIR}${NC}"
echo -e "${GREEN}✓ Symlink: ${BACKUP_ROOT}/latest -> ${BACKUP_DIR}${NC}\n"
