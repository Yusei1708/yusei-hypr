import unittest
from unittest.mock import patch, MagicMock
import json
import os
import signal
from pathlib import Path

# Import AntigravityTrayGuard directly
import importlib.util

spec = importlib.util.spec_from_file_location(
    "AntigravityTrayGuard",
    Path(__file__).parent.parent.parent / "config/hypr/scripts/AntigravityTrayGuard.py"
)
tray_guard_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tray_guard_mod)
AntigravityTrayGuard = tray_guard_mod.AntigravityTrayGuard


class TestAntigravityTrayGuard(unittest.TestCase):
    def setUp(self):
        # Instantiate without running Gtk loop or connecting UI
        with patch.object(tray_guard_mod.AppIndicator3.Indicator, "new") as mock_new, \
             patch.object(AntigravityTrayGuard, "_sync_tray_state"):
            mock_indicator = MagicMock()
            mock_new.return_value = mock_indicator
            self.guard = AntigravityTrayGuard()

    def test_hypr_dispatch_lua_success(self):
        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(stdout="ok\n", returncode=0)
            res = self.guard._hypr_dispatch("hl.dsp.focus({ window = 'class:antigravity' })", "focuswindow class:antigravity")
            self.assertTrue(res)
            mock_run.assert_called_once()
            self.assertIn("hl.dsp.focus", mock_run.call_args[0][0][2])

    def test_hypr_dispatch_fallback_to_legacy(self):
        with patch("subprocess.run") as mock_run:
            # First call (lua) fails, second call (legacy) succeeds
            mock_run.side_effect = [
                MagicMock(stdout="error\n", returncode=7),
                MagicMock(stdout="ok\n", returncode=0),
            ]
            res = self.guard._hypr_dispatch("hl.dsp.focus({ window = 'class:antigravity' })", "focuswindow class:antigravity")
            self.assertTrue(res)
            self.assertEqual(mock_run.call_count, 2)

    def test_get_antigravity_windows(self):
        sample_clients = [
            {"class": "kitty", "address": "0x123", "workspace": {"id": 1, "name": "1"}},
            {"class": "antigravity", "address": "0x55bca2cf18f0", "workspace": {"id": 2, "name": "2"}},
        ]
        with patch("subprocess.check_output", return_value=json.dumps(sample_clients)):
            windows = self.guard._get_antigravity_windows()
            self.assertEqual(len(windows), 1)
            self.assertEqual(windows[0]["address"], "0x55bca2cf18f0")
            self.assertEqual(windows[0]["workspace"]["name"], "2")

    def test_on_open_clicked_focuses_window_and_switches_workspace(self):
        sample_clients = [
            {"class": "antigravity", "address": "0x55bca2cf18f0", "workspace": {"id": 2, "name": "2"}},
        ]
        with patch.object(self.guard, "_get_antigravity_windows", return_value=sample_clients), \
             patch.object(self.guard, "_hypr_dispatch") as mock_dispatch:
            self.guard._on_open_clicked()
            # Must dispatch workspace focus and window focus
            self.assertEqual(mock_dispatch.call_count, 2)
            calls = mock_dispatch.call_args_list
            self.assertIn('hl.dsp.focus({ workspace = "2" })', calls[0][0][0])
            self.assertIn('hl.dsp.focus({ window = "address:0x55bca2cf18f0" })', calls[1][0][0])

    def test_on_quit_clicked_terminates_main_process(self):
        sample_clients = [
            {"class": "antigravity", "address": "0x55bca2cf18f0", "workspace": {"id": 2, "name": "2"}},
        ]
        with patch.object(self.guard, "_get_antigravity_windows", return_value=sample_clients), \
             patch.object(self.guard, "_get_antigravity_main_pids", return_value=[2085]), \
             patch.object(self.guard, "_hypr_dispatch") as mock_dispatch, \
             patch("os.kill") as mock_kill:
            self.guard._on_quit_clicked()
            # Must close window
            mock_dispatch.assert_called_once()
            self.assertIn('hl.dsp.window.close({ window = "address:0x55bca2cf18f0" })', mock_dispatch.call_args[0][0])
            # Must kill main PID with SIGTERM
            mock_kill.assert_called_once_with(2085, signal.SIGTERM)


if __name__ == "__main__":
    unittest.main()
