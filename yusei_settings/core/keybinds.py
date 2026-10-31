"""
Keybinds Cheat Sheet Parser & Normalizer
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Parses Hyprland keybinding configurations (bindd, bindeld, bindmd, binded,
bindlnd, bindld, bind) into structured JSON with category groupings,
normalized UI key badges, and command metadata.
"""

import os
import re
from pathlib import Path
from typing import Dict, List, Any, Optional

SECTION_MAP = {
    1: "Standard Application Shortcuts",
    2: "Features & Utility Menus",
    3: "Window States, Floating & Scratchpads",
    4: "Bar & Notification Controls",
    5: "System, Session & Power Management",
    6: "Layout Dispatches",
    7: "Window Focus, Cycling & Movement",
    8: "Workspaces",
    9: "Mouse Controls",
    10: "Multimedia & Fn Audio Keys",
    11: "Screenshots",
    12: "Laptop & Hardware Addendums",
}

SECTION_ID_MAP = {
    1: "standard_application_shortcuts",
    2: "features_utility_menus",
    3: "window_states_floating_scratchpads",
    4: "bar_notification_controls",
    5: "system_session_power_management",
    6: "layout_dispatches",
    7: "window_focus_cycling_movement",
    8: "workspaces",
    9: "mouse_controls",
    10: "multimedia_fn_audio_keys",
    11: "screenshots",
    12: "laptop_hardware_addendums",
}

CODE_KEY_MAP = {f"code:{10 + i}": str(i + 1) if i < 9 else "0" for i in range(10)}

SPECIAL_KEY_MAP = {
    "mouse:272": "LMB",
    "mouse:273": "RMB",
    "mouse_down": "Scroll Down",
    "mouse_up": "Scroll Up",
    "Return": "Enter",
    "SPACE": "Space",
    "tab": "Tab",
    "TAB": "Tab",
    "left": "Left",
    "right": "Right",
    "up": "Up",
    "down": "Down",
    "bracketleft": "[",
    "bracketright": "]",
    "period": ".",
    "comma": ",",
    "Delete": "Delete",
    "Print": "Print",
    "XF86AudioRaiseVolume": "Volume +",
    "XF86AudioLowerVolume": "Volume -",
    "XF86AudioMute": "Mute",
    "XF86AudioMicMute": "Mic Mute",
    "XF86AudioPlay": "Play/Pause",
    "XF86AudioPause": "Play/Pause",
    "XF86AudioPlayPause": "Play/Pause",
    "XF86AudioNext": "Next Track",
    "XF86AudioPrev": "Prev Track",
    "XF86AudioStop": "Stop",
    "XF86MonBrightnessUp": "Brightness +",
    "XF86MonBrightnessDown": "Brightness -",
    "XF86KbdBrightnessUp": "Kbd Brightness +",
    "XF86KbdBrightnessDown": "Kbd Brightness -",
    "XF86TouchpadToggle": "Touchpad",
    "XF86Sleep": "Sleep",
    "XF86Rfkill": "Airplane Mode",
    "XF86Launch1": "ROG Control",
    "XF86Launch3": "Aura RGB",
    "XF86Launch4": "Fan Mode",
}


class KeybindParser:
    def __init__(self, config_path: Optional[str] = None):
        if config_path:
            self.config_path = Path(config_path)
        else:
            workspace_root = Path(__file__).resolve().parent.parent.parent
            self.config_path = workspace_root / "config" / "hypr" / "keybinds.conf"

    @staticmethod
    def normalize_mods(mods_str: str) -> List[str]:
        if not mods_str or not mods_str.strip():
            return []
        tokens = mods_str.strip().split()
        normalized = []
        for token in tokens:
            t = token.strip()
            if t in ("$mainMod", "SUPER"):
                normalized.append("Super")
            elif t in ("SHIFT", "SHIFT_L"):
                normalized.append("Shift")
            elif t in ("CTRL", "CONTROL"):
                normalized.append("Ctrl")
            elif t in ("ALT", "ALT_L"):
                normalized.append("Alt")
            else:
                normalized.append(t)
        return normalized

    @staticmethod
    def normalize_key(key_str: str) -> str:
        k = key_str.strip()
        if k in CODE_KEY_MAP:
            return CODE_KEY_MAP[k]
        if k in SPECIAL_KEY_MAP:
            return SPECIAL_KEY_MAP[k]
        return k

    def parse(self) -> List[Dict[str, Any]]:
        if not self.config_path.exists():
            return []

        content = self.config_path.read_text(encoding="utf-8", errors="ignore")
        lines = content.splitlines()

        current_category = "General"
        current_cat_id = "general"
        parsed_binds: List[Dict[str, Any]] = []

        for line_idx, line in enumerate(lines, 1):
            stripped = line.strip()
            if not stripped:
                continue

            # Check section headers: e.g. # 1. Standard Application Shortcuts
            sec_match = re.match(r"^#\s*([0-9]+)\.\s*(.+)", stripped)
            if sec_match:
                sec_num = int(sec_match.group(1))
                current_category = SECTION_MAP.get(sec_num, sec_match.group(2).split("(")[0].strip())
                current_cat_id = SECTION_ID_MAP.get(
                    sec_num,
                    re.sub(r"[^a-z0-9]+", "_", current_category.lower()).strip("_"),
                )
                continue

            if stripped.startswith("#"):
                continue

            if "=" not in stripped:
                continue

            directive, rest = stripped.split("=", 1)
            directive = directive.strip()
            if not directive.startswith("bind"):
                continue

            # Split comma separated parameters
            parts = [p.strip() for p in rest.split(",")]

            if directive.endswith("d"):
                # bindd = MODS, KEY, DESCRIPTION, DISPATCHER, [ARGS...]
                mods = parts[0] if len(parts) > 0 else ""
                key = parts[1] if len(parts) > 1 else ""
                desc = parts[2] if len(parts) > 2 else ""
                dispatcher = parts[3] if len(parts) > 3 else ""
                args = ", ".join(parts[4:]).strip() if len(parts) > 4 else ""
            else:
                # bind = MODS, KEY, DISPATCHER, [ARGS...]
                mods = parts[0] if len(parts) > 0 else ""
                key = parts[1] if len(parts) > 1 else ""
                desc = ""
                dispatcher = parts[2] if len(parts) > 2 else ""
                args = ", ".join(parts[3:]).strip() if len(parts) > 3 else ""

            norm_mods = self.normalize_mods(mods)
            norm_key = self.normalize_key(key)
            all_keys = norm_mods + ([norm_key] if norm_key else [])
            combo_display = " + ".join(all_keys)

            parsed_binds.append({
                "category": current_category,
                "category_id": current_cat_id,
                "directive": directive,
                "type": directive,
                "mods": mods,
                "key": key,
                "keys": all_keys,
                "combo_display": combo_display,
                "description": desc,
                "dispatcher": dispatcher,
                "args": args,
                "command": args,
                "raw_line": stripped,
                "line_number": line_idx,
            })

        return parsed_binds

    def get_categories(self) -> List[Dict[str, Any]]:
        binds = self.parse()
        seen = {}
        for b in binds:
            cat_id = b["category_id"]
            if cat_id not in seen:
                seen[cat_id] = {
                    "id": cat_id,
                    "name": b["category"],
                    "count": 0,
                }
            seen[cat_id]["count"] += 1
        return list(seen.values())

    def get_grouped(self) -> Dict[str, List[Dict[str, Any]]]:
        binds = self.parse()
        grouped: Dict[str, List[Dict[str, Any]]] = {}
        for b in binds:
            cat_id = b["category_id"]
            if cat_id not in grouped:
                grouped[cat_id] = []
            grouped[cat_id].append(b)
        return grouped
