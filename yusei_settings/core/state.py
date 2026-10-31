"""
System & Workspace State Manager
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Detects currently active configurations by analyzing symlinks and include directives.
Supports custom target directories for sandbox testing.
"""

import os
import re
from pathlib import Path
from typing import Dict, Any, Optional

class StateManager:
    def __init__(self, target_home: Optional[str] = None):
        """
        :param target_home: Allows mocking $HOME for safe dry-run / sandbox testing.
        """
        if target_home:
            self.home = Path(target_home).resolve()
        else:
            self.home = Path(os.environ.get("HOME", "/home/user")).resolve()
            
        self.config_dir = self.home / ".config"

    def get_active_state(self) -> Dict[str, Any]:
        """Returns the dictionary of currently active theme and layout IDs."""
        return {
            "waybar_layout": self.get_active_waybar_layout(),
            "waybar_style": self.get_active_waybar_style(),
            "rofi_theme": self.get_active_rofi_theme(),
            "kitty_theme": self.get_active_kitty_theme(),
            "hyprland_animation": self.get_active_hyprland_animation(),
            "current_wallpaper": self.get_active_wallpaper(),
        }

    def get_active_waybar_layout(self) -> str:
        cfg = self.config_dir / "waybar" / "config"
        if not cfg.exists():
            cfg_json = self.config_dir / "waybar" / "config.jsonc"
            if cfg_json.exists():
                return "End-4 Material 3"
            return "Default"

        if cfg.is_symlink():
            try:
                target = cfg.resolve()
                return target.name
            except Exception:
                pass
        return "Active Layout"

    def get_active_waybar_style(self) -> str:
        style = self.config_dir / "waybar" / "style.css"
        if not style.exists():
            return "Default"
        if style.is_symlink():
            try:
                return style.resolve().stem
            except Exception:
                pass
        return "Active Style"

    def get_active_rofi_theme(self) -> str:
        cfg = self.config_dir / "rofi" / "config.rasi"
        if not cfg.exists():
            return "End-4-Material3"
        try:
            content = cfg.read_text(encoding="utf-8", errors="ignore")
            match = re.search(r'@theme\s+["\']~?/\.config/rofi/themes/([^"\']+)\.rasi["\']', content)
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
            match = re.search(r'include\s+\./kitty-themes/([^"\']+)\.conf', content)
            if match:
                return match.group(1)
        except Exception:
            pass
        return "01-Wallust"

    def get_active_hyprland_animation(self) -> str:
        cfg = self.config_dir / "hypr" / "animations.conf"
        if not cfg.exists():
            return "00-default"
        try:
            content = cfg.read_text(encoding="utf-8", errors="ignore")
            match = re.search(r'source\s*=\s*\./animations/([^"\']+)\.conf', content)
            if match:
                return match.group(1)
        except Exception:
            pass
        return "00-default"

    def get_active_wallpaper(self) -> str:
        cur = self.config_dir / "hypr" / ".current_wallpaper"
        if cur.exists() and cur.is_symlink():
            try:
                return cur.resolve().name
            except Exception:
                pass
        return "default.jpg"
