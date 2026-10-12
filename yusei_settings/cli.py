"""
yusei-settings CLI entrypoint
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Supports running the Windows 11 Web UI, GTK4 native desktop window,
listing catalog items, or running sandboxed self-tests.
"""

import argparse
import sys
import os
from pathlib import Path

# Ensure package root is in python path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from yusei_settings.core.discovery import DiscoveryEngine
from yusei_settings.core.state import StateManager
from yusei_settings.core.safety import SafetyEngine
from yusei_settings.server import create_server
from yusei_settings.ui.gtk import launch_gtk_app, is_gtk_available

def main():
    parser = argparse.ArgumentParser(description="yusei-settings: Linux/Hyprland Desktop Settings Application")
    parser.add_argument("--web", action="store_true", help="Launch the local Windows 11 Fluent web interface (Default)")
    parser.add_argument("--gui", action="store_true", help="Launch the native GTK4 / Libadwaita desktop window")
    parser.add_argument("--port", type=int, default=8999, help="Port for the local web interface (default: 8999)")
    parser.add_argument("--host", type=str, default="127.0.0.1", help="Host address (default: 127.0.0.1)")
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
            for it in items[:6]:
                print(f"  • {it.get('name')} (ID: {it.get('id')})")
            if len(items) > 6:
                print(f"  ... và {len(items) - 6} mục khác.")
        return 0

    # 2. Native GTK4 GUI Mode
    if args.gui:
        if not is_gtk_available():
            print("[WARN] GTK4 / Libadwaita is not available in current display environment.")
            print("[INFO] Falling back to Windows 11 Web UI...")
        else:
            return launch_gtk_app(workspace_root, args.target_home)

    # 3. Web UI Mode (Default)
    server = create_server(args.host, args.port, workspace_root, args.target_home)
    print(f"\n=======================================================")
    print(f"  ✨ YUSEI-SETTINGS IS RUNNING ✨")
    print(f"  Giao diện cài đặt: http://{args.host}:{args.port}")
    print(f"  Nhấn Ctrl+C để dừng ứng dụng.")
    print(f"=======================================================\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nĐã đóng yusei-settings.")
        server.server_close()
    return 0

if __name__ == "__main__":
    sys.exit(main())
