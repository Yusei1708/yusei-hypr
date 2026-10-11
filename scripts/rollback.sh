#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Idempotent Safe Rollback Module
# ==============================================================================
# Reverts ~/.config changes to the pre-installation backup snapshot.
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}:: [Rollback] Bắt đầu quy trình hoàn nguyên cấu hình...${NC}"

BACKUP_ROOT="$HOME/.config/yusei-hypr-backups"

if [[ ! -d "$BACKUP_ROOT" ]]; then
    echo -e "${RED}[ERROR] Không tìm thấy thư mục sao lưu tại: $BACKUP_ROOT${NC}"
    exit 1
fi

# Locate latest backup snapshot
TARGET_SNAPSHOT=""
if [[ -L "$BACKUP_ROOT/latest" && -d "$BACKUP_ROOT/latest" ]]; then
    TARGET_SNAPSHOT="$(readlink -f "$BACKUP_ROOT/latest")"
else
    # Find most recent backup directory
    TARGET_SNAPSHOT="$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "backup_*" | sort -r | head -n 1)"
fi

if [[ -z "$TARGET_SNAPSHOT" || ! -d "$TARGET_SNAPSHOT" ]]; then
    echo -e "${RED}[ERROR] Không tìm thấy bản snapshot nào hợp lệ trong $BACKUP_ROOT!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Đang hoàn nguyên từ snapshot: $TARGET_SNAPSHOT${NC}"

# Check for manifest.json
MANIFEST="$TARGET_SNAPSHOT/manifest.json"
if [[ -f "$MANIFEST" ]]; then
    echo -e "${BLUE}:: Đọc manifest.json...${NC}"
    
    # Remove newly created targets that didn't exist before
    python3 -c "
import json, os, shutil, sys

with open('$MANIFEST', 'r') as f:
    data = json.load(f)

home = os.environ.get('HOME', '')
for item in data.get('non_existing_targets', []):
    path = os.path.join(home, '.config', item)
    if os.path.exists(path):
        if os.path.isdir(path):
            shutil.rmtree(path)
        else:
            os.remove(path)
        print(f'Đã dọn dẹp cấu hình mới tạo: ~/.config/{item}')
" 2>/dev/null || true

    # Restore previously backed up targets
    python3 -c "
import json, os, shutil, sys

with open('$MANIFEST', 'r') as f:
    data = json.load(f)

home = os.environ.get('HOME', '')
snapshot = '$TARGET_SNAPSHOT'
for item in data.get('backed_up_targets', []):
    src = os.path.join(snapshot, item)
    dest = os.path.join(home, '.config', item)
    if os.path.exists(src):
        if os.path.exists(dest):
            if os.path.isdir(dest):
                shutil.rmtree(dest)
            else:
                os.remove(dest)
        if os.path.isdir(src):
            shutil.copytree(src, dest)
        else:
            shutil.copy2(src, dest)
        print(f'Đã khôi phục: ~/.config/{item}')
" 2>/dev/null || true
else
    # Fallback restoration: copy all folders in snapshot back to ~/.config
    for item in "$TARGET_SNAPSHOT"/*; do
        base="$(basename "$item")"
        if [[ "$base" != "manifest.json" ]]; then
            rm -rf "$HOME/.config/$base"
            cp -a "$item" "$HOME/.config/"
            echo -e "${GREEN}✓ Đã khôi phục: ~/.config/$base${NC}"
        fi
    done
fi

echo -e "${GREEN}🎉 Hoàn nguyên hoàn tất thành công! Trạng thái cấu hình ban đầu đã được phục hồi.${NC}"
exit 0
