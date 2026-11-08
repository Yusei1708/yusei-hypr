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
            self.discovery = DiscoveryEngine(workspace_root)
            self.state_mgr = StateManager(target_home)
            self.safety = SafetyEngine(target_home)
            self.power_mgr = PowerManager(workspace_root, target_home)
            self.searchable_rows: List[Tuple[Adw.ExpanderRow, Adw.ActionRow, str]] = []
            self.searchable_wp_cards: List[Tuple[Any, str]] = []
            self.wp_card_map: Dict[str, Tuple[Any, Any]] = {}
            self.wp_group: Optional[Any] = None
            self.wp_expander: Optional[Any] = None
            self.wp_random_pic: Optional[Any] = None
            self.wallpapers_catalog: List[Dict[str, Any]] = []
            self._thumb_cache_dir = Path.home() / ".cache" / "yusei-hypr" / "wall_thumbs"
            try:
                self._thumb_cache_dir.mkdir(parents=True, exist_ok=True)
            except Exception:
                pass

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
        ) -> Gtk.FlowBoxChild:
            child = Gtk.FlowBoxChild()
            child.set_focusable(False)

            card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            card.add_css_class("catalog-item-card")
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
            return child

        def do_activate(self):
            existing_win = self.get_active_window()
            if existing_win is not None:
                existing_win.present()
                return
            self._install_custom_css()
            win = Adw.PreferencesWindow(application=self, title="Cài Đặt Hệ Thống (yusei-settings)")
            win.set_default_size(1360, 820)
            win.set_search_enabled(True)

            catalog = self.discovery.discover_all()
            active = self.state_mgr.get_active_state()
            self.searchable_rows.clear()
            self.searchable_wp_cards.clear()
            self.wp_card_map.clear()

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

            # Helper to build full catalog expander sections in a 3-column grid without truncation
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
                group = Adw.PreferencesGroup(title=esc(group_title))
                expander = Adw.ExpanderRow(
                    title=esc(f"{expander_title} ({len(items)} lựa chọn)"),
                    subtitle=esc(expander_subtitle)
                )
                expander.set_expanded(expanded_by_default)

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

                for item in items:
                    sub_txt = subtitle_fn(item)
                    child = self._create_3col_card_child(
                        title_txt=item["name"],
                        sub_txt=sub_txt,
                        btn_label=btn_label,
                        on_click_cb=lambda btn, ck=category_key, it=item: self.on_apply_clicked(btn, ck, it, win),
                    )
                    flowbox.append(child)

                    search_blob = f"{item.get('name', '')} {item.get('raw_name', '')} {sub_txt}".lower()
                    self.searchable_rows.append((expander, child, search_blob))

                grid_row.set_child(flowbox)
                expander.add_row(grid_row)
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

            self._widen_page_clamp(page_appearance)
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
                title=esc("Hiệu Ứng & Bo Góc Cửa Sổ"),
                description=esc("Thay đổi có hiệu lực ngay lập tức trên phiên Hyprland hiện tại")
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
            for item in anims:
                sub_txt = f"{item.get('description', 'Đường cong bezier')} ({item.get('raw_name', '')})"
                child_a = self._create_3col_card_child(
                    title_txt=item["name"],
                    sub_txt=sub_txt,
                    btn_label="Kích hoạt",
                    on_click_cb=lambda btn, it=item: self.on_apply_clicked(btn, "hyprland_animation", it, win),
                )
                anim_flow.append(child_a)
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
            for p_id, p_name, p_desc in [
                ("eco", "Tiết kiệm điện (Eco)", "Hạ xung nhịp CPU, giảm màn hình về 60Hz"),
                ("balanced", "Cân bằng (Balanced)", "Tự động cân bằng hiệu năng và tiêu thụ điện"),
                ("turbo", "Hiệu năng tối đa (Turbo)", "Xung nhịp CPU tối đa, tần số quét cao nhất")
            ]:
                child_p = self._create_3col_card_child(
                    title_txt=p_name,
                    sub_txt=p_desc,
                    btn_label="Kích hoạt",
                    on_click_cb=lambda btn, pid=p_id, pname=p_name: self.on_power_profile_clicked(btn, pid, pname, win),
                )
                prof_flow.append(child_p)
            prof_row.set_child(prof_flow)
            group_profiles.add(prof_row)
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
            self._widen_page_clamp(page_power)
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
                ("Làm mới Thanh Waybar & SwayNC", "Khởi động lại Waybar và nạp lại CSS SwayNC tức thì", "~/.config/hypr/scripts/Refresh.sh"),
                ("Mở Bộ Chọn Hình Nền (Rofi)", "Duyệt hình nền có ảnh thu nhỏ và áp dụng Wallust", "~/.config/hypr/scripts/WallpaperSelect.sh"),
                ("Bảng Phím Tắt Hệ Thống (KeyHints)", "Xem danh sách toàn bộ phím tắt trên yusei-hypr", "~/.config/hypr/scripts/KeyHints.sh"),
            ]
            for t_title, t_sub, t_cmd in quick_tools:
                child_t = self._create_3col_card_child(
                    title_txt=t_title,
                    sub_txt=t_sub,
                    btn_label="Chạy",
                    on_click_cb=lambda _b, c=t_cmd: subprocess.Popen(["bash", "-c", os.path.expanduser(c)]),
                )
                tools_flow.append(child_t)
            tools_row.set_child(tools_flow)
            group_tools.add(tools_row)
            page_apps.add(group_tools)
            self._widen_page_clamp(page_apps)
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
            self._widen_page_clamp(page_backup)
            win.add(page_backup)

            win.present()

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
                self.wp_card_map[raw_name] = (card_btn, lbl)

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

        def _set_picture_pixbuf(self, pic_widget: Gtk.Picture, pixbuf: Any) -> bool:
            try:
                texture = Gdk.Texture.new_for_pixbuf(pixbuf)
                pic_widget.set_paintable(texture)
            except Exception:
                pass
            return GLib.SOURCE_REMOVE

        def _load_thumbnails_async(self, tasks: List[Tuple[Gtk.Picture, str]]):
            for pic_widget, file_path in tasks:
                pixbuf = self._get_or_create_thumb_pixbuf(file_path)
                if pixbuf is not None:
                    GLib.idle_add(self._set_picture_pixbuf, pic_widget, pixbuf)

        def _update_active_wallpaper_ui(self, active_raw_name: str):
            if self.wp_expander is not None:
                self.wp_expander.set_subtitle(
                    esc(f"Đang dùng: {active_raw_name} • Nhấn trực tiếp vào ảnh để đặt hình nền (như Super + W)")
                )
            for raw_name, (btn, lbl) in self.wp_card_map.items():
                if raw_name == active_raw_name:
                    btn.add_css_class("wallpaper-card-active")
                    lbl.add_css_class("wallpaper-label-active")
                else:
                    btn.remove_css_class("wallpaper-card-active")
                    lbl.remove_css_class("wallpaper-label-active")

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
            res = self.safety.apply_change("wallpaper", item["id"], item["file_path"], confirmed=True)
            raw_name = item.get("raw_name", item["name"])
            self._update_active_wallpaper_ui(raw_name)
            toast = Adw.Toast(title=f"Đã đặt hình nền: {raw_name}")
            toast.set_timeout(3)
            toast.set_button_label("Hoàn tác")
            toast.connect(
                "button-clicked",
                lambda _t: self.on_rollback_clicked(res.get("snapshot_id"), parent_window, "wallpaper"),
            )
            parent_window.add_toast(toast)

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

            # Filter visual wallpaper cards
            wp_matches = 0
            for wp_child, blob in self.searchable_wp_cards:
                matched = (not query) or (query in blob)
                wp_child.set_visible(matched)
                if matched:
                    wp_matches += 1

            if self.wp_expander is not None:
                has_wp = wp_matches > 0
                self.wp_expander.set_visible(has_wp)
                if query and has_wp:
                    self.wp_expander.set_expanded(True)

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
            if category in ("wallpaper", None):
                restored_wp_file = self.safety.config_dir / "hypr" / "wallpaper.jpg"
                cur_sym = self.safety.config_dir / "hypr" / ".current_wallpaper"
                target_wp = None
                if cur_sym.is_symlink():
                    try:
                        target_wp = str(cur_sym.resolve())
                    except Exception:
                        pass
                if not target_wp and restored_wp_file.exists():
                    target_wp = str(restored_wp_file.resolve())
                if target_wp:
                    rofi_link = self.safety.config_dir / "rofi" / ".current_wallpaper"
                    try:
                        if rofi_link.exists() or rofi_link.is_symlink():
                            rofi_link.unlink()
                        rofi_link.symlink_to(target_wp)
                    except Exception:
                        pass
                    wallust_script = str(self.safety.home / ".config/hypr/scripts/WallustSwww.sh")
                    subprocess.Popen(
                        [
                            "bash", "-c",
                            f'swww img "{target_wp}" --transition-type any --transition-fps 60 --transition-duration 1.0 >/dev/null 2>&1 || true; '
                            f'[ -x "{wallust_script}" ] && "{wallust_script}" "{target_wp}" >/dev/null 2>&1 || true'
                        ],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                    self._update_active_wallpaper_ui(Path(target_wp).name)

            toast = Adw.Toast(title=f"Đã hoàn tác về bản sao lưu {snapshot_id}!")
            toast.set_timeout(3)
            parent_window.add_toast(toast)

    app = YuseiSettingsApp()
    return app.run([sys.argv[0]])
