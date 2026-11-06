"""
Unit Tests for PowerManager and Power HTTP Endpoints
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Validates:
1. PowerManager.get_status() telemetry schema
2. PowerManager profile switching and configuration persistence
3. Server HTTP endpoints:
   - GET /api/power/status
   - POST /api/power/profile
   - POST /api/power/config
"""

import json
import os
import shutil
import tempfile
import threading
import time
import unittest
import urllib.request
import urllib.error
from pathlib import Path

from yusei_settings.core.power import PowerManager
from yusei_settings.server import create_server


class TestPowerAPI(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="yusei_power_test_")
        self.mock_home = Path(self.test_dir) / "home"
        self.mock_home.mkdir(parents=True, exist_ok=True)
        self.mock_config = self.mock_home / ".config" / "hypr"
        self.mock_config.mkdir(parents=True, exist_ok=True)
        self.workspace_root = str(Path(__file__).resolve().parent.parent.parent)
        self.power_mgr = PowerManager(self.workspace_root, str(self.mock_home))

    def tearDown(self):
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def test_01_power_manager_status_structure(self):
        """Verify get_status returns complete telemetry schema with all required fields."""
        status = self.power_mgr.get_status()
        required_keys = [
            "has_battery",
            "ac_online",
            "battery_percent",
            "battery_status",
            "power_watts",
            "profile",
            "monitor_name",
            "current_hz",
            "max_hz",
            "auto_60hz",
        ]
        for key in required_keys:
            self.assertIn(key, status, f"Key '{key}' must be present in power status")

        self.assertIsInstance(status["auto_60hz"], bool)
        self.assertIn(status["profile"], ["eco", "balanced", "turbo"])

    def test_02_power_manager_set_profile(self):
        """Verify setting valid profiles updates state and rejects invalid ones."""
        res_eco = self.power_mgr.set_profile("eco")
        self.assertTrue(res_eco["success"])
        self.assertEqual(res_eco["profile"], "eco")

        res_bal = self.power_mgr.set_profile("balanced")
        self.assertTrue(res_bal["success"])
        self.assertEqual(res_bal["profile"], "balanced")

        res_turbo = self.power_mgr.set_profile("turbo")
        self.assertTrue(res_turbo["success"])
        self.assertEqual(res_turbo["profile"], "turbo")

        with self.assertRaises(ValueError):
            self.power_mgr.set_profile("invalid_profile_name")

    def test_03_power_manager_set_config(self):
        """Verify set_config saves auto_60hz and power_daemon to power.json in sandbox."""
        res = self.power_mgr.set_config(auto_60hz=False, power_daemon=False)
        self.assertTrue(res["success"])
        self.assertFalse(res["auto_60hz"])
        self.assertFalse(res["power_daemon"])

        cfg_file = self.mock_config / "power.json"
        self.assertTrue(cfg_file.exists(), "power.json must be created in mock config")
        data = json.loads(cfg_file.read_text(encoding="utf-8"))
        self.assertFalse(data.get("auto_60hz"))
        self.assertFalse(data.get("power_daemon"))

        res_true = self.power_mgr.set_config(auto_60hz=True, power_daemon=True)
        self.assertTrue(res_true["success"])
        self.assertTrue(res_true["auto_60hz"])
        self.assertTrue(res_true["power_daemon"])
        data = json.loads(cfg_file.read_text(encoding="utf-8"))
        self.assertTrue(data.get("auto_60hz"))
        self.assertTrue(data.get("power_daemon"))

    def test_03b_cached_state_fallback(self):
        """Verify fallback get_status accurately restores cached current_hz and max_hz from state_file."""
        state_file = self.mock_config / ".power-optimizer.state"
        state_file.write_text(json.dumps({"profile": "turbo", "current_hz": 144, "max_hz": 144}), encoding="utf-8")
        fallback_mgr = PowerManager("/nonexistent/workspace", str(self.mock_home))
        status = fallback_mgr.get_status()
        self.assertEqual(status["profile"], "turbo")
        self.assertEqual(status["current_hz"], 144)
        self.assertEqual(status["max_hz"], 144)
        self.assertTrue(status["power_daemon"])

    def test_04_http_endpoints_integration(self):
        """Verify HTTP endpoints /api/power/status, /api/power/profile, and /api/power/config."""
        port = 19890
        server = create_server("127.0.0.1", port, self.workspace_root, str(self.mock_home))
        t = threading.Thread(target=server.serve_forever, daemon=True)
        t.start()
        time.sleep(0.15)

        try:
            # 1. GET /api/power/status
            req = urllib.request.Request(f"http://127.0.0.1:{port}/api/power/status")
            with urllib.request.urlopen(req) as resp:
                self.assertEqual(resp.status, 200)
                data = json.loads(resp.read().decode("utf-8"))
                self.assertIn("battery_percent", data)
                self.assertIn("profile", data)
                self.assertIn("current_hz", data)

            # 2. POST /api/power/profile (eco)
            post_body = json.dumps({"profile": "eco"}).encode("utf-8")
            req = urllib.request.Request(
                f"http://127.0.0.1:{port}/api/power/profile",
                data=post_body,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req) as resp:
                self.assertEqual(resp.status, 200)
                data = json.loads(resp.read().decode("utf-8"))
                self.assertTrue(data.get("success"))
                self.assertEqual(data.get("profile"), "eco")

            # 3. POST /api/power/profile (invalid -> 400)
            bad_body = json.dumps({"profile": "overclock_9000"}).encode("utf-8")
            req_bad = urllib.request.Request(
                f"http://127.0.0.1:{port}/api/power/profile",
                data=bad_body,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(req_bad)
            ctx.exception.close()
            self.assertEqual(ctx.exception.code, 400)

            # 4. POST /api/power/config (toggle auto_60hz)
            cfg_body = json.dumps({"auto_60hz": False}).encode("utf-8")
            req_cfg = urllib.request.Request(
                f"http://127.0.0.1:{port}/api/power/config",
                data=cfg_body,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req_cfg) as resp:
                self.assertEqual(resp.status, 200)
                data = json.loads(resp.read().decode("utf-8"))
                self.assertTrue(data.get("success"))
                self.assertFalse(data.get("auto_60hz"))

            # 5. POST /api/power/toggle-hz
            req_toggle = urllib.request.Request(
                f"http://127.0.0.1:{port}/api/power/toggle-hz",
                data=b"{}",
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req_toggle) as resp:
                self.assertEqual(resp.status, 200)
                data = json.loads(resp.read().decode("utf-8"))
                self.assertTrue(data.get("success"))
                self.assertIn("current_hz", data)

            # 6. POST /api/power/cycle-profile
            req_cycle = urllib.request.Request(
                f"http://127.0.0.1:{port}/api/power/cycle-profile",
                data=b"{}",
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req_cycle) as resp:
                self.assertEqual(resp.status, 200)
                data = json.loads(resp.read().decode("utf-8"))
                self.assertTrue(data.get("success"))
                self.assertIn(data.get("profile"), ["eco", "balanced", "turbo"])

        finally:
            server.shutdown()
            server.server_close()

    def test_05_power_manager_toggle_hz(self):
        """Verify PowerManager.toggle_hz alternates refresh rate and updates state file."""
        state_file = self.mock_config / ".power-optimizer.state"
        state_file.write_text(json.dumps({"current_hz": 60, "max_hz": 144}), encoding="utf-8")

        res_up = self.power_mgr.toggle_hz()
        self.assertTrue(res_up.get("success"))
        self.assertEqual(res_up.get("current_hz"), 144)
        self.assertEqual(res_up.get("max_hz"), 144)

        data = json.loads(state_file.read_text(encoding="utf-8"))
        self.assertEqual(data.get("current_hz"), 144)

        res_down = self.power_mgr.toggle_hz()
        self.assertTrue(res_down.get("success"))
        self.assertEqual(res_down.get("current_hz"), 60)
        data = json.loads(state_file.read_text(encoding="utf-8"))
        self.assertEqual(data.get("current_hz"), 60)

    def test_06_power_manager_cycle_profile(self):
        """Verify PowerManager.cycle_profile cycles eco -> balanced -> turbo -> eco."""
        self.power_mgr.set_profile("eco")
        res1 = self.power_mgr.cycle_profile()
        self.assertEqual(res1.get("profile"), "balanced")

        res2 = self.power_mgr.cycle_profile()
        self.assertEqual(res2.get("profile"), "turbo")

        res3 = self.power_mgr.cycle_profile()
        self.assertEqual(res3.get("profile"), "eco")

