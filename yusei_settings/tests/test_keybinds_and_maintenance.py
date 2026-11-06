"""
Unit Tests for KeybindParser, System Maintenance Endpoints, and Dynamic Theming
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Validates:
1. KeybindParser parsing of config/hypr/keybinds.conf (>=150 binds, 12 categories, normalizations, Super+Tab, Alt+Tab, etc.)
2. Server HTTP Endpoints (/api/keybinds, /api/system/status, /api/system/update/check, /api/system/backup, /api/system/update/apply)
3. Dynamic Theming integration in SafetyEngine.apply_change("wallpaper", ...) generating all 4 theme files
4. Decorations config using dynamic tokens ($primary $secondary 45deg) and bin/theme-engine.sh executable wrapper
"""

import json
import os
import shutil
import stat
import tempfile
import threading
import time
import unittest
import urllib.request
from pathlib import Path

from yusei_settings.core.keybinds import KeybindParser
from yusei_settings.core.safety import SafetyEngine
from yusei_settings.server import create_server


class TestKeybindsAndMaintenance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workspace_root = Path(__file__).resolve().parent.parent.parent
        cls.keybinds_file = cls.workspace_root / "config" / "hypr" / "keybinds.conf"
        cls.decorations_file = cls.workspace_root / "config" / "hypr" / "decorations.conf"
        cls.wrapper_script = cls.workspace_root / "bin" / "theme-engine.sh"

    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="yusei_test_m3_")
        self.mock_home = Path(self.test_dir) / "home"
        self.mock_home.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    # -------------------------------------------------------------------------
    # 1. KeybindParser Verification
    # -------------------------------------------------------------------------
    def test_01_keybinds_parser_count_and_categories(self):
        """Verify parsing >= 150 keybinds and all 12 categories present."""
        parser = KeybindParser(str(self.keybinds_file))
        binds = parser.parse()
        categories = parser.get_categories()
        grouped = parser.get_grouped()

        self.assertGreaterEqual(len(binds), 150, "Should parse at least 150 keybindings")
        self.assertEqual(len(categories), 12, "Should discover exactly 12 categories")
        self.assertEqual(len(grouped), 12, "Grouped dictionary should have 12 categories")

        expected_categories = [
            "Standard Application Shortcuts",
            "Features & Utility Menus",
            "Window States, Floating & Scratchpads",
            "Bar & Notification Controls",
            "System, Session & Power Management",
            "Layout Dispatches",
            "Window Focus, Cycling & Movement",
            "Workspaces",
            "Mouse Controls",
            "Multimedia & Fn Audio Keys",
            "Screenshots",
            "Laptop & Hardware Addendums",
        ]
        found_cat_names = [c["name"] for c in categories]
        for exp in expected_categories:
            self.assertIn(exp, found_cat_names, f"Category '{exp}' should be present in parsed categories")

    def test_02_keybinds_token_normalization(self):
        """Verify key token normalizations for UI badges."""
        parser = KeybindParser(str(self.keybinds_file))

        # Modifier normalizations
        self.assertEqual(parser.normalize_mods("$mainMod"), ["Super"])
        self.assertEqual(parser.normalize_mods("$mainMod SHIFT"), ["Super", "Shift"])
        self.assertEqual(parser.normalize_mods("$mainMod CTRL"), ["Super", "Ctrl"])
        self.assertEqual(parser.normalize_mods("CTRL ALT"), ["Ctrl", "Alt"])
        self.assertEqual(parser.normalize_mods("ALT_L"), ["Alt"])
        self.assertEqual(parser.normalize_mods("SHIFT_L"), ["Shift"])

        # Hardware keycode normalizations
        self.assertEqual(parser.normalize_key("code:10"), "1")
        self.assertEqual(parser.normalize_key("code:11"), "2")
        self.assertEqual(parser.normalize_key("code:18"), "9")
        self.assertEqual(parser.normalize_key("code:19"), "0")

        # Mouse button normalizations
        self.assertEqual(parser.normalize_key("mouse:272"), "LMB")
        self.assertEqual(parser.normalize_key("mouse:273"), "RMB")

        # XF86 audio & brightness normalizations
        self.assertEqual(parser.normalize_key("XF86AudioRaiseVolume"), "Volume +")
        self.assertEqual(parser.normalize_key("XF86AudioLowerVolume"), "Volume -")
        self.assertEqual(parser.normalize_key("XF86AudioMute"), "Mute")
        self.assertEqual(parser.normalize_key("XF86AudioPlay"), "Play/Pause")
        self.assertEqual(parser.normalize_key("XF86AudioPause"), "Play/Pause")
        self.assertEqual(parser.normalize_key("XF86MonBrightnessUp"), "Brightness +")
        self.assertEqual(parser.normalize_key("XF86MonBrightnessDown"), "Brightness -")

    def test_03_critical_keybinds_presence(self):
        """Verify critical binds: Super + Tab, Alt + Tab, Super + Shift + Tab."""
        parser = KeybindParser(str(self.keybinds_file))
        binds = parser.parse()
        combos = [b["combo_display"] for b in binds]

        self.assertIn("Super + Tab", combos, "Super + Tab must be parsed")
        self.assertIn("Alt + Tab", combos, "Alt + Tab must be parsed")
        self.assertIn("Super + Shift + Tab", combos, "Super + Shift + Tab must be parsed")

    # -------------------------------------------------------------------------
    # 2. Server HTTP Endpoints
    # -------------------------------------------------------------------------
    def test_04_server_http_endpoints(self):
        """Verify GET /api/keybinds, GET /api/system/status, and POST /api/system/backup."""
        server = create_server(host="127.0.0.1", port=9234, workspace_root=str(self.workspace_root), target_home=str(self.mock_home))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        time.sleep(0.2)

        try:
            # 1. GET /api/keybinds
            url_kb = "http://127.0.0.1:9234/api/keybinds"
            with urllib.request.urlopen(url_kb) as resp:
                self.assertEqual(resp.status, 200)
                data = json.loads(resp.read().decode("utf-8"))
                self.assertIn("total", data)
                self.assertGreaterEqual(data["total"], 150)
                self.assertIn("categories", data)
                self.assertEqual(len(data["categories"]), 12)
                self.assertIn("keybinds", data)
                self.assertGreaterEqual(len(data["keybinds"]), 150)

            # 2. GET /api/system/status
            url_st = "http://127.0.0.1:9234/api/system/status"
            with urllib.request.urlopen(url_st) as resp:
                self.assertEqual(resp.status, 200)
                data = json.loads(resp.read().decode("utf-8"))
                self.assertIn("git_branch", data)
                self.assertIn("dirty", data)
                self.assertIn("last_backup", data)

            # 3. GET /api/system/update/check
            url_up = "http://127.0.0.1:9234/api/system/update/check"
            with urllib.request.urlopen(url_up) as resp:
                self.assertEqual(resp.status, 200)
                data = json.loads(resp.read().decode("utf-8"))
                self.assertIn("update_available", data)
                self.assertIn("current_commit", data)

            # 4. POST /api/system/backup
            url_bk = "http://127.0.0.1:9234/api/system/backup"
            req = urllib.request.Request(url_bk, data=b"{}", headers={"Content-Type": "application/json"}, method="POST")
            with urllib.request.urlopen(req) as resp:
                self.assertEqual(resp.status, 200)
                data = json.loads(resp.read().decode("utf-8"))
                self.assertTrue(data.get("success"), "Backup trigger should succeed")
                self.assertIn("backup_dir", data)
                self.assertTrue(Path(data["backup_dir"]).exists(), "Backup directory should exist")

            # 5. POST /api/system/update/apply (dry-run)
            url_up_apply = "http://127.0.0.1:9234/api/system/update/apply"
            req_up = urllib.request.Request(
                url_up_apply,
                data=json.dumps({"confirmed": True, "dry_run": True}).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST"
            )
            with urllib.request.urlopen(req_up) as resp:
                self.assertEqual(resp.status, 200)
                data = json.loads(resp.read().decode("utf-8"))
                self.assertTrue(data.get("success"), "Update dry-run should succeed")

        finally:
            server.shutdown()
            server.server_close()

    # -------------------------------------------------------------------------
    # 3. Dynamic Theming Integration
    # -------------------------------------------------------------------------
    def test_05_dynamic_theming_on_wallpaper_apply(self):
        """In temporary sandbox, verifies SafetyEngine.apply_change("wallpaper", ...) generates all 4 color files."""
        safety = SafetyEngine(target_home=str(self.mock_home))
        wallpaper_src = self.workspace_root / "assets" / "wallpapers" / "default.jpg"

        result = safety.apply_change("wallpaper", "default", str(wallpaper_src), confirmed=True)
        self.assertTrue(result["success"])

        # Check all 4 dynamically generated files
        colors_conf = self.mock_home / ".config" / "hypr" / "colors.conf"
        colors_css = self.mock_home / ".config" / "waybar" / "colors.css"
        colors_rasi = self.mock_home / ".config" / "rofi" / "colors.rasi"
        theme_conf = self.mock_home / ".config" / "kitty" / "theme.conf"

        self.assertTrue(colors_conf.exists(), "hypr/colors.conf must be generated")
        self.assertTrue(colors_css.exists(), "waybar/colors.css must be generated")
        self.assertTrue(colors_rasi.exists(), "rofi/colors.rasi must be generated")
        self.assertTrue(theme_conf.exists(), "kitty/theme.conf must be generated")

        # Verify colors.conf content
        conf_content = colors_conf.read_text(encoding="utf-8")
        self.assertIn("$primary", conf_content)
        self.assertIn("$secondary", conf_content)

    # -------------------------------------------------------------------------
    # 4. Decorations & Wrapper Verification
    # -------------------------------------------------------------------------
    def test_06_decorations_and_theme_wrapper(self):
        """Verifies decorations.conf border and bin/theme-engine.sh existence and executable permission."""
        # 1. decorations.conf border line
        self.assertTrue(self.decorations_file.exists(), "decorations.conf must exist")
        deco_content = self.decorations_file.read_text(encoding="utf-8")
        self.assertIn(
            "col.active_border = $primary $secondary 45deg",
            deco_content,
            "decorations.conf must use dynamic tokens $primary $secondary 45deg"
        )

        # 2. bin/theme-engine.sh wrapper
        self.assertTrue(self.wrapper_script.exists(), "bin/theme-engine.sh must exist")
        mode = os.stat(self.wrapper_script).st_mode
        self.assertTrue(bool(mode & stat.S_IXUSR), "bin/theme-engine.sh must be executable")


if __name__ == "__main__":
    unittest.main()
