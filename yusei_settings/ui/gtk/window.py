"""
Native Libadwaita & GTK4 Settings Window
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Provides modern GNOME / Libadwaita preferences window with full catalog access,
instant live-filtering search, real-time Hyprland controls, and 5-stage safety rollback.
"""

import os
import re
import sys
import subprocess
from pathlib import Path
from typing import Optional, Any, List, Tuple

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
    from gi.repository import Gtk, Adw, Gio, GLib

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
            self.discovery = DiscoveryEngine(workspace_root)
            self.state_mgr = StateManager(target_home)
            self.safety = SafetyEngine(target_home)
            self.power_mgr = PowerManager(workspace_root, target_home)
            self.searchable_rows: List[Tuple[Adw.ExpanderRow, Adw.ActionRow, str]] = []

        def _get_hypr_decoration_state(self) -> Tuple[int, bool]:
            """Reads current rounding and blur state from hyprctl or config."""
            rounding = 16
            blur_enabled = True
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
            val = int(spin_btn.get_value())
            try:
                subprocess.run(
                    ["hyprctl", "keyword", "decoration:rounding", str(val)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                    timeout=2,
                )
            except Exception:
                pass
            # Persist in UserDecorations.conf if present
            user_dec = self.safety.home / ".config/hypr/UserConfigs/UserDecorations.conf"
            if user_dec.exists():
                try:
                    txt = user_dec.read_text(encoding="utf-8", errors="ignore")
                    txt = re.sub(r"(^\s*rounding\s*=\s*)\d+", rf"\g<1>{val}", txt, flags=re.MULTILINE)
                    user_dec.write_text(txt, encoding="utf-8")
                except Exception:
                    pass

        def _apply_hypr_blur(self, switch_row, _pspec, win):
            active = switch_row.get_active()
            val_str = "true" if active else "false"
            try:
                subprocess.run(
                    ["hyprctl", "keyword", "decoration:blur:enabled", val_str],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                    timeout=2,
                )
            except Exception:
                pass
            user_dec = self.safety.home / ".config/hypr/UserConfigs/UserDecorations.conf"
            if user_dec.exists():
                try:
                    txt = user_dec.read_text(encoding="utf-8", errors="ignore")
                    txt = re.sub(
                        r"(blur\s*\{[^}]*?enabled\s*=\s*)(true|false|yes|no|1|0)",
                        rf"\g<1>{val_str}",
                        txt,
                         count=1,
                        flags=re.DOTALL,
                    )
                    user_dec.write_text(txt, encoding="utf-8")
                except Exception:
                    pass
            toast = Adw.Toast(title=f"Đã {'bật' if active else 'tắt'} hiệu ứng làm mờ nền (Blur)")
            toast.set_timeout(2)
            win.add_toast(toast)

        def do_activate(self):
            win = Adw.PreferencesWindow(application=self, title="Cài Đặt Hệ Thống (yusei-settings)")
            win.set_default_size(1020, 740)
            win.set_search_enabled(True)

            catalog = self.discovery.discover_all()
            active = self.state_mgr.get_active_state()
            self.searchable_rows.clear()

            # -----------------------------------------------------------------
            # PAGE 1: Giao diện & Layout (Appearance)
            # -----------------------------------------------------------------
            page_appearance = Adw.PreferencesPage(
                title="Giao diện & Layout",
                icon_name="preferences-desktop-theme-symbolic"
            )

            # Quick Filter Bar
            group_filter = Adw.PreferencesGroup(
                title="Tìm Kiếm & Lọc Nhanh",
                description="Hiển thị đầy đủ 100% kho giao diện, bố cục, bảng màu và hình nền trên hệ thống"
            )
            search_entry = Gtk.SearchEntry(
                placeholder_text="Nhập tên layout, style, theme Rofi/Kitty hoặc tên hình nền để lọc..."
            )
            search_entry.set_margin_top(4)
            search_entry.set_margin_bottom(4)
            search_entry.connect("search-changed", self.on_filter_changed)
            group_filter.add(search_entry)
            page_appearance.add(group_filter)

            # Helper to build full catalog expander sections without any truncation
            def build_catalog_section(
                group_title: str,
                expander_title: str,
                expander_subtitle: str,
                items: list,
                category_key: str,
                btn_label: str,
                subtitle_fn,
                expanded_by_default: bool = False
            ):
                group = Adw.PreferencesGroup(title=group_title)
                expander = Adw.ExpanderRow(
                    title=esc(f"{expander_title} ({len(items)} lựa chọn)"),
                    subtitle=esc(expander_subtitle)
                )
                expander.set_expanded(expanded_by_default)

                for item in items:
                    sub_txt = subtitle_fn(item)
                    row = Adw.ActionRow(
                        title=esc(item["name"]),
                        subtitle=esc(sub_txt)
                    )
                    btn = Gtk.Button(label=btn_label)
                    btn.set_valign(Gtk.Align.CENTER)
                    btn.add_css_class("suggested-action")
                    btn.connect("clicked", self.on_apply_clicked, category_key, item, win)
                    row.add_suffix(btn)
                    expander.add_row(row)

                    search_blob = f"{item.get('name', '')} {item.get('raw_name', '')} {sub_txt}".lower()
                    self.searchable_rows.append((expander, row, search_blob))

                group.add(expander)
                page_appearance.add(group)

            # 1. Waybar Layouts (Full list)
            waybar_layouts = catalog.get("waybar_layouts", [])
            build_catalog_section(
                group_title="Thanh Trạng Thái Waybar (Layouts)",
                expander_title="Danh sách Bố cục Waybar",
                expander_subtitle=f"Đang dùng: {active.get('waybar_layout', 'Default')} • Nhấn để xem toàn bộ {len(waybar_layouts)} bố cục",
                items=waybar_layouts,
                category_key="waybar_layout",
                btn_label="Áp dụng",
                subtitle_fn=lambda it: f"{it.get('position', 'TOP')} • {it.get('raw_name', '')}",
                expanded_by_default=True
            )

            # 2. Waybar Styles (Full list)
            waybar_styles = catalog.get("waybar_styles", [])
            build_catalog_section(
                group_title="Phong Cách Waybar CSS (Styles)",
                expander_title="Danh sách Kiểu dáng CSS Waybar",
                expander_subtitle=f"Đang dùng: {active.get('waybar_style', 'Default')} • Nhấn để xem toàn bộ {len(waybar_styles)} kiểu dáng",
                items=waybar_styles,
                category_key="waybar_style",
                btn_label="Áp dụng",
                subtitle_fn=lambda it: f"Phong cách: {it.get('theme_tag', 'Modern')} • {it.get('raw_name', '')}",
                expanded_by_default=False
            )

            # 3. Wallpapers (Full list from ~/Pictures/wallpapers + assets/wallpapers)
            wallpapers = catalog.get("wallpapers", [])
            build_catalog_section(
                group_title="Hình Nền Hệ Thống & Đồng Bộ Màu Động (Wallpapers)",
                expander_title="Kho Hình Nền Chất Lượng Cao",
                expander_subtitle=f"Đang dùng: {active.get('wallpaper', 'wallpaper.jpg')} • Nhấn để chọn trong {len(wallpapers)} hình nền",
                items=wallpapers,
                category_key="wallpaper",
                btn_label="Đặt hình nền",
                subtitle_fn=lambda it: it.get("description", it.get("raw_name", "")),
                expanded_by_default=False
            )

            # 4. Rofi Themes (Full list)
            rofi_themes = catalog.get("rofi_themes", [])
            build_catalog_section(
                group_title="Giao Diện Menu Ứng Dụng Rofi (Themes)",
                expander_title="Danh sách Giao diện Rofi Launcher",
                expander_subtitle=f"Đang dùng: {active.get('rofi_theme', 'Default')} • Nhấn để chọn trong {len(rofi_themes)} giao diện",
                items=rofi_themes,
                category_key="rofi_theme",
                btn_label="Áp dụng",
                subtitle_fn=lambda it: f"Kiểu dáng: {it.get('style_type', 'Card')} • {it.get('raw_name', '')}",
                expanded_by_default=False
            )

            # 5. Kitty Terminal Themes (Full list - 340+ themes)
            kitty_themes = catalog.get("kitty_themes", [])
            build_catalog_section(
                group_title="Bảng Màu Terminal Kitty (Themes)",
                expander_title="Kho Bảng Màu Kitty Terminal",
                expander_subtitle=f"Đang dùng: {active.get('kitty_theme', 'Default')} • Nhấn để chọn trong {len(kitty_themes)} bảng màu",
                items=kitty_themes,
                category_key="kitty_theme",
                btn_label="Áp dụng",
                subtitle_fn=lambda it: f"{it.get('description', '')} ({it.get('raw_name', '')})",
                expanded_by_default=False
            )

            win.add(page_appearance)

            # -----------------------------------------------------------------
            # PAGE 2: Hyprland (Animations & Effects)
            # -----------------------------------------------------------------
            page_hyprland = Adw.PreferencesPage(
                title="Hyprland",
                icon_name="preferences-system-windows-symbolic"
            )
            cur_rounding, cur_blur = self._get_hypr_decoration_state()

            group_hypr = Adw.PreferencesGroup(
                title="Hiệu Ứng & Bo Góc Cửa Sổ",
                description="Thay đổi có hiệu lực ngay lập tức trên phiên Hyprland hiện tại"
            )
            row_round = Adw.ActionRow(
                title=esc("Bo góc cửa sổ (Rounding)"),
                subtitle=esc("Điều chỉnh bán kính bo tròn góc cửa sổ (0px - 30px)")
            )
            spin_round = Gtk.SpinButton.new_with_range(0, 30, 1)
            spin_round.set_value(cur_rounding)
            spin_round.set_valign(Gtk.Align.CENTER)
            spin_round.connect("value-changed", self._apply_hypr_rounding, win)
            row_round.add_suffix(spin_round)
            group_hypr.add(row_round)

            row_blur = Adw.SwitchRow(
                title=esc("Làm mờ nền (Dual-pass Kawase Blur)"),
                subtitle=esc("Hiệu ứng kính mờ trong suốt phía sau cửa sổ"),
                active=cur_blur
            )
            row_blur.connect("notify::active", self._apply_hypr_blur, win)
            group_hypr.add(row_blur)
            page_hyprland.add(group_hypr)

            # Animations List (Full list)
            anims = catalog.get("hyprland_animations", [])
            group_anim = Adw.PreferencesGroup(
                title=f"Động Lực Học Cửa Sổ (Animations - {len(anims)} Presets)",
                description="Chọn cấu hình chuyển động cửa sổ và đường cong Bezier"
            )
            for item in anims:
                row = Adw.ActionRow(
                    title=esc(item["name"]),
                    subtitle=esc(f"{item.get('description', 'Đường cong bezier')} ({item.get('raw_name', '')})")
                )
                btn = Gtk.Button(label="Kích hoạt")
                btn.set_valign(Gtk.Align.CENTER)
                btn.add_css_class("suggested-action")
                btn.connect("clicked", self.on_apply_clicked, "hyprland_animation", item, win)
                row.add_suffix(btn)
                group_anim.add(row)
            page_hyprland.add(group_anim)

            win.add(page_hyprland)

            # -----------------------------------------------------------------
            # PAGE 3: Nguồn điện & Pin (Power & Battery)
            # -----------------------------------------------------------------
            page_power = Adw.PreferencesPage(
                title="Nguồn điện & Pin",
                icon_name="battery-symbolic"
            )
            group_power_status = Adw.PreferencesGroup(title="Giám Sát Nguồn & Pin")
            power_st = self.power_mgr.get_status()
            self.row_bat = Adw.ActionRow(
                title=esc("Dung lượng pin & Nguồn"),
                subtitle=esc(f"{power_st.get('battery_percent', 100)}% ({power_st.get('battery_status', 'AC Only')}) • {'Cắm sạc AC' if power_st.get('ac_online') else 'Dùng pin'} • Profile: {power_st.get('profile', 'balanced').upper()}")
            )
            group_power_status.add(self.row_bat)

            self.row_rate = Adw.ActionRow(
                title=esc("Màn hình & Tần số quét"),
                subtitle=esc(f"{power_st.get('monitor_name', 'Display')} • {power_st.get('current_hz', 60)} Hz (Tối đa: {power_st.get('max_hz', 60)} Hz)")
            )
            group_power_status.add(self.row_rate)
            page_power.add(group_power_status)

            group_profiles = Adw.PreferencesGroup(title="Profile Năng Lượng")
            for p_id, p_name, p_desc in [
                ("eco", "Tiết kiệm điện (Eco)", "Hạ xung nhịp CPU, giảm màn hình về 60Hz"),
                ("balanced", "Cân bằng (Balanced)", "Tự động cân bằng hiệu năng và tiêu thụ điện"),
                ("turbo", "Hiệu năng tối đa (Turbo)", "Xung nhịp CPU tối đa, tần số quét cao nhất")
            ]:
                row_p = Adw.ActionRow(title=esc(p_name), subtitle=esc(p_desc))
                btn_p = Gtk.Button(label="Kích hoạt")
                btn_p.set_valign(Gtk.Align.CENTER)
                btn_p.connect("clicked", self.on_power_profile_clicked, p_id, p_name, win)
                row_p.add_suffix(btn_p)
                group_profiles.add(row_p)
            page_power.add(group_profiles)

            group_power_cfg = Adw.PreferencesGroup(title="Tùy Chọn Tần Số Quét")
            row_auto_60hz = Adw.SwitchRow(
                title=esc("Tự động hạ màn hình xuống 60Hz khi rút sạc"),
                subtitle=esc("Khôi phục tần số quét cao khi cắm sạc"),
                active=power_st.get("auto_60hz", True)
            )
            row_auto_60hz.connect("notify::active", lambda w, p: self.power_mgr.set_config(w.get_active()))
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
            win.add(page_power)

            # -----------------------------------------------------------------
            # PAGE 4: Ứng dụng & Công cụ (Applications & Tools)
            # -----------------------------------------------------------------
            page_apps = Adw.PreferencesPage(
                title="Ứng dụng",
                icon_name="system-run-symbolic"
            )
            group_apps = Adw.PreferencesGroup(title="Ứng Dụng Mặc Định")
            group_apps.add(Adw.ActionRow(title=esc("Terminal mặc định ($term)"), subtitle=esc("kitty")))
            group_apps.add(Adw.ActionRow(title=esc("Trình quản lý tệp ($files)"), subtitle=esc("thunar")))
            page_apps.add(group_apps)

            group_tools = Adw.PreferencesGroup(
                title="Công Cụ Nhanh Hyprland",
                description="Khởi chạy nhanh các trình chọn trực quan và làm mới hệ thống"
            )
            quick_tools = [
                ("Làm mới Thanh Waybar & SwayNC", "Khởi động lại Waybar và nạp lại CSS SwayNC tức thì", "~/.config/hypr/scripts/Refresh.sh"),
                ("Mở Bộ Chọn Hình Nền (Rofi)", "Duyệt hình nền có ảnh thu nhỏ và áp dụng Wallust", "~/.config/hypr/scripts/WallpaperSelect.sh"),
                ("Bảng Phím Tắt Hệ Thống (KeyHints)", "Xem danh sách toàn bộ phím tắt trên yusei-hypr", "~/.config/hypr/scripts/KeyHints.sh"),
            ]
            for t_title, t_sub, t_cmd in quick_tools:
                r_tool = Adw.ActionRow(title=esc(t_title), subtitle=esc(t_sub))
                b_tool = Gtk.Button(label="Chạy")
                b_tool.set_valign(Gtk.Align.CENTER)
                b_tool.connect("clicked", lambda _b, c=t_cmd: subprocess.Popen(["bash", "-c", os.path.expanduser(c)]))
                r_tool.add_suffix(b_tool)
                group_tools.add(r_tool)
            page_apps.add(group_tools)
            win.add(page_apps)

            # -----------------------------------------------------------------
            # PAGE 5: Sao lưu & Khôi phục (Backup & Restore)
            # -----------------------------------------------------------------
            page_backup = Adw.PreferencesPage(
                title="Sao lưu & Khôi phục",
                icon_name="drive-harddisk-symbolic"
            )
            self.group_backup = Adw.PreferencesGroup(
                title="Lịch Sử Snapshots An Toàn",
                description="Mỗi khi áp dụng cấu hình mới, một bản sao lưu tự động được tạo tại đây"
            )
            self._populate_snapshots(win)
            page_backup.add(self.group_backup)
            win.add(page_backup)

            win.present()

        def _populate_snapshots(self, win):
            snaps = self.safety.list_snapshots()
            if snaps:
                for s in snaps:
                    sid = s.get("snapshot_id", "")
                    row_s = Adw.ActionRow(
                        title=esc(sid),
                        subtitle=esc(f"Thời gian: {s.get('created_at', '')} • {len(s.get('backed_up_files', []))} tệp")
                    )
                    btn_r = Gtk.Button(label="Khôi phục")
                    btn_r.set_valign(Gtk.Align.CENTER)
                    btn_r.connect("clicked", lambda b, snap_id=sid: self.on_rollback_clicked(snap_id, win))
                    row_s.add_suffix(btn_r)
                    self.group_backup.add(row_s)
            else:
                self.group_backup.add(
                    Adw.ActionRow(
                        title=esc("Chưa có bản snapshot nào"),
                        subtitle=esc("Snapshot tự động tạo khi bấm Áp dụng bất kỳ mục nào")
                    )
                )

        def on_filter_changed(self, search_entry):
            query = search_entry.get_text().strip().lower()
            expander_matches = {}
            for expander, row, blob in self.searchable_rows:
                matched = (not query) or (query in blob)
                row.set_visible(matched)
                if matched:
                    expander_matches[expander] = expander_matches.get(expander, 0) + 1

            for expander, _row, _blob in self.searchable_rows:
                has_match = expander_matches.get(expander, 0) > 0
                expander.set_visible(has_match)
                if query and has_match:
                    expander.set_expanded(True)

        def _refresh_power_labels(self):
            st = self.power_mgr.get_status()
            self.row_bat.set_subtitle(
                esc(f"{st.get('battery_percent', 100)}% ({st.get('battery_status', 'AC Only')}) • {'Cắm sạc AC' if st.get('ac_online') else 'Dùng pin'} • Profile: {st.get('profile', 'balanced').upper()}")
            )
            self.row_rate.set_subtitle(
                esc(f"{st.get('monitor_name', 'Display')} • {st.get('current_hz', 60)} Hz (Tối đa: {st.get('max_hz', 60)} Hz)")
            )

        def on_power_profile_clicked(self, _button, profile_id: str, profile_name: str, win):
            self.power_mgr.set_profile(profile_id)
            self._refresh_power_labels()
            toast = Adw.Toast(title=f"Đã chuyển sang chế độ: {profile_name}")
            toast.set_timeout(2)
            win.add_toast(toast)

        def on_toggle_hz_clicked(self, _button, win):
            self.power_mgr.toggle_hz()
            self._refresh_power_labels()
            toast = Adw.Toast(title="Đã chuyển đổi tần số quét màn hình!")
            toast.set_timeout(2)
            win.add_toast(toast)

        def on_apply_clicked(self, button, category, item, parent_window):
            res = self.safety.apply_change(category, item["id"], item["file_path"], confirmed=True)
            toast = Adw.Toast(title=f"Đã áp dụng: {item['name']}")
            toast.set_timeout(3)
            toast.set_button_label("Hoàn tác")
            toast.connect("button-clicked", lambda _t: self.on_rollback_clicked(res.get("snapshot_id"), parent_window, category))
            parent_window.add_toast(toast)

        def on_rollback_clicked(self, snapshot_id, parent_window, category: Optional[str] = None):
            self.safety.rollback(snapshot_id)
            if category in ("waybar_layout", "waybar_style", None):
                subprocess.Popen(
                    ["bash", "-c", "pkill -SIGUSR2 waybar 2>/dev/null || nohup waybar >/dev/null 2>&1 &"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            if category in ("kitty_theme", None):
                subprocess.run(["pkill", "-SIGUSR1", "kitty"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            if category in ("hyprland_animation", None):
                subprocess.run(["hyprctl", "reload", "config-only"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)

            toast = Adw.Toast(title=f"Đã hoàn tác về bản sao lưu {snapshot_id}!")
            toast.set_timeout(3)
            parent_window.add_toast(toast)

    app = YuseiSettingsApp()
    return app.run([sys.argv[0]])
