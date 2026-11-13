"""
System & Workspace State Manager
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Detects currently active configurations by analyzing symlinks and include directives.
Supports custom target directories for sandbox testing.
"""

import os
import re
from pathlib import Path
from typing import Any, Dict, Optional


class StateManager:
    def __init__(self, target_home: Optional[str] = None):
        """
        :param target_home: Allows mocking $HOME for safe dry-run / sandbox testing.
        """
        if target_home:
            self.home = Path(target_home).resolve()
        else:
            self.home = Path(os.environ.get("HOME", str(Path.home()))).resolve()

        self.config_dir = self.home / ".config"

    def get_active_state(self) -> Dict[str, Any]:
        """Returns the dictionary of currently active theme and layout IDs."""
        active_wp = self.get_active_wallpaper()
        return {
            "waybar_layout": self.get_active_waybar_layout(),
            "waybar_style": self.get_active_waybar_style(),
            "rofi_theme": self.get_active_rofi_theme(),
            "kitty_theme": self.get_active_kitty_theme(),
            "hyprland_animation": self.get_active_hyprland_animation(),
            "active_wallpaper": active_wp,
            "current_wallpaper": active_wp,
            "wallpaper": active_wp,
        }

    @staticmethod
    def _match_by_bytes(target_file: Path, candidates_dir: Path, use_stem: bool = False) -> Optional[str]:
        if not target_file.is_file() or not candidates_dir.is_dir():
            return None
        try:
            target_bytes = target_file.read_bytes()
        except Exception:
            return None
        for cand in sorted(candidates_dir.iterdir()):
            if cand.is_file() and not cand.name.startswith("."):
                try:
                    if cand.read_bytes() == target_bytes:
                        return cand.stem if use_stem else cand.name
                except Exception:
                    pass
        return None

    def get_active_waybar_layout(self) -> str:
        cfg = self.config_dir / "waybar" / "config"
        if not cfg.exists() and not cfg.is_symlink():
            cfg_json = self.config_dir / "waybar" / "config.jsonc"
            if cfg_json.exists():
                return "[TOP] End-4 Material 3"
            return "[TOP] End-4 Material 3"

        if cfg.is_symlink():
            try:
                return cfg.resolve().name
            except Exception:
                pass

        matched = self._match_by_bytes(cfg, self.config_dir / "waybar" / "configs", use_stem=False)
        if matched:
            return matched

        try:
            content = cfg.read_text(encoding="utf-8", errors="ignore")
            if "End-4" in content or "Material 3" in content:
                return "[TOP] End-4 Material 3"
        except Exception:
            pass
        return "Active Layout"

    def get_active_waybar_style(self) -> str:
        style = self.config_dir / "waybar" / "style.css"
        if not style.exists() and not style.is_symlink():
            return "[End-4] Material 3"
        if style.is_symlink():
            try:
                return style.resolve().stem
            except Exception:
                pass

        matched = self._match_by_bytes(style, self.config_dir / "waybar" / "style", use_stem=True)
        if matched:
            return matched
        return "Active Style"

    def get_active_rofi_theme(self) -> str:
        cfg = self.config_dir / "rofi" / "config.rasi"
        if not cfg.exists():
            return "End-4-Material3"
        try:
            content = cfg.read_text(encoding="utf-8", errors="ignore")
            match = re.search(
                r'^\s*@theme\s+["\'](?:[^"\']*/)?rofi/themes/([^"\']+)\.rasi["\']',
                content,
                flags=re.MULTILINE,
            )
            if match:
                return match.group(1)
            if "Material 3" in content or "End-4" in content:
                return "End-4-Material3"
        except Exception:
            pass
        return "End-4-Material3"

    def get_active_kitty_theme(self) -> str:
        cfg = self.config_dir / "kitty" / "kitty.conf"
        if not cfg.exists():
            return "01-Wallust"
        try:
            content = cfg.read_text(encoding="utf-8", errors="ignore")
            match = re.search(
                r'^\s*include\s+\./kitty-themes/([^"\'\r\n#]+?)\.conf\s*(?:#.*)?$',
                content,
                flags=re.MULTILINE,
            )
            if match:
                return match.group(1).strip()
        except Exception:
            pass
        return "01-Wallust"

    def get_active_hyprland_animation(self) -> str:
        cfg = self.config_dir / "hypr" / "animations.conf"
        if not cfg.exists():
            return "00-default"
        try:
            content = cfg.read_text(encoding="utf-8", errors="ignore")
            match = re.search(
                r'^\s*source\s*=\s*\./animations/([^"\'\r\n#]+?)\.conf\s*(?:#.*)?$',
                content,
                flags=re.MULTILINE,
            )
            if match:
                return match.group(1).strip()
        except Exception:
            pass
        return "00-default"

    def _wallpaper_path_to_id(self, raw_path: str, base_dir: Optional[Path] = None) -> str:
        p = Path(raw_path)
        if not p.is_absolute() and base_dir is not None:
            p = base_dir / p

        wp_roots = [
            self.home / "Pictures" / "wallpapers",
            self.config_dir / "hypr" / "wallpapers",
        ]
        for root in wp_roots:
            try:
                rel = p.resolve().relative_to(root.resolve())
                return rel.with_suffix("").as_posix()
            except Exception:
                pass

        parts = p.parts
        if "wallpapers" in parts:
            idx = len(parts) - 1 - parts[::-1].index("wallpapers")
            rel_parts = parts[idx + 1 :]
            if rel_parts:
                return Path(*rel_parts).with_suffix("").as_posix()

        return p.stem

    def get_active_wallpaper(self) -> str:
        candidates = [
            self.config_dir / "rofi" / ".current_wallpaper",
            self.config_dir / "hypr" / ".current_wallpaper",
        ]
        for cur in candidates:
            try:
                if cur.is_symlink():
                    target_str = os.readlink(cur)
                    if target_str:
                        return self._wallpaper_path_to_id(target_str, base_dir=cur.parent)
                elif cur.exists() and cur.is_file():
                    content = cur.read_text(encoding="utf-8", errors="ignore").strip()
                    if content and "\n" not in content and len(content) < 512:
                        return self._wallpaper_path_to_id(content, base_dir=cur.parent)
            except Exception:
                pass
        return "default"
