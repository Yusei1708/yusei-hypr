"""
5-Stage Safety Protocol & Rollback Engine
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Implements strict impact analysis, pre-apply verification, automated snapshots,
explicit user confirmation barriers, surgical modification, and 1-click rollback.
"""

import os
import shutil
import json
import time
from pathlib import Path
from typing import Dict, List, Any, Optional

class SafetyEngine:
    def __init__(self, target_home: Optional[str] = None):
        """
        :param target_home: Allows mocking target directory for tests and sandboxes.
        """
        if target_home:
            self.home = Path(target_home).resolve()
        else:
            self.home = Path(os.environ.get("HOME", "/home/user")).resolve()

        self.config_dir = self.home / ".config"
        self.backups_dir = self.config_dir / "yusei-settings-backups"
        self.backups_dir.mkdir(parents=True, exist_ok=True)

    def analyze_impact(self, category: str, item_id: str, source_path: str) -> Dict[str, Any]:
        """
        Stage 1 & 2: Analyzes exact files that will be modified without writing anything.
        """
        affected_files = []
        source_p = Path(source_path)

        if category == "waybar_layout":
            target = self.config_dir / "waybar" / "config"
            affected_files.append({
                "target": str(target),
                "action": "symlink",
                "source": str(source_p),
                "description": f"Symlink Waybar layout to {source_p.name}",
            })
        elif category == "waybar_style":
            target = self.config_dir / "waybar" / "style.css"
            affected_files.append({
                "target": str(target),
                "action": "symlink",
                "source": str(source_p),
                "description": f"Symlink Waybar style to {source_p.name}",
            })
        elif category == "rofi_theme":
            target = self.config_dir / "rofi" / "config.rasi"
            affected_files.append({
                "target": str(target),
                "action": "modify_theme_directive",
                "source": str(source_p),
                "description": f"Update @theme directive in Rofi config to {item_id}",
            })
        elif category == "kitty_theme":
            target = self.config_dir / "kitty" / "kitty.conf"
            affected_files.append({
                "target": str(target),
                "action": "modify_include_directive",
                "source": str(source_p),
                "description": f"Update include directive in Kitty config to ./kitty-themes/{source_p.name}",
            })
        elif category == "hyprland_animation":
            target = self.config_dir / "hypr" / "animations.conf"
            affected_files.append({
                "target": str(target),
                "action": "modify_source_directive",
                "source": str(source_p),
                "description": f"Update animation source to ./animations/{source_p.name}",
            })
        elif category == "wallpaper":
            target = self.config_dir / "hypr" / "wallpaper.jpg"
            target_symlink = self.config_dir / "hypr" / ".current_wallpaper"
            affected_files.append({
                "target": str(target),
                "action": "copy",
                "source": str(source_p),
                "description": f"Set default wallpaper copy to {source_p.name}",
            })
            affected_files.append({
                "target": str(target_symlink),
                "action": "symlink",
                "source": str(source_p),
                "description": f"Update .current_wallpaper symlink",
            })

        return {
            "status": "READY_FOR_CONFIRMATION",
            "category": category,
            "item_id": item_id,
            "source_path": source_path,
            "affected_files": affected_files,
            "unaffected_scope": "All unrelated desktop configurations, keybinds, rules, and daemons will remain untouched.",
            "confirmation_required": True,
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        }

    def create_snapshot(self, files_to_backup: List[str]) -> str:
        """
        Stage 3: Creates a timestamped backup snapshot with manifest.json.
        """
        timestamp = time.strftime("%Y%m%d_%H%M%S")
        snapshot_id = f"snapshot_{timestamp}"
        snapshot_dir = self.backups_dir / snapshot_id
        snapshot_dir.mkdir(parents=True, exist_ok=True)

        manifest = {
            "snapshot_id": snapshot_id,
            "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "backed_up_files": [],
            "non_existent_files": [],
        }

        for path_str in files_to_backup:
            target_p = Path(path_str)
            rel_name = target_p.name
            backup_dest = snapshot_dir / rel_name

            if target_p.exists():
                if target_p.is_symlink():
                    link_target = str(os.readlink(target_p))
                    manifest["backed_up_files"].append({
                        "original_path": str(target_p),
                        "is_symlink": True,
                        "link_target": link_target,
                    })
                elif target_p.is_file():
                    shutil.copy2(target_p, backup_dest)
                    manifest["backed_up_files"].append({
                        "original_path": str(target_p),
                        "is_symlink": False,
                        "backup_file": rel_name,
                    })
            else:
                manifest["non_existent_files"].append(str(target_p))

        # Write manifest.json
        manifest_file = snapshot_dir / "manifest.json"
        manifest_file.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

        # Update latest pointer
        latest_file = self.backups_dir / "latest.json"
        latest_file.write_text(json.dumps({"latest_snapshot": snapshot_id}, indent=2), encoding="utf-8")

        return snapshot_id

    def apply_change(self, category: str, item_id: str, source_path: str, confirmed: bool) -> Dict[str, Any]:
        """
        Stage 4 & 5: Requires confirmation, takes snapshot, then performs surgical update.
        """
        if not confirmed:
            raise PermissionError("Explicit user confirmation is mandatory before executing apply.")

        impact = self.analyze_impact(category, item_id, source_path)
        targets_to_backup = [f["target"] for f in impact["affected_files"]]
        
        # 1. Create snapshot
        snapshot_id = self.create_snapshot(targets_to_backup)

        # 2. Execute surgical modifications
        for item in impact["affected_files"]:
            target_p = Path(item["target"])
            target_p.parent.mkdir(parents=True, exist_ok=True)
            source_p = Path(item["source"])

            if item["action"] == "symlink":
                if target_p.exists() or target_p.is_symlink():
                    target_p.unlink()
                # Create relative symlink if within same hierarchy or absolute
                try:
                    rel = os.path.relpath(source_p, target_p.parent)
                    target_p.symlink_to(rel)
                except Exception:
                    target_p.symlink_to(source_p)

            elif item["action"] == "copy":
                if target_p.is_symlink():
                    target_p.unlink()
                shutil.copy2(source_p, target_p)

            elif item["action"] == "modify_theme_directive":
                content = ""
                if target_p.exists():
                    content = target_p.read_text(encoding="utf-8", errors="ignore")
                
                new_theme_line = f'@theme "~/.config/rofi/themes/{source_p.name}"'
                if "@theme" in content:
                    lines = []
                    for line in content.splitlines():
                        if line.strip().startswith("@theme"):
                            lines.append(new_theme_line)
                        else:
                            lines.append(line)
                    content = "\n".join(lines) + "\n"
                else:
                    content += f"\n{new_theme_line}\n"
                target_p.write_text(content, encoding="utf-8")

            elif item["action"] == "modify_include_directive":
                content = ""
                if target_p.exists():
                    content = target_p.read_text(encoding="utf-8", errors="ignore")
                new_inc_line = f"include ./kitty-themes/{source_p.name}"
                if "include ./kitty-themes/" in content:
                    import re
                    content = re.sub(r'include\s+\./kitty-themes/.*\.conf', new_inc_line, content)
                else:
                    content += f"\n{new_inc_line}\n"
                target_p.write_text(content, encoding="utf-8")

            elif item["action"] == "modify_source_directive":
                target_p.write_text(f"source = ./animations/{source_p.name}\n", encoding="utf-8")

        return {
            "success": True,
            "message": f"Successfully applied {item_id} cleanly.",
            "category": category,
            "item_id": item_id,
            "snapshot_id": snapshot_id,
            "can_rollback": True,
            "applied_files": impact["affected_files"],
        }

    def rollback(self, snapshot_id: Optional[str] = None) -> Dict[str, Any]:
        """
        Instant 1-Click Rollback to pre-apply state.
        """
        if not snapshot_id:
            latest_file = self.backups_dir / "latest.json"
            if not latest_file.exists():
                raise FileNotFoundError("No recent snapshot available for rollback.")
            data = json.loads(latest_file.read_text(encoding="utf-8"))
            snapshot_id = data.get("latest_snapshot")

        snapshot_dir = self.backups_dir / snapshot_id
        manifest_file = snapshot_dir / "manifest.json"
        if not manifest_file.exists():
            raise FileNotFoundError(f"Snapshot manifest not found in {snapshot_dir}")

        manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
        restored = []

        # 1. Remove files that were newly created during apply
        for non_ext_path in manifest.get("non_existent_files", []):
            p = Path(non_ext_path)
            if p.exists() or p.is_symlink():
                p.unlink()
                restored.append({"file": str(p), "action": "removed_newly_created"})

        # 2. Restore backed up files
        for item in manifest.get("backed_up_files", []):
            orig_p = Path(item["original_path"])
            if orig_p.exists() or orig_p.is_symlink():
                orig_p.unlink()

            if item.get("is_symlink"):
                orig_p.symlink_to(item["link_target"])
                restored.append({"file": str(orig_p), "action": "restored_symlink"})
            else:
                backup_file = snapshot_dir / item["backup_file"]
                shutil.copy2(backup_file, orig_p)
                restored.append({"file": str(orig_p), "action": "restored_file"})

        return {
            "success": True,
            "snapshot_id": snapshot_id,
            "restored_items": restored,
            "message": f"Rollback successfully restored {len(restored)} configuration targets.",
        }

    def list_snapshots(self) -> List[Dict[str, Any]]:
        """Returns list of historical backup snapshots."""
        snapshots = []
        if not self.backups_dir.exists():
            return snapshots

        for path in sorted(self.backups_dir.iterdir(), reverse=True):
            if path.is_dir() and (path / "manifest.json").exists():
                try:
                    data = json.loads((path / "manifest.json").read_text(encoding="utf-8"))
                    snapshots.append(data)
                except Exception:
                    pass
        return snapshots
