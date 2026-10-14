#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Idempotent Safe Rollback Module
# ==============================================================================
# Reverts ~/.config changes to the pre-installation backup snapshot.
# Usage:
#   scripts/rollback.sh [SNAPSHOT_DIR] [--dry-run]
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DRY_RUN=false
TARGET_SNAPSHOT=""

for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
    elif [[ "$arg" != -* && -z "$TARGET_SNAPSHOT" ]]; then
        TARGET_SNAPSHOT="$arg"
    fi
done

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
LATEST_LINK="$CONFIG_HOME/yusei-hypr-backup-latest"
LEGACY_LATEST="$CONFIG_HOME/yusei-hypr-backups/latest"

echo -e "${BLUE}:: [Rollback] Bắt đầu quy trình hoàn nguyên cấu hình...${NC}"

# If target snapshot not explicitly passed, discover latest snapshot
if [[ -z "$TARGET_SNAPSHOT" ]]; then
    if [[ -L "$LATEST_LINK" && -d "$LATEST_LINK" ]]; then
        TARGET_SNAPSHOT="$(readlink -f "$LATEST_LINK")"
    elif [[ -d "$LATEST_LINK" ]]; then
        TARGET_SNAPSHOT="$LATEST_LINK"
    elif [[ -L "$LEGACY_LATEST" && -d "$LEGACY_LATEST" ]]; then
        TARGET_SNAPSHOT="$(readlink -f "$LEGACY_LATEST")"
    else
        # Search newest directory matching yusei-hypr-backup-*
        TARGET_SNAPSHOT="$(find "$CONFIG_HOME" -maxdepth 1 -type d -name "yusei-hypr-backup-[0-9]*" 2>/dev/null | sort -r | head -n 1 || true)"
        if [[ -z "$TARGET_SNAPSHOT" && -d "$CONFIG_HOME/yusei-hypr-backups" ]]; then
            TARGET_SNAPSHOT="$(find "$CONFIG_HOME/yusei-hypr-backups" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | sort -r | head -n 1 || true)"
        fi
    fi
fi

if [[ -n "$TARGET_SNAPSHOT" && -L "$TARGET_SNAPSHOT" ]]; then
    TARGET_SNAPSHOT="$(readlink -f "$TARGET_SNAPSHOT")"
fi

if [[ -z "$TARGET_SNAPSHOT" || ! -d "$TARGET_SNAPSHOT" ]]; then
    echo -e "${RED}[ERROR] Không tìm thấy bản snapshot nào hợp lệ để hoàn nguyên!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Đang hoàn nguyên từ snapshot: $TARGET_SNAPSHOT${NC}"

MANIFEST="$TARGET_SNAPSHOT/manifest.json"

if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}:: [DRY-RUN] Mô phỏng hoàn nguyên từ: $TARGET_SNAPSHOT${NC}"
    if [[ -f "$MANIFEST" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Sẽ phân tích manifest.json để dọn dẹp các target mới và khôi phục target cũ...${NC}"
    else
        echo -e "${YELLOW}[DRY-RUN] Không có manifest.json; sẽ khôi phục trực tiếp các thư mục cấu hình con.${NC}"
    fi
    exit 0
fi

RESTORED=false

if [[ -f "$MANIFEST" ]] && command -v python3 &>/dev/null; then
    echo -e "${BLUE}:: Đọc manifest.json qua python3...${NC}"
    if python3 -c "
import json, os, shutil, sys

manifest_file = sys.argv[1]
config_home = sys.argv[2]
snapshot = sys.argv[3]

def is_safe_target(item, base_dir):
    if not isinstance(item, str):
        return False
    item = item.strip()
    if not item or item in ('', '.', '..', '/', '~') or item.startswith(('/', '~')):
        return False
    norm = os.path.normpath(os.path.join(base_dir, item))
    base_norm = os.path.normpath(base_dir)
    return norm.startswith(base_norm + os.sep)

with open(manifest_file, 'r', encoding='utf-8') as f:
    data = json.load(f)

for item in data.get('non_existing_targets', []):
    if not is_safe_target(item, config_home):
        continue
    path = os.path.join(config_home, item)
    if os.path.islink(path):
        os.unlink(path)
        print(f'Đã dọn dẹp liên kết mới tạo: {path}')
    elif os.path.isdir(path):
        shutil.rmtree(path)
        print(f'Đã dọn dẹp thư mục cấu hình mới tạo: {path}')
    elif os.path.exists(path):
        os.remove(path)
        print(f'Đã dọn dẹp tệp cấu hình mới tạo: {path}')

for item in data.get('backed_up_targets', []):
    if not is_safe_target(item, config_home):
        continue
    src = os.path.join(snapshot, item)
    dest = os.path.join(config_home, item)
    if os.path.exists(src) or os.path.islink(src):
        if os.path.islink(dest):
            os.unlink(dest)
        elif os.path.isdir(dest):
            shutil.rmtree(dest)
        elif os.path.exists(dest):
            os.remove(dest)

        if os.path.islink(src):
            linkto = os.readlink(src)
            os.symlink(linkto, dest)
        elif os.path.isdir(src):
            shutil.copytree(src, dest, symlinks=True)
        else:
            shutil.copy2(src, dest, follow_symlinks=False)
        print(f'Đã khôi phục: {dest}')
" "$MANIFEST" "$CONFIG_HOME" "$TARGET_SNAPSHOT"; then
        RESTORED=true
    else
        echo -e "${YELLOW}⚠️ Python manifest parser gặp lỗi, chuyển sang cơ chế fallback thuần Bash...${NC}"
    fi
fi

if [ "$RESTORED" = "false" ]; then
    echo -e "${BLUE}:: Khôi phục qua cơ chế thuần Bash...${NC}"

    parse_manifest_items() {
        local key="$1"
        local file="$2"
        if command -v jq &>/dev/null; then
            jq -r --arg k "$key" '.[$k][]? // empty' "$file" 2>/dev/null || true
        else
            tr '\n' ' ' < "$file" 2>/dev/null | grep -oP "\"$key\"\s*:\s*\[\K[^\]]*" 2>/dev/null \
                | grep -oP '"[^"]+"' 2>/dev/null \
                | tr -d '"' || true
        fi
    }

    if [[ -f "$MANIFEST" ]]; then
        # 1. Clean up non_existing_targets
        while IFS= read -r item; do
            item="$(echo "$item" | xargs 2>/dev/null || echo "$item")"
            if [[ -z "$item" || "$item" == "." || "$item" == ".." || "$item" == "/" || "$item" == "~" || "$item" == *"/"* ]]; then
                continue
            fi
            path="$CONFIG_HOME/$item"
            if [[ -L "$path" ]]; then
                rm -f "$path"
                echo -e "${GREEN}✓ Đã dọn dẹp liên kết mới tạo: $path${NC}"
            elif [[ -d "$path" ]]; then
                rm -rf "$path"
                echo -e "${GREEN}✓ Đã dọn dẹp thư mục cấu hình mới tạo: $path${NC}"
            elif [[ -e "$path" ]]; then
                rm -f "$path"
                echo -e "${GREEN}✓ Đã dọn dẹp cấu hình mới tạo: $path${NC}"
            fi
        done < <(parse_manifest_items "non_existing_targets" "$MANIFEST")

        # 2. Restore backed_up_targets
        while IFS= read -r item; do
            item="$(echo "$item" | xargs 2>/dev/null || echo "$item")"
            if [[ -z "$item" || "$item" == "." || "$item" == ".." || "$item" == "/" || "$item" == "~" || "$item" == *"/"* ]]; then
                continue
            fi
            src="$TARGET_SNAPSHOT/$item"
            dest="$CONFIG_HOME/$item"
            if [[ -e "$src" || -L "$src" ]]; then
                if [[ -L "$dest" ]]; then
                    rm -f "$dest"
                elif [[ -d "$dest" ]]; then
                    rm -rf "$dest"
                elif [[ -e "$dest" ]]; then
                    rm -f "$dest"
                fi
                cp -a "$src" "$dest"
                echo -e "${GREEN}✓ Đã khôi phục: ~/.config/$item${NC}"
            fi
        done < <(parse_manifest_items "backed_up_targets" "$MANIFEST")
    else
        # Direct folder fallback when manifest.json does not exist
        for item in "$TARGET_SNAPSHOT"/*; do
            base="$(basename "$item")"
            if [[ -z "$base" || "$base" == "." || "$base" == ".." || "$base" == "/" || "$base" == "~" || "$base" == "manifest.json" || "$base" == "manifest.json.tmp" ]]; then
                continue
            fi
            dest="$CONFIG_HOME/$base"
            if [[ -L "$dest" ]]; then
                rm -f "$dest"
            elif [[ -d "$dest" ]]; then
                rm -rf "$dest"
            elif [[ -e "$dest" ]]; then
                rm -f "$dest"
            fi
            cp -a "$item" "$dest"
            echo -e "${GREEN}✓ Đã khôi phục: ~/.config/$base${NC}"
        done
    fi
fi

echo -e "${GREEN}🎉 Hoàn nguyên hoàn tất thành công! Trạng thái cấu hình ban đầu đã được phục hồi.${NC}"
exit 0
