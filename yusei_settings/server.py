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
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional

from yusei_settings.core.discovery import DiscoveryEngine
from yusei_settings.core.keybinds import KeybindParser
from yusei_settings.core.power import PowerManager
from yusei_settings.core.preview import PreviewEngine
from yusei_settings.core.safety import SafetyEngine
from yusei_settings.core.state import StateManager


MAX_POST_BODY_BYTES = 1_048_576
LOCAL_HOSTNAMES = {"localhost", "127.0.0.1", "::1"}
ALLOWED_WALLPAPER_EXTS = {".jpg", ".jpeg", ".png", ".webp"}


class RequestValidationError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


class SettingsRequestHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, workspace_root: Optional[str] = None, target_home: Optional[str] = None, **kwargs):
        self.workspace_root = str(Path(workspace_root).resolve()) if workspace_root else str(Path(__file__).resolve().parent.parent)
        self.target_home = str(Path(target_home).resolve()) if target_home else None
        self.home_dir = Path(self.target_home).resolve() if self.target_home else Path(os.environ.get("HOME", str(Path.home()))).resolve()

        self.discovery = DiscoveryEngine(self.workspace_root, target_home=self.target_home)
        self.state_mgr = StateManager(self.target_home)
        self.safety_engine = SafetyEngine(self.target_home)
        self.power_mgr = PowerManager(self.workspace_root, self.target_home)

        kb_candidates = [
            self.home_dir / ".config" / "hypr" / "keybinds.conf",
            self.home_dir / ".config" / "hypr" / "hyprland.lua",
            Path(self.workspace_root) / "config" / "hypr" / "keybinds.conf",
            Path(self.workspace_root) / "config" / "hypr" / "hyprland.lua",
        ]
        keybinds_conf = next((p for p in kb_candidates if p.exists()), kb_candidates[2])
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
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    @staticmethod
    def _validate_rel_parts(rel_path: str) -> List[str]:
        unquoted = urllib.parse.unquote(rel_path)
        if "\x00" in unquoted or "\\" in unquoted or unquoted.startswith("/"):
            raise PermissionError("Path traversal detected")
        raw_parts = unquoted.split("/")
        if any(part == ".." for part in raw_parts):
            raise PermissionError("Path traversal detected")
        return [part for part in raw_parts if part and part != "."]

    @classmethod
    def _resolve_under_root(cls, base_dir: Path, rel_path: str) -> Path:
        parts = cls._validate_rel_parts(rel_path)
        if not parts:
            raise FileNotFoundError("Empty relative path")
        resolved_base = base_dir.resolve()
        resolved_target = (resolved_base / Path(*parts)).resolve()
        if not resolved_target.is_relative_to(resolved_base) or resolved_target == resolved_base:
            raise PermissionError("Path traversal detected")
        return resolved_target

    def _allowed_source_roots(self, canonical_cat: str) -> List[Path]:
        ws = Path(self.workspace_root).resolve()
        ws_cfg = ws / "config"
        home_cfg = self.home_dir / ".config"
        share_assets = self.home_dir / ".local" / "share" / "yusei-hypr" / "assets"

        mapping = {
            "waybar_layout": [ws_cfg / "waybar" / "configs", home_cfg / "waybar" / "configs"],
            "waybar_style": [ws_cfg / "waybar" / "style", home_cfg / "waybar" / "style"],
            "rofi_theme": [
                ws_cfg / "rofi" / "themes",
                home_cfg / "rofi" / "themes",
                ws_cfg / "rofi" / "config.rasi",
                home_cfg / "rofi" / "config.rasi",
            ],
            "kitty_theme": [ws_cfg / "kitty" / "kitty-themes", home_cfg / "kitty" / "kitty-themes"],
            "hyprland_animation": [ws_cfg / "hypr" / "animations", home_cfg / "hypr" / "animations"],
            "wallpaper": [
                ws / "assets" / "wallpapers",
                share_assets / "wallpapers",
                self.home_dir / "Pictures" / "wallpapers",
                home_cfg / "hypr" / "wallpapers",
            ],
        }
        return mapping.get(canonical_cat, [])

    def _validate_source_path(self, canonical_cat: str, source_path: Any) -> Path:
        if not isinstance(source_path, str) or not source_path or "\x00" in source_path:
            raise ValueError("Invalid source_path")
        try:
            resolved_src = Path(source_path).resolve(strict=True)
        except FileNotFoundError as exc:
            raise FileNotFoundError(f"Source file not found: {source_path}") from exc
        if not resolved_src.is_file():
            raise ValueError("source_path must reference a regular file")

        if canonical_cat == "wallpaper" and resolved_src.suffix.lower() not in ALLOWED_WALLPAPER_EXTS:
            raise ValueError("Unsupported wallpaper file type")

        allowed_roots = self._allowed_source_roots(canonical_cat)
        for root in allowed_roots:
            resolved_root = root.resolve()
            if resolved_src == resolved_root or resolved_src.is_relative_to(resolved_root):
                return resolved_src

        raise PermissionError("Access denied: source_path outside allowed asset roots")

    def _check_csrf_and_content_type(self) -> None:
        host_hdr = self.headers.get("Host")
        if host_hdr:
            parsed_host = urllib.parse.urlsplit(f"//{host_hdr.strip()}")
            if (parsed_host.hostname or "").lower() not in LOCAL_HOSTNAMES:
                raise RequestValidationError(403, "Forbidden: untrusted Host header")

        sec_fetch_site = self.headers.get("Sec-Fetch-Site")
        if sec_fetch_site and sec_fetch_site.strip().lower() == "cross-site":
            raise RequestValidationError(403, "Forbidden: cross-site request blocked")

        origin = self.headers.get("Origin")
        if origin is not None:
            origin_s = origin.strip()
            if not origin_s or origin_s.lower() == "null":
                raise RequestValidationError(403, "Forbidden: untrusted Origin")
            parsed_origin = urllib.parse.urlparse(origin_s)
            if parsed_origin.scheme not in {"http", "https"} or (parsed_origin.hostname or "").lower() not in LOCAL_HOSTNAMES:
                raise RequestValidationError(403, "Forbidden: cross-origin request blocked")

        referer = self.headers.get("Referer")
        if referer is not None:
            parsed_ref = urllib.parse.urlparse(referer.strip())
            if parsed_ref.scheme not in {"http", "https"} or (parsed_ref.hostname or "").lower() not in LOCAL_HOSTNAMES:
                raise RequestValidationError(403, "Forbidden: untrusted Referer")

        content_type = self.headers.get("Content-Type", "")
        media_type = content_type.split(";", 1)[0].strip().lower()
        if media_type != "application/json":
            raise RequestValidationError(415, "Unsupported Media Type: Content-Type must be application/json")

    def _read_json_body(self) -> Dict[str, Any]:
        raw_len = self.headers.get("Content-Length")
        if raw_len is None or raw_len == "":
            content_len = 0
        else:
            try:
                content_len = int(raw_len.strip())
            except ValueError as exc:
                raise RequestValidationError(400, "Invalid Content-Length header") from exc
            if content_len < 0:
                raise RequestValidationError(400, "Negative Content-Length header")
            if content_len > MAX_POST_BODY_BYTES:
                raise RequestValidationError(413, "Request payload exceeds 1 MiB limit")

        body = self.rfile.read(content_len) if content_len > 0 else b"{}"
        if content_len > 0 and len(body) != content_len:
            raise RequestValidationError(400, "Incomplete request body")

        try:
            text = body.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise RequestValidationError(400, "Request body is not valid UTF-8") from exc

        try:
            payload = json.loads(text)
        except json.JSONDecodeError as exc:
            raise RequestValidationError(400, f"Malformed JSON payload: {exc.msg}") from exc

        if not isinstance(payload, dict):
            raise RequestValidationError(400, "JSON body must be an object")

        return payload

    def serve_file(self, file_path: Path, allowed_roots: List[Path]):
        """Serves a regular file only if strictly contained within allowed_roots."""
        try:
            resolved_file = file_path.resolve()
            is_valid = any(resolved_file.is_relative_to(root.resolve()) for root in allowed_roots)
            if not is_valid:
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
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        web_root = (Path(self.workspace_root) / "yusei_settings" / "ui" / "web").resolve()

        # Static index
        if path == "/" or path == "/index.html":
            index_file = web_root / "index.html"
            return self.serve_file(index_file, [web_root])

        # Static UI assets
        if path.startswith("/ui/web/"):
            rel_path = path[len("/ui/web/"):]
            try:
                target_file = self._resolve_under_root(web_root, rel_path)
            except PermissionError:
                self.send_error(403, "Access denied: Path traversal detected")
                return
            except FileNotFoundError:
                self.send_error(404, "File not found")
                return
            return self.serve_file(target_file, [web_root])

        # Assets (wallpapers/icons)
        if path.startswith("/assets/"):
            rel_path = path[len("/assets/"):]
            try:
                parts = self._validate_rel_parts(rel_path)
            except PermissionError:
                self.send_error(403, "Access denied: Path traversal detected")
                return

            if not parts:
                self.send_error(404, "File not found")
                return

            repo_assets = self.discovery.assets_dir.resolve()
            pics_wp_root = (self.home_dir / "Pictures" / "wallpapers").resolve()
            hypr_wp_root = (self.home_dir / ".config" / "hypr" / "wallpapers").resolve()
            allowed_roots = [repo_assets, pics_wp_root, hypr_wp_root]

            target_file: Optional[Path] = None
            try:
                cand = self._resolve_under_root(repo_assets, "/".join(parts))
                if cand.exists() and cand.is_file():
                    target_file = cand
            except PermissionError:
                self.send_error(403, "Access denied: Path traversal detected")
                return
            except FileNotFoundError:
                pass

            if target_file is None and parts[0] == "wallpapers" and len(parts) >= 2:
                wp_sub = "/".join(parts[1:])
                for wp_root in (pics_wp_root, hypr_wp_root):
                    try:
                        cand = self._resolve_under_root(wp_root, wp_sub)
                        if cand.exists() and cand.is_file():
                            target_file = cand
                            break
                    except PermissionError:
                        self.send_error(403, "Access denied: Path traversal detected")
                        return
                    except FileNotFoundError:
                        pass

            if target_file is None:
                self.send_error(404, "File not found")
                return
            return self.serve_file(target_file, allowed_roots)

        # API: Catalog
        if path == "/api/catalog":
            catalog = self.discovery.discover_all()
            for item in catalog.get("waybar_layouts", []):
                item["preview_svg"] = PreviewEngine.generate_waybar_svg(item.get("position", "TOP"), item.get("name", ""))
            for item in catalog.get("rofi_themes", []):
                item["preview_svg"] = PreviewEngine.generate_rofi_svg(item.get("style_type", "Centered Card"))
            for item in catalog.get("kitty_themes", []):
                item["preview_svg"] = PreviewEngine.generate_kitty_svg(item.get("palette", {}))
            for item in catalog.get("hyprland_animations", []):
                item["preview_svg"] = PreviewEngine.generate_animation_svg(item.get("name", ""), item.get("id", ""))

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
                    capture_output=True, text=True, check=False, timeout=3
                )
                if b_proc.returncode == 0:
                    branch = b_proc.stdout.strip()
                c_proc = subprocess.run(
                    ["git", "-C", self.workspace_root, "rev-parse", "HEAD"],
                    capture_output=True, text=True, check=False, timeout=3
                )
                if c_proc.returncode == 0:
                    commit = c_proc.stdout.strip()
                s_proc = subprocess.run(
                    ["git", "-C", self.workspace_root, "status", "--porcelain"],
                    capture_output=True, text=True, check=False, timeout=3
                )
                if s_proc.returncode == 0 and s_proc.stdout.strip():
                    is_dirty = True
            except Exception:
                pass

            cfg_dir = self.home_dir / ".config"

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
            return self.send_json(self._check_system_updates())

        # API: Power & Battery Status
        if path == "/api/power/status":
            status = self.power_mgr.get_status()
            return self.send_json(status)

        self.send_error(404, "Endpoint not found")

    def _check_system_updates(self) -> Dict[str, Any]:
        current_commit = ""
        remote_commit = ""
        branch = "main"
        checked = False
        update_available: Optional[bool] = None
        behind = 0
        dry_run_ready = False

        git_env = os.environ.copy()
        git_env["GIT_TERMINAL_PROMPT"] = "0"

        try:
            b_proc = subprocess.run(
                ["git", "-C", self.workspace_root, "rev-parse", "--abbrev-ref", "HEAD"],
                env=git_env, capture_output=True, text=True, check=False, timeout=3,
            )
            if b_proc.returncode == 0 and b_proc.stdout.strip():
                branch = b_proc.stdout.strip()

            c_proc = subprocess.run(
                ["git", "-C", self.workspace_root, "rev-parse", "HEAD"],
                env=git_env, capture_output=True, text=True, check=False, timeout=3,
            )
            if c_proc.returncode == 0:
                current_commit = c_proc.stdout.strip()

            if current_commit and branch != "HEAD":
                ls_proc = subprocess.run(
                    ["git", "-C", self.workspace_root, "ls-remote", "--heads", "origin", branch],
                    env=git_env, capture_output=True, text=True, check=False, timeout=3,
                )
                if ls_proc.returncode == 0 and ls_proc.stdout.strip():
                    remote_commit = ls_proc.stdout.strip().split()[0]
                    checked = True
                    if remote_commit == current_commit:
                        update_available = False
                        behind = 0
                    else:
                        anc = subprocess.run(
                            ["git", "-C", self.workspace_root, "merge-base", "--is-ancestor", remote_commit, "HEAD"],
                            env=git_env, capture_output=True, text=True, check=False, timeout=2,
                        )
                        if anc.returncode == 0:
                            update_available = False
                            behind = 0
                        else:
                            update_available = True
                            cnt = subprocess.run(
                                ["git", "-C", self.workspace_root, "rev-list", "--count", f"HEAD..{remote_commit}"],
                                env=git_env, capture_output=True, text=True, check=False, timeout=2,
                            )
                            if cnt.returncode == 0 and cnt.stdout.strip().isdigit():
                                behind = int(cnt.stdout.strip())
                            else:
                                behind = 1
        except Exception:
            pass

        update_script = Path(self.workspace_root) / "update.sh"
        if update_script.exists():
            try:
                env = os.environ.copy()
                if self.target_home:
                    env["HOME"] = str(self.home_dir)
                    env["XDG_CONFIG_HOME"] = str(self.home_dir / ".config")
                dry_proc = subprocess.run(
                    [str(update_script), "-y", "--skip-git", "--no-reload", "--dry-run"],
                    env=env, capture_output=True, text=True, check=False, timeout=5,
                )
                dry_run_ready = (dry_proc.returncode == 0)
            except Exception:
                dry_run_ready = False

        if not checked:
            message = "Không kiểm tra được bản cập nhật từ xa (chế độ ngoại tuyến hoặc không có remote)."
        elif update_available:
            message = f"Có {behind} bản cập nhật mới từ kho lưu trữ ({remote_commit[:8]})."
        else:
            message = "Hệ thống đang ở phiên bản mới nhất."

        return {
            "update_available": update_available,
            "checked": checked,
            "current_commit": current_commit,
            "remote_commit": remote_commit,
            "behind": behind,
            "dry_run_ready": dry_run_ready,
            "message": message,
        }

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        try:
            self._check_csrf_and_content_type()
            payload = self._read_json_body()
        except RequestValidationError as exc:
            return self.send_json({"success": False, "message": exc.message}, status=exc.status)

        # API: Analyze Impact (Stages 1 & 2)
        if path == "/api/analyze":
            category = payload.get("category")
            item_id = payload.get("item_id", "")
            source_path = payload.get("source_path")
            try:
                canonical_cat = SafetyEngine.normalize_category(category)
                resolved_src = self._validate_source_path(canonical_cat, source_path)
                impact = self.safety_engine.analyze_impact(canonical_cat, str(item_id), str(resolved_src))
                return self.send_json(impact)
            except PermissionError as exc:
                return self.send_json({"success": False, "message": str(exc)}, status=403)
            except (ValueError, FileNotFoundError) as exc:
                return self.send_json({"success": False, "message": str(exc)}, status=400)

        # API: Apply Change (Stages 4 & 5)
        if path == "/api/apply":
            category = payload.get("category")
            item_id = payload.get("item_id", "")
            source_path = payload.get("source_path")
            confirmed = bool(payload.get("confirmed", False))
            try:
                canonical_cat = SafetyEngine.normalize_category(category)
                resolved_src = self._validate_source_path(canonical_cat, source_path)
                result = self.safety_engine.apply_change(canonical_cat, str(item_id), str(resolved_src), confirmed)
                return self.send_json(result)
            except PermissionError as exc:
                status = 403 if "outside allowed" in str(exc) else 400
                return self.send_json({"success": False, "message": str(exc)}, status=status)
            except (ValueError, FileNotFoundError) as exc:
                return self.send_json({"success": False, "message": str(exc)}, status=400)
            except Exception as exc:
                return self.send_json({"success": False, "message": str(exc)}, status=500)

        # API: Rollback
        if path == "/api/rollback":
            snapshot_id = payload.get("snapshot_id")
            try:
                if snapshot_id is not None:
                    SafetyEngine.validate_snapshot_id(snapshot_id)
                result = self.safety_engine.rollback(snapshot_id)
                return self.send_json(result)
            except (ValueError, FileNotFoundError) as exc:
                return self.send_json({"success": False, "message": str(exc)}, status=400)
            except Exception as exc:
                return self.send_json({"success": False, "message": str(exc)}, status=500)

        # API: System Backup Snapshot
        if path == "/api/system/backup":
            backup_script = Path(self.workspace_root) / "scripts" / "03-backup.sh"
            env = os.environ.copy()
            if self.target_home:
                env["HOME"] = str(self.home_dir)
                env["XDG_CONFIG_HOME"] = str(self.home_dir / ".config")

            try:
                proc = subprocess.run(
                    [str(backup_script)],
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=30,
                )
                home_p = Path(env.get("HOME", str(self.home_dir)))
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

                status = 200 if proc.returncode == 0 else 500
                return self.send_json({
                    "success": proc.returncode == 0,
                    "backup_dir": backup_dir,
                    "manifest": manifest,
                    "log": proc.stdout,
                }, status=status)
            except Exception as exc:
                return self.send_json({"success": False, "message": str(exc)}, status=500)

        # API: System Update Apply
        if path == "/api/system/update/apply":
            update_script = Path(self.workspace_root) / "update.sh"
            if not update_script.exists():
                return self.send_json({"success": False, "message": "update.sh not found in workspace"}, status=400)

            confirmed = bool(payload.get("confirmed", False))
            dry_run = bool(payload.get("dry_run", not confirmed))

            cmd = [str(update_script), "-y", "--no-reload"]
            if self.target_home or dry_run or payload.get("skip_git", False):
                cmd.append("--skip-git")
            if dry_run or not confirmed:
                cmd.append("--dry-run")

            env = os.environ.copy()
            if self.target_home:
                env["HOME"] = str(self.home_dir)
                env["XDG_CONFIG_HOME"] = str(self.home_dir / ".config")

            try:
                proc = subprocess.run(
                    cmd,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=60,
                )
                ok = proc.returncode == 0
                return self.send_json({
                    "success": ok,
                    "dry_run": dry_run or not confirmed,
                    "log": proc.stdout + proc.stderr,
                    "message": "Update completed" if ok else f"update.sh exited with code {proc.returncode}",
                }, status=200 if ok else 500)
            except Exception as exc:
                return self.send_json({"success": False, "message": str(exc)}, status=500)

        # API: Set Power Profile (eco, balanced, turbo)
        if path == "/api/power/profile":
            profile = payload.get("profile", "")
            try:
                result = self.power_mgr.set_profile(profile)
                status = 200 if result.get("success") else 400
                return self.send_json(result, status=status)
            except Exception as exc:
                return self.send_json({"success": False, "message": str(exc)}, status=400)

        # API: Cycle Power Profile (eco -> balanced -> turbo -> eco)
        if path == "/api/power/cycle-profile":
            try:
                result = self.power_mgr.cycle_profile()
                status = 200 if result.get("success") else 500
                return self.send_json(result, status=status)
            except Exception as exc:
                return self.send_json({"success": False, "message": str(exc)}, status=500)

        # API: Set Power Config (auto_60hz, power_daemon, ac_profile, bat_profile)
        if path == "/api/power/config":
            try:
                result = self.power_mgr.set_config(
                    auto_60hz=payload.get("auto_60hz"),
                    power_daemon=payload.get("power_daemon"),
                    ac_profile=payload.get("ac_profile"),
                    bat_profile=payload.get("bat_profile"),
                )
                status = 200 if result.get("success") else 400
                return self.send_json(result, status=status)
            except ValueError as exc:
                return self.send_json({"success": False, "message": str(exc)}, status=400)
            except Exception as exc:
                return self.send_json({"success": False, "message": str(exc)}, status=500)

        # API: Toggle Refresh Rate (60Hz <-> Max Hz)
        if path == "/api/power/toggle-hz":
            try:
                result = self.power_mgr.toggle_hz()
                status = 200 if result.get("success") else 500
                return self.send_json(result, status=status)
            except Exception as exc:
                return self.send_json({"success": False, "message": str(exc)}, status=500)

        self.send_error(404, "Endpoint not found")


def create_server(host: str = "127.0.0.1", port: int = 8999, workspace_root: Optional[str] = None, target_home: Optional[str] = None) -> HTTPServer:
    handler = lambda *args, **kwargs: SettingsRequestHandler(
        *args,
        workspace_root=workspace_root,
        target_home=target_home,
        **kwargs
    )
    return HTTPServer((host, port), handler)
