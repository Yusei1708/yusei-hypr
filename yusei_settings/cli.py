"""
yusei-settings CLI entrypoint
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Launches the native GTK4 / Libadwaita desktop settings window
or lists discovered catalog items in terminal.
"""

import argparse
import sys
from pathlib import Path

# Ensure package root is in python path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from yusei_settings.core.discovery import DiscoveryEngine
from yusei_settings.ui.gtk import launch_gtk_app, is_gtk_available

def main():
    parser = argparse.ArgumentParser(description="yusei-settings: Native GTK4/Libadwaita Desktop Settings Application")
    parser.add_argument("--gui", action="store_true", help="Launch the native GTK4 / Libadwaita desktop window (Default)")
    parser.add_argument("--list", action="store_true", help="List all discovered layouts and themes in terminal")
    parser.add_argument("--target-home", type=str, default=None, help="Mock target home directory for safe sandbox testing")

    args = parser.parse_args()
    workspace_root = str(Path(__file__).resolve().parent.parent)

    # 1. Terminal List Mode
    if args.list:
        disc = DiscoveryEngine(workspace_root)
        cat = disc.discover_all()
        print("\n=== YUSEI-SETTINGS DISCOVERED CATALOG ===")
        for key, items in cat.items():
            print(f"\n[{key.upper()}] ({len(items)} items):")
            for it in items:
                print(f"  • {it.get('name')} (ID: {it.get('id')})")
        return 0

    # 2. Native GTK4 / Libadwaita Desktop Window
    if is_gtk_available():
        return launch_gtk_app(workspace_root, args.target_home)

    print("[ERROR] Không thể mở giao diện GTK4 / Libadwaita. Vui lòng chạy ứng dụng trong môi trường đồ họa Wayland/X11.")
    return 1

if __name__ == "__main__":
    sys.exit(main())
