"""
Dynamic Theme and Layout Discovery Engine
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Discovers available Waybar layouts/styles, Rofi themes, Kitty color palettes,
Hyprland animations, and wallpapers. Extensible via ComponentRegistry.
"""

import os
import re
import json
from pathlib import Path
from typing import Dict, List, Any, Optional

class DiscoveryEngine:
    def __init__(self, workspace_root: Optional[str] = None):
        if workspace_root:
            self.root = Path(workspace_root).resolve()
        else:
            # Default to repo root (2 levels above core/)
            self.root = Path(__file__).resolve().parent.parent.parent
            
        cand_config = self.root / "config"
        if cand_config.exists() and (cand_config / "waybar").exists():
            self.config_dir = cand_config
        elif (Path.home() / ".config" / "waybar").exists():
            self.config_dir = Path.home() / ".config"
        else:
            self.config_dir = cand_config

        cand_assets = self.root / "assets"
        if cand_assets.exists() and (cand_assets / "wallpapers").exists():
            self.assets_dir = cand_assets
        elif (Path.home() / ".local/share/yusei-hypr/assets").exists():
            self.assets_dir = Path.home() / ".local/share/yusei-hypr/assets"
        else:
            self.assets_dir = cand_assets
        
        # Registry of extensible component scanners
        self._scanners = {
            "waybar_layouts": self.discover_waybar_layouts,
            "waybar_styles": self.discover_waybar_styles,
            "rofi_themes": self.discover_rofi_themes,
            "kitty_themes": self.discover_kitty_themes,
            "hyprland_animations": self.discover_hyprland_animations,
            "wallpapers": self.discover_wallpapers,
        }

    def register_scanner(self, category: str, scanner_func):
        """Allows 3rd-party plugins or extensions to register new discovery domains."""
        self._scanners[category] = scanner_func

    def discover_all(self, fast_scan: bool = False) -> Dict[str, List[Dict[str, Any]]]:
        """Runs all registered discovery scanners and returns grouped catalog."""
        self._fast_scan = fast_scan
        catalog = {}
        for category, scanner in self._scanners.items():
            try:
                catalog[category] = scanner()
            except Exception as e:
                catalog[category] = [{"id": "error", "name": f"Error scanning {category}: {e}"}]
        self._fast_scan = False
        return catalog

    def discover_waybar_layouts(self) -> List[Dict[str, Any]]:
        """Scans config/waybar/configs/ for available layouts."""
        layouts_dir = self.config_dir / "waybar" / "configs"
        results = []
        if not layouts_dir.exists():
            return results

        fast = getattr(self, "_fast_scan", False)
        for path in sorted(layouts_dir.iterdir()):
            if path.is_file() and not path.name.startswith("."):
                name = path.name
                
                # Determine bar placement badge
                position = "TOP"
                if "[BOT" in name or "BOT &" in name:
                    position = "BOTTOM"
                elif "[LEFT]" in name:
                    position = "LEFT"
                elif "[RIGHT]" in name:
                    position = "RIGHT"
                elif "Split" in name or "Summit" in name:
                    position = "SPLIT"

                is_end4 = "End-4" in name or "Material 3" in name
                
                # Extract modules if JSON format (skipped in fast_scan mode for instant GUI startup)
                modules_summary = ["workspaces", "clock", "audio", "battery", "network"]
                if not fast:
                    try:
                        content = path.read_text(encoding="utf-8", errors="ignore")
                        cleaned = re.sub(r'//.*', '', content)
                        cleaned = re.sub(r'/\*.*?\*/', '', cleaned, flags=re.DOTALL)
                        data = json.loads(cleaned)
                        extracted = []
                        for key in ["modules-left", "modules-center", "modules-right"]:
                            if key in data and isinstance(data[key], list):
                                extracted.extend(data[key])
                        if extracted:
                            modules_summary = extracted
                    except Exception:
                        pass

                results.append({
                    "id": name,
                    "name": name.replace("[TOP]", "").replace("[BOT]", "").replace("[LEFT]", "").replace("[RIGHT]", "").strip(),
                    "raw_name": name,
                    "category": "waybar_layout",
                    "position": position,
                    "is_default": is_end4,
                    "file_path": str(path),
                    "description": f"Waybar layout placed at {position} screen edge." + (" (End-4 Material 3 Design)" if is_end4 else ""),
                    "modules": modules_summary[:6],
                    "target_config": "~/.config/waybar/config",
                })
        return results

    def discover_waybar_styles(self) -> List[Dict[str, Any]]:
        """Scans config/waybar/style/ for available CSS visual styles."""
        styles_dir = self.config_dir / "waybar" / "style"
        results = []
        if not styles_dir.exists():
            return results

        for path in sorted(styles_dir.iterdir()):
            if path.is_file() and path.suffix == ".css":
                name = path.stem
                is_end4 = "End-4" in name or "Material 3" in name
                
                theme_tag = "Modern"
                if "Translucent" in name:
                    theme_tag = "Translucent"
                elif "Neon" in name or "Glow" in name:
                    theme_tag = "Neon"
                elif "Catppuccin" in name:
                    theme_tag = "Catppuccin"
                elif "Glass" in name:
                    theme_tag = "Glassmorphism"
                elif "Dark" in name:
                    theme_tag = "Dark"
                elif "Light" in name:
                    theme_tag = "Light"

                results.append({
                    "id": name,
                    "name": name.replace("[End-4]", "").replace("[Colored]", "").replace("[Extra]", "").strip(),
                    "raw_name": path.name,
                    "category": "waybar_style",
                    "theme_tag": theme_tag,
                    "is_default": is_end4,
                    "file_path": str(path),
                    "description": f"CSS theme with {theme_tag} aesthetic for Waybar status bar.",
                    "target_config": "~/.config/waybar/style.css",
                })
        return results

    def discover_rofi_themes(self) -> List[Dict[str, Any]]:
        """Scans config/rofi/themes/ and config/rofi/ for launcher layouts."""
        themes_dir = self.config_dir / "rofi" / "themes"
        results = []
        
        # Add primary End-4 default launcher
        main_rofi = self.config_dir / "rofi" / "config.rasi"
        if main_rofi.exists():
            results.append({
                "id": "End-4-Material3",
                "name": "End-4 Material 3 (Centered Card)",
                "raw_name": "config.rasi",
                "category": "rofi_theme",
                "style_type": "Centered Card",
                "is_default": True,
                "file_path": str(main_rofi),
                "description": "Material 3 dual-column floating launcher card with 16px radius and search pill.",
                "target_config": "~/.config/rofi/config.rasi",
            })

        if themes_dir.exists():
            for path in sorted(themes_dir.iterdir()):
                if path.is_file() and path.suffix == ".rasi":
                    if path.stem == "End-4-Material3":
                        continue
                    name = path.stem
                    style_type = "Grid"
                    if "Win11" in name:
                        style_type = "Windows 11 List"
                    elif "FullScreen" in name:
                        style_type = "Fullscreen Overlay"
                    elif "Vertical" in name:
                        style_type = "Vertical Dock"
                    elif "Fancy" in name:
                        style_type = "Card Grid"

                    results.append({
                        "id": name,
                        "name": name.replace("KooL_", "").replace("style-", "Style ").replace("-", " "),
                        "raw_name": path.name,
                        "category": "rofi_theme",
                        "style_type": style_type,
                        "is_default": False,
                        "file_path": str(path),
                        "description": f"Rofi application launcher with {style_type} layout.",
                        "target_config": "~/.config/rofi/config.rasi",
                    })
        return results

    def discover_kitty_themes(self) -> List[Dict[str, Any]]:
        """Scans config/kitty/kitty-themes/ and extracts primary palette colors."""
        themes_dir = self.config_dir / "kitty" / "kitty-themes"
        results = []
        if not themes_dir.exists():
            return results

        fast = getattr(self, "_fast_scan", False)
        color_regex = None if fast else re.compile(r'^\s*(background|foreground|color[0-7])\s+([#0-9a-fA-F]{6,8})', re.IGNORECASE)

        for path in sorted(themes_dir.iterdir()):
            if path.is_file() and path.suffix == ".conf":
                name = path.stem
                is_wallust = "01-Wallust" in name
                
                # Extract color swatches (skipped in fast_scan mode for instant GUI startup)
                palette = {
                    "background": "#141316",
                    "foreground": "#e3e2e6",
                    "swatches": ["#1f1f23", "#f2b8b5", "#b4e09f", "#fce788", "#a8c7fa", "#d3bbff", "#99e7eb", "#e3e2e6"]
                }
                if not fast and color_regex is not None:
                    try:
                        content = path.read_text(encoding="utf-8", errors="ignore")
                        for line in content.splitlines():
                            match = color_regex.match(line)
                            if match:
                                key, val = match.group(1).lower(), match.group(2)
                                if key == "background":
                                    palette["background"] = val
                                elif key == "foreground":
                                    palette["foreground"] = val
                                elif key.startswith("color"):
                                    idx = int(key.replace("color", ""))
                                    if idx < len(palette["swatches"]):
                                        palette["swatches"][idx] = val
                    except Exception:
                        pass

                results.append({
                    "id": name,
                    "name": name.replace("00-", "").replace("01-", "").replace("-", " "),
                    "raw_name": path.name,
                    "category": "kitty_theme",
                    "is_default": is_wallust,
                    "file_path": str(path),
                    "palette": palette,
                    "description": "Dynamic Wallust wallpaper theme" if is_wallust else f"Terminal color theme {name}.",
                    "target_config": "~/.config/kitty/kitty-themes/" + path.name,
                })
        return results

    def discover_hyprland_animations(self) -> List[Dict[str, Any]]:
        """Scans config/hypr/animations/ for physics bezier curves."""
        anim_dir = self.config_dir / "hypr" / "animations"
        results = []
        if not anim_dir.exists():
            return results

        for path in sorted(anim_dir.iterdir()):
            if path.is_file() and path.suffix == ".conf":
                name = path.stem
                is_end4 = "END-4" in name
                
                description = "Default fluid bezier curves"
                if "END-4" in name:
                    description = "End-4 Expressive Material 3 fast physics curves."
                elif "HYDE" in name:
                    description = "HyDE dynamic responsive bezier animation curve."
                elif "ML4W" in name:
                    description = "ML4W smooth balanced window motion profiles."

                results.append({
                    "id": name,
                    "name": name.replace("00-", "").replace("-", " "),
                    "raw_name": path.name,
                    "category": "hyprland_animation",
                    "is_default": is_end4,
                    "file_path": str(path),
                    "description": description,
                    "target_config": "~/.config/hypr/animations/" + path.name,
                })
        return results

    def discover_wallpapers(self) -> List[Dict[str, Any]]:
        """Scans assets/wallpapers/ and user picture folders for high-resolution backgrounds."""
        search_dirs = [self.assets_dir / "wallpapers"]
        home_wp = Path.home() / "Pictures" / "wallpapers"
        if home_wp.exists() and home_wp not in search_dirs:
            search_dirs.append(home_wp)
        hypr_wp = Path.home() / ".config" / "hypr" / "wallpapers"
        if hypr_wp.exists() and hypr_wp not in search_dirs:
            search_dirs.append(hypr_wp)

        results = []
        seen = set()
        for wp_dir in search_dirs:
            if not wp_dir.exists():
                continue
            for path in sorted(wp_dir.rglob("*")):
                if path.is_file() and path.suffix.lower() in [".jpg", ".jpeg", ".png", ".webp"]:
                    if path.name in seen:
                        continue
                    seen.add(path.name)
                    name = path.stem
                    folder_hint = path.parent.name if path.parent != wp_dir else "Wallpapers"
                    results.append({
                        "id": name,
                        "name": name.replace("-", " ").replace("_", " ").title(),
                        "raw_name": path.name,
                        "category": "wallpaper",
                        "file_path": str(path),
                        "relative_url": f"/assets/wallpapers/{path.name}",
                        "description": f"{folder_hint} • {path.suffix[1:].upper()} ({path.name})",
                    })
        return results
