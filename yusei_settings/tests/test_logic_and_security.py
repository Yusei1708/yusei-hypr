"""
Comprehensive Regression & Security Tests for Commit 5 (`yusei_settings`)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Strictly sandboxed using `tempfile.TemporaryDirectory()` — never modifies
host `~/.config`, `~/.local`, or `/etc`.
"""

import http.client
import json
import os
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

from yusei_settings.core.keybinds import KeybindParser
from yusei_settings.core.power import PowerManager
from yusei_settings.core.safety import SafetyEngine
from yusei_settings.server import create_server
from yusei_settings.ui.gtk.window import (
    _read_user_decorations_state,
    _update_user_decorations_file,
)


class TestSafetyEngineCommit5(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="yusei_safety_c5_")
        self.root = Path(self._tmp.name)
        self.home = self.root / "home"
        self.assets = self.root / "assets"
        self.home.mkdir(parents=True, exist_ok=True)
        self.assets.mkdir(parents=True, exist_ok=True)
        self.engine = SafetyEngine(target_home=str(self.home))

    def tearDown(self):
        self._tmp.cleanup()

    def test_plural_and_singular_categories_supported(self):
        """Plural and singular aliases normalize consistently and apply cleanly."""
        wp_src = self.assets / "wall.png"
        wp_src.write_bytes(b"\x89PNG\r\n\x1a\n")
        layout_src = self.assets / "layout.jsonc"
        layout_src.write_text('{"position":"TOP"}', encoding="utf-8")
        rofi_src = self.assets / "material.rasi"
        rofi_src.write_text("configuration {}", encoding="utf-8")
        kitty_src = self.assets / "cat.conf"
        kitty_src.write_text("background #111111\n", encoding="utf-8")
        anim_src = self.assets / "anim-end4.conf"
        anim_src.write_text("animations {\n    enabled = yes\n}\n", encoding="utf-8")

        cases = [
            ("wallpapers", "wallpaper", wp_src),
            ("wallpaper", "wallpaper", wp_src),
            ("waybar_layouts", "waybar_layout", layout_src),
            ("waybar_layout", "waybar_layout", layout_src),
            ("rofi_themes", "rofi_theme", rofi_src),
            ("rofi_theme", "rofi_theme", rofi_src),
            ("kitty_themes", "kitty_theme", kitty_src),
            ("kitty_theme", "kitty_theme", kitty_src),
            ("hyprland_animations", "hyprland_animation", anim_src),
            ("hyprland_animation", "hyprland_animation", anim_src),
        ]

        for raw_cat, expected_canonical, src_file in cases:
            self.assertEqual(SafetyEngine.normalize_category(raw_cat), expected_canonical)
            impact = self.engine.analyze_impact(raw_cat, src_file.stem, str(src_file))
            self.assertEqual(impact["category"], expected_canonical)
            # Avoid invoking host theme-engine.sh during unit test wallpaper apply
            res = self.engine.apply_change(
                raw_cat,
                src_file.stem,
                str(src_file),
                confirmed=True,
                skip_snapshot=(expected_canonical == "wallpaper"),
            )
            self.assertTrue(res["success"])
            self.assertEqual(res["category"], expected_canonical)

        with self.assertRaises(ValueError):
            SafetyEngine.normalize_category("unknown_cat")

    def test_hyprland_animation_preserves_fadedpms_zero_and_rolls_back(self):
        """Applying animation preserves fadeDpms = 0 in both files and rolls back cleanly."""
        hypr_dir = self.home / ".config" / "hypr"
        user_cfg = hypr_dir / "UserConfigs"
        user_cfg.mkdir(parents=True, exist_ok=True)

        orig_anim = hypr_dir / "animations.conf"
        orig_user_anim = user_cfg / "UserAnimations.conf"
        orig_anim.write_text("# original animations.conf\n", encoding="utf-8")
        orig_user_anim.write_text("# original UserAnimations.conf\n", encoding="utf-8")

        preset = self.assets / "snappy.conf"
        preset.write_text(
            "animations {\n    bezier = fast, 0.2, 0.9, 0.2, 1.0\n    animation = fadeDpms, 1\n}\n",
            encoding="utf-8",
        )

        res = self.engine.apply_change("hyprland_animation", "snappy", str(preset), confirmed=True)
        snap_id = res["snapshot_id"]
        self.assertIsNotNone(snap_id)

        anim_after = orig_anim.read_text(encoding="utf-8")
        user_anim_after = orig_user_anim.read_text(encoding="utf-8")
        self.assertIn("source = ./animations/snappy.conf", anim_after)
        self.assertRegex(anim_after, r"animation\s*=\s*fadeDpms\s*,\s*0")
        self.assertRegex(user_anim_after, r"animation\s*=\s*fadeDpms\s*,\s*0")
        self.assertNotRegex(user_anim_after, r"animation\s*=\s*fadeDpms\s*,\s*1")

        rb = self.engine.rollback(snap_id)
        self.assertTrue(rb["success"])
        self.assertEqual(orig_anim.read_text(encoding="utf-8"), "# original animations.conf\n")
        self.assertEqual(orig_user_anim.read_text(encoding="utf-8"), "# original UserAnimations.conf\n")

    def test_hyprland_animation_clamps_speeds_above_100(self):
        """Applying an animation preset clamps speeds > 100 down to 100 in UserAnimations.conf."""
        (self.home / ".config" / "hypr" / "UserConfigs").mkdir(parents=True, exist_ok=True)
        preset = self.assets / "overspeed.conf"
        preset.write_text(
            "animations {\n"
            "    animation = borderangle, 1, 180, liner, loop # keep comment\n"
            "    animation = windows, 1, 6, wind, slide\n"
            "}\n",
            encoding="utf-8",
        )
        res = self.engine.apply_change("hyprland_animation", "overspeed", str(preset), confirmed=True)
        self.assertTrue(res["success"])
        user_anim = (self.home / ".config" / "hypr" / "UserConfigs" / "UserAnimations.conf").read_text(encoding="utf-8")
        self.assertIn("animation = borderangle, 1, 100, liner, loop # keep comment", user_anim)
        self.assertNotIn("180", user_anim)
        self.assertRegex(user_anim, r"animation\s*=\s*fadeDpms\s*,\s*0")

    def test_waybar_fallback_launch_prioritizes_local_bin_in_path(self):
        """When waybar is not running in live session, fallback Popen prepends ~/.local/bin to PATH."""
        style_src = self.assets / "waybar_test.css"
        style_src.write_text("/* style */\n", encoding="utf-8")
        failed_sig = mock.Mock(returncode=1)
        with mock.patch.dict(os.environ, {"HOME": str(self.home)}, clear=False), \
             mock.patch("yusei_settings.core.safety.subprocess.run", return_value=failed_sig), \
             mock.patch("yusei_settings.core.safety.subprocess.Popen") as mock_popen:
            res = self.engine.apply_change("waybar_style", "waybar_test", str(style_src), confirmed=True)
        self.assertTrue(res["success"])
        mock_popen.assert_called_once()
        popen_kwargs = mock_popen.call_args.kwargs
        env_passed = popen_kwargs["env"]
        expected_prefix = str(self.home / ".local" / "bin")
        self.assertTrue(env_passed["PATH"].startswith(expected_prefix + ":"))
        self.assertEqual(env_passed["HOME"], str(self.home))

    def test_rofi_theme_resolves_to_end4_and_never_loops_config_rasi(self):
        """Legacy config.rasi input resolves to End-4-Material3.rasi; self-referential config.rasi errors."""
        rofi_assets = self.assets / "rofi"
        themes_dir = rofi_assets / "themes"
        themes_dir.mkdir(parents=True, exist_ok=True)
        legacy_cfg = rofi_assets / "config.rasi"
        legacy_cfg.write_text('@theme "~/.config/rofi/themes/End-4-Material3.rasi"\n', encoding="utf-8")
        end4_theme = themes_dir / "End-4-Material3.rasi"
        end4_theme.write_text("/* End-4 theme */\n", encoding="utf-8")

        res = self.engine.apply_change("rofi_theme", "End-4-Material3", str(legacy_cfg), confirmed=True)
        self.assertTrue(res["success"])
        target_cfg = (self.home / ".config" / "rofi" / "config.rasi").read_text(encoding="utf-8")
        self.assertIn("End-4-Material3.rasi", target_cfg)
        self.assertNotIn('@theme "', target_cfg.split("End-4-Material3.rasi", 1)[1])

        # Without themes/ fallback, config.rasi self-target MUST raise ValueError cleanly
        orphan_dir = self.assets / "orphan_rofi"
        orphan_dir.mkdir(parents=True, exist_ok=True)
        orphan_cfg = orphan_dir / "config.rasi"
        orphan_cfg.write_text("/* orphan */", encoding="utf-8")
        with self.assertRaises(ValueError):
            self.engine.apply_change("rofi_theme", "bad", str(orphan_cfg), confirmed=True)

    def test_broken_symlink_and_missing_source_fail_before_snapshot_or_mutation(self):
        """Missing sources and broken symlinks raise FileNotFoundError before creating backups."""
        target = self.home / ".config" / "kitty" / "kitty.conf"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("font_size 11\n", encoding="utf-8")

        broken_link = self.assets / "broken.conf"
        broken_link.symlink_to(self.assets / "nonexistent_target.conf")
        missing_path = self.assets / "does_not_exist.conf"

        for bad_src in (broken_link, missing_path):
            with self.assertRaises(FileNotFoundError):
                self.engine.apply_change("kitty_theme", "broken", str(bad_src), confirmed=True)

        self.assertFalse(self.engine.backups_dir.exists() and any(self.engine.backups_dir.iterdir()))
        self.assertEqual(target.read_text(encoding="utf-8"), "font_size 11\n")

    def test_rollback_blocks_path_traversal_and_outside_home_targets(self):
        """Rollback rejects invalid snapshot IDs and manifest targets escaping target_home."""
        for bad_id in ("../etc", "..", "a/b", "snap;rm"):
            with self.assertRaises(ValueError):
                self.engine.rollback(bad_id)

        outside_file = self.root / "outside_victim.txt"
        outside_file.write_text("do_not_touch", encoding="utf-8")

        # Tamper manifest backed_up_files path outside home
        snap_dir = self.engine.backups_dir / "snapshot_tampered"
        snap_dir.mkdir(parents=True, exist_ok=True)
        (snap_dir / "000_victim").write_text("overwritten", encoding="utf-8")
        (snap_dir / "manifest.json").write_text(
            json.dumps({
                "snapshot_id": "snapshot_tampered",
                "backed_up_files": [
                    {
                        "original_path": str(outside_file),
                        "is_symlink": False,
                        "backup_file": "000_victim",
                    }
                ],
                "non_existent_files": [],
            }),
            encoding="utf-8",
        )

        with self.assertRaises(ValueError):
            self.engine.rollback("snapshot_tampered")
        self.assertEqual(outside_file.read_text(encoding="utf-8"), "do_not_touch")

        # Tamper manifest non_existent_files path outside home
        (snap_dir / "manifest.json").write_text(
            json.dumps({
                "snapshot_id": "snapshot_tampered",
                "backed_up_files": [],
                "non_existent_files": [str(outside_file)],
            }),
            encoding="utf-8",
        )
        with self.assertRaises(ValueError):
            self.engine.rollback("snapshot_tampered")
        self.assertEqual(outside_file.read_text(encoding="utf-8"), "do_not_touch")


class TestServerSecurityCommit5(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="yusei_srv_sec_")
        self.root = Path(self._tmp.name)
        self.mock_home = self.root / "home"
        self.mock_home.mkdir(parents=True, exist_ok=True)
        self.workspace_root = str(Path(__file__).resolve().parent.parent.parent)

        self.server = create_server(
            host="127.0.0.1",
            port=0,
            workspace_root=self.workspace_root,
            target_home=str(self.mock_home),
        )
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self._tmp.cleanup()

    def _raw_request(self, method: str, target: str, body: bytes = b"", headers: dict = None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            conn.request(method, target, body=body, headers=headers or {})
            resp = conn.getresponse()
            raw = resp.read()
            return resp.status, raw
        finally:
            conn.close()

    def test_http_path_traversal_blocked_with_403(self):
        """Literal '..' and URL-encoded '%2f..%2f' traversal probes return 403."""
        for bad_path in (
            "/ui/web/../../etc/passwd",
            "/assets/..%2f..%2fetc/passwd",
            "/assets/%2f..%2fetc/passwd",
            "/assets/wallpapers/..%2f..%2fetc/passwd",
        ):
            status, _ = self._raw_request("GET", bad_path)
            self.assertEqual(status, 403, f"Expected 403 for {bad_path}, got {status}")

    def test_csrf_and_content_type_guards(self):
        """CSRF headers return 403 and non-JSON Content-Type returns 415."""
        valid_body = json.dumps({"power_daemon": False}).encode("utf-8")

        csrf_cases = [
            {"Host": "evil.example.com", "Content-Type": "application/json"},
            {"Host": f"127.0.0.1:{self.port}", "Sec-Fetch-Site": "cross-site", "Content-Type": "application/json"},
            {"Host": f"127.0.0.1:{self.port}", "Origin": "https://evil.com", "Content-Type": "application/json"},
            {"Host": f"127.0.0.1:{self.port}", "Origin": "null", "Content-Type": "application/json"},
            {"Host": f"127.0.0.1:{self.port}", "Referer": "http://attacker.local/pwn", "Content-Type": "application/json"},
        ]
        for hdrs in csrf_cases:
            status, _ = self._raw_request("POST", "/api/power/config", body=valid_body, headers=hdrs)
            self.assertEqual(status, 403, f"Expected 403 for headers {hdrs}, got {status}")

        status_ct, _ = self._raw_request(
            "POST",
            "/api/power/config",
            body=valid_body,
            headers={"Host": f"127.0.0.1:{self.port}", "Content-Type": "text/plain"},
        )
        self.assertEqual(status_ct, 415)

    def test_invalid_inputs_return_400_never_500_and_neutralize_metacharacters(self):
        """Invalid JSON/category/bool return 400 and shell metacharacters cannot execute commands."""
        base_headers = {
            "Host": f"127.0.0.1:{self.port}",
            "Origin": f"http://127.0.0.1:{self.port}",
            "Content-Type": "application/json",
        }

        # Malformed JSON -> 400
        status, _ = self._raw_request("POST", "/api/power/config", body=b"{bad json", headers=base_headers)
        self.assertEqual(status, 400)

        # Invalid strict booleans -> 400 (never 500)
        for bad_bool in (1, 0, "maybe", ["true"]):
            status, data = self._raw_request(
                "POST",
                "/api/power/config",
                body=json.dumps({"auto_60hz": bad_bool}).encode("utf-8"),
                headers=base_headers,
            )
            self.assertEqual(status, 400)
            self.assertFalse(json.loads(data)["success"])

        # Invalid category on /api/analyze & /api/apply -> 400
        for endpoint in ("/api/analyze", "/api/apply"):
            status, data = self._raw_request(
                "POST",
                endpoint,
                body=json.dumps({
                    "category": "invalid_cat",
                    "item_id": "x",
                    "source_path": "/tmp/nonexistent",
                    "confirmed": True,
                }).encode("utf-8"),
                headers=base_headers,
            )
            self.assertEqual(status, 400)
            self.assertFalse(json.loads(data)["success"])

        # Outside allowed root / metacharacters in source_path & snapshot_id rejected cleanly
        outside_file = self.root / "outside.rasi"
        outside_file.write_text("/* outside */", encoding="utf-8")
        status_out, _ = self._raw_request(
            "POST",
            "/api/apply",
            body=json.dumps({
                "category": "rofi_themes",
                "item_id": "outside",
                "source_path": str(outside_file),
                "confirmed": True,
            }).encode("utf-8"),
            headers=base_headers,
        )
        self.assertEqual(status_out, 403)

        pwn_marker = self.root / "shell_injection_pwned"
        status_meta_src, _ = self._raw_request(
            "POST",
            "/api/apply",
            body=json.dumps({
                "category": "rofi_themes",
                "item_id": "bad",
                "source_path": f"/etc/passwd;touch {pwn_marker}",
                "confirmed": True,
            }).encode("utf-8"),
            headers=base_headers,
        )
        self.assertEqual(status_meta_src, 400)
        self.assertFalse(pwn_marker.exists())

        status_rb_meta, _ = self._raw_request(
            "POST",
            "/api/rollback",
            body=json.dumps({"snapshot_id": f"snap;touch {pwn_marker}"}).encode("utf-8"),
            headers=base_headers,
        )
        self.assertEqual(status_rb_meta, 400)
        self.assertFalse(pwn_marker.exists())

        # Valid source with shell metacharacters in item_id runs purely in Python without shell exec
        allowed_theme = self.mock_home / ".config" / "rofi" / "themes" / "SafeTheme.rasi"
        allowed_theme.parent.mkdir(parents=True, exist_ok=True)
        allowed_theme.write_text("/* safe */", encoding="utf-8")
        status_apply_item, data_apply = self._raw_request(
            "POST",
            "/api/apply",
            body=json.dumps({
                "category": "rofi_themes",
                "item_id": f"foo;touch {pwn_marker};$(id)",
                "source_path": str(allowed_theme),
                "confirmed": True,
            }).encode("utf-8"),
            headers=base_headers,
        )
        self.assertEqual(status_apply_item, 200)
        self.assertTrue(json.loads(data_apply)["success"])
        self.assertFalse(pwn_marker.exists())


class TestKeybindParserCommit5(unittest.TestCase):
    def test_bind_vs_bindd_conf_field_parsing(self):
        """Legacy 4-field bind has empty description; 5-field bindd parses description separately."""
        with tempfile.TemporaryDirectory(prefix="yusei_kb_c5_") as tmp:
            kb_conf = Path(tmp) / "keybinds.conf"
            kb_conf.write_text(
                "# 1. Standard Application Shortcuts\n"
                "bind = $mainMod, Return, exec, kitty\n"
                "bindd = $mainMod SHIFT, S, Capture region screenshot, exec, ScreenShot.sh --area\n",
                encoding="utf-8",
            )
            items = KeybindParser(str(kb_conf)).parse()
            self.assertEqual(len(items), 2)

            plain_bind = items[0]
            self.assertEqual(plain_bind["directive"], "bind")
            self.assertEqual(plain_bind["description"], "")
            self.assertEqual(plain_bind["dispatcher"], "exec")
            self.assertEqual(plain_bind["args"], "kitty")

            desc_bind = items[1]
            self.assertEqual(desc_bind["directive"], "bindd")
            self.assertEqual(desc_bind["description"], "Capture region screenshot")
            self.assertEqual(desc_bind["dispatcher"], "exec")
            self.assertEqual(desc_bind["args"], "ScreenShot.sh --area")

    def test_hyprland_lua_loop_expanded_binds_without_helper_leakage(self):
        """Parsing repo config/hypr/hyprland.lua expands loop binds with zero helper artifacts."""
        repo_root = Path(__file__).resolve().parent.parent.parent
        lua_path = repo_root / "config" / "hypr" / "hyprland.lua"
        binds = KeybindParser(str(lua_path)).parse()

        self.assertGreater(len(binds), 40)
        combos = {b["combo_display"] for b in binds}
        for expected_combo in (
            "Super + Left",
            "Super + Right",
            "Super + 1",
            "Super + 0",
            "Super + Ctrl + F9",
            "Super + Ctrl + F12",
        ):
            self.assertIn(expected_combo, combos, f"Missing loop-expanded combo {expected_combo}")

        # Ensure loop variables / helper definitions did not leak as fake keybinds
        for item in binds:
            key = item.get("key", "")
            self.assertNotIn("..", key)
            self.assertNotIn("function", key)
            self.assertNotIn(key.lower(), {"dir", "ws", "fn_name", "pair"})


class TestPowerManagerCommit5(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="yusei_pwr_c5_")
        self.root = Path(self._tmp.name)
        self.mock_home = self.root / "home"
        self.hypr_cfg = self.mock_home / ".config" / "hypr"
        self.hypr_cfg.mkdir(parents=True, exist_ok=True)
        self.workspace_root = str(Path(__file__).resolve().parent.parent.parent)
        self.power_mgr = PowerManager(self.workspace_root, str(self.mock_home))

    def tearDown(self):
        self._tmp.cleanup()

    def test_toggle_hz_alternates_60_and_max_hz_and_preserves_false_booleans(self):
        """toggle_hz alternates 60 <-> max_hz and get_status honors explicit false flags."""
        cfg_file = self.hypr_cfg / "power.json"
        state_file = self.hypr_cfg / ".power-optimizer.state"
        cfg_file.write_text(
            json.dumps({"power_daemon": False, "auto_60hz": False, "ac_profile": "turbo", "bat_profile": "eco"}),
            encoding="utf-8",
        )
        state_file.write_text(json.dumps({"current_hz": 60, "max_hz": 144, "profile": "balanced"}), encoding="utf-8")

        status = self.power_mgr.get_status()
        self.assertIs(status["power_daemon"], False)
        self.assertIs(status["auto_60hz"], False)

        up = self.power_mgr.toggle_hz()
        self.assertTrue(up["success"])
        self.assertEqual(up["current_hz"], 144)

        down = self.power_mgr.toggle_hz()
        self.assertTrue(down["success"])
        self.assertEqual(down["current_hz"], 60)

    def test_strict_bool_validation_and_script_error_propagation(self):
        """Invalid bools fail set_config; script failures prevent optimistic state overwrites."""
        for bad_val in (1, 0, "not_bool", []):
            res = self.power_mgr.set_config(auto_60hz=bad_val)
            self.assertFalse(res["success"])

        state_file = self.hypr_cfg / ".power-optimizer.state"
        state_file.write_text(json.dumps({"current_hz": 60, "max_hz": 144, "profile": "eco"}), encoding="utf-8")

        # Point sandbox PowerManager to a workspace whose power-optimizer.sh fails
        bad_ws = self.root / "bad_ws"
        (bad_ws / "scripts").mkdir(parents=True, exist_ok=True)
        bad_script = bad_ws / "scripts" / "power-optimizer.sh"
        bad_script.write_text("#!/usr/bin/env bash\necho 'simulated failure' >&2\nexit 1\n", encoding="utf-8")
        bad_script.chmod(0o755)
        failing_mgr = PowerManager(str(bad_ws), str(self.mock_home))

        with mock.patch("yusei_settings.core.power.os.path.exists", return_value=True):
            hz_res = failing_mgr.toggle_hz()
            prof_res = failing_mgr.set_profile("turbo")

        self.assertFalse(hz_res["success"])
        self.assertFalse(prof_res["success"])
        persisted = json.loads(state_file.read_text(encoding="utf-8"))
        self.assertEqual(persisted["current_hz"], 60)
        self.assertEqual(persisted["profile"], "eco")


class TestGtkWindowDecorationsHelpersCommit5(unittest.TestCase):
    def test_update_and_read_user_decorations_creates_and_updates_cleanly(self):
        """_update_user_decorations_file creates/updates rounding & blur cleanly inside decoration {}."""
        with tempfile.TemporaryDirectory(prefix="yusei_dec_c5_") as tmp:
            mock_home = Path(tmp)

            # 1. File does not exist yet -> creates UserDecorations.conf with decoration { ... }
            dec_path = _update_user_decorations_file(mock_home, rounding=12, blur_enabled=False)
            self.assertTrue(dec_path.exists())
            text1 = dec_path.read_text(encoding="utf-8")
            self.assertIn("decoration {", text1)
            self.assertEqual(_read_user_decorations_state(mock_home), (12, False))

            # 2. Existing file with extra unrelated rules preserved across surgical update
            dec_path.write_text(
                "decoration {\n"
                "    rounding = 12\n"
                "    active_opacity = 0.95 # keep comment\n"
                "    blur {\n"
                "        size = 5\n"
                "        enabled = false\n"
                "    }\n"
                "}\n",
                encoding="utf-8",
            )
            _update_user_decorations_file(mock_home, rounding=20, blur_enabled=True)
            text2 = dec_path.read_text(encoding="utf-8")
            self.assertIn("active_opacity = 0.95 # keep comment", text2)
            self.assertIn("size = 5", text2)
            self.assertEqual(_read_user_decorations_state(mock_home), (20, True))


if __name__ == "__main__":
    unittest.main()
