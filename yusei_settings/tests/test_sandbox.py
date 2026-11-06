"""
Automated Sandbox & Safety Tests for yusei-settings
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Tests Discovery, Previews, State, and the 5-Stage Safety Protocol
within an isolated temporary directory. Verifies zero changes to real ~/.config.
"""

import unittest
import tempfile
import shutil
import os
from pathlib import Path

from yusei_settings.core.discovery import DiscoveryEngine
from yusei_settings.core.preview import PreviewEngine
from yusei_settings.core.state import StateManager
from yusei_settings.core.safety import SafetyEngine

class TestYuseiSettingsSandbox(unittest.TestCase):
    def setUp(self):
        # Create an isolated mock sandbox directory
        self.test_dir = tempfile.mkdtemp(prefix="yusei_sandbox_")
        self.mock_home = Path(self.test_dir) / "home"
        self.mock_home.mkdir()
        self.mock_config = self.mock_home / ".config"
        self.mock_config.mkdir()

        # Workspace root
        self.workspace_root = str(Path(__file__).resolve().parent.parent.parent)

    def tearDown(self):
        # Clean up sandbox
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def test_01_discovery_engine(self):
        """Verify discovery engine scans all domains and extracts metadata."""
        disc = DiscoveryEngine(self.workspace_root)
        catalog = disc.discover_all()

        self.assertIn("waybar_layouts", catalog)
        self.assertGreater(len(catalog["waybar_layouts"]), 30, "Should discover > 30 Waybar layouts")

        self.assertIn("waybar_styles", catalog)
        self.assertGreater(len(catalog["waybar_styles"]), 30, "Should discover > 30 Waybar styles")

        self.assertIn("rofi_themes", catalog)
        self.assertGreater(len(catalog["rofi_themes"]), 15, "Should discover > 15 Rofi themes")

        self.assertIn("kitty_themes", catalog)
        self.assertGreater(len(catalog["kitty_themes"]), 100, "Should discover > 100 Kitty themes")

        self.assertIn("hyprland_animations", catalog)
        self.assertGreater(len(catalog["hyprland_animations"]), 10, "Should discover > 10 Hyprland animations")

        self.assertIn("wallpapers", catalog)
        self.assertGreater(len(catalog["wallpapers"]), 10, "Should discover > 10 wallpapers")

    def test_02_preview_engine(self):
        """Verify PreviewEngine produces valid SVG vector mockups."""
        top_svg = PreviewEngine.generate_waybar_svg("TOP", "Test Top")
        self.assertTrue(top_svg.startswith("<svg") and top_svg.endswith("</svg>"))

        split_svg = PreviewEngine.generate_waybar_svg("SPLIT", "Test Split")
        self.assertIn("Top Split Bar", split_svg)

        left_svg = PreviewEngine.generate_waybar_svg("LEFT", "Test Left")
        self.assertIn("Vertical Bar", left_svg)

        kitty_svg = PreviewEngine.generate_kitty_svg({
            "background": "#1e1e2e",
            "foreground": "#cdd6f4",
            "swatches": ["#000", "#111", "#222", "#333", "#444", "#555", "#666", "#777"]
        })
        self.assertIn("#1e1e2e", kitty_svg)

        rofi_svg = PreviewEngine.generate_rofi_svg("Centered Card")
        self.assertIn("Search Pill", rofi_svg)

    def test_03_safety_confirmation_barrier(self):
        """Verify that apply without explicit confirmation raises PermissionError."""
        safety = SafetyEngine(target_home=str(self.mock_home))
        dummy_source = Path(self.workspace_root) / "config" / "waybar" / "configs" / "[TOP] End-4 Material 3"

        with self.assertRaises(PermissionError):
            safety.apply_change("waybar_layout", "End-4 Material 3", str(dummy_source), confirmed=False)

    def test_04_safety_apply_and_rollback(self):
        """Verify 5-step apply workflow, snapshot creation, and clean rollback."""
        safety = SafetyEngine(target_home=str(self.mock_home))
        source_layout = Path(self.workspace_root) / "config" / "waybar" / "configs" / "[TOP] End-4 Material 3"
        
        # 1. Analyze impact (dry run)
        impact = safety.analyze_impact("waybar_layout", "End-4 Material 3", str(source_layout))
        self.assertEqual(impact["status"], "READY_FOR_CONFIRMATION")
        self.assertEqual(len(impact["affected_files"]), 1)
        expected_target = self.mock_config / "waybar" / "config"
        self.assertEqual(impact["affected_files"][0]["target"], str(expected_target))

        # 2. Apply with confirmed=True
        result = safety.apply_change("waybar_layout", "End-4 Material 3", str(source_layout), confirmed=True)
        self.assertTrue(result["success"])
        snapshot_id = result["snapshot_id"]
        self.assertTrue(expected_target.exists(), "Target symlink should be created")
        self.assertTrue(expected_target.is_symlink(), "Target should be a symlink")

        # 3. Check snapshot manifest
        snapshots = safety.list_snapshots()
        self.assertEqual(len(snapshots), 1)
        self.assertEqual(snapshots[0]["snapshot_id"], snapshot_id)

        # 4. Rollback
        rollback_res = safety.rollback(snapshot_id)
        self.assertTrue(rollback_res["success"])
        # Since target was non-existent before, rollback should have removed it
        self.assertFalse(expected_target.exists(), "Rollback should restore target to pre-apply non-existent state")

    def test_05_zero_real_config_leakage(self):
        """Confirm that real ~/.config was never modified by our sandbox operations."""
        real_home = Path(os.environ.get("HOME", "/home/yusei1708"))
        safety = SafetyEngine(target_home=str(self.mock_home))
        dummy_source = Path(self.workspace_root) / "config" / "waybar" / "configs" / "[TOP] End-4 Material 3"
        safety.apply_change("waybar_layout", "End-4 Material 3", str(dummy_source), confirmed=True)

        # Confirm target was only created inside mock sandbox
        self.assertTrue(str(safety.config_dir).startswith(str(self.test_dir)))
        self.assertFalse(str(safety.config_dir) == str(real_home / ".config"))

if __name__ == "__main__":
    unittest.main()
