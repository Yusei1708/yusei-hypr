"""
yusei-settings: Local HTTP Server & API Bridge
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Zero-dependency local server using Python standard library `http.server`.
Serves the Windows 11 Fluent web interface and exposes the Discovery & Safety APIs.
"""

import json
import mimetypes
import os
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from typing import Optional

from yusei_settings.core.discovery import DiscoveryEngine
from yusei_settings.core.state import StateManager
from yusei_settings.core.safety import SafetyEngine
from yusei_settings.core.preview import PreviewEngine

class SettingsRequestHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, workspace_root: Optional[str] = None, target_home: Optional[str] = None, **kwargs):
        self.workspace_root = workspace_root or str(Path(__file__).resolve().parent.parent)
        self.target_home = target_home
        self.discovery = DiscoveryEngine(self.workspace_root)
        self.state_mgr = StateManager(self.target_home)
        self.safety_engine = SafetyEngine(self.target_home)
        super().__init__(*args, **kwargs)

    def log_message(self, format, *args):
        # Quiet logger for non-intrusive operations
        pass

    def send_json(self, data: dict, status: int = 200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def serve_file(self, file_path: Path):
        if not file_path.exists() or not file_path.is_file():
            self.send_error(404, "File not found")
            return

        mime_type, _ = mimetypes.guess_type(str(file_path))
        if not mime_type:
            mime_type = "application/octet-stream"

        content = file_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", mime_type)
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        # Static index
        if path == "/" or path == "/index.html":
            index_file = Path(self.workspace_root) / "yusei_settings" / "ui" / "web" / "index.html"
            return self.serve_file(index_file)

        # Static UI assets
        if path.startswith("/ui/web/"):
            rel_path = path.replace("/ui/web/", "")
            target_file = Path(self.workspace_root) / "yusei_settings" / "ui" / "web" / rel_path
            return self.serve_file(target_file)

        # Assets (wallpapers/icons)
        if path.startswith("/assets/"):
            rel_path = path.replace("/assets/", "")
            target_file = Path(self.workspace_root) / "assets" / rel_path
            return self.serve_file(target_file)

        # API: Catalog
        if path == "/api/catalog":
            catalog = self.discovery.discover_all()
            # Enrich items with preview SVGs
            for item in catalog.get("waybar_layouts", []):
                item["preview_svg"] = PreviewEngine.generate_waybar_svg(item.get("position", "TOP"), item.get("name", ""))
            for item in catalog.get("rofi_themes", []):
                item["preview_svg"] = PreviewEngine.generate_rofi_svg(item.get("style_type", "Centered Card"))
            for item in catalog.get("kitty_themes", []):
                item["preview_svg"] = PreviewEngine.generate_kitty_svg(item.get("palette", {}))
            for item in catalog.get("hyprland_animations", []):
                item["preview_svg"] = PreviewEngine.generate_waybar_svg("TOP", item.get("name", ""))

            return self.send_json(catalog)

        # API: Active State
        if path == "/api/state":
            state = self.state_mgr.get_active_state()
            return self.send_json(state)

        # API: Snapshots History
        if path == "/api/snapshots":
            snapshots = self.safety_engine.list_snapshots()
            return self.send_json(snapshots)

        self.send_error(404, "Endpoint not found")

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        content_len = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_len) if content_len > 0 else b"{}"
        try:
            payload = json.loads(body.decode("utf-8"))
        except Exception:
            payload = {}

        # API: Analyze Impact (Stages 1 & 2)
        if path == "/api/analyze":
            category = payload.get("category")
            item_id = payload.get("item_id")
            source_path = payload.get("source_path")
            impact = self.safety_engine.analyze_impact(category, item_id, source_path)
            return self.send_json(impact)

        # API: Apply Change (Stages 4 & 5)
        if path == "/api/apply":
            category = payload.get("category")
            item_id = payload.get("item_id")
            source_path = payload.get("source_path")
            confirmed = bool(payload.get("confirmed", False))
            try:
                result = self.safety_engine.apply_change(category, item_id, source_path, confirmed)
                return self.send_json(result)
            except Exception as e:
                return self.send_json({"success": False, "message": str(e)}, status=400)

        # API: Rollback
        if path == "/api/rollback":
            snapshot_id = payload.get("snapshot_id")
            try:
                result = self.safety_engine.rollback(snapshot_id)
                return self.send_json(result)
            except Exception as e:
                return self.send_json({"success": False, "message": str(e)}, status=400)

        self.send_error(404, "Endpoint not found")

def create_server(host: str = "127.0.0.1", port: int = 8999, workspace_root: Optional[str] = None, target_home: Optional[str] = None) -> HTTPServer:
    handler = lambda *args, **kwargs: SettingsRequestHandler(
        *args,
        workspace_root=workspace_root,
        target_home=target_home,
        **kwargs
    )
    return HTTPServer((host, port), handler)
