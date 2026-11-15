"""
Unit Tests for DecorationsManager & Hyprland Blur/Opacity HTTP API
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Validates:
1. Schema bounds, defaults, strict type checks, and finite-float coercion
2. Conf parser & surgical updater preserving comments, inline blocks, and nested shadow blocks
3. Persistence to UserDecorations.conf + yusei-decorations.lua and sandboxed live Lua/keyword calls
4. HTTP REST endpoints: GET /api/hypr/decorations, POST /api/hypr/decorations, POST /api/hypr/decorations/reset
5. Web UI & GTK4 integration checks
"""

import ast
import builtins
import json
import os
import shutil
import subprocess
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest import mock

from yusei_settings.core.decorations import (
    DecorationsManager,
    get_default_state,
    parse_decorations_text,
    update_decorations_text,
)
from yusei_settings.server import create_server


class TestDecorationsAPI(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="yusei_dec_api_")
        self.mock_home = Path(self.test_dir) / "home"
        self.mock_config = self.mock_home / ".config" / "hypr" / "UserConfigs"
        self.mock_config.mkdir(parents=True, exist_ok=True)
        self.workspace_root = str(Path(__file__).resolve().parent.parent.parent)
        self.mgr = DecorationsManager(self.workspace_root, str(self.mock_home))

    def tearDown(self):
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def test_01_parse_and_update_preserves_comments_and_ignores_shadow(self):
        """Nested `shadow { enabled = false }` must never overwrite `blur.enabled`."""
        sample = (
            "decoration {\n"
            "    rounding = 10 # corner radius\n"
            "    active_opacity = 0.90\n"
            "    shadow {\n"
            "        enabled = false\n"
            "    }\n"
            "    blur {\n"
            "        enabled = true\n"
            "        size = 5 # original size\n"
            "        passes = 2\n"
            "    }\n"
            "}\n"
        )
        parsed = parse_decorations_text(sample)
        self.assertEqual(parsed["rounding"], 10)
        self.assertEqual(parsed["active_opacity"], 0.90)
        self.assertIs(parsed["blur_enabled"], True)
        self.assertEqual(parsed["blur_size"], 5)

        updated = update_decorations_text(
            sample,
            {
                "active_opacity": 0.80,
                "inactive_opacity": 0.85,
                "blur_size": 9,
                "blur_brightness": 1.15,
            },
        )
        self.assertIn("rounding = 10 # corner radius", updated)
        self.assertIn("active_opacity = 0.80", updated)
        self.assertIn("inactive_opacity = 0.85", updated)
        self.assertIn("size = 9 # original size", updated)
        self.assertIn("brightness = 1.15", updated)
        # shadow.enabled must remain intact
        self.assertIn("    shadow {\n        enabled = false\n    }", updated)

    def test_02_apply_persists_conf_and_override_lua_in_sandbox(self):
        """Applying 0.80 opacity persists both UserDecorations.conf and yusei-decorations.lua cleanly."""
        res = self.mgr.apply(
            {
                "active_opacity": 0.80,
                "inactive_opacity": 0.85,
                "fullscreen_opacity": 1.00,
                "override_all_apps": True,
                "blur_size": 7,
                "blur_passes": 3,
                "blur_vibrancy": 0.35,
            },
            persist=True,
            live=False,
        )
        self.assertTrue(res["success"])
        self.assertEqual(res["state"]["active_opacity"], 0.80)
        self.assertEqual(res["state"]["blur_size"], 7)

        dec_conf = self.mock_config / "UserDecorations.conf"
        dec_lua = self.mock_config / "yusei-decorations.lua"
        self.assertTrue(dec_conf.exists())
        self.assertTrue(dec_lua.exists())

        conf_txt = dec_conf.read_text(encoding="utf-8")
        self.assertIn("active_opacity = 0.80", conf_txt)
        self.assertIn("vibrancy = 0.35", conf_txt)

        lua_txt = dec_lua.read_text(encoding="utf-8")
        self.assertIn('name = "global-opacity-override"', lua_txt)
        self.assertIn('opacity = "0.80 override 0.85 override 1.00 override"', lua_txt)

        # Reload via fresh manager instance
        state_reloaded = DecorationsManager(self.workspace_root, str(self.mock_home)).get_state()["state"]
        self.assertEqual(state_reloaded["active_opacity"], 0.80)
        self.assertEqual(state_reloaded["inactive_opacity"], 0.85)
        self.assertEqual(state_reloaded["blur_size"], 7)
        self.assertTrue(state_reloaded["override_all_apps"])

        # Toggle override_all_apps off
        res2 = self.mgr.apply({"override_all_apps": False}, persist=True, live=False)
        self.assertFalse(res2["state"]["override_all_apps"])
        lua_txt2 = dec_lua.read_text(encoding="utf-8")
        self.assertIn("override_all_apps = false", lua_txt2)
        self.assertNotIn("hl.window_rule", lua_txt2)

    def test_03_validation_rejects_bad_bounds_and_types(self):
        """Strict validation catches booleans-as-numbers, NaN/Inf, out-of-range floats, unknown keys."""
        bad_payloads = [
            {"active_opacity": 0.10},        # below 0.30
            {"active_opacity": 1.25},        # above 1.00
            {"active_opacity": float("nan")},
            {"active_opacity": True},        # bool is subclass of int in Python!
            {"blur_size": 0},
            {"blur_size": 50},
            {"blur_passes": 2.5},            # float passed for int field
            {"blur_enabled": "maybe"},
            {"unknown_key": 123},
        ]
        for payload in bad_payloads:
            with self.assertRaises(ValueError, msg=f"Expected ValueError for {payload}"):
                self.mgr.validate_patch(payload)

    def test_04_live_compositor_lua_and_keyword_fallback(self):
        """When running in a live session, applies via `hyprctl eval` and falls back cleanly on error."""
        live_mgr = DecorationsManager(self.workspace_root, target_home=None)
        with (
            mock.patch.object(live_mgr, "_is_live_session", return_value=True),
            mock.patch("yusei_settings.core.decorations.subprocess.run") as mock_run,
            mock.patch.object(live_mgr, "_read_persisted_state", return_value=get_default_state()),
            mock.patch.object(live_mgr, "_read_live_hypr_overrides", side_effect=lambda s: s),
        ):
            mock_run.return_value = subprocess.CompletedProcess(
                args=["hyprctl", "eval", "..."], returncode=0, stdout="ok\n", stderr=""
            )
            res = live_mgr.apply({"active_opacity": 0.80}, persist=False, live=True)
            self.assertEqual(res["applied_via"], "lua")
            eval_args = mock_run.call_args[0][0]
            self.assertEqual(eval_args[:2], ["hyprctl", "eval"])
            self.assertIn("active_opacity = 0.80", eval_args[2])
            self.assertIn("global-opacity-override", eval_args[2])

        with (
            mock.patch.object(live_mgr, "_is_live_session", return_value=True),
            mock.patch("yusei_settings.core.decorations.subprocess.run") as mock_run,
            mock.patch.object(live_mgr, "_read_persisted_state", return_value=get_default_state()),
            mock.patch.object(live_mgr, "_read_live_hypr_overrides", side_effect=lambda s: s),
        ):
            mock_run.side_effect = [
                subprocess.CompletedProcess(args=["hyprctl", "eval"], returncode=7, stdout="err", stderr=""),
                subprocess.CompletedProcess(args=["hyprctl", "--batch"], returncode=0, stdout="ok", stderr=""),
            ]
            res = live_mgr.apply({"blur_size": 8}, persist=False, live=True)
            self.assertEqual(res["applied_via"], "keyword")
            self.assertEqual(mock_run.call_args_list[1][0][0][1], "--batch")

    def test_05_http_endpoints_and_security(self):
        """Verify GET/POST/reset endpoints, preview vs persist semantics, and CSRF Origin check."""
        server = create_server("127.0.0.1", 0, self.workspace_root, str(self.mock_home))
        port = server.server_address[1]
        t = threading.Thread(target=server.serve_forever, daemon=True)
        t.start()

        try:
            # 1. GET state
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/hypr/decorations") as resp:
                self.assertEqual(resp.status, 200)
                data = json.loads(resp.read().decode("utf-8"))
                self.assertTrue(data["success"])
                self.assertIn("active_opacity", data["state"])
                self.assertIn("blur_vibrancy", data["bounds"])
                self.assertGreaterEqual(len(data["opacity_presets"]), 4)

            # 2. Preview update (persist=False -> does not write file yet)
            req_preview = urllib.request.Request(
                f"http://127.0.0.1:{port}/api/hypr/decorations",
                data=json.dumps({"active_opacity": 0.78, "persist": False}).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req_preview) as resp:
                self.assertEqual(resp.status, 200)
                preview_data = json.loads(resp.read().decode("utf-8"))
                self.assertFalse(preview_data["persisted"])
                self.assertEqual(preview_data["state"]["active_opacity"], 0.78)
            self.assertFalse((self.mock_config / "UserDecorations.conf").exists())

            # 3. Persisted update (0.80 / 0.90)
            req_save = urllib.request.Request(
                f"http://127.0.0.1:{port}/api/hypr/decorations",
                data=json.dumps({"active_opacity": 0.80, "inactive_opacity": 0.90, "blur_size": 8, "persist": True}).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req_save) as resp:
                self.assertEqual(resp.status, 200)
                save_data = json.loads(resp.read().decode("utf-8"))
                self.assertTrue(save_data["persisted"])
                self.assertEqual(save_data["state"]["active_opacity"], 0.80)
                self.assertEqual(save_data["state"]["inactive_opacity"], 0.90)
            self.assertTrue((self.mock_config / "UserDecorations.conf").exists())

            # 4. Bad value -> 400
            req_bad = urllib.request.Request(
                f"http://127.0.0.1:{port}/api/hypr/decorations",
                data=json.dumps({"active_opacity": 0.05}).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(req_bad)
            ctx.exception.close()
            self.assertEqual(ctx.exception.code, 400)

            # 5. CSRF Origin check -> 403
            req_csrf = urllib.request.Request(
                f"http://127.0.0.1:{port}/api/hypr/decorations/reset",
                data=b"{}",
                headers={"Content-Type": "application/json", "Origin": "https://evil.example.com"},
                method="POST",
            )
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(req_csrf)
            ctx.exception.close()
            self.assertEqual(ctx.exception.code, 403)

            # 6. Valid reset -> restores default 0.90
            req_reset = urllib.request.Request(
                f"http://127.0.0.1:{port}/api/hypr/decorations/reset",
                data=b"{}",
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req_reset) as resp:
                self.assertEqual(resp.status, 200)
                rst = json.loads(resp.read().decode("utf-8"))
                self.assertEqual(rst["state"]["active_opacity"], 0.90)
                self.assertEqual(rst["state"]["blur_size"], 5)

            # 7. Web UI contains live slider controls
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/") as resp:
                html = resp.read().decode("utf-8")
                self.assertIn("dec-slider-active_opacity", html)
                self.assertIn("dec-slider-blur_vibrancy", html)
                self.assertIn("btn-reset-hypr-decorations", html)

        finally:
            server.shutdown()
            server.server_close()

    def test_06_no_undefined_python_symbols_in_package(self):
        """Regression guard: ensures no missing imports (e.g. hashlib in GTK window.py) across yusei_settings."""
        builtin_names = set(dir(builtins)) | {
            "__name__", "__file__", "__doc__", "__package__", "__spec__", "__cached__"
        }
        pkg_root = Path(__file__).resolve().parent.parent

        def collect_scope_defs(node):
            defs = set()
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                for arg in node.args.posonlyargs + node.args.args + node.args.kwonlyargs:
                    defs.add(arg.arg)
                if node.args.vararg:
                    defs.add(node.args.vararg.arg)
                if node.args.kwarg:
                    defs.add(node.args.kwarg.arg)
                stmts = node.body
            elif isinstance(node, (ast.ClassDef, ast.Module)):
                stmts = node.body
            else:
                return defs

            for stmt in stmts:
                for sub in ast.walk(stmt):
                    if isinstance(sub, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and sub is not stmt:
                        continue
                    if isinstance(sub, (ast.Import, ast.ImportFrom)):
                        for alias in sub.names:
                            defs.add(alias.asname or alias.name.split(".")[0])
                    elif isinstance(sub, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                        defs.add(sub.name)
                    elif isinstance(sub, ast.Name) and isinstance(sub.ctx, ast.Store):
                        defs.add(sub.id)
                    elif isinstance(sub, ast.ExceptHandler) and sub.name:
                        defs.add(sub.name)
                    elif isinstance(sub, ast.NamedExpr):
                        defs.add(sub.target.id)
            return defs

        def scan(node, scopes, issues):
            if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
                cur = collect_scope_defs(node)
                next_scopes = scopes + [cur]
                for stmt in node.body:
                    scan(stmt, next_scopes, issues)
                return
            if isinstance(node, ast.Lambda):
                ldefs = {a.arg for a in (node.args.posonlyargs + node.args.args + node.args.kwonlyargs)}
                if node.args.vararg:
                    ldefs.add(node.args.vararg.arg)
                if node.args.kwarg:
                    ldefs.add(node.args.kwarg.arg)
                scan(node.body, scopes + [ldefs], issues)
                return
            if isinstance(node, (ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)):
                cdefs = set()
                for gen in node.generators:
                    for sub in ast.walk(gen.target):
                        if isinstance(sub, ast.Name):
                            cdefs.add(sub.id)
                for gen in node.generators:
                    scan(gen.iter, scopes, issues)
                    for cond in gen.ifs:
                        scan(cond, scopes + [cdefs], issues)
                if isinstance(node, ast.DictComp):
                    scan(node.key, scopes + [cdefs], issues)
                    scan(node.value, scopes + [cdefs], issues)
                else:
                    scan(node.elt, scopes + [cdefs], issues)
                return
            if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):
                if node.id not in builtin_names and not any(node.id in s for s in scopes):
                    issues.append((node.lineno, node.id))
            for child in ast.iter_child_nodes(node):
                scan(child, scopes, issues)

        all_issues = {}
        for py_file in sorted(pkg_root.rglob("*.py")):
            tree = ast.parse(py_file.read_text(encoding="utf-8"), filename=str(py_file))
            file_issues = []
            scan(tree, [], file_issues)
            if file_issues:
                all_issues[str(py_file.relative_to(pkg_root))] = file_issues

        self.assertEqual(all_issues, {}, f"Undefined Python symbols detected: {all_issues}")


if __name__ == "__main__":
    unittest.main()
