"""
5-Stage Safety Protocol & Rollback Engine
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Implements strict impact analysis, pre-apply verification, automated snapshots,
explicit user confirmation barriers, surgical modification, and 1-click rollback.
"""

import json
import os
import re
import shutil
import subprocess
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional


CATEGORY_ALIASES = {
    "waybar_layout": "waybar_layout",
    "waybar_layouts": "waybar_layout",
    "waybar_style": "waybar_style",
    "waybar_styles": "waybar_style",
    "rofi_theme": "rofi_theme",
    "rofi_themes": "rofi_theme",
    "kitty_theme": "kitty_theme",
    "kitty_themes": "kitty_theme",
    "hyprland_animation": "hyprland_animation",
    "hyprland_animations": "hyprland_animation",
    "wallpaper": "wallpaper",
    "wallpapers": "wallpaper",
}

_SAFE_SNAPSHOT_ID_RE = re.compile(r"^[A-Za-z0-9._-]+$")


class SafetyEngine:
    def __init__(self, target_home: Optional[str] = None):
        """
        :param target_home: Allows mocking target directory for tests and sandboxes.
        """
        if target_home:
            self.home = Path(target_home).resolve()
        else:
            self.home = Path(os.environ.get("HOME", str(Path.home()))).resolve()

        self.config_dir = self.home / ".config"
        self.backups_dir = self.config_dir / "yusei-settings-backups"
        self._active_wp_proc: Optional[subprocess.Popen] = None

    @staticmethod
    def normalize_category(category: Optional[str]) -> str:
        """Maps singular/plural category names to their canonical singular key."""
        if not isinstance(category, str):
            raise ValueError(f"Unsupported category: {category!r}")
        canonical = CATEGORY_ALIASES.get(category.strip().lower())
        if not canonical:
            raise ValueError(f"Unsupported category: {category!r}")
        return canonical

    @staticmethod
    def validate_snapshot_id(snapshot_id: Any) -> str:
        """Validates a single-segment snapshot identifier without path traversal."""
        if (
            not isinstance(snapshot_id, str)
            or not snapshot_id
            or snapshot_id in {".", ".."}
            or not _SAFE_SNAPSHOT_ID_RE.fullmatch(snapshot_id)
        ):
            raise ValueError(f"Invalid snapshot_id: {snapshot_id!r}")
        return snapshot_id

    @staticmethod
    def _resolve_rofi_source(source_p: Path, item_id: Optional[str] = None) -> Path:
        """Resolves legacy config.rasi references to the actual themes/*.rasi file."""
        if source_p.name != "config.rasi":
            return source_p
        themes_dir = source_p.parent / "themes"
        candidates = []
        if isinstance(item_id, str) and item_id and "/" not in item_id and "\\" not in item_id:
            candidates.append(themes_dir / f"{item_id}.rasi")
        candidates.append(themes_dir / "End-4-Material3.rasi")
        for cand in candidates:
            if cand.exists() and cand.is_file():
                return cand
        return source_p

    @staticmethod
    def _ensure_fade_dpms_disabled(content: str) -> str:
        """Ensures `animation = fadeDpms, 0` is present inside an animation config."""
        if re.search(r"^\s*animation\s*=\s*fadeDpms\s*,", content, flags=re.MULTILINE):
            return re.sub(
                r"^\s*animation\s*=\s*fadeDpms\s*,.*$",
                "    animation = fadeDpms, 0",
                content,
                flags=re.MULTILINE,
            )

        block_close = re.search(r"\n\}\s*$", content)
        if re.search(r"animations\s*\{", content) and block_close:
            prefix = content[:block_close.start()].rstrip("\n")
            return f"{prefix}\n    animation = fadeDpms, 0\n}}\n"

        stripped = content.rstrip("\n")
        if stripped:
            stripped += "\n\n"
        return f"{stripped}animations {{\n    animation = fadeDpms, 0\n}}\n"

    def _is_within_home(self, path: Path) -> bool:
        """Checks containment without dereferencing a final symlink target."""
        abs_p = Path(os.path.abspath(str(path)))
        return abs_p.is_relative_to(self.home)

    def analyze_impact(self, category: str, item_id: str, source_path: str) -> Dict[str, Any]:
        """
        Stage 1 & 2: Analyzes exact files that will be modified without writing anything.
        """
        canonical_cat = self.normalize_category(category)
        if not isinstance(source_path, str) or not source_path or "\x00" in source_path:
            raise ValueError("Invalid source_path")

        affected_files = []
        source_p = Path(source_path)

        if canonical_cat == "waybar_layout":
            target = self.config_dir / "waybar" / "config"
            affected_files.append({
                "target": str(target),
                "action": "symlink",
                "source": str(source_p),
                "description": f"Symlink Waybar layout to {source_p.name}",
            })
        elif canonical_cat == "waybar_style":
            target = self.config_dir / "waybar" / "style.css"
            affected_files.append({
                "target": str(target),
                "action": "symlink",
                "source": str(source_p),
                "description": f"Symlink Waybar style to {source_p.name}",
            })
        elif canonical_cat == "rofi_theme":
            resolved_rofi_src = self._resolve_rofi_source(source_p, item_id)
            target = self.config_dir / "rofi" / "config.rasi"
            affected_files.append({
                "target": str(target),
                "action": "modify_theme_directive",
                "source": str(resolved_rofi_src),
                "description": f"Update @theme directive in Rofi config to {resolved_rofi_src.name}",
            })
        elif canonical_cat == "kitty_theme":
            target = self.config_dir / "kitty" / "kitty.conf"
            current_theme = self.config_dir / "kitty" / "current-theme.conf"
            affected_files.append({
                "target": str(target),
                "action": "modify_include_directive",
                "source": str(source_p),
                "description": f"Update include directive in Kitty config to ./kitty-themes/{source_p.name}",
            })
            affected_files.append({
                "target": str(current_theme),
                "action": "copy",
                "source": str(source_p),
                "description": f"Sync Kitty current-theme.conf to {source_p.name}",
            })
        elif canonical_cat == "hyprland_animation":
            target = self.config_dir / "hypr" / "animations.conf"
            affected_files.append({
                "target": str(target),
                "action": "modify_source_directive",
                "source": str(source_p),
                "description": f"Update animation source to ./animations/{source_p.name} (preserving fadeDpms = 0)",
            })
            user_anim = self.config_dir / "hypr" / "UserConfigs" / "UserAnimations.conf"
            if user_anim.parent.exists():
                affected_files.append({
                    "target": str(user_anim),
                    "action": "sync_user_animations",
                    "source": str(source_p),
                    "description": f"Sync UserAnimations.conf with {source_p.name} (preserving fadeDpms = 0)",
                })
        elif canonical_cat == "wallpaper":
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
                "description": "Update .current_wallpaper symlink",
            })

        return {
            "status": "READY_FOR_CONFIRMATION",
            "category": canonical_cat,
            "item_id": item_id,
            "source_path": str(source_p),
            "affected_files": affected_files,
            "unaffected_scope": "All unrelated desktop configurations, keybinds, rules, and daemons will remain untouched.",
            "confirmation_required": True,
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        }

    def create_snapshot(self, files_to_backup: List[str]) -> str:
        """
        Stage 3: Creates a timestamped backup snapshot with manifest.json.
        """
        self.backups_dir.mkdir(parents=True, exist_ok=True)
        base_id = f"snapshot_{time.strftime('%Y%m%d_%H%M%S')}"
        snapshot_id = base_id
        suffix = 1
        while (self.backups_dir / snapshot_id).exists():
            snapshot_id = f"{base_id}_{suffix}"
            suffix += 1

        snapshot_dir = self.backups_dir / snapshot_id
        snapshot_dir.mkdir(parents=True, exist_ok=True)

        manifest = {
            "snapshot_id": snapshot_id,
            "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "backed_up_files": [],
            "non_existent_files": [],
        }

        for idx, path_str in enumerate(files_to_backup):
            target_p = Path(path_str)
            if target_p.is_symlink():
                link_target = str(os.readlink(target_p))
                manifest["backed_up_files"].append({
                    "original_path": str(target_p),
                    "is_symlink": True,
                    "link_target": link_target,
                })
            elif target_p.exists() and target_p.is_file():
                backup_name = f"{idx:03d}_{target_p.name}"
                backup_dest = snapshot_dir / backup_name
                shutil.copy2(target_p, backup_dest)
                manifest["backed_up_files"].append({
                    "original_path": str(target_p),
                    "is_symlink": False,
                    "backup_file": backup_name,
                })
            else:
                manifest["non_existent_files"].append(str(target_p))

        manifest_file = snapshot_dir / "manifest.json"
        manifest_file.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

        latest_file = self.backups_dir / "latest.json"
        latest_file.write_text(json.dumps({"latest_snapshot": snapshot_id}, indent=2), encoding="utf-8")

        return snapshot_id

    def _run_wallpaper_reload(self, resolved_wp: str, wallust_script: str, engine_script: str) -> None:
        """Applies live wallpaper and dynamic color extraction without shell interpolation."""
        env = os.environ.copy()
        local_bin = str(self.home / ".local" / "bin")
        env["PATH"] = f"{local_bin}:{env.get('PATH', '')}"

        try:
            chk = subprocess.run(
                ["pgrep", "-x", "swww-daemon"],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            if chk.returncode != 0:
                subprocess.Popen(
                    ["swww-daemon", "--format", "xrgb"],
                    env=env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
                time.sleep(0.2)

            proc = subprocess.Popen(
                [
                    "swww",
                    "img",
                    resolved_wp,
                    "--transition-type",
                    "any",
                    "--transition-fps",
                    "60",
                    "--transition-duration",
                    "1.2",
                    "--transition-bezier",
                    ".43,1.19,1,.4",
                ],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            self._active_wp_proc = proc
            proc.wait(timeout=10)
        except Exception:
            pass

        for script_path in (wallust_script, engine_script):
            sp = Path(script_path)
            if sp.is_file() and os.access(sp, os.X_OK):
                try:
                    proc = subprocess.Popen(
                        ["bash", str(sp), resolved_wp],
                        env=env,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                    self._active_wp_proc = proc
                    proc.wait(timeout=15)
                except Exception:
                    pass
                break

    def apply_change(
        self,
        category: str,
        item_id: str,
        source_path: str,
        confirmed: bool,
        skip_snapshot: bool = False,
    ) -> Dict[str, Any]:
        """
        Stage 4 & 5: Requires confirmation, takes snapshot (unless skip_snapshot=True), then performs surgical update.
        """
        if not confirmed:
            raise PermissionError("Explicit user confirmation is mandatory before executing apply.")

        canonical_cat = self.normalize_category(category)
        impact = self.analyze_impact(canonical_cat, item_id, source_path)

        # Verify resolved source file exists before creating snapshots or mutating configs
        for item in impact["affected_files"]:
            src = Path(item["source"])
            if not src.exists() or not src.is_file():
                raise FileNotFoundError(f"Source file not found: {src}")

        targets_to_backup = [f["target"] for f in impact["affected_files"]]
        snapshot_id = None if skip_snapshot else self.create_snapshot(targets_to_backup)

        real_home = Path(os.environ.get("HOME", str(Path.home()))).resolve()
        is_live_session = (self.home == real_home)

        for item in impact["affected_files"]:
            target_p = Path(item["target"])
            target_p.parent.mkdir(parents=True, exist_ok=True)
            source_p = Path(item["source"])

            if item["action"] == "symlink":
                if target_p.exists() or target_p.is_symlink():
                    target_p.unlink()
                if canonical_cat == "waybar_layout":
                    local_cfg = target_p.parent / "configs" / source_p.name
                    if not local_cfg.exists() and source_p.exists():
                        local_cfg.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(source_p, local_cfg)
                    if local_cfg.exists():
                        target_p.symlink_to(local_cfg)
                    else:
                        target_p.symlink_to(source_p.resolve())
                elif canonical_cat == "waybar_style":
                    local_style = target_p.parent / "style" / source_p.name
                    if not local_style.exists() and source_p.exists():
                        local_style.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(source_p, local_style)
                    if local_style.exists():
                        target_p.symlink_to(local_style)
                    else:
                        target_p.symlink_to(source_p.resolve())
                else:
                    try:
                        target_p.symlink_to(source_p.resolve())
                    except Exception:
                        rel = os.path.relpath(source_p, target_p.parent)
                        target_p.symlink_to(rel)

            elif item["action"] == "copy":
                if skip_snapshot and canonical_cat == "wallpaper":
                    if target_p.exists() or target_p.is_symlink():
                        target_p.unlink()
                    try:
                        target_p.symlink_to(source_p.resolve())
                    except Exception:
                        shutil.copy2(source_p, target_p)
                else:
                    if target_p.is_symlink():
                        target_p.unlink()
                    shutil.copy2(source_p, target_p)

            elif item["action"] == "modify_theme_directive":
                if source_p.name == "config.rasi":
                    raise ValueError("Cannot point Rofi @theme to config.rasi itself.")

                content = ""
                if target_p.exists():
                    content = target_p.read_text(encoding="utf-8", errors="ignore")

                local_theme = target_p.parent / "themes" / source_p.name
                if not local_theme.exists() or local_theme.resolve() != source_p.resolve():
                    local_theme.parent.mkdir(parents=True, exist_ok=True)
                    if source_p.resolve() != local_theme.resolve():
                        shutil.copy2(source_p, local_theme)

                theme_ref = (
                    f"~/.config/rofi/themes/{source_p.name}"
                    if is_live_session
                    else f"{self.config_dir}/rofi/themes/{source_p.name}"
                )
                new_theme_line = f'@theme "{theme_ref}"'

                lines = content.splitlines()
                replaced = False
                new_lines = []
                for line in lines:
                    if line.strip().startswith("@theme"):
                        if not replaced:
                            new_lines.append(new_theme_line)
                            replaced = True
                    else:
                        new_lines.append(line)

                if replaced:
                    content = "\n".join(new_lines) + "\n"
                else:
                    base = content.rstrip("\n")
                    content = f"{base}\n{new_theme_line}\n" if base else f"{new_theme_line}\n"
                target_p.write_text(content, encoding="utf-8")

            elif item["action"] == "modify_include_directive":
                local_kitty_theme = target_p.parent / "kitty-themes" / source_p.name
                if not local_kitty_theme.exists() and source_p.exists():
                    local_kitty_theme.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source_p, local_kitty_theme)

                content = ""
                if target_p.exists():
                    content = target_p.read_text(encoding="utf-8", errors="ignore")
                new_inc_line = f"include ./kitty-themes/{source_p.name}"
                inc_pattern = re.compile(r"^[ \t]*(?:#[ \t]*)?include[ \t]+\./kitty-themes/[^\r\n]*", re.MULTILINE)
                if inc_pattern.search(content):
                    content = inc_pattern.sub(new_inc_line, content, count=1)
                else:
                    base = content.rstrip("\n")
                    content = f"{base}\n{new_inc_line}\n" if base else f"{new_inc_line}\n"
                target_p.write_text(content, encoding="utf-8")

            elif item["action"] == "modify_source_directive":
                local_anim = target_p.parent / "animations" / source_p.name
                if not local_anim.exists() and source_p.exists():
                    local_anim.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source_p, local_anim)

                anim_text = (
                    f"source = ./animations/{source_p.name}\n\n"
                    "animations {\n"
                    "    animation = fadeDpms, 0\n"
                    "}\n"
                )
                target_p.write_text(anim_text, encoding="utf-8")

            elif item["action"] == "sync_user_animations":
                preset_text = source_p.read_text(encoding="utf-8", errors="ignore")
                target_p.write_text(self._ensure_fade_dpms_disabled(preset_text), encoding="utf-8")

        if is_live_session:
            if canonical_cat in ("waybar_layout", "waybar_style"):
                try:
                    sig_proc = subprocess.run(
                        ["pkill", "-SIGUSR2", "waybar"],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        check=False,
                    )
                    if sig_proc.returncode != 0:
                        subprocess.Popen(
                            ["waybar"],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                            start_new_session=True,
                        )
                except Exception:
                    pass
            elif canonical_cat == "kitty_theme":
                try:
                    subprocess.run(
                        ["pkill", "-SIGUSR1", "kitty"],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        check=False,
                    )
                except Exception:
                    pass
            elif canonical_cat == "hyprland_animation":
                try:
                    subprocess.run(
                        ["hyprctl", "reload", "config-only"],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        check=False,
                        timeout=3,
                    )
                except Exception:
                    pass
            elif canonical_cat == "wallpaper":
                resolved_wp = str(Path(source_path).resolve())
                rofi_link = self.config_dir / "rofi" / ".current_wallpaper"
                try:
                    rofi_link.parent.mkdir(parents=True, exist_ok=True)
                    if rofi_link.exists() or rofi_link.is_symlink():
                        rofi_link.unlink()
                    rofi_link.symlink_to(resolved_wp)
                except Exception:
                    pass

                if self._active_wp_proc and self._active_wp_proc.poll() is None:
                    try:
                        self._active_wp_proc.terminate()
                    except Exception:
                        pass

                engine_script = str(Path(__file__).resolve().parent.parent.parent / "scripts" / "theme-engine.sh")
                wallust_script = str(self.home / ".config/hypr/scripts/WallustSwww.sh")
                threading.Thread(
                    target=self._run_wallpaper_reload,
                    args=(resolved_wp, wallust_script, engine_script),
                    daemon=True,
                ).start()
        elif canonical_cat == "wallpaper":
            try:
                engine_script = Path(__file__).resolve().parent.parent.parent / "scripts" / "theme-engine.sh"
                if engine_script.exists():
                    env = os.environ.copy()
                    env["HOME"] = str(self.home)
                    subprocess.run(
                        [str(engine_script), str(Path(source_path).resolve())],
                        env=env,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        check=False,
                        timeout=5,
                    )
            except Exception:
                pass

        return {
            "success": True,
            "message": f"Successfully applied {item_id} cleanly.",
            "category": canonical_cat,
            "item_id": item_id,
            "snapshot_id": snapshot_id,
            "can_rollback": not skip_snapshot,
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

        safe_id = self.validate_snapshot_id(snapshot_id)
        backups_root = self.backups_dir.resolve()
        snapshot_dir = (backups_root / safe_id).resolve()
        if not snapshot_dir.is_relative_to(backups_root) or snapshot_dir == backups_root:
            raise ValueError(f"Snapshot path escapes backup root: {safe_id!r}")

        manifest_file = snapshot_dir / "manifest.json"
        if not manifest_file.exists():
            raise FileNotFoundError(f"Snapshot manifest not found in {snapshot_dir}")

        manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
        restored = []

        # 1. Remove files that were newly created during apply
        for non_ext_path in manifest.get("non_existent_files", []):
            p = Path(non_ext_path)
            if not self._is_within_home(p):
                raise ValueError(f"Refusing to remove file outside target home: {p}")
            if p.exists() or p.is_symlink():
                p.unlink()
                restored.append({"file": str(p), "action": "removed_newly_created"})

        # 2. Restore backed up files
        for item in manifest.get("backed_up_files", []):
            orig_p = Path(item["original_path"])
            if not self._is_within_home(orig_p):
                raise ValueError(f"Refusing to restore file outside target home: {orig_p}")
            orig_p.parent.mkdir(parents=True, exist_ok=True)
            if orig_p.exists() or orig_p.is_symlink():
                orig_p.unlink()

            if item.get("is_symlink"):
                orig_p.symlink_to(item["link_target"])
                restored.append({"file": str(orig_p), "action": "restored_symlink"})
            else:
                backup_rel = item.get("backup_file", "")
                if not backup_rel or "/" in backup_rel or "\\" in backup_rel or backup_rel in {".", ".."}:
                    raise ValueError(f"Invalid backup_file in manifest: {backup_rel!r}")
                backup_file = (snapshot_dir / backup_rel).resolve()
                if not backup_file.is_relative_to(snapshot_dir):
                    raise ValueError(f"Backup file escapes snapshot directory: {backup_rel!r}")
                shutil.copy2(backup_file, orig_p)
                restored.append({"file": str(orig_p), "action": "restored_file"})

        return {
            "success": True,
            "snapshot_id": safe_id,
            "restored_items": restored,
            "message": f"Rollback successfully restored {len(restored)} configuration targets.",
        }

    def list_snapshots(self) -> List[Dict[str, Any]]:
        """Returns list of historical backup snapshots."""
        snapshots = []
        if not self.backups_dir.exists():
            return snapshots

        dirs = [p for p in self.backups_dir.iterdir() if p.is_dir() and (p / "manifest.json").exists()]
        dirs.sort(key=lambda p: (p.stat().st_mtime, p.name), reverse=True)
        for path in dirs:
            try:
                data = json.loads((path / "manifest.json").read_text(encoding="utf-8"))
                snapshots.append(data)
            except Exception:
                pass
        return snapshots
