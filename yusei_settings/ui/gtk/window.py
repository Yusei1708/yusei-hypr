"""
Native Libadwaita & GTK4 Settings Window
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Provides modern GNOME / Libadwaita preferences window with full catalog access,
instant live-filtering search, real-time Hyprland controls, and 5-stage safety rollback.
"""

import os
import re
import sys
import hashlib
import random
import threading
import subprocess
from pathlib import Path
from typing import Optional, Any, List, Tuple, Dict

from yusei_settings.core.decorations import (
    BLUR_PRESETS,
    DECORATION_SCHEMA,
    OPACITY_PRESETS,
    DecorationsManager,
    atomic_write_text,
    format_conf_value,
    get_default_state,
    parse_decorations_text,
    parse_hypr_bool_option,
    update_decorations_text,
)


def _parse_decorations_text(text: str) -> Tuple[Optional[int], Optional[bool]]:
    """Extracts active rounding and blur:enabled from Hyprland decoration config text."""
    parsed = parse_decorations_text(text)
    rounding = parsed.get("rounding")
    blur_enabled = parsed.get("blur_enabled")
    return (int(rounding) if rounding is not None else None), blur_enabled


def _update_user_decorations_file(
    home: Path,
    *,
    rounding: Optional[int] = None,
    blur_enabled: Optional[bool] = None,
    updates: Optional[Dict[str, Any]] = None,
) -> Path:
    """Persists decoration keys atomically to UserDecorations.conf under `home`."""
    user_dec = home / ".config" / "hypr" / "UserConfigs" / "UserDecorations.conf"
    txt = user_dec.read_text(encoding="utf-8", errors="ignore") if user_dec.exists() else ""
    merged_updates: Dict[str, Any] = dict(updates or {})
    if rounding is not None:
        merged_updates["rounding"] = int(rounding)
    if blur_enabled is not None:
        merged_updates["blur_enabled"] = bool(blur_enabled)
    txt = update_decorations_text(txt, merged_updates)
    atomic_write_text(user_dec, txt)
    return user_dec


def _parse_hypr_bool_option(out: str) -> Optional[bool]:
    """Parses Hyprland getoption output across 0.57+ (`bool: true/false`) and legacy (`int: 1/0`)."""
    return parse_hypr_bool_option(out)


def _apply_hypr_lua_or_keyword(lua_expr: str, keyword: str, value: str) -> None:
    """Applies a Hyprland config option via 0.57+ `hyprctl eval` first, falling back to `hyprctl keyword`."""
    try:
        res = subprocess.run(
            ["hyprctl", "eval", lua_expr],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=2,
            check=False,
        )
        stdout = (res.stdout or "").strip().lower()
        combined = f"{stdout}\n{(res.stderr or '').strip().lower()}"
        if res.returncode == 0 and stdout.startswith("ok") and "error" not in combined and "unknown" not in combined:
            return
    except Exception:
        pass
    try:
        subprocess.run(
            ["hyprctl", "keyword", keyword, str(value)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
            check=False,
        )
    except Exception:
        pass


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
            self.decorations_mgr = DecorationsManager(workspace_root, target_home)
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
            self._dec_state: Dict[str, Any] = get_default_state()
            self._dec_sliders: Dict[str, Tuple[Any, Any]] = {}
            self._dec_switches: Dict[str, Any] = {}
            self._dec_blur_detail_widgets: List[Any] = []
            self._opacity_preset_btns: List[Tuple[float, Any]] = []
            self._blur_preset_btns: List[Tuple[int, int, Any]] = []
            self._dec_link_switch: Optional[Any] = None
            self._dec_spin_round: Optional[Any] = None
            self._dec_preview_timer_id: Optional[int] = None
            self._dec_persist_timer_id: Optional[int] = None
            self._dec_dirty_persist: bool = False
            self._dec_apply_lock = threading.Lock()
            self._dec_pending_work: Optional[Tuple[Dict[str, Any], bool]] = None
            self._dec_worker_running: bool = False
            self._active_win: Optional[Any] = None
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

        def _sync_dec_ui_from_state(self, state: Dict[str, Any], sync_link_switch: bool = False):
            """Updates all Hyprland blur/opacity widgets from `state` without firing signals."""
            self._dec_state = dict(state)
            self._syncing_hypr_state = True
            try:
                for key, (scale, pill_lbl) in self._dec_sliders.items():
                    if key in state:
                        val = state[key]
                        scale.set_value(float(val))
                        pill_lbl.set_text(format_conf_value(key, val))
                for key, sw in self._dec_switches.items():
                    if key in state:
                        sw.set_active(bool(state[key]))
                if self._dec_spin_round is not None and "rounding" in state:
                    self._dec_spin_round.set_value(int(state["rounding"]))
                if sync_link_switch and self._dec_link_switch is not None:
                    same = abs(float(state.get("active_opacity", 0.9)) - float(state.get("inactive_opacity", 0.9))) < 0.005
                    self._dec_link_switch.set_active(same)
            finally:
                self._syncing_hypr_state = False

            blur_on = bool(state.get("blur_enabled", True))
            for widget in self._dec_blur_detail_widgets:
                widget.set_sensitive(blur_on)
            self._refresh_dec_preset_highlights()

        def _refresh_dec_preset_highlights(self):
            act = float(self._dec_state.get("active_opacity", 0.90))
            inact = float(self._dec_state.get("inactive_opacity", 0.90))
            linked = bool(self._dec_link_switch.get_active()) if self._dec_link_switch is not None else False
            for preset_val, btn in self._opacity_preset_btns:
                is_match = abs(act - preset_val) < 0.005 and (not linked or abs(inact - preset_val) < 0.005)
                if is_match:
                    btn.add_css_class("dec-preset-active")
                else:
                    btn.remove_css_class("dec-preset-active")

            blur_on = bool(self._dec_state.get("blur_enabled", True))
            sz = int(self._dec_state.get("blur_size", 5))
            ps = int(self._dec_state.get("blur_passes", 2))
            for psz, pps, btn in self._blur_preset_btns:
                if blur_on and sz == psz and ps == pps:
                    btn.add_css_class("dec-preset-active")
                else:
                    btn.remove_css_class("dec-preset-active")

        def _enqueue_dec_apply(self, snapshot: Dict[str, Any], persist: bool):
            with self._dec_apply_lock:
                if self._dec_pending_work is not None:
                    _prev_snap, prev_persist = self._dec_pending_work
                    persist = persist or prev_persist
                self._dec_pending_work = (snapshot, persist)
                if self._dec_worker_running:
                    return
                self._dec_worker_running = True

            def _worker():
                while True:
                    with self._dec_apply_lock:
                        work = self._dec_pending_work
                        self._dec_pending_work = None
                        if work is None:
                            self._dec_worker_running = False
                            return
                    snap, do_persist = work
                    try:
                        self.decorations_mgr.apply(snap, persist=do_persist, live=True)
                    except Exception as exc:
                        err = str(exc)
                        GLib.idle_add(
                            lambda m=err: (
                                self._show_error(self._active_win, "Lỗi cập nhật hiệu ứng mờ nền", m),
                                GLib.SOURCE_REMOVE,
                            )[1]
                        )

            threading.Thread(target=_worker, daemon=True).start()

        def _cancel_dec_timers(self):
            if self._dec_preview_timer_id is not None:
                GLib.source_remove(self._dec_preview_timer_id)
                self._dec_preview_timer_id = None
            if self._dec_persist_timer_id is not None:
                GLib.source_remove(self._dec_persist_timer_id)
                self._dec_persist_timer_id = None

        def _schedule_dec_apply(self, *, immediate_persist: bool = False):
            """Coalesces rapid slider drags into 45ms live previews and 260ms atomic saves."""
            if immediate_persist:
                self._cancel_dec_timers()
                self._dec_dirty_persist = False
                self._enqueue_dec_apply(dict(self._dec_state), persist=True)
                return

            self._dec_dirty_persist = True
            if self._dec_preview_timer_id is not None:
                GLib.source_remove(self._dec_preview_timer_id)
            if self._dec_persist_timer_id is not None:
                GLib.source_remove(self._dec_persist_timer_id)

            def _on_preview():
                self._dec_preview_timer_id = None
                self._enqueue_dec_apply(dict(self._dec_state), persist=False)
                return GLib.SOURCE_REMOVE

            def _on_persist():
                self._dec_persist_timer_id = None
                self._dec_dirty_persist = False
                self._enqueue_dec_apply(dict(self._dec_state), persist=True)
                return GLib.SOURCE_REMOVE

            self._dec_preview_timer_id = GLib.timeout_add(45, _on_preview)
            self._dec_persist_timer_id = GLib.timeout_add(260, _on_persist)

        def _on_dec_slider_changed(self, scale, key: str, pill_lbl):
            if self._syncing_hypr_state:
                return
            spec = DECORATION_SCHEMA[key]
            ftype, mn, mx, _step, dec = spec[0], spec[1], spec[2], spec[3], spec[4]
            raw = scale.get_value()
            if ftype is int:
                val: Any = int(max(mn, min(mx, round(raw))))
            else:
                val = round(max(float(mn), min(float(mx), float(raw))), dec)

            self._dec_state[key] = val
            pill_lbl.set_text(format_conf_value(key, val))

            if key == "active_opacity" and self._dec_link_switch is not None and self._dec_link_switch.get_active():
                self._dec_state["inactive_opacity"] = val
                pair = self._dec_sliders.get("inactive_opacity")
                if pair is not None:
                    in_scale, in_lbl = pair
                    self._syncing_hypr_state = True
                    try:
                        in_scale.set_value(float(val))
                        in_lbl.set_text(format_conf_value("inactive_opacity", val))
                    finally:
                        self._syncing_hypr_state = False

            self._refresh_dec_preset_highlights()
            self._schedule_dec_apply(immediate_persist=False)

        def _on_dec_switch_toggled(self, switch_row, _pspec, key: str, win):
            if self._syncing_hypr_state:
                return
            active = bool(switch_row.get_active())
            self._dec_state[key] = active
            if key == "blur_enabled":
                for widget in self._dec_blur_detail_widgets:
                    widget.set_sensitive(active)
                self._refresh_dec_preset_highlights()
                self._show_toast(
                    win,
                    f"Đã {'bật' if active else 'tắt'} hiệu ứng làm mờ nền (Blur)",
                    timeout=2,
                )
            elif key == "override_all_apps":
                self._show_toast(
                    win,
                    "Đang ghi đè opacity lên toàn bộ cửa sổ (kể cả video)" if active else "Đã chuyển về opacity riêng theo từng app",
                    timeout=2,
                )
            self._schedule_dec_apply(immediate_persist=True)

        def _on_opacity_link_toggled(self, switch_row, _pspec):
            if self._syncing_hypr_state:
                return
            if switch_row.get_active():
                act_val = self._dec_state.get("active_opacity", 0.90)
                if abs(float(self._dec_state.get("inactive_opacity", 0.90)) - float(act_val)) >= 0.005:
                    self._dec_state["inactive_opacity"] = act_val
                    pair = self._dec_sliders.get("inactive_opacity")
                    if pair is not None:
                        in_scale, in_lbl = pair
                        self._syncing_hypr_state = True
                        try:
                            in_scale.set_value(float(act_val))
                            in_lbl.set_text(format_conf_value("inactive_opacity", act_val))
                        finally:
                            self._syncing_hypr_state = False
                    self._schedule_dec_apply(immediate_persist=True)
            self._refresh_dec_preset_highlights()

        def _on_opacity_preset_clicked(self, _btn, val: float, win):
            next_state = dict(self._dec_state)
            next_state["active_opacity"] = round(float(val), 2)
            if self._dec_link_switch is not None and self._dec_link_switch.get_active():
                next_state["inactive_opacity"] = round(float(val), 2)
            self._sync_dec_ui_from_state(next_state)
            self._schedule_dec_apply(immediate_persist=True)
            self._show_toast(win, f"Đã đặt độ trong suốt nền: {val:.2f}", timeout=2)

        def _on_blur_preset_clicked(self, _btn, size_val: int, passes_val: int, label: str, win):
            next_state = dict(self._dec_state)
            next_state["blur_enabled"] = True
            next_state["blur_size"] = int(size_val)
            next_state["blur_passes"] = int(passes_val)
            self._sync_dec_ui_from_state(next_state)
            self._schedule_dec_apply(immediate_persist=True)
            self._show_toast(win, f"Đã chọn cấu hình Blur: {label}", timeout=2)

        def _on_reset_decorations_clicked(self, _btn, win):
            defaults = get_default_state()
            self._sync_dec_ui_from_state(defaults, sync_link_switch=True)
            self._schedule_dec_apply(immediate_persist=True)
            self._show_toast(win, "Đã khôi phục mặc định hiệu ứng mờ nền & bo góc", timeout=2)

        def _on_hypr_rounding_changed(self, spin_btn):
            if self._syncing_hypr_state:
                return
            self._dec_state["rounding"] = int(spin_btn.get_value())
            self._schedule_dec_apply(immediate_persist=True)

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
            .dec-value-pill {
                background-color: rgba(168, 199, 250, 0.14);
                color: #a8c7fa;
                font-family: monospace;
                font-size: 12px;
                font-weight: 700;
                padding: 4px 10px;
                border-radius: 999px;
                border: 1px solid rgba(168, 199, 250, 0.28);
            }
            .dec-preset-btn {
                border-radius: 8px;
                padding: 4px 10px;
                font-size: 12px;
                font-weight: 600;
            }
            .dec-preset-active {
                background-color: #a8c7fa;
                color: #042f65;
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
            self._active_win = win
            self.searchable_rows.clear()
            self.searchable_wp_cards.clear()
            self.wp_card_map.clear()
            self.category_cards.clear()
            self.category_expanders.clear()
            self.lazy_section_builders.clear()
            self._dec_sliders.clear()
            self._dec_switches.clear()
            self._dec_blur_detail_widgets.clear()
            self._opacity_preset_btns.clear()
            self._blur_preset_btns.clear()
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
            # PAGE 2: Hyprland (Blur, Opacity & Animations)
            # -----------------------------------------------------------------
            page_hyprland = Adw.PreferencesPage(
                title="Hyprland",
                icon_name="preferences-system-windows-symbolic"
            )

            def add_dec_slider_row(
                target_group: Adw.PreferencesGroup,
                key: str,
                title: str,
                subtitle: str,
                marks: Optional[List[float]] = None,
                is_blur_detail: bool = False,
            ) -> Adw.ActionRow:
                spec = DECORATION_SCHEMA[key]
                mn, mx, step, dec, default_val = spec[1], spec[2], spec[3], spec[4], spec[8]
                row = Adw.ActionRow(title=esc(title), subtitle=esc(subtitle))
                box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
                box.set_valign(Gtk.Align.CENTER)

                scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, float(mn), float(mx), float(step))
                scale.set_size_request(230, -1)
                scale.set_valign(Gtk.Align.CENTER)
                scale.set_draw_value(False)
                scale.set_digits(dec)
                scale.set_round_digits(dec)
                scale.set_value(float(default_val))
                if marks:
                    for mv in marks:
                        scale.add_mark(float(mv), Gtk.PositionType.BOTTOM, None)

                pill = Gtk.Label(label=format_conf_value(key, default_val))
                pill.set_width_chars(6)
                pill.set_xalign(0.5)
                pill.add_css_class("dec-value-pill")

                scale.connect("value-changed", lambda sc, k=key, pl=pill: self._on_dec_slider_changed(sc, k, pl))
                box.append(scale)
                box.append(pill)
                row.add_suffix(box)
                target_group.add(row)
                self._dec_sliders[key] = (scale, pill)
                if is_blur_detail:
                    self._dec_blur_detail_widgets.append(row)
                return row

            group_glass = Adw.PreferencesGroup(
                title=esc("Độ Trong Suốt & Kính Mờ (Frosted Glass)"),
                description=esc("Kéo thanh trượt để chỉnh độ trong suốt nền cửa sổ linh hoạt (0.80, 0.90, 1.00...)")
            )
            btn_reset_dec = Gtk.Button(label="Khôi phục mặc định")
            btn_reset_dec.set_valign(Gtk.Align.CENTER)
            btn_reset_dec.connect("clicked", self._on_reset_decorations_clicked, win)
            group_glass.set_header_suffix(btn_reset_dec)

            row_op_presets = Adw.ActionRow(
                title=esc("Mức độ mờ nhanh (Quick Presets)"),
                subtitle=esc("Chọn nhanh độ trong suốt nền phổ biến hoặc kéo thanh trượt bên dưới")
            )
            op_preset_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
            op_preset_box.set_valign(Gtk.Align.CENTER)
            for p_item in OPACITY_PRESETS:
                pv = float(p_item["value"])
                pbtn = Gtk.Button(label=f"{pv:.2f}")
                pbtn.set_tooltip_text(p_item["label"])
                pbtn.add_css_class("dec-preset-btn")
                pbtn.connect("clicked", self._on_opacity_preset_clicked, pv, win)
                op_preset_box.append(pbtn)
                self._opacity_preset_btns.append((pv, pbtn))
            row_op_presets.add_suffix(op_preset_box)
            group_glass.add(row_op_presets)

            row_link_opacity = Adw.SwitchRow(
                title=esc("Đồng bộ Inactive theo Active"),
                subtitle=esc("Tự động giữ cửa sổ nền không focus cùng độ mờ với cửa sổ đang chọn"),
                active=True
            )
            row_link_opacity.connect("notify::active", self._on_opacity_link_toggled)
            self._dec_link_switch = row_link_opacity
            group_glass.add(row_link_opacity)

            add_dec_slider_row(
                group_glass,
                "active_opacity",
                "Độ trong suốt cửa sổ Active (0.30 – 1.00)",
                "Độ đục của cửa sổ đang sử dụng (0.80 = kính mờ rõ, 0.90 = mặc định, 1.00 = đặc)",
                marks=[0.50, 0.80, 0.90, 1.00],
            )
            add_dec_slider_row(
                group_glass,
                "inactive_opacity",
                "Độ trong suốt cửa sổ Inactive (0.30 – 1.00)",
                "Độ đục của các cửa sổ nền phía sau",
                marks=[0.50, 0.80, 0.90, 1.00],
            )
            add_dec_slider_row(
                group_glass,
                "fullscreen_opacity",
                "Độ trong suốt toàn màn hình (Fullscreen)",
                "Độ đục khi ứng dụng chạy chế độ toàn màn hình (1.00 giữ ảnh sắc nét)",
                marks=[0.80, 0.90, 1.00],
            )

            row_override_all = Adw.SwitchRow(
                title=esc("Ghi đè toàn bộ ứng dụng (kể cả Video/Media)"),
                subtitle=esc("Áp dụng đồng bộ độ mờ cho mọi app như Antigravity, Terminal, Browser và Video"),
                active=True
            )
            row_override_all.connect("notify::active", self._on_dec_switch_toggled, "override_all_apps", win)
            self._dec_switches["override_all_apps"] = row_override_all
            group_glass.add(row_override_all)
            page_hyprland.add(group_glass)

            group_blur = Adw.PreferencesGroup(
                title=esc("Làm Mờ Nền (Dual-pass Kawase Blur) & Bo Góc"),
                description=esc("Tinh chỉnh bán kính mờ, số lớp lọc, độ sáng và độ rực màu xuyên kính")
            )
            row_blur = Adw.SwitchRow(
                title=esc("Bật hiệu ứng làm mờ nền (Dual-pass Kawase Blur)"),
                subtitle=esc("Hiệu ứng kính mờ phía sau cửa sổ, Rofi, Waybar và SwayNC"),
                active=True
            )
            row_blur.connect("notify::active", self._on_dec_switch_toggled, "blur_enabled", win)
            self._dec_switches["blur_enabled"] = row_blur
            group_blur.add(row_blur)

            row_blur_presets = Adw.ActionRow(
                title=esc("Cường độ Blur nhanh"),
                subtitle=esc("Áp dụng nhanh cặp Size × Passes chuẩn")
            )
            blur_preset_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
            blur_preset_box.set_valign(Gtk.Align.CENTER)
            for bp in BLUR_PRESETS:
                bsz, bps, blbl = int(bp["blur_size"]), int(bp["blur_passes"]), str(bp["label"])
                bbtn = Gtk.Button(label=blbl)
                bbtn.add_css_class("dec-preset-btn")
                bbtn.connect("clicked", self._on_blur_preset_clicked, bsz, bps, blbl, win)
                blur_preset_box.append(bbtn)
                self._blur_preset_btns.append((bsz, bps, bbtn))
            row_blur_presets.add_suffix(blur_preset_box)
            self._dec_blur_detail_widgets.append(row_blur_presets)
            group_blur.add(row_blur_presets)

            add_dec_slider_row(
                group_blur,
                "blur_size",
                "Độ rộng vùng mờ (Blur Size: 1 – 20)",
                "Bán kính khuếch tán làm nhòe chi tiết ảnh nền phía sau kính",
                marks=[2, 5, 10, 15],
                is_blur_detail=True,
            )
            add_dec_slider_row(
                group_blur,
                "blur_passes",
                "Số lớp lọc mịn (Blur Passes: 1 – 6)",
                "Số lần lặp Kawase — tăng độ mịn của nền kính (giá trị cao tốn GPU hơn)",
                marks=[1, 2, 3, 4],
                is_blur_detail=True,
            )
            add_dec_slider_row(
                group_blur,
                "blur_brightness",
                "Độ sáng nền mờ (Brightness: 0.30 – 1.50)",
                "Điều chỉnh độ sáng/tối của phần ảnh nền xuyên qua kính mờ",
                marks=[0.80, 1.00, 1.20],
                is_blur_detail=True,
            )
            add_dec_slider_row(
                group_blur,
                "blur_vibrancy",
                "Độ rực màu xuyên kính (Vibrancy: 0.00 – 1.00)",
                "Tăng độ bão hòa màu wallpaper xuyên qua cửa sổ (hiệu ứng macOS vibrancy)",
                marks=[0.00, 0.20, 0.50, 0.80],
                is_blur_detail=True,
            )
            add_dec_slider_row(
                group_blur,
                "blur_contrast",
                "Độ tương phản mờ (Contrast: 0.30 – 1.50)",
                "Cân chỉnh độ tương phản vùng nền mờ phía sau",
                marks=[0.80, 0.90, 1.10],
                is_blur_detail=True,
            )
            add_dec_slider_row(
                group_blur,
                "blur_noise",
                "Hạt nhiễu kính mờ (Noise: 0.000 – 0.100)",
                "Thêm nhiễu nhẹ giúp nền mờ mịn hơn trên gradient tối",
                marks=[0.00, 0.012, 0.05],
                is_blur_detail=True,
            )

            row_xray = Adw.SwitchRow(
                title=esc("Xuyên thấu wallpaper (Blur X-Ray)"),
                subtitle=esc("Cho phép cửa sổ nổi nhìn trực tiếp ra wallpaper thay vì chồng mờ lên cửa sổ khác"),
                active=True
            )
            row_xray.connect("notify::active", self._on_dec_switch_toggled, "blur_xray", win)
            self._dec_switches["blur_xray"] = row_xray
            self._dec_blur_detail_widgets.append(row_xray)
            group_blur.add(row_xray)

            row_ignore_op = Adw.SwitchRow(
                title=esc("Blur bỏ qua Alpha cửa sổ (Ignore Opacity)"),
                subtitle=esc("Giữ vùng mờ đầy đủ ngay cả khi cửa sổ dùng opacity rất thấp"),
                active=True
            )
            row_ignore_op.connect("notify::active", self._on_dec_switch_toggled, "blur_ignore_opacity", win)
            self._dec_switches["blur_ignore_opacity"] = row_ignore_op
            self._dec_blur_detail_widgets.append(row_ignore_op)
            group_blur.add(row_ignore_op)

            row_round = Adw.ActionRow(
                title=esc("Bo góc cửa sổ (Rounding)"),
                subtitle=esc("Điều chỉnh bán kính bo tròn góc cửa sổ (0px – 30px)")
            )
            spin_round = Gtk.SpinButton.new_with_range(0, 30, 1)
            spin_round.set_value(10)
            spin_round.set_valign(Gtk.Align.CENTER)
            spin_round.connect("value-changed", self._on_hypr_rounding_changed)
            self._dec_spin_round = spin_round
            row_round.add_suffix(spin_round)
            group_blur.add(row_round)

            page_hyprland.add(group_blur)

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
                dec_payload = self.decorations_mgr.get_state()
                dec_st = dec_payload.get("state", get_default_state())
                power_st = self.power_mgr.get_status()

                def _apply_live_state():
                    self._sync_dec_ui_from_state(dec_st, sync_link_switch=True)
                    self._syncing_hypr_state = True
                    try:
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

        def _thumb_cache_path(self, file_path: str) -> Optional[Path]:
            p = Path(file_path)
            if not p.exists():
                return None
            stat = p.stat()
            cache_key = hashlib.md5(f"{file_path}:{stat.st_mtime_ns}:{stat.st_size}".encode("utf-8")).hexdigest()
            return self._thumb_cache_dir / f"{cache_key}.jpg"

        @staticmethod
        def _texture_from_file(path: Path) -> Optional[Any]:
            if hasattr(Gdk.Texture, "new_from_filename"):
                return Gdk.Texture.new_from_filename(str(path))
            return Gdk.Texture.new_from_bytes(GLib.Bytes.new(path.read_bytes()))

        def _get_or_create_thumb_pixbuf(self, file_path: str) -> Optional[Any]:
            try:
                cache_file = self._thumb_cache_path(file_path)
                if cache_file is None:
                    return None

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

        def _get_or_create_thumb_paintable(self, file_path: str) -> Optional[Any]:
            try:
                cache_file = self._thumb_cache_path(file_path)
                if cache_file is None:
                    return None
                if cache_file.exists():
                    try:
                        return self._texture_from_file(cache_file)
                    except Exception:
                        pass

                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(file_path, 240, 135, False)
                if pixbuf is None:
                    return None
                try:
                    pixbuf.savev(str(cache_file), "jpeg", ["quality"], ["85"])
                    if cache_file.exists():
                        return self._texture_from_file(cache_file)
                except Exception:
                    pass
                return Gdk.Texture.new_for_pixbuf(pixbuf)
            except Exception:
                return None

        def _apply_pixbuf_batch(self, batch: List[Tuple[Gtk.Picture, Any]]) -> bool:
            for pic_widget, media in batch:
                try:
                    texture = (
                        media
                        if isinstance(media, Gdk.Paintable)
                        else Gdk.Texture.new_for_pixbuf(media)
                    )
                    pic_widget.set_paintable(texture)
                except Exception:
                    pass
            return GLib.SOURCE_REMOVE

        def _load_thumbnails_async(self, tasks: List[Tuple[Gtk.Picture, str]]):
            batch: List[Tuple[Gtk.Picture, Any]] = []
            batch_limit = 9
            for pic_widget, file_path in tasks:
                media = self._get_or_create_thumb_paintable(file_path)
                if media is not None:
                    batch.append((pic_widget, media))
                    if len(batch) >= batch_limit:
                        GLib.idle_add(self._apply_pixbuf_batch, batch)
                        batch = []
                        batch_limit = 24
            if batch:
                GLib.idle_add(self._apply_pixbuf_batch, batch)

        def _on_window_close_request(self, _win) -> bool:
            if self._filter_timeout_id is not None:
                GLib.source_remove(self._filter_timeout_id)
                self._filter_timeout_id = None
            self._cancel_dec_timers()
            if self._dec_dirty_persist:
                self._dec_dirty_persist = False
                try:
                    self.decorations_mgr.persist_state(dict(self._dec_state))
                except Exception:
                    pass
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
