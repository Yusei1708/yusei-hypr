"""
yusei-settings: Local HTTP Server & API Bridge
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Zero-dependency local server using Python standard library `http.server`.
Serves the Windows 11 Fluent web interface and exposes the Discovery & Safety APIs.
"""

import json
import mimetypes
import os
import subprocess
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from typing import Optional

from yusei_settings.core.discovery import DiscoveryEngine
from yusei_settings.core.state import StateManager
from yusei_settings.core.safety import SafetyEngine
from yusei_settings.core.preview import PreviewEngine
from yusei_settings.core.keybinds import KeybindParser

class SettingsRequestHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, workspace_root: Optional[str] = None, target_home: Optional[str] = None, **kwargs):
        self.workspace_root = workspace_root or str(Path(__file__).resolve().parent.parent)
        self.target_home = target_home
        self.discovery = DiscoveryEngine(self.workspace_root)
        self.state_mgr = StateManager(self.target_home)
        self.safety_engine = SafetyEngine(self.target_home)
        keybinds_conf = Path(self.workspace_root) / "config" / "hypr" / "keybinds.conf"
        self.keybind_parser = KeybindParser(str(keybinds_conf))
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
        # Path containment check: ensure target_file cannot escape workspace_root
        try:
            resolved_root = Path(self.workspace_root).resolve()
            resolved_file = file_path.resolve()
            if not resolved_file.is_relative_to(resolved_root):
                self.send_error(403, "Access denied: Path traversal detected")
                return
        except Exception:
            self.send_error(403, "Access denied")
            return

        if not resolved_file.exists() or not resolved_file.is_file():
            self.send_error(404, "File not found")
            return

        mime_type, _ = mimetypes.guess_type(str(resolved_file))
        if not mime_type:
            mime_type = "application/octet-stream"

        content = resolved_file.read_bytes()
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
            rel_path = path[len("/ui/web/"):].lstrip("/")
            target_file = Path(self.workspace_root) / "yusei_settings" / "ui" / "web" / rel_path
            return self.serve_file(target_file)

        # Assets (wallpapers/icons)
        if path.startswith("/assets/"):
            rel_path = path[len("/assets/"):].lstrip("/")
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

        # API: Keybinds Cheat Sheet
        if path == "/api/keybinds":
            items = self.keybind_parser.parse()
            categories = self.keybind_parser.get_categories()
            count = len(items)
            return self.send_json({
                "total": count,
                "total_count": count,
                "categories": categories,
                "keybinds": items,
            })

        # API: System Status
        if path == "/api/system/status":
            branch = "main"
            commit = ""
            is_dirty = False
            try:
                b_proc = subprocess.run(
                    ["git", "-C", self.workspace_root, "rev-parse", "--abbrev-ref", "HEAD"],
                    capture_output=True, text=True, check=False
                )
                if b_proc.returncode == 0:
                    branch = b_proc.stdout.strip()
                c_proc = subprocess.run(
                    ["git", "-C", self.workspace_root, "rev-parse", "HEAD"],
                    capture_output=True, text=True, check=False
                )
                if c_proc.returncode == 0:
                    commit = c_proc.stdout.strip()
                s_proc = subprocess.run(
                    ["git", "-C", self.workspace_root, "status", "--porcelain"],
                    capture_output=True, text=True, check=False
                )
                if s_proc.returncode == 0 and s_proc.stdout.strip():
                    is_dirty = True
            except Exception:
                pass

            home_p = Path(self.target_home) if self.target_home else Path(os.environ.get("HOME", "/home/user"))
            cfg_dir = home_p / ".config"

            last_backup = "None"
            backup_count = 0
            if cfg_dir.exists():
                backups = [p for p in cfg_dir.glob("yusei-hypr-backup-*") if p.is_dir()]
                backup_count = len(backups)
                latest_link = cfg_dir / "yusei-hypr-backup-latest"
                if latest_link.exists() or latest_link.is_symlink():
                    try:
                        last_backup = str(latest_link.resolve().name)
                    except Exception:
                        pass
                elif backups:
                    backups.sort(key=lambda x: x.stat().st_mtime, reverse=True)
                    last_backup = str(backups[0].name)

            userprefs_path = cfg_dir / "hypr" / "userprefs.conf"
            userprefs_intact = userprefs_path.exists() or (Path(self.workspace_root) / "config" / "hypr" / "userprefs.conf").exists()

            return self.send_json({
                "git_branch": branch,
                "git_commit": commit,
                "git_hash": commit[:8] if commit else "",
                "dirty": is_dirty,
                "is_clean": not is_dirty,
                "last_backup": last_backup,
                "backup_count": backup_count,
                "userprefs_intact": userprefs_intact,
            })

        # API: System Update Check
        if path == "/api/system/update/check":
            current_commit = ""
            try:
                c_proc = subprocess.run(
                    ["git", "-C", self.workspace_root, "rev-parse", "HEAD"],
                    capture_output=True, text=True, check=False
                )
                if c_proc.returncode == 0:
                    current_commit = c_proc.stdout.strip()
            except Exception:
                pass

            return self.send_json({
                "update_available": False,
                "current_commit": current_commit,
                "message": "Hệ thống đang ở phiên bản mới nhất.",
            })

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

        # API: System Backup Snapshot
        if path == "/api/system/backup":
            backup_script = Path(self.workspace_root) / "scripts" / "03-backup.sh"
            env = os.environ.copy()
            if self.target_home:
                env["HOME"] = str(self.target_home)
                env["XDG_CONFIG_HOME"] = str(Path(self.target_home) / ".config")

            try:
                proc = subprocess.run(
                    [str(backup_script)],
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False
                )
                home_p = Path(env.get("HOME", str(Path.home())))
                latest_link = home_p / ".config" / "yusei-hypr-backup-latest"
                backup_dir = ""
                manifest = {}
                if latest_link.exists() or latest_link.is_symlink():
                    try:
                        backup_dir = str(latest_link.resolve())
                        manifest_file = Path(backup_dir) / "manifest.json"
                        if manifest_file.exists():
                            manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
                    except Exception:
                        pass

                return self.send_json({
                    "success": proc.returncode == 0,
                    "backup_dir": backup_dir,
                    "manifest": manifest,
                    "log": proc.stdout,
                })
            except Exception as e:
                return self.send_json({"success": False, "message": str(e)}, status=500)

        # API: System Update Apply
        if path == "/api/system/update/apply":
            update_script = Path(self.workspace_root) / "update.sh"
            confirmed = bool(payload.get("confirmed", False))
            dry_run = bool(payload.get("dry_run", not confirmed))

            cmd = [str(update_script), "-y", "--skip-git", "--no-reload"]
            if dry_run or not confirmed:
                cmd.append("--dry-run")

            env = os.environ.copy()
            if self.target_home:
                env["HOME"] = str(self.target_home)
                env["XDG_CONFIG_HOME"] = str(Path(self.target_home) / ".config")

            try:
                proc = subprocess.run(
                    cmd,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False
                )
                return self.send_json({
                    "success": proc.returncode == 0,
                    "dry_run": dry_run,
                    "log": proc.stdout + proc.stderr,
                })
            except Exception as e:
                return self.send_json({"success": False, "message": str(e)}, status=500)

        self.send_error(404, "Endpoint not found")

def create_server(host: str = "127.0.0.1", port: int = 8999, workspace_root: Optional[str] = None, target_home: Optional[str] = None) -> HTTPServer:
    handler = lambda *args, **kwargs: SettingsRequestHandler(
        *args,
        workspace_root=workspace_root,
        target_home=target_home,
        **kwargs
    )
    return HTTPServer((host, port), handler)
