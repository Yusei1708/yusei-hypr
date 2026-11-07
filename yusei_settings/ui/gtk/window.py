"""
Native Libadwaita & GTK4 Settings Window
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Provides modern GNOME / Libadwaita preferences window with cards,
switch rows, action buttons, dynamic Pango escaping, and safety confirmation dialogs.
"""

import os
import sys
import threading
import subprocess
import webbrowser
from typing import Optional, Any

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

        def do_activate(self):
            win = Adw.PreferencesWindow(application=self, title=esc("Cài Đặt Hệ Thống (yusei-settings)"))
            win.set_default_size(980, 700)

            # -----------------------------------------------------------------
            # PAGE 1: Giao diện & Layout (Appearance)
            # -----------------------------------------------------------------
            page_appearance = Adw.PreferencesPage(
                title=esc("Giao diện & Layout"),
                icon_name="preferences-desktop-theme-symbolic"
            )

            # Web UI Launcher Banner
            group_web = Adw.PreferencesGroup(title=esc("Giao Diện Windows 11 Web UI"))
            row_web = Adw.ActionRow(
                title=esc("Mở Giao Diện Web Nâng Cao"),
                subtitle=esc("Khởi chạy phiên bản Web Fluent Windows 11 trực quan trên trình duyệt với 8 trang chức năng")
            )
            btn_web = Gtk.Button(label=esc("Mở Web UI"))
            btn_web.add_css_class("suggested-action")
            btn_web.connect("clicked", self.on_open_web_clicked)
            row_web.add_suffix(btn_web)
            group_web.add(row_web)
            page_appearance.add(group_web)

            catalog = self.discovery.discover_all()
            active = self.state_mgr.get_active_state()

            # Group: Waybar Layouts
            group_waybar = Adw.PreferencesGroup(title=esc("Thanh Trạng Thái Waybar (Layouts)"))
            for item in catalog.get("waybar_layouts", [])[:8]:
                row = Adw.ActionRow(
                    title=esc(item["name"]),
                    subtitle=esc(f"{item.get('position', 'TOP')} • {item.get('description', '')}")
                )
                btn = Gtk.Button(label=esc("Áp dụng"))
                btn.add_css_class("suggested-action")
                btn.connect("clicked", self.on_apply_clicked, "waybar_layout", item, win)
                row.add_suffix(btn)
                group_waybar.add(row)
            page_appearance.add(group_waybar)

            # Group: Waybar Styles
            group_waybar_styles = Adw.PreferencesGroup(title=esc("Phong Cách Waybar CSS (Styles)"))
            for item in catalog.get("waybar_styles", [])[:8]:
                row = Adw.ActionRow(
                    title=esc(item["name"]),
                    subtitle=esc(f"Phong cách: {item.get('theme_tag', 'Modern')}")
                )
                btn = Gtk.Button(label=esc("Áp dụng"))
                btn.connect("clicked", self.on_apply_clicked, "waybar_style", item, win)
                row.add_suffix(btn)
                group_waybar_styles.add(row)
            page_appearance.add(group_waybar_styles)

            # Group: Rofi Themes
            group_rofi = Adw.PreferencesGroup(title=esc("Giao Diện Menu Rofi (Themes)"))
            for item in catalog.get("rofi_themes", [])[:6]:
                row = Adw.ActionRow(
                    title=esc(item["name"]),
                    subtitle=esc(f"Kiểu dáng: {item.get('style_type', 'Card')}")
                )
                btn = Gtk.Button(label=esc("Áp dụng"))
                btn.connect("clicked", self.on_apply_clicked, "rofi_theme", item, win)
                row.add_suffix(btn)
                group_rofi.add(row)
            page_appearance.add(group_rofi)

            # Group: Kitty Terminal Themes
            group_kitty = Adw.PreferencesGroup(title=esc("Bảng Màu Terminal Kitty (Themes)"))
            for item in catalog.get("kitty_themes", [])[:6]:
                row = Adw.ActionRow(
                    title=esc(item["name"]),
                    subtitle=esc(item.get("description", ""))
                )
                btn = Gtk.Button(label=esc("Áp dụng"))
                btn.connect("clicked", self.on_apply_clicked, "kitty_theme", item, win)
                row.add_suffix(btn)
                group_kitty.add(row)
            page_appearance.add(group_kitty)

            # Group: Curated Wallpapers
            group_wallpapers = Adw.PreferencesGroup(title=esc("Hình Nền & Màu Sắc Động (Wallpapers)"))
            for item in catalog.get("wallpapers", [])[:6]:
                row = Adw.ActionRow(
                    title=esc(item["name"]),
                    subtitle=esc(item.get("description", "Hình nền chất lượng cao"))
                )
                btn = Gtk.Button(label=esc("Đặt hình nền"))
                btn.connect("clicked", self.on_apply_clicked, "wallpaper", item, win)
                row.add_suffix(btn)
                group_wallpapers.add(row)
            page_appearance.add(group_wallpapers)

            win.add(page_appearance)

            # -----------------------------------------------------------------
            # PAGE 2: Hyprland (Animations & Effects)
            # -----------------------------------------------------------------
            page_hyprland = Adw.PreferencesPage(
                title=esc("Hyprland"),
                icon_name="preferences-system-windows-symbolic"
            )
            group_hypr = Adw.PreferencesGroup(title=esc("Hiệu Ứng & Bo Góc Cửa Sổ"))
            row_round = Adw.ActionRow(title=esc("Bo góc cửa sổ (Rounding)"), subtitle=esc("Mặc định chuẩn 16px"))
            row_round.add_suffix(Gtk.Label(label=esc("16px")))
            group_hypr.add(row_round)

            row_blur = Adw.SwitchRow(title=esc("Làm mờ nền (Dual-pass Kawase Blur)"), active=True)
            group_hypr.add(row_blur)
            page_hyprland.add(group_hypr)

            # Animations List
            group_anim = Adw.PreferencesGroup(title=esc("Động Lực Học Cửa Sổ (Animations)"))
            for item in catalog.get("hyprland_animations", [])[:6]:
                row = Adw.ActionRow(
                    title=esc(item["name"]),
                    subtitle=esc(item.get("description", "Đường cong bezier"))
                )
                btn = Gtk.Button(label=esc("Kích hoạt"))
                btn.connect("clicked", self.on_apply_clicked, "hyprland_animation", item, win)
                row.add_suffix(btn)
                group_anim.add(row)
            page_hyprland.add(group_anim)

            win.add(page_hyprland)

            # -----------------------------------------------------------------
            # PAGE 3: Nguồn điện & Pin (Power & Battery)
            # -----------------------------------------------------------------
            page_power = Adw.PreferencesPage(
                title=esc("Nguồn điện & Pin"),
                icon_name="battery-symbolic"
            )
            group_power_status = Adw.PreferencesGroup(title=esc("Giám Sát Nguồn & Pin"))
            power_st = self.power_mgr.get_status()
            row_bat = Adw.ActionRow(
                title=esc("Dung lượng pin & Nguồn"),
                subtitle=esc(f"{power_st.get('battery_percent', 100)}% ({power_st.get('battery_status', 'AC Only')}) • {'Cắm sạc AC' if power_st.get('ac_online') else 'Dùng pin'}")
            )
            group_power_status.add(row_bat)

            row_rate = Adw.ActionRow(
                title=esc("Màn hình & Tần số quét"),
                subtitle=esc(f"{power_st.get('monitor_name', 'Display')} • {power_st.get('current_hz', 60)} Hz (Tối đa: {power_st.get('max_hz', 60)} Hz)")
            )
            group_power_status.add(row_rate)
            page_power.add(group_power_status)

            group_profiles = Adw.PreferencesGroup(title=esc("Profile Năng Lượng"))
            for p_id, p_name, p_desc in [
                ("eco", "Tiết kiệm điện (Eco)", "Hạ xung nhịp CPU, giảm màn hình về 60Hz"),
                ("balanced", "Cân bằng (Balanced)", "Tự động cân bằng hiệu năng và tiêu thụ điện"),
                ("turbo", "Hiệu năng tối đa (Turbo)", "Xung nhịp CPU tối đa, tần số quét cao nhất")
            ]:
                row_p = Adw.ActionRow(title=esc(p_name), subtitle=esc(p_desc))
                btn_p = Gtk.Button(label=esc("Kích hoạt"))
                btn_p.connect("clicked", lambda b, prof=p_id: self.power_mgr.set_profile(prof))
                row_p.add_suffix(btn_p)
                group_profiles.add(row_p)
            page_power.add(group_profiles)

            group_power_cfg = Adw.PreferencesGroup(title=esc("Tùy Chọn Tần Số Quét"))
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
            btn_toggle_hz = Gtk.Button(label=esc("Chuyển đổi Hz"))
            btn_toggle_hz.connect("clicked", lambda b: self.power_mgr.toggle_hz())
            row_toggle_hz.add_suffix(btn_toggle_hz)
            group_power_cfg.add(row_toggle_hz)

            page_power.add(group_power_cfg)
            win.add(page_power)

            # -----------------------------------------------------------------
            # PAGE 4: Ứng dụng (Applications)
            # -----------------------------------------------------------------
            page_apps = Adw.PreferencesPage(
                title=esc("Ứng dụng"),
                icon_name="system-run-symbolic"
            )
            group_apps = Adw.PreferencesGroup(title=esc("Ứng Dụng Mặc Định"))
            group_apps.add(Adw.ActionRow(title=esc("Terminal ($term)"), subtitle=esc("Kitty")))
            group_apps.add(Adw.ActionRow(title=esc("Trình quản lý tệp ($files)"), subtitle=esc("Thunar")))
            page_apps.add(group_apps)
            win.add(page_apps)

            # -----------------------------------------------------------------
            # PAGE 5: Sao lưu & Khôi phục (Backup & Restore)
            # -----------------------------------------------------------------
            page_backup = Adw.PreferencesPage(
                title=esc("Sao lưu & Khôi phục"),
                icon_name="drive-harddisk-symbolic"
            )
            group_backup = Adw.PreferencesGroup(title=esc("Lịch Sử Snapshots An Toàn"))
            snaps = self.safety.list_snapshots()
            if snaps:
                for s in snaps[:5]:
                    row_s = Adw.ActionRow(
                        title=esc(s.get("snapshot_id", "")),
                        subtitle=esc(f"Thời gian: {s.get('created_at', '')} • {len(s.get('backed_up_files', []))} tệp")
                    )
                    btn_r = Gtk.Button(label=esc("Khôi phục"))
                    btn_r.connect("clicked", lambda b, sid=s.get("snapshot_id"): self.on_rollback_clicked(sid, win))
                    row_s.add_suffix(btn_r)
                    group_backup.add(row_s)
            else:
                group_backup.add(Adw.ActionRow(title=esc("Chưa có bản snapshot nào"), subtitle=esc("Snapshot tự động tạo khi bấm Apply")))

            page_backup.add(group_backup)
            win.add(page_backup)

            win.present()

        def on_open_web_clicked(self, button):
            def _launch_web():
                port = 8999
                host = "127.0.0.1"
                url = f"http://{host}:{port}"
                import socket
                is_running = False
                try:
                    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                        is_running = (s.connect_ex((host, port)) == 0)
                except Exception:
                    pass

                if not is_running:
                    cmd = [sys.executable, "-m", "yusei_settings.cli", "--web", "--no-browser"]
                    subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    import time
                    time.sleep(0.5)

                webbrowser.open(url)

            threading.Thread(target=_launch_web, daemon=True).start()

        def on_apply_clicked(self, button, category, item, parent_window):
            impact = self.safety.analyze_impact(category, item["id"], item["file_path"])
            files_desc = "\n".join([f"• {f['action'].upper()}: {f['target']}" for f in impact["affected_files"]])

            dialog = Adw.MessageDialog(
                transient_for=parent_window,
                heading=esc(f"Xác nhận áp dụng: {item['name']}"),
                body=esc(f"Các file cấu hình sẽ được cập nhật:\n{files_desc}\n\nMột bản snapshot sao lưu sẽ tự động được tạo trước khi áp dụng.")
            )
            dialog.add_response("cancel", "Hủy bỏ")
            dialog.add_response("apply", "Xác Nhận Áp Dụng")
            dialog.set_response_appearance("apply", Adw.ResponseAppearance.SUGGESTED)

            def handle_resp(d, response_id):
                if response_id == "apply":
                    res = self.safety.apply_change(category, item["id"], item["file_path"], confirmed=True)
                    # Trigger instant hot-reload
                    if category in ("waybar_layout", "waybar_style"):
                        subprocess.run(["pkill", "-SIGUSR2", "waybar"], check=False)
                    elif category == "kitty_theme":
                        subprocess.run(["pkill", "-SIGUSR1", "kitty"], check=False)
                    elif category == "hyprland_animation":
                        subprocess.run(["hyprctl", "reload", "config-only"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)

                    toast = Adw.Toast(title=esc(f"Đã áp dụng thành công {item['name']}!"))
                    toast.set_button_label("Hoàn tác")
                    toast.connect("button-clicked", lambda t: self.safety.rollback(res.get("snapshot_id")))
                    parent_window.add_toast(toast)

            dialog.connect("response", handle_resp)
            dialog.present()

        def on_rollback_clicked(self, snapshot_id, parent_window):
            res = self.safety.rollback(snapshot_id)
            toast = Adw.Toast(title=esc(f"Đã hoàn tác thành công snapshot {snapshot_id}!"))
            parent_window.add_toast(toast)

    app = YuseiSettingsApp()
    # Pass clean argument vector containing only the application executable
    return app.run([sys.argv[0]])
