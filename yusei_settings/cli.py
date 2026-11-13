"""
yusei-settings CLI entrypoint
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Launches the native GTK4 / Libadwaita desktop settings window,
starts the local Web UI server (--web), or lists discovered catalog items.
"""

import argparse
import os
import sys
import threading
import webbrowser
from pathlib import Path
from typing import Optional

# Ensure package root is in python path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from yusei_settings.core.discovery import DiscoveryEngine
from yusei_settings.server import create_server
from yusei_settings.ui.gtk import is_gtk_available, launch_gtk_app


def resolve_workspace_root(explicit_root: Optional[str] = None, target_home: Optional[str] = None) -> str:
    """
    Resolves the workspace/assets root accurately even when launched from
    ~/.local/bin/yusei-settings -> ~/.local/share/yusei-hypr/yusei_settings/cli.py.
    """
    if explicit_root:
        return str(Path(explicit_root).resolve())

    package_root = Path(__file__).resolve().parent.parent
    if (package_root / "config").is_dir() or (package_root / "assets").is_dir() or (package_root / ".git").exists():
        return str(package_root)

    env_dir = os.environ.get("YUSEI_HYPR_DIR")
    home_dir = Path(target_home).resolve() if target_home else Path(os.environ.get("HOME", str(Path.home()))).resolve()

    candidates = []
    if env_dir:
        candidates.append(Path(env_dir))
    candidates.extend([
        home_dir / ".local" / "share" / "yusei-hypr",
        home_dir / "yusei-hypr",
        home_dir / "Documents" / "yusei-hypr",
        home_dir / "Projects" / "yusei-hypr",
    ])

    for cand in candidates:
        if (cand / "config").is_dir() and (cand / "assets").is_dir():
            return str(cand.resolve())

    for cand in candidates:
        if (cand / "yusei_settings").is_dir() and ((cand / "assets").is_dir() or (cand / "scripts").is_dir()):
            return str(cand.resolve())

    return str(package_root)


def launch_web_server(
    workspace_root: str,
    target_home: Optional[str] = None,
    port: int = 8999,
    open_browser: bool = True,
) -> int:
    if port < 0 or port > 65535:
        print(f"[ERROR] Invalid port: {port}", file=sys.stderr)
        return 2

    try:
        server = create_server(
            host="127.0.0.1",
            port=port,
            workspace_root=workspace_root,
            target_home=target_home,
        )
    except OSError as exc:
        print(f"[ERROR] Không thể khởi chạy Web UI tại 127.0.0.1:{port}: {exc}", file=sys.stderr)
        return 1

    actual_port = server.server_address[1]
    url = f"http://127.0.0.1:{actual_port}/"
    print(f"yusei-settings Web UI đang chạy tại: {url}", flush=True)

    if open_browser:
        threading.Timer(0.3, lambda: webbrowser.open(url)).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()
        server.server_close()
    return 0


def main(argv: Optional[list] = None):
    parser = argparse.ArgumentParser(description="yusei-settings: Desktop Settings Application (GTK4 / Web UI)")
    parser.add_argument("--gui", action="store_true", help="Launch the native GTK4 / Libadwaita desktop window (Default)")
    parser.add_argument("--web", action="store_true", help="Start the local Web UI HTTP server and open in browser")
    parser.add_argument("--port", type=int, default=8999, help="Port for --web server (default: 8999)")
    parser.add_argument("--no-browser", action="store_true", help="Do not automatically open a browser in --web mode")
    parser.add_argument("--list", action="store_true", help="List all discovered layouts and themes in terminal")
    parser.add_argument("--target-home", type=str, default=None, help="Mock target home directory for safe sandbox testing")
    parser.add_argument("--workspace-root", type=str, default=None, help="Explicit workspace/repo root directory")

    args = parser.parse_args(argv)
    workspace_root = resolve_workspace_root(args.workspace_root, args.target_home)

    # 1. Terminal List Mode
    if args.list:
        disc = DiscoveryEngine(workspace_root, target_home=args.target_home)
        cat = disc.discover_all()
        print("\n=== YUSEI-SETTINGS DISCOVERED CATALOG ===")
        for key, items in cat.items():
            print(f"\n[{key.upper()}] ({len(items)} items):")
            for it in items:
                print(f"  • {it.get('name')} (ID: {it.get('id')})")
        return 0

    # 2. Local Web UI Mode
    if args.web:
        return launch_web_server(
            workspace_root=workspace_root,
            target_home=args.target_home,
            port=args.port,
            open_browser=not args.no_browser,
        )

    # 3. Native GTK4 / Libadwaita Desktop Window
    if is_gtk_available():
        return launch_gtk_app(workspace_root, args.target_home)

    print(
        "[ERROR] Không thể mở giao diện GTK4 / Libadwaita. "
        "Hãy chạy trong phiên Wayland/X11 hoặc dùng `--web` để mở giao diện trình duyệt."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
