"""
Native Libadwaita & GTK4 Settings Window
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Provides modern GNOME / Libadwaita preferences window with full catalog access,
instant live-filtering search, real-time Hyprland controls, and 5-stage safety rollback.
"""

import os
import re
import sys
import stat
import hashlib
import random
import tempfile
import threading
import subprocess
from pathlib import Path
from typing import Optional, Any, List, Tuple, Dict

_DECORATION_OPEN_RE = re.compile(r"^([ \t]*)decoration\s*\{(.*)$")
_ROUNDING_RE = re.compile(r"^([ \t]*rounding\s*=\s*)(-?\d+(?:\.\d+)?)(.*)$")
_BLUR_OPEN_RE = re.compile(r"^([ \t]*)blur\s*\{(.*)$")
_BLUR_ENABLED_RE = re.compile(
    r"^([ \t]*enabled\s*=\s*)(true|false|yes|no|1|0)\b(.*)$",
    re.IGNORECASE,
)


def _split_line_comment(line: str) -> Tuple[str, str, str]:
    """Splits a config line into (code_part, comment_part, newline)."""
    nl = "\n" if line.endswith("\n") else ""
    raw = line[:-1] if nl else line
    if "#" in raw:
        idx = raw.index("#")
        return raw[:idx], raw[idx:], nl
    return raw, "", nl


def _atomic_write_text(path: Path, content: str) -> None:
    """Atomically writes UTF-8 text via temp file in same directory + os.replace."""
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    fd, tmp_path = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=str(path.parent),
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp_path, mode)
        os.replace(tmp_path, path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def _parse_decorations_text(text: str) -> Tuple[Optional[int], Optional[bool]]:
    """Extracts active rounding and blur:enabled from Hyprland decoration config text."""
    rounding: Optional[int] = None
    blur_enabled: Optional[bool] = None
    depth = 0
    blur_depth: Optional[int] = None

    for line in text.splitlines():
        code, _comment, _nl = _split_line_comment(line)

        if blur_depth is None:
            m_round = _ROUNDING_RE.match(code)
            if m_round:
                try:
                    rounding = int(float(m_round.group(2)))
                except ValueError:
                    pass
            m_blur = _BLUR_OPEN_RE.match(code)
            if m_blur:
                blur_depth = depth
                depth += code.count("{") - code.count("}")
                rest = m_blur.group(2)
                if depth <= blur_depth:
                    inside = rest.split("}", 1)[0]
                    m_en = re.search(
                        r"\benabled\s*=\s*(true|false|yes|no|1|0)\b",
                        inside,
                        re.IGNORECASE,
                    )
                    if m_en:
                        blur_enabled = m_en.group(1).lower() in ("true", "yes", "1")
                    blur_depth = None
                continue
        else:
            m_en = _BLUR_ENABLED_RE.match(code)
            if m_en:
                blur_enabled = m_en.group(2).lower() in ("true", "yes", "1")
            depth += code.count("{") - code.count("}")
            if depth <= blur_depth:
                blur_depth = None
            continue

        depth += code.count("{") - code.count("}")

    return rounding, blur_enabled


def _append_inside_decoration(text: str, inner_lines: List[str]) -> str:
    """Inserts lines inside the first top-level `decoration { ... }` block or appends a new block."""
    lines = text.splitlines(keepends=True)
    depth = 0
    dec_depth: Optional[int] = None
    dec_indent = ""
    child_indent: Optional[str] = None

    for idx, line in enumerate(lines):
        code, comment, nl = _split_line_comment(line)
        if dec_depth is None:
            m_dec = _DECORATION_OPEN_RE.match(code)
            if m_dec and depth == 0:
                dec_indent = m_dec.group(1)
                dec_depth = depth
                depth += code.count("{") - code.count("}")
                if depth <= dec_depth:
                    before_close, close_and_after = m_dec.group(2).split("}", 1)
                    extra = before_close.strip()
                    indent = f"{dec_indent}    "
                    body = "".join(f"{indent}{l}\n" for l in inner_lines)
                    if extra:
                        body = f"{indent}{extra}\n{body}"
                    lines[idx] = f"{dec_indent}decoration {{\n{body}{dec_indent}}}{close_and_after}{comment}{nl}"
                    return "".join(lines)
                continue
            depth += code.count("{") - code.count("}")
        else:
            if child_indent is None and code.strip() and not code.lstrip().startswith("}"):
                child_indent = code[: len(code) - len(code.lstrip())]
            depth += code.count("{") - code.count("}")
            if depth <= dec_depth:
                indent = child_indent or f"{dec_indent}    "
                inserted = [f"{indent}{l}\n" for l in inner_lines]
                lines[idx:idx] = inserted
                return "".join(lines)

    if not text:
        sep = ""
    elif text.endswith("\n\n"):
        sep = ""
    elif text.endswith("\n"):
        sep = "\n"
    else:
        sep = "\n\n"
    body = "".join(f"    {l}\n" for l in inner_lines)
    return f"{text}{sep}decoration {{\n{body}}}\n"


def _set_decorations_rounding(text: str, rounding: int) -> str:
    """Updates an active rounding line in place or adds `rounding = N` inside `decoration { ... }`."""
    lines = text.splitlines(keepends=True)
    for idx, line in enumerate(lines):
        code, comment, nl = _split_line_comment(line)
        m_round = _ROUNDING_RE.match(code)
        if m_round:
            lines[idx] = f"{m_round.group(1)}{int(rounding)}{m_round.group(3)}{comment}{nl}"
            return "".join(lines)

    return _append_inside_decoration(text, [f"rounding = {int(rounding)}"])


def _set_decorations_blur(text: str, enabled: bool) -> str:
    """Updates `blur { enabled = ... }` in place or adds it inside `decoration { ... }`."""
    val_str = "true" if enabled else "false"
    lines = text.splitlines(keepends=True)
    depth = 0
    blur_depth: Optional[int] = None
    blur_start_idx: Optional[int] = None
    blur_indent = ""
    child_indent: Optional[str] = None

    for idx, line in enumerate(lines):
        code, comment, nl = _split_line_comment(line)

        if blur_depth is None:
            m_blur = _BLUR_OPEN_RE.match(code)
            if m_blur:
                blur_indent = m_blur.group(1)
                blur_depth = depth
                blur_start_idx = idx
                depth += code.count("{") - code.count("}")
                if depth <= blur_depth:
                    rest = m_blur.group(2)
                    before_close, close_and_after = rest.split("}", 1)
                    if re.search(
                        r"\benabled\s*=\s*(?:true|false|yes|no|1|0)\b",
                        before_close,
                        re.IGNORECASE,
                    ):
                        updated_inside = re.sub(
                            r"(\benabled\s*=\s*)(?:true|false|yes|no|1|0)\b",
                            rf"\g<1>{val_str}",
                            before_close,
                            count=1,
                            flags=re.IGNORECASE,
                        )
                        lines[idx] = f"{blur_indent}blur {{{updated_inside}}}{close_and_after}{comment}{nl}"
                    else:
                        extra = before_close.strip()
                        inner_lines = f"{blur_indent}    enabled = {val_str}\n"
                        if extra:
                            inner_lines += f"{blur_indent}    {extra}\n"
                        lines[idx] = (
                            f"{blur_indent}blur {{\n"
                            f"{inner_lines}"
                            f"{blur_indent}}}{close_and_after}{comment}{nl}"
                        )
                    return "".join(lines)
                continue
            depth += code.count("{") - code.count("}")
        else:
            m_en = _BLUR_ENABLED_RE.match(code)
            if m_en:
                lines[idx] = f"{m_en.group(1)}{val_str}{m_en.group(3)}{comment}{nl}"
                return "".join(lines)
            if child_indent is None and code.strip() and not code.lstrip().startswith("}"):
                child_indent = code[: len(code) - len(code.lstrip())]
            depth += code.count("{") - code.count("}")
            if depth <= blur_depth and blur_start_idx is not None:
                indent = child_indent or f"{blur_indent}    "
                lines.insert(blur_start_idx + 1, f"{indent}enabled = {val_str}\n")
                return "".join(lines)

    return _append_inside_decoration(text, ["blur {", f"    enabled = {val_str}", "}"])


def _update_user_decorations_file(
    home: Path,
    *,
    rounding: Optional[int] = None,
    blur_enabled: Optional[bool] = None,
) -> Path:
    """Persists rounding and/or blur state atomically to UserDecorations.conf under `home`."""
    user_dec = home / ".config" / "hypr" / "UserConfigs" / "UserDecorations.conf"
    txt = user_dec.read_text(encoding="utf-8", errors="ignore") if user_dec.exists() else ""
    if rounding is not None:
        txt = _set_decorations_rounding(txt, rounding)
    if blur_enabled is not None:
        txt = _set_decorations_blur(txt, blur_enabled)
    _atomic_write_text(user_dec, txt)
    return user_dec


def _read_user_decorations_state(home: Path) -> Tuple[int, bool]:
    """Reads fallback rounding and blur state from configs under `home`."""
    rounding = 16
    blur_enabled = True
    hypr_dir = home / ".config" / "hypr"
    for cfg in (
        hypr_dir / "decorations.conf",
        hypr_dir / "UserConfigs" / "UserDecorations.conf",
    ):
        if not cfg.exists():
            continue
        try:
            r, b = _parse_decorations_text(cfg.read_text(encoding="utf-8", errors="ignore"))
            if r is not None:
                rounding = r
            if b is not None:
                blur_enabled = b
        except Exception:
            pass
    return rounding, blur_enabled


def _read_default_apps(home: Path) -> Tuple[str, str]:
    """Reads `$term` and `$files` (or Lua equivalents) from Hyprland configs under `home`."""
    term: Optional[str] = None
    files: Optional[str] = None
    hypr_dir = home / ".config" / "hypr"
    conf_candidates = [
        hypr_dir / "userprefs.conf",
        hypr_dir / "UserConfigs" / "01-UserDefaults.conf",
        hypr_dir / "UserConfigs" / "UserKeybinds.conf",
        hypr_dir / "keybinds.conf",
    ]
    for cfg in conf_candidates:
        if not cfg.exists():
            continue
        try:
            for line in cfg.read_text(encoding="utf-8", errors="ignore").splitlines():
                clean = line.split("#", 1)[0].strip()
                if not clean:
                    continue
                if term is None:
                    m = re.match(r"^\$term\s*=\s*(.+)$", clean)
                    if m:
                        val = m.group(1).strip().strip("\"'")
                        if val:
                            term = val
                if files is None:
                    m = re.match(r"^\$files\s*=\s*(.+)$", clean)
                    if m:
                        val = m.group(1).strip().strip("\"'")
                        if val:
                            files = val
        except Exception:
            pass
        if term is not None and files is not None:
            break

    if term is None or files is None:
        for lua_cfg in (hypr_dir / "userprefs.lua", hypr_dir / "hyprland.lua"):
            if not lua_cfg.exists():
                continue
            try:
                for line in lua_cfg.read_text(encoding="utf-8", errors="ignore").splitlines():
                    clean = line.split("--", 1)[0].strip()
                    if not clean:
                        continue
                    if term is None:
                        m = re.match(r"^(?:local\s+)?terminal\s*=\s*[\"']([^\"']+)[\"']", clean)
                        if m:
                            term = m.group(1).strip()
                    if files is None:
                        m = re.match(r"^(?:local\s+)?fileManager\s*=\s*[\"']([^\"']+)[\"']", clean)
                        if m:
                            files = m.group(1).strip()
            except Exception:
                pass
            if term is not None and files is not None:
                break

    return term or "kitty", files or "thunar"

def is_gtk_available() -> bool:
    try:
        import gi
        gi.require_version("Gtk", "4.0")
        gi.require_version("Adw", "1")
        from gi.repository import Gtk, Adw
        return True
    except Exception:
        return False

def launch_gtk_app(workspace_root: Optional[str] = None, target_home: Optional[str] = None):
    if not is_gtk_available():
        print("[ERROR] GTK4 / Libadwaita is not available or DISPLAY is not set.")
        return 1

    import gi
    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import Gtk, Adw, Gio, GLib, Gdk, GdkPixbuf, Pango

    from yusei_settings.core.discovery import DiscoveryEngine
    from yusei_settings.core.state import StateManager
    from yusei_settings.core.safety import SafetyEngine
    from yusei_settings.core.power import PowerManager

    def esc(text: Any) -> str:
        """Escapes text ONLY for Pango-markup widgets (Adw.ActionRow / ExpanderRow / SwitchRow title & subtitle)."""
        if text is None:
            return ""
        return GLib.markup_escape_text(str(text))

    class YuseiSettingsApp(Adw.Application):
        def __init__(self):
            super().__init__(application_id="io.github.yusei.Settings", flags=Gio.ApplicationFlags.FLAGS_NONE)
            self.discovery = DiscoveryEngine(workspace_root, target_home=target_home)
            self.state_mgr = StateManager(target_home)
            self.safety = SafetyEngine(target_home)
            self.power_mgr = PowerManager(workspace_root, target_home)
            self.searchable_rows: List[Tuple[Adw.ExpanderRow, Adw.ActionRow, str]] = []
            self.searchable_wp_cards: List[Tuple[Any, str]] = []
            self.wp_card_map: Dict[str, Tuple[Any, Any, str]] = {}
            self.category_cards: Dict[str, Dict[str, Tuple[Any, Dict[str, Any]]]] = {}
            self.category_expanders: Dict[str, Tuple[Any, str]] = {}
            self.lazy_section_builders: List[Any] = []
            self.wp_group: Optional[Any] = None
            self.wp_expander: Optional[Any] = None
            self.wp_random_pic: Optional[Any] = None
            self.wallpapers_catalog: List[Dict[str, Any]] = []
            self._syncing_hypr_state: bool = False
            self._filter_timeout_id: Optional[int] = None
            self._pre_search_expanded: Optional[Dict[Any, bool]] = None
            self._thumb_cache_dir = self.safety.home / ".cache" / "yusei-settings" / "thumbs"
            try:
                self._thumb_cache_dir.mkdir(parents=True, exist_ok=True)
            except Exception:
                pass

        def _is_live_session(self) -> bool:
            try:
                return self.safety.home == Path.home().resolve()
            except Exception:
                return False

        def _show_toast(
            self,
            win,
            message: str,
            timeout: int = 3,
            button_label: Optional[str] = None,
            on_button_clicked=None,
        ):
            if win is None:
                return
            toast = Adw.Toast()
            if hasattr(toast, "set_use_markup"):
                toast.set_use_markup(False)
                toast.set_title(str(message))
            else:
                toast.set_title(esc(message))
            toast.set_timeout(timeout)
            if button_label and on_button_clicked is not None:
                toast.set_button_label(button_label)
                toast.connect("button-clicked", on_button_clicked)
            win.add_toast(toast)

        def _present_dialog(
            self,
            win,
            heading: str,
            body: str,
            responses: List[Tuple[str, str]],
            default_response: str,
            close_response: str,
            suggested_response: Optional[str] = None,
            on_response=None,
        ):
            if hasattr(Adw, "AlertDialog"):
                dlg = Adw.AlertDialog(heading=str(heading), body=str(body))
                present_fn = lambda: dlg.present(win)
            else:
                dlg = Adw.MessageDialog(
                    transient_for=win,
                    modal=True,
                    heading=str(heading),
                    body=str(body),
                )
                present_fn = dlg.present

            for rid, label in responses:
                dlg.add_response(rid, label)
            if suggested_response is not None:
                dlg.set_response_appearance(suggested_response, Adw.ResponseAppearance.SUGGESTED)
            dlg.set_default_response(default_response)
            dlg.set_close_response(close_response)
            if on_response is not None:
                dlg.connect("response", on_response)
            present_fn()

        def _show_error(self, win, heading: str, message: str):
            self._show_toast(win, f"{heading}: {message}", timeout=4)
            if win is None:
                return
            try:
                self._present_dialog(
                    win,
                    heading=heading,
                    body=message,
                    responses=[("ok", "Đóng")],
                    default_response="ok",
                    close_response="ok",
                )
            except Exception:
                pass

        def _get_hypr_decoration_state(self) -> Tuple[int, bool]:
            """Reads current rounding and blur state from hyprctl (live session) or config."""
            rounding, blur_enabled = _read_user_decorations_state(self.safety.home)
            if not self._is_live_session():
                return rounding, blur_enabled
            try:
                out = subprocess.check_output(["hyprctl", "getoption", "decoration:rounding"], text=True, timeout=2)
                m = re.search(r"int:\s*(\d+)", out)
                if m:
                    rounding = int(m.group(1))
            except Exception:
                pass
            try:
                out = subprocess.check_output(["hyprctl", "getoption", "decoration:blur:enabled"], text=True, timeout=2)
                m = re.search(r"int:\s*(\d+)", out)
                if m:
                    blur_enabled = (int(m.group(1)) == 1)
            except Exception:
                pass
            return rounding, blur_enabled

        def _apply_hypr_rounding(self, spin_btn, win):
            if self._syncing_hypr_state:
                return
            val = int(spin_btn.get_value())
            if self._is_live_session():
                try:
                    subprocess.Popen(
                        ["hyprctl", "keyword", "decoration:rounding", str(val)],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                except Exception:
                    pass
            try:
                _update_user_decorations_file(self.safety.home, rounding=val)
            except Exception as exc:
                self._show_error(win, "Lỗi lưu bo góc", str(exc))

        def _apply_hypr_blur(self, switch_row, _pspec, win):
            if self._syncing_hypr_state:
                return
            active = bool(switch_row.get_active())
            val_str = "true" if active else "false"
            if self._is_live_session():
                try:
                    subprocess.Popen(
                        ["hyprctl", "keyword", "decoration:blur:enabled", val_str],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                except Exception:
                    pass
            try:
                _update_user_decorations_file(self.safety.home, blur_enabled=active)
            except Exception as exc:
                self._show_error(win, "Lỗi lưu hiệu ứng làm mờ", str(exc))
                return
            self._show_toast(
                win,
                f"Đã {'bật' if active else 'tắt'} hiệu ứng làm mờ nền (Blur)",
                timeout=2,
            )

        def _install_custom_css(self):
            css_provider = Gtk.CssProvider()
            css_data = b"""
            .wallpaper-grid-scroll {
                background-color: rgba(16, 16, 22, 0.55);
                border-radius: 12px;
                padding: 8px;
            }
            .wallpaper-card {
                background-color: rgba(28, 28, 36, 0.88);
                border-radius: 12px;
                padding: 6px;
                border: 2px solid transparent;
                transition: all 150ms ease;
            }
            .wallpaper-card:hover {
                background-color: rgba(46, 48, 62, 0.96);
                border-color: rgba(168, 199, 250, 0.55);
            }
            .wallpaper-card-active {
                background-color: rgba(40, 54, 78, 0.96);
                border-color: #a8c7fa;
            }
            .wallpaper-thumb-frame {
                border-radius: 8px;
                background-color: #141318;
            }
            .wallpaper-label {
                font-size: 11.5px;
                font-weight: 600;
                color: #e3e2e6;
                padding: 4px 8px;
                margin-top: 5px;
                border-radius: 6px;
            }
            .wallpaper-label-random {
                background-color: #b8c8d4;
                color: #12161f;
                font-size: 11.5px;
                font-weight: 700;
                border-radius: 6px;
                padding: 4px 14px;
                margin-top: 5px;
            }
            .wallpaper-label-active {
                background-color: #a8c7fa;
                color: #042f65;
                font-weight: 700;
            }
            .catalog-grid-box {
                padding: 10px;
            }
            .catalog-item-card {
                background-color: rgba(34, 35, 44, 0.85);
                border-radius: 10px;
                padding: 10px 14px;
                border: 1px solid rgba(255, 255, 255, 0.07);
                transition: all 140ms ease;
            }
            .catalog-item-card:hover {
                background-color: rgba(48, 50, 64, 0.95);
                border-color: rgba(168, 199, 250, 0.45);
            }
            .catalog-item-card-active {
                background-color: rgba(40, 54, 78, 0.96);
                border: 2px solid #a8c7fa;
            }
            .catalog-item-title {
                font-size: 13px;
                font-weight: 700;
                color: #e3e2e6;
            }
            .catalog-item-subtitle {
                font-size: 11px;
                color: #9aa0b0;
                margin-top: 2px;
            }
            """
            try:
                css_provider.load_from_data(css_data)
                display = Gdk.Display.get_default()
                if display is not None:
                    Gtk.StyleContext.add_provider_for_display(
                        display,
                        css_provider,
                        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
                    )
            except Exception:
                pass

        def _widen_page_clamp(self, widget: Gtk.Widget, max_width: int = 1480):
            if isinstance(widget, Adw.Clamp):
                widget.set_maximum_size(max_width)
                widget.set_tightening_threshold(1050)
            child = widget.get_first_child()
            while child is not None:
                self._widen_page_clamp(child, max_width)
                child = child.get_next_sibling()

        def _create_3col_card_child(
            self,
            title_txt: str,
            sub_txt: str,
            btn_label: str,
            on_click_cb,
            is_active: bool = False,
        ) -> Tuple[Gtk.FlowBoxChild, Gtk.Box]:
            child = Gtk.FlowBoxChild()
            child.set_focusable(False)

            card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            card.add_css_class("catalog-item-card")
            if is_active:
                card.add_css_class("catalog-item-card-active")
            card.set_hexpand(True)

            text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            text_box.set_hexpand(True)
            text_box.set_valign(Gtk.Align.CENTER)

            lbl_title = Gtk.Label(label=str(title_txt))
            lbl_title.set_halign(Gtk.Align.START)
            lbl_title.set_xalign(0.0)
            lbl_title.set_ellipsize(Pango.EllipsizeMode.END)
            lbl_title.set_max_width_chars(28)
            lbl_title.add_css_class("catalog-item-title")

            lbl_sub = Gtk.Label(label=str(sub_txt))
            lbl_sub.set_halign(Gtk.Align.START)
            lbl_sub.set_xalign(0.0)
            lbl_sub.set_ellipsize(Pango.EllipsizeMode.END)
            lbl_sub.set_max_width_chars(34)
            lbl_sub.add_css_class("catalog-item-subtitle")

            text_box.append(lbl_title)
            text_box.append(lbl_sub)

            btn = Gtk.Button(label=btn_label)
            btn.set_valign(Gtk.Align.CENTER)
            btn.add_css_class("suggested-action")
            btn.connect("clicked", on_click_cb)

            card.append(text_box)
            card.append(btn)
            card.set_tooltip_text(f"{title_txt}\n{sub_txt}")
            child.set_child(card)
            return child, card

        def do_activate(self):
            existing_win = self.get_active_window()
            if existing_win is not None:
                existing_win.present()
                return
            self._install_custom_css()
            win = Adw.PreferencesWindow(application=self, title="Cài Đặt Hệ Thống (yusei-settings)")
            win.set_default_size(1360, 820)
            win.set_search_enabled(True)

            catalog = self.discovery.discover_all(fast_scan=True)
            active = self.state_mgr.get_active_state()
            if self._filter_timeout_id is not None:
                GLib.source_remove(self._filter_timeout_id)
                self._filter_timeout_id = None
            self._pre_search_expanded = None
            self.searchable_rows.clear()
            self.searchable_wp_cards.clear()
            self.wp_card_map.clear()
            self.category_cards.clear()
            self.category_expanders.clear()
            self.lazy_section_builders.clear()
            win.connect("close-request", self._on_window_close_request)

            # -----------------------------------------------------------------
            # PAGE 1: Giao diện & Layout (Appearance)
            # -----------------------------------------------------------------
            page_appearance = Adw.PreferencesPage(
                title="Giao diện & Layout",
                icon_name="preferences-desktop-theme-symbolic"
            )

            # Quick Filter Bar
            group_filter = Adw.PreferencesGroup(
                title=esc("Tìm Kiếm & Lọc Nhanh"),
                description=esc("Hiển thị đầy đủ 100% kho giao diện, bố cục, bảng màu và hình nền trên hệ thống")
            )
            search_entry = Gtk.SearchEntry(
                placeholder_text="Nhập tên layout, style, theme Rofi/Kitty hoặc tên hình nền để lọc..."
            )
            search_entry.set_margin_top(4)
            search_entry.set_margin_bottom(4)
            search_entry.connect("search-changed", self.on_filter_changed)
            group_filter.add(search_entry)
            page_appearance.add(group_filter)

            # Helper to build full catalog expander sections in a 3-column grid (lazy when collapsed)
            def build_catalog_section(
                group_title: str,
                expander_title: str,
                expander_subtitle: str,
                subtitle_suffix: str,
                items: list,
                category_key: str,
                btn_label: str,
                subtitle_fn,
                expanded_by_default: bool = False
            ):
                group = Adw.PreferencesGroup(title=esc(group_title))
                expander = Adw.ExpanderRow(
                    title=esc(f"{expander_title} ({len(items)} lựa chọn)"),
                    subtitle=esc(expander_subtitle)
                )
                expander.set_expanded(expanded_by_default)
                self.category_expanders[category_key] = (expander, subtitle_suffix)
                self.category_cards[category_key] = {}

                grid_row = Adw.PreferencesRow()
                grid_row.set_activatable(False)
                grid_row.set_focusable(False)

                flowbox = Gtk.FlowBox()
                flowbox.set_valign(Gtk.Align.START)
                flowbox.set_min_children_per_line(3)
                flowbox.set_max_children_per_line(3)
                flowbox.set_column_spacing(12)
                flowbox.set_row_spacing(10)
                flowbox.set_homogeneous(True)
                flowbox.set_selection_mode(Gtk.SelectionMode.NONE)
                flowbox.add_css_class("catalog-grid-box")

                populated = {"done": False}
                active_val = str(active.get(category_key, "")).strip().lower()

                def populate_cards():
                    if populated["done"]:
                        return
                    populated["done"] = True
                    for item in items:
                        sub_txt = subtitle_fn(item)
                        raw_n = str(item.get("raw_name", "")).strip().lower()
                        name_n = str(item.get("name", "")).strip().lower()
                        id_n = str(item.get("id", "")).strip().lower()
                        is_act = bool(active_val) and (active_val in (raw_n, name_n, id_n))
                        child, card = self._create_3col_card_child(
                            title_txt=item["name"],
                            sub_txt=sub_txt,
                            btn_label=btn_label,
                            on_click_cb=lambda btn, ck=category_key, it=item: self.on_apply_clicked(btn, ck, it, win),
                            is_active=is_act,
                        )
                        flowbox.append(child)
                        self.category_cards[category_key][item["id"]] = (card, item)
                        search_blob = f"{item.get('name', '')} {item.get('raw_name', '')} {sub_txt}".lower()
                        self.searchable_rows.append((expander, child, search_blob))

                if expanded_by_default:
                    populate_cards()
                else:
                    self.lazy_section_builders.append(populate_cards)
                    expander.connect(
                        "notify::expanded",
                        lambda exp, _pspec, fn=populate_cards: fn() if exp.get_expanded() else None,
                    )

                grid_row.set_child(flowbox)
                expander.add_row(grid_row)
                group.add(expander)
                page_appearance.add(group)

            # 1. Waybar Layouts (Full list)
            waybar_layouts = catalog.get("waybar_layouts", [])
            wb_layout_suffix = f"Nhấn để xem toàn bộ {len(waybar_layouts)} bố cục"
            build_catalog_section(
                group_title="Thanh Trạng Thái Waybar (Layouts)",
                expander_title="Danh sách Bố cục Waybar",
                expander_subtitle=f"Đang dùng: {active.get('waybar_layout', 'Default')} • {wb_layout_suffix}",
                subtitle_suffix=wb_layout_suffix,
                items=waybar_layouts,
                category_key="waybar_layout",
                btn_label="Áp dụng",
                subtitle_fn=lambda it: f"{it.get('position', 'TOP')} • {it.get('raw_name', '')}",
                expanded_by_default=True
            )

            # 2. Waybar Styles (Full list)
            waybar_styles = catalog.get("waybar_styles", [])
            wb_style_suffix = f"Nhấn để xem toàn bộ {len(waybar_styles)} kiểu dáng"
            build_catalog_section(
                group_title="Phong Cách Waybar CSS (Styles)",
                expander_title="Danh sách Kiểu dáng CSS Waybar",
                expander_subtitle=f"Đang dùng: {active.get('waybar_style', 'Default')} • {wb_style_suffix}",
                subtitle_suffix=wb_style_suffix,
                items=waybar_styles,
                category_key="waybar_style",
                btn_label="Áp dụng",
                subtitle_fn=lambda it: f"Phong cách: {it.get('theme_tag', 'Modern')} • {it.get('raw_name', '')}",
                expanded_by_default=False
            )

            # 3. Wallpapers (Visual Thumbnail Grid like Super + W)
            wallpapers = catalog.get("wallpapers", [])
            self.wallpapers_catalog = wallpapers
            self._build_wallpaper_grid_section(
                page_appearance=page_appearance,
                wallpapers=wallpapers,
                active_wp=active.get("wallpaper", "default.jpg"),
                win=win,
            )

            # 4. Rofi Themes (Full list)
            rofi_themes = catalog.get("rofi_themes", [])
            rofi_suffix = f"Nhấn để chọn trong {len(rofi_themes)} giao diện"
            build_catalog_section(
                group_title="Giao Diện Menu Ứng Dụng Rofi (Themes)",
                expander_title="Danh sách Giao diện Rofi Launcher",
                expander_subtitle=f"Đang dùng: {active.get('rofi_theme', 'Default')} • {rofi_suffix}",
                subtitle_suffix=rofi_suffix,
                items=rofi_themes,
                category_key="rofi_theme",
                btn_label="Áp dụng",
                subtitle_fn=lambda it: f"Kiểu dáng: {it.get('style_type', 'Card')} • {it.get('raw_name', '')}",
                expanded_by_default=False
            )

            # 5. Kitty Terminal Themes (Full list - 340+ themes)
            kitty_themes = catalog.get("kitty_themes", [])
            kitty_suffix = f"Nhấn để chọn trong {len(kitty_themes)} bảng màu"
            build_catalog_section(
                group_title="Bảng Màu Terminal Kitty (Themes)",
                expander_title="Kho Bảng Màu Kitty Terminal",
                expander_subtitle=f"Đang dùng: {active.get('kitty_theme', 'Default')} • {kitty_suffix}",
                subtitle_suffix=kitty_suffix,
                items=kitty_themes,
                category_key="kitty_theme",
                btn_label="Áp dụng",
                subtitle_fn=lambda it: f"{it.get('description', '')} ({it.get('raw_name', '')})",
                expanded_by_default=False
            )

            self._widen_page_clamp(page_appearance)
            win.add(page_appearance)

            # -----------------------------------------------------------------
            # PAGE 2: Hyprland (Animations & Effects)
            # -----------------------------------------------------------------
            page_hyprland = Adw.PreferencesPage(
                title="Hyprland",
                icon_name="preferences-system-windows-symbolic"
            )

            group_hypr = Adw.PreferencesGroup(
                title=esc("Hiệu Ứng & Bo Góc Cửa Sổ"),
                description=esc("Thay đổi có hiệu lực ngay lập tức trên phiên Hyprland hiện tại")
            )
            row_round = Adw.ActionRow(
                title=esc("Bo góc cửa sổ (Rounding)"),
                subtitle=esc("Điều chỉnh bán kính bo tròn góc cửa sổ (0px - 30px)")
            )
            spin_round = Gtk.SpinButton.new_with_range(0, 30, 1)
            spin_round.set_value(16)
            spin_round.set_valign(Gtk.Align.CENTER)
            spin_round.connect("value-changed", self._apply_hypr_rounding, win)
            row_round.add_suffix(spin_round)
            group_hypr.add(row_round)

            row_blur = Adw.SwitchRow(
                title=esc("Làm mờ nền (Dual-pass Kawase Blur)"),
                subtitle=esc("Hiệu ứng kính mờ trong suốt phía sau cửa sổ"),
                active=True
            )
            row_blur.connect("notify::active", self._apply_hypr_blur, win)
            group_hypr.add(row_blur)
            page_hyprland.add(group_hypr)

            # Animations List (3-column grid)
            anims = catalog.get("hyprland_animations", [])
            group_anim = Adw.PreferencesGroup(
                title=esc(f"Động Lực Học Cửa Sổ (Animations - {len(anims)} Presets)"),
                description=esc("Chọn cấu hình chuyển động cửa sổ và đường cong Bezier")
            )
            anim_row = Adw.PreferencesRow(activatable=False, focusable=False)
            anim_flow = Gtk.FlowBox(
                valign=Gtk.Align.START,
                min_children_per_line=3,
                max_children_per_line=3,
                column_spacing=12,
                row_spacing=10,
                homogeneous=True,
                selection_mode=Gtk.SelectionMode.NONE,
            )
            anim_flow.add_css_class("catalog-grid-box")
            self.category_cards["hyprland_animation"] = {}
            active_anim = str(active.get("hyprland_animation", "")).strip().lower()
            for item in anims:
                sub_txt = f"{item.get('description', 'Đường cong bezier')} ({item.get('raw_name', '')})"
                raw_n = str(item.get("raw_name", "")).strip().lower()
                name_n = str(item.get("name", "")).strip().lower()
                id_n = str(item.get("id", "")).strip().lower()
                is_act = bool(active_anim) and (active_anim in (raw_n, name_n, id_n))
                child_a, card_a = self._create_3col_card_child(
                    title_txt=item["name"],
                    sub_txt=sub_txt,
                    btn_label="Kích hoạt",
                    on_click_cb=lambda btn, it=item: self.on_apply_clicked(btn, "hyprland_animation", it, win),
                    is_active=is_act,
                )
                anim_flow.append(child_a)
                self.category_cards["hyprland_animation"][item["id"]] = (card_a, item)
            anim_row.set_child(anim_flow)
            group_anim.add(anim_row)
            page_hyprland.add(group_anim)

            self._widen_page_clamp(page_hyprland)
            win.add(page_hyprland)

            # -----------------------------------------------------------------
            # PAGE 3: Nguồn điện & Pin (Power & Battery)
            # -----------------------------------------------------------------
            page_power = Adw.PreferencesPage(
                title="Nguồn điện & Pin",
                icon_name="battery-symbolic"
            )
            group_power_status = Adw.PreferencesGroup(title=esc("Giám Sát Nguồn & Pin"))
            self.row_bat = Adw.ActionRow(
                title=esc("Dung lượng pin & Nguồn"),
                subtitle=esc("Đang kiểm tra trạng thái nguồn điện & pin...")
            )
            group_power_status.add(self.row_bat)

            self.row_rate = Adw.ActionRow(
                title=esc("Màn hình & Tần số quét"),
                subtitle=esc("Đang kiểm tra tần số quét màn hình...")
            )
            group_power_status.add(self.row_rate)
            page_power.add(group_power_status)

            group_profiles = Adw.PreferencesGroup(title="Profile Năng Lượng")
            prof_row = Adw.PreferencesRow(activatable=False, focusable=False)
            prof_flow = Gtk.FlowBox(
                valign=Gtk.Align.START,
                min_children_per_line=3,
                max_children_per_line=3,
                column_spacing=12,
                row_spacing=10,
                homogeneous=True,
                selection_mode=Gtk.SelectionMode.NONE,
            )
            prof_flow.add_css_class("catalog-grid-box")
            self.category_cards["power_profile"] = {}
            for p_id, p_name, p_desc in [
                ("eco", "Tiết kiệm điện (Eco)", "Hạ xung nhịp CPU, giảm màn hình về 60Hz"),
                ("balanced", "Cân bằng (Balanced)", "Tự động cân bằng hiệu năng và tiêu thụ điện"),
                ("turbo", "Hiệu năng tối đa (Turbo)", "Xung nhịp CPU tối đa, tần số quét cao nhất")
            ]:
                child_p, card_p = self._create_3col_card_child(
                    title_txt=p_name,
                    sub_txt=p_desc,
                    btn_label="Kích hoạt",
                    on_click_cb=lambda btn, pid=p_id, pname=p_name: self.on_power_profile_clicked(btn, pid, pname, win),
                    is_active=False,
                )
                prof_flow.append(child_p)
                self.category_cards["power_profile"][p_id] = (card_p, {"id": p_id, "name": p_name})
            prof_row.set_child(prof_flow)
            group_profiles.add(prof_row)
            page_power.add(group_profiles)

            group_power_cfg = Adw.PreferencesGroup(title="Tùy Chọn Tần Số Quét")
            row_auto_60hz = Adw.SwitchRow(
                title=esc("Tự động hạ màn hình xuống 60Hz khi rút sạc"),
                subtitle=esc("Khôi phục tần số quét cao khi cắm sạc"),
                active=True
            )
            row_auto_60hz.connect("notify::active", self._on_auto_60hz_toggled, win)
            group_power_cfg.add(row_auto_60hz)

            row_toggle_hz = Adw.ActionRow(
                title=esc("Chuyển đổi tần số quét thủ công"),
                subtitle=esc("Chuyển đổi qua lại giữa 60Hz và tần số quét tối đa của màn hình")
            )
            btn_toggle_hz = Gtk.Button(label="Chuyển đổi Hz")
            btn_toggle_hz.set_valign(Gtk.Align.CENTER)
            btn_toggle_hz.connect("clicked", self.on_toggle_hz_clicked, win)
            row_toggle_hz.add_suffix(btn_toggle_hz)
            group_power_cfg.add(row_toggle_hz)

            page_power.add(group_power_cfg)
            self._widen_page_clamp(page_power)
            win.add(page_power)

            # -----------------------------------------------------------------
            # PAGE 4: Ứng dụng & Công cụ (Applications & Tools)
            # -----------------------------------------------------------------
            page_apps = Adw.PreferencesPage(
                title="Ứng dụng",
                icon_name="system-run-symbolic"
            )
            term_cmd, files_cmd = _read_default_apps(self.safety.home)
            group_apps = Adw.PreferencesGroup(title="Ứng Dụng Mặc Định")
            group_apps.add(Adw.ActionRow(title=esc("Terminal mặc định ($term)"), subtitle=esc(term_cmd)))
            group_apps.add(Adw.ActionRow(title=esc("Trình quản lý tệp ($files)"), subtitle=esc(files_cmd)))
            page_apps.add(group_apps)

            group_tools = Adw.PreferencesGroup(
                title="Công Cụ Nhanh Hyprland",
                description="Khởi chạy nhanh các trình chọn trực quan và làm mới hệ thống"
            )
            tools_row = Adw.PreferencesRow(activatable=False, focusable=False)
            tools_flow = Gtk.FlowBox(
                valign=Gtk.Align.START,
                min_children_per_line=3,
                max_children_per_line=3,
                column_spacing=12,
                row_spacing=10,
                homogeneous=True,
                selection_mode=Gtk.SelectionMode.NONE,
            )
            tools_flow.add_css_class("catalog-grid-box")
            quick_tools = [
                ("Làm mới Thanh Waybar & SwayNC", "Khởi động lại Waybar và nạp lại CSS SwayNC tức thì", ".config/hypr/scripts/Refresh.sh"),
                ("Mở Bộ Chọn Hình Nền (Rofi)", "Duyệt hình nền có ảnh thu nhỏ và áp dụng Wallust", ".config/hypr/scripts/WallpaperSelect.sh"),
                ("Bảng Phím Tắt Hệ Thống (KeyHints)", "Xem danh sách toàn bộ phím tắt trên yusei-hypr", ".config/hypr/scripts/KeyHints.sh"),
            ]
            for t_title, t_sub, t_rel in quick_tools:
                child_t, _card_t = self._create_3col_card_child(
                    title_txt=t_title,
                    sub_txt=t_sub,
                    btn_label="Chạy",
                    on_click_cb=lambda _b, rel=t_rel: self._run_quick_tool(rel, win),
                )
                tools_flow.append(child_t)
            tools_row.set_child(tools_flow)
            group_tools.add(tools_row)
            page_apps.add(group_tools)
            self._widen_page_clamp(page_apps)
            win.add(page_apps)

            win.present()

            # Populate live Hyprland & Power state asynchronously off the GTK main thread
            def _load_live_state_bg():
                cur_rounding, cur_blur = self._get_hypr_decoration_state()
                power_st = self.power_mgr.get_status()

                def _apply_live_state():
                    self._syncing_hypr_state = True
                    try:
                        spin_round.set_value(cur_rounding)
                        row_blur.set_active(bool(cur_blur))
                        row_auto_60hz.set_active(bool(power_st.get("auto_60hz", True)))
                    finally:
                        self._syncing_hypr_state = False
                    self._apply_power_status_to_ui(power_st)
                    return GLib.SOURCE_REMOVE

                GLib.idle_add(_apply_live_state)

            threading.Thread(target=_load_live_state_bg, daemon=True).start()

        def _build_wallpaper_grid_section(
            self,
            page_appearance: Adw.PreferencesPage,
            wallpapers: List[Dict[str, Any]],
            active_wp: str,
            win: Adw.PreferencesWindow,
        ):
            group = Adw.PreferencesGroup(title=esc("Hình Nền Hệ Thống & Đồng Bộ Màu Động (Wallpapers)"))
            self.wp_group = group

            expander = Adw.ExpanderRow(
                title=esc(f"Kho Hình Nền Chất Lượng Cao ({len(wallpapers)} lựa chọn)"),
                subtitle=esc(f"Đang dùng: {active_wp} • Nhấn trực tiếp vào ảnh để đặt hình nền (như Super + W)"),
            )
            expander.set_expanded(True)
            self.wp_expander = expander

            # Container row inside expander holding the scrollable visual grid (3 columns)
            grid_row = Adw.PreferencesRow()
            grid_row.set_activatable(False)
            grid_row.set_focusable(False)

            scrolled = Gtk.ScrolledWindow()
            scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            scrolled.set_min_content_height(480)
            scrolled.set_max_content_height(560)
            scrolled.set_propagate_natural_height(True)
            scrolled.set_hexpand(True)
            scrolled.set_margin_top(8)
            scrolled.set_margin_bottom(8)
            scrolled.set_margin_start(8)
            scrolled.set_margin_end(8)
            scrolled.add_css_class("wallpaper-grid-scroll")

            flowbox = Gtk.FlowBox()
            flowbox.set_valign(Gtk.Align.START)
            flowbox.set_max_children_per_line(3)
            flowbox.set_min_children_per_line(3)
            flowbox.set_column_spacing(16)
            flowbox.set_row_spacing(16)
            flowbox.set_homogeneous(True)
            flowbox.set_selection_mode(Gtk.SelectionMode.NONE)

            thumb_tasks: List[Tuple[Gtk.Picture, str]] = []

            # 1. First Card: ". random" (matches Super + W)
            if wallpapers:
                rand_sample = random.choice(wallpapers)
                rand_child = Gtk.FlowBoxChild()
                rand_child.set_focusable(False)

                rand_btn = Gtk.Button()
                rand_btn.set_has_frame(False)
                rand_btn.add_css_class("wallpaper-card")
                rand_btn.set_tooltip_text("Chọn ngẫu nhiên một hình nền (. random)")

                rand_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
                rand_box.set_halign(Gtk.Align.CENTER)

                rand_frame = Gtk.Box()
                rand_frame.set_size_request(240, 135)
                rand_frame.set_halign(Gtk.Align.CENTER)
                rand_frame.set_overflow(Gtk.Overflow.HIDDEN)
                rand_frame.add_css_class("wallpaper-thumb-frame")

                rand_pic = Gtk.Picture()
                rand_pic.set_size_request(240, 135)
                rand_pic.set_can_shrink(True)
                if hasattr(Gtk, "ContentFit"):
                    rand_pic.set_content_fit(Gtk.ContentFit.COVER)
                rand_frame.append(rand_pic)
                self.wp_random_pic = rand_pic
                thumb_tasks.append((rand_pic, rand_sample["file_path"]))

                rand_lbl = Gtk.Label(label=". random")
                rand_lbl.set_halign(Gtk.Align.CENTER)
                rand_lbl.add_css_class("wallpaper-label-random")

                rand_box.append(rand_frame)
                rand_box.append(rand_lbl)
                rand_btn.set_child(rand_box)
                rand_btn.connect("clicked", self.on_random_wallpaper_clicked, win)
                rand_child.set_child(rand_btn)
                flowbox.append(rand_child)
                self.searchable_wp_cards.append((rand_child, ". random ngau nhien ngẫu nhiên"))

            # 2. All Wallpaper Cards with 16:9 Thumbnails (3 columns)
            active_norm = active_wp.strip().lower()
            for item in wallpapers:
                raw_name = item.get("raw_name", item.get("name", ""))
                is_active = (
                    raw_name.lower() == active_norm
                    or item.get("id", "").lower() == active_norm
                )

                child = Gtk.FlowBoxChild()
                child.set_focusable(False)

                card_btn = Gtk.Button()
                card_btn.set_has_frame(False)
                card_btn.add_css_class("wallpaper-card")
                if is_active:
                    card_btn.add_css_class("wallpaper-card-active")
                card_btn.set_tooltip_text(f"{item.get('name', raw_name)} ({raw_name})\nNhấn để đặt làm hình nền")

                card_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
                card_box.set_halign(Gtk.Align.CENTER)

                thumb_frame = Gtk.Box()
                thumb_frame.set_size_request(240, 135)
                thumb_frame.set_halign(Gtk.Align.CENTER)
                thumb_frame.set_overflow(Gtk.Overflow.HIDDEN)
                thumb_frame.add_css_class("wallpaper-thumb-frame")

                pic = Gtk.Picture()
                pic.set_size_request(240, 135)
                pic.set_can_shrink(True)
                if hasattr(Gtk, "ContentFit"):
                    pic.set_content_fit(Gtk.ContentFit.COVER)
                thumb_frame.append(pic)
                thumb_tasks.append((pic, item["file_path"]))

                lbl = Gtk.Label(label=raw_name)
                lbl.set_halign(Gtk.Align.CENTER)
                lbl.set_ellipsize(Pango.EllipsizeMode.END)
                lbl.set_max_width_chars(28)
                lbl.add_css_class("wallpaper-label")
                if is_active:
                    lbl.add_css_class("wallpaper-label-active")

                card_box.append(thumb_frame)
                card_box.append(lbl)
                card_btn.set_child(card_box)
                card_btn.connect("clicked", self.on_wallpaper_card_clicked, item, win)

                child.set_child(card_btn)
                flowbox.append(child)

                search_blob = f"{item.get('name', '')} {raw_name} {item.get('description', '')}".lower()
                self.searchable_wp_cards.append((child, search_blob))
                wp_key = item.get("file_path") or raw_name
                self.wp_card_map[wp_key] = (card_btn, lbl, raw_name)

            scrolled.set_child(flowbox)
            grid_row.set_child(scrolled)
            expander.add_row(grid_row)
            group.add(expander)
            page_appearance.add(group)

            # Start non-blocking background thumbnail loader
            if thumb_tasks:
                t = threading.Thread(
                    target=self._load_thumbnails_async,
                    args=(thumb_tasks,),
                    daemon=True,
                )
                t.start()

        def _get_or_create_thumb_pixbuf(self, file_path: str) -> Optional[Any]:
            try:
                p = Path(file_path)
                if not p.exists():
                    return None
                stat = p.stat()
                cache_key = hashlib.md5(f"{file_path}:{stat.st_mtime_ns}:{stat.st_size}".encode("utf-8")).hexdigest()
                cache_file = self._thumb_cache_dir / f"{cache_key}.jpg"

                if cache_file.exists():
                    try:
                        return GdkPixbuf.Pixbuf.new_from_file(str(cache_file))
                    except Exception:
                        pass

                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(file_path, 240, 135, False)
                if pixbuf is not None:
                    try:
                        pixbuf.savev(str(cache_file), "jpeg", ["quality"], ["85"])
                    except Exception:
                        pass
                return pixbuf
            except Exception:
                return None

        def _apply_pixbuf_batch(self, batch: List[Tuple[Gtk.Picture, Any]]) -> bool:
            for pic_widget, pixbuf in batch:
                try:
                    texture = Gdk.Texture.new_for_pixbuf(pixbuf)
                    pic_widget.set_paintable(texture)
                except Exception:
                    pass
            return GLib.SOURCE_REMOVE

        def _load_thumbnails_async(self, tasks: List[Tuple[Gtk.Picture, str]]):
            batch: List[Tuple[Gtk.Picture, Any]] = []
            for pic_widget, file_path in tasks:
                pixbuf = self._get_or_create_thumb_pixbuf(file_path)
                if pixbuf is not None:
                    batch.append((pic_widget, pixbuf))
                    if len(batch) >= 16:
                        GLib.idle_add(self._apply_pixbuf_batch, batch)
                        batch = []
            if batch:
                GLib.idle_add(self._apply_pixbuf_batch, batch)

        def _on_window_close_request(self, _win) -> bool:
            if self._filter_timeout_id is not None:
                GLib.source_remove(self._filter_timeout_id)
                self._filter_timeout_id = None
            return False

        def _run_quick_tool(self, rel_path: str, win):
            script_path = self.safety.home / rel_path
            if not script_path.exists():
                self._show_error(win, "Không tìm thấy công cụ", f"Tệp không tồn tại: {script_path}")
                return
            try:
                subprocess.Popen(["bash", str(script_path)])
            except Exception as exc:
                self._show_error(win, "Không thể khởi chạy công cụ", str(exc))

        def _update_active_wallpaper_ui(self, active_raw_name: str, active_file_path: Optional[str] = None):
            if self.wp_expander is not None:
                self.wp_expander.set_subtitle(
                    esc(f"Đang dùng: {active_raw_name} • Nhấn trực tiếp vào ảnh để đặt hình nền (như Super + W)")
                )
            for wp_key, (btn, lbl, raw_name) in self.wp_card_map.items():
                is_match = (wp_key == active_file_path) if active_file_path else (raw_name == active_raw_name)
                if is_match:
                    btn.add_css_class("wallpaper-card-active")
                    lbl.add_css_class("wallpaper-label-active")
                else:
                    btn.remove_css_class("wallpaper-card-active")
                    lbl.remove_css_class("wallpaper-label-active")

        def _update_active_category_ui(self, category: str, active_id: str, display_name: str):
            cards_map = self.category_cards.get(category, {})
            for cid, (card_widget, _it) in cards_map.items():
                if cid == active_id:
                    card_widget.add_css_class("catalog-item-card-active")
                else:
                    card_widget.remove_css_class("catalog-item-card-active")
            exp_info = self.category_expanders.get(category)
            if exp_info is not None:
                expander, suffix = exp_info
                expander.set_subtitle(esc(f"Đang dùng: {display_name} • {suffix}"))

        def on_random_wallpaper_clicked(self, _button, parent_window):
            if not self.wallpapers_catalog:
                return
            chosen = random.choice(self.wallpapers_catalog)
            if self.wp_random_pic is not None and len(self.wallpapers_catalog) > 1:
                next_sample = random.choice(self.wallpapers_catalog)
                threading.Thread(
                    target=self._load_thumbnails_async,
                    args=([(self.wp_random_pic, next_sample["file_path"])],),
                    daemon=True,
                ).start()
            self.on_wallpaper_card_clicked(None, chosen, parent_window)

        def on_wallpaper_card_clicked(self, _button, item: Dict[str, Any], parent_window):
            # Live preview / rapid wallpaper switcher intentionally skips snapshot creation.
            try:
                res = self.safety.apply_change(
                    "wallpaper",
                    item["id"],
                    item["file_path"],
                    confirmed=True,
                    skip_snapshot=True,
                )
            except Exception as exc:
                self._show_error(parent_window, "Không thể đổi hình nền", str(exc))
                return
            if isinstance(res, dict) and not res.get("success", True):
                self._show_error(parent_window, "Không thể đổi hình nền", res.get("message", "Lỗi không xác định"))
                return
            raw_name = item.get("raw_name", item["name"])
            self._update_active_wallpaper_ui(raw_name, item.get("file_path"))
            self._show_toast(parent_window, f"Đã đặt hình nền: {raw_name}", timeout=2)

        def _all_filter_expanders(self) -> List[Any]:
            expanders = [exp for exp, _suffix in self.category_expanders.values()]
            if self.wp_expander is not None:
                expanders.append(self.wp_expander)
            return expanders

        def _apply_search_filter(self, query: str) -> bool:
            self._filter_timeout_id = None

            if query:
                if self._pre_search_expanded is None:
                    self._pre_search_expanded = {
                        exp: bool(exp.get_expanded()) for exp in self._all_filter_expanders()
                    }
                if self.lazy_section_builders:
                    builders = list(self.lazy_section_builders)
                    self.lazy_section_builders.clear()
                    for builder_fn in builders:
                        builder_fn()

            expander_matches: Dict[Any, int] = {}
            for expander, row, blob in self.searchable_rows:
                matched = (not query) or (query in blob)
                row.set_visible(matched)
                if matched:
                    expander_matches[expander] = expander_matches.get(expander, 0) + 1

            for exp, _suffix in self.category_expanders.values():
                has_match = (not query) or (expander_matches.get(exp, 0) > 0)
                exp.set_visible(has_match)
                if query and has_match:
                    exp.set_expanded(True)

            # Filter visual wallpaper cards
            wp_matches = 0
            for wp_child, blob in self.searchable_wp_cards:
                matched = (not query) or (query in blob)
                wp_child.set_visible(matched)
                if matched:
                    wp_matches += 1

            if self.wp_expander is not None:
                has_wp = (not query) or (wp_matches > 0)
                self.wp_expander.set_visible(has_wp)
                if query and has_wp:
                    self.wp_expander.set_expanded(True)

            if not query and self._pre_search_expanded is not None:
                for exp, was_expanded in self._pre_search_expanded.items():
                    exp.set_expanded(was_expanded)
                self._pre_search_expanded = None

            return GLib.SOURCE_REMOVE

        def on_filter_changed(self, search_entry):
            if self._filter_timeout_id is not None:
                GLib.source_remove(self._filter_timeout_id)
                self._filter_timeout_id = None
            query = search_entry.get_text().strip().lower()
            self._filter_timeout_id = GLib.timeout_add(200, self._apply_search_filter, query)

        def _apply_power_status_to_ui(self, st: Dict[str, Any]):
            prof = str(st.get("profile", "balanced")).lower()
            self.row_bat.set_subtitle(
                esc(f"{st.get('battery_percent', 100)}% ({st.get('battery_status', 'AC Only')}) • {'Cắm sạc AC' if st.get('ac_online') else 'Dùng pin'} • Profile: {prof.upper()}")
            )
            self.row_rate.set_subtitle(
                esc(f"{st.get('monitor_name', 'Display')} • {st.get('current_hz', 60)} Hz (Tối đa: {st.get('max_hz', 60)} Hz)")
            )
            self._update_active_category_ui("power_profile", prof, prof)

        def _refresh_power_labels_async(self):
            def _worker():
                st = self.power_mgr.get_status()
                GLib.idle_add(lambda: (self._apply_power_status_to_ui(st), GLib.SOURCE_REMOVE)[1])
            threading.Thread(target=_worker, daemon=True).start()

        def _on_auto_60hz_toggled(self, switch_row, _pspec, win):
            if self._syncing_hypr_state:
                return
            active = bool(switch_row.get_active())

            def _worker():
                err_msg: Optional[str] = None
                res: Optional[Dict[str, Any]] = None
                try:
                    res = self.power_mgr.set_config(auto_60hz=active)
                    if not isinstance(res, dict) or not res.get("success", False):
                        err_msg = (res or {}).get("message") or "Không thể cập nhật cấu hình tự động 60Hz."
                except Exception as exc:
                    err_msg = str(exc)

                def _finish():
                    if err_msg is not None:
                        self._syncing_hypr_state = True
                        try:
                            switch_row.set_active(not active)
                        finally:
                            self._syncing_hypr_state = False
                        self._show_error(win, "Lỗi cấu hình 60Hz tự động", err_msg)
                    else:
                        msg = (res or {}).get("message") or (
                            "Đã bật tự động hạ 60Hz khi rút sạc" if active else "Đã tắt tự động hạ 60Hz khi rút sạc"
                        )
                        self._show_toast(win, msg, timeout=2)
                    return GLib.SOURCE_REMOVE

                GLib.idle_add(_finish)

            threading.Thread(target=_worker, daemon=True).start()

        def _run_power_action_async(
            self,
            win,
            action_fn,
            error_heading: str,
            default_err: str,
            on_success,
        ):
            def _worker():
                err_msg: Optional[str] = None
                res: Optional[Dict[str, Any]] = None
                st: Optional[Dict[str, Any]] = None
                try:
                    res = action_fn()
                    if not isinstance(res, dict) or not res.get("success", False):
                        err_msg = (res or {}).get("message") or default_err
                    st = self.power_mgr.get_status()
                except Exception as exc:
                    err_msg = str(exc)

                def _finish():
                    if st is not None:
                        self._apply_power_status_to_ui(st)
                    if err_msg is not None:
                        self._show_error(win, error_heading, err_msg)
                    else:
                        on_success(res or {})
                    return GLib.SOURCE_REMOVE

                GLib.idle_add(_finish)

            threading.Thread(target=_worker, daemon=True).start()

        def on_power_profile_clicked(self, _button, profile_id: str, profile_name: str, win):
            def _on_ok(_res):
                self._update_active_category_ui("power_profile", profile_id, profile_name)
                self._show_toast(win, f"Đã chuyển sang chế độ: {profile_name}", timeout=2)

            self._run_power_action_async(
                win,
                lambda: self.power_mgr.set_profile(profile_id),
                error_heading="Lỗi chuyển chế độ nguồn",
                default_err=f"Không thể chuyển profile {profile_name}.",
                on_success=_on_ok,
            )

        def on_toggle_hz_clicked(self, _button, win):
            self._run_power_action_async(
                win,
                self.power_mgr.toggle_hz,
                error_heading="Lỗi chuyển đổi Hz",
                default_err="Không thể chuyển đổi tần số quét.",
                on_success=lambda res: self._show_toast(
                    win,
                    res.get("message") or "Đã chuyển đổi tần số quét màn hình!",
                    timeout=2,
                ),
            )

        def _rollback_snapshot(self, snapshot_id: str, category: str, parent_window):
            try:
                rb_res = self.safety.rollback(snapshot_id)
            except Exception as exc:
                self._show_error(parent_window, "Hoàn tác thất bại", str(exc))
                return
            if not isinstance(rb_res, dict) or not rb_res.get("success", False):
                err_msg = (rb_res or {}).get("message") or "Không thể hoàn tác bản sao lưu."
                self._show_error(parent_window, "Hoàn tác thất bại", err_msg)
                return

            try:
                active = self.state_mgr.get_active_state()
                active_val = str(active.get(category, "")).strip()
                cards_map = self.category_cards.get(category, {})
                matched_id = ""
                display_name = active_val or "Default"
                active_low = active_val.lower()
                for cid, (_card, it) in cards_map.items():
                    raw_n = str(it.get("raw_name", "")).strip().lower()
                    name_n = str(it.get("name", "")).strip().lower()
                    id_n = str(it.get("id", "")).strip().lower()
                    if active_low and active_low in (raw_n, name_n, id_n):
                        matched_id = cid
                        display_name = it.get("raw_name", it.get("name", display_name))
                        break
                self._update_active_category_ui(category, matched_id, display_name)
            except Exception:
                pass
            self._show_toast(parent_window, f"Đã hoàn tác bản sao lưu: {snapshot_id}", timeout=3)

        def on_apply_clicked(self, button, category, item, parent_window):
            file_path = item.get("file_path")
            item_id = item.get("id")
            if not file_path or not item_id:
                self._show_error(parent_window, "Không thể áp dụng", "Thiếu thông tin tệp nguồn của mục đã chọn.")
                return

            try:
                impact = self.safety.analyze_impact(category, item_id, file_path)
            except Exception as exc:
                self._show_error(parent_window, "Không thể phân tích tác động", str(exc))
                return

            affected = impact.get("affected_files", [])
            if affected:
                files_summary = "\n".join(
                    f"• {entry.get('target', '')} ({entry.get('action', '')})"
                    for entry in affected
                )
            else:
                files_summary = "• (Không có tệp nào bị thay đổi)"

            display_name = item.get("raw_name", item.get("name", ""))
            heading = f"Xác nhận áp dụng: {item.get('name', display_name)}"
            body = (
                f"Các tệp cấu hình sẽ được cập nhật:\n{files_summary}\n\n"
                "Hệ thống sẽ tự động tạo bản sao lưu (snapshot) trước khi thay đổi."
            )

            def _execute_apply():
                try:
                    res = self.safety.apply_change(
                        category,
                        item_id,
                        file_path,
                        confirmed=True,
                        skip_snapshot=False,
                    )
                except Exception as exc:
                    self._show_error(parent_window, "Áp dụng cấu hình thất bại", str(exc))
                    return

                if not isinstance(res, dict) or not res.get("success", False):
                    err_msg = (res or {}).get("message") or "Thao tác áp dụng cấu hình không thành công."
                    self._show_error(parent_window, "Áp dụng cấu hình thất bại", err_msg)
                    return

                self._update_active_category_ui(category, item_id, display_name)
                snapshot_id = res.get("snapshot_id")
                title_msg = (
                    f"Đã áp dụng: {item.get('name', display_name)} (Snapshot: {snapshot_id})"
                    if snapshot_id
                    else f"Đã áp dụng: {item.get('name', display_name)}"
                )
                self._show_toast(
                    parent_window,
                    title_msg,
                    timeout=5,
                    button_label="Hoàn tác" if snapshot_id else None,
                    on_button_clicked=(
                        (lambda _t, sid=snapshot_id, cat=category: self._rollback_snapshot(sid, cat, parent_window))
                        if snapshot_id
                        else None
                    ),
                )

            def _on_response(_dialog, response_id):
                if response_id == "apply":
                    _execute_apply()

            self._present_dialog(
                parent_window,
                heading=heading,
                body=body,
                responses=[("cancel", "Hủy"), ("apply", "Áp dụng")],
                default_response="apply",
                close_response="cancel",
                suggested_response="apply",
                on_response=_on_response,
            )

    app = YuseiSettingsApp()
    return app.run([sys.argv[0]])
