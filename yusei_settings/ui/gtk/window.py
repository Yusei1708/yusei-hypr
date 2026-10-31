"""
Native Libadwaita & GTK4 Settings Window
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Provides modern GNOME / Libadwaita preferences window with cards,
switch rows, action buttons, and safety confirmation dialogs.
"""

import sys
from typing import Optional

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

    class YuseiSettingsApp(Adw.Application):
        def __init__(self):
            super().__init__(application_id="io.github.yusei.Settings", flags=Gio.ApplicationFlags.FLAGS_NONE)
            self.discovery = DiscoveryEngine(workspace_root)
            self.state_mgr = StateManager(target_home)
            self.safety = SafetyEngine(target_home)
            self.power_mgr = PowerManager(workspace_root, target_home)

        def do_activate(self):
            win = Adw.PreferencesWindow(application=self, title="Cài Đặt Hệ Thống (yusei-settings)")
            win.set_default_size(960, 680)

            # -----------------------------------------------------------------
            # PAGE 1: Giao diện & Layout
            # -----------------------------------------------------------------
            page_appearance = Adw.PreferencesPage(
                title="Giao diện & Layout",
                icon_name="preferences-desktop-theme-symbolic"
            )

            group_waybar = Adw.PreferencesGroup(title="Thanh Trạng Thái Waybar (Layouts)")
            catalog = self.discovery.discover_all()
            active = self.state_mgr.get_active_state()

            for item in catalog.get("waybar_layouts", [])[:8]:
                row = Adw.ActionRow(
                    title=item["name"],
                    subtitle=f"{item['position']} • {item['description']}"
                )
                btn = Gtk.Button(label="Áp dụng")
                btn.add_css_class("suggested-action")
                btn.connect("clicked", self.on_apply_clicked, "waybar_layout", item, win)
                row.add_suffix(btn)
                group_waybar.add(row)

            page_appearance.add(group_waybar)

            group_kitty = Adw.PreferencesGroup(title="Bảng Màu Terminal Kitty (Themes)")
            for item in catalog.get("kitty_themes", [])[:6]:
                row = Adw.ActionRow(
                    title=item["name"],
                    subtitle=item["description"]
                )
                btn = Gtk.Button(label="Áp dụng")
                btn.connect("clicked", self.on_apply_clicked, "kitty_theme", item, win)
                row.add_suffix(btn)
                group_kitty.add(row)

            page_appearance.add(group_kitty)
            win.add(page_appearance)

            # -----------------------------------------------------------------
            # PAGE 2: Hyprland
            # -----------------------------------------------------------------
            page_hyprland = Adw.PreferencesPage(
                title="Hyprland",
                icon_name="preferences-system-windows-symbolic"
            )
            group_hypr = Adw.PreferencesGroup(title="Hiệu Ứng & Bo Góc Cửa Sổ")
            row_round = Adw.ActionRow(title="Bo góc cửa sổ (Rounding)", subtitle="Mặc định chuẩn 16px")
            row_round.add_suffix(Gtk.Label(label="16px"))
            group_hypr.add(row_round)

            row_blur = Adw.SwitchRow(title="Làm mờ nền (Dual-pass Kawase Blur)", active=True)
            group_hypr.add(row_blur)
            page_hyprland.add(group_hypr)
            win.add(page_hyprland)

            # -----------------------------------------------------------------
            # PAGE: Nguồn điện & Pin
            # -----------------------------------------------------------------
            page_power = Adw.PreferencesPage(
                title="Nguồn điện & Pin",
                icon_name="battery-symbolic"
            )
            group_power_status = Adw.PreferencesGroup(title="Giám Sát Nguồn & Pin")
            power_st = self.power_mgr.get_status()
            row_bat = Adw.ActionRow(
                title="Dung lượng pin & Nguồn",
                subtitle=f"{power_st.get('battery_percent', 100)}% ({power_st.get('battery_status', 'AC Only')}) • {'Cắm sạc AC' if power_st.get('ac_online') else 'Dùng pin'}"
            )
            group_power_status.add(row_bat)

            row_rate = Adw.ActionRow(
                title="Màn hình & Tần số quét",
                subtitle=f"{power_st.get('monitor_name', 'Display')} • {power_st.get('current_hz', 60)} Hz (Tối đa: {power_st.get('max_hz', 60)} Hz)"
            )
            group_power_status.add(row_rate)
            page_power.add(group_power_status)

            group_profiles = Adw.PreferencesGroup(title="Profile Năng Lượng")
            for p_id, p_name, p_desc in [
                ("eco", "Tiết kiệm điện (Eco)", "Hạ xung nhịp CPU, giảm màn hình về 60Hz"),
                ("balanced", "Cân bằng (Balanced)", "Tự động cân bằng hiệu năng và tiêu thụ điện"),
                ("turbo", "Hiệu năng tối đa (Turbo)", "Xung nhịp CPU tối đa, tần số quét cao nhất")
            ]:
                row_p = Adw.ActionRow(title=p_name, subtitle=p_desc)
                btn_p = Gtk.Button(label="Kích hoạt")
                btn_p.connect("clicked", lambda b, prof=p_id: self.power_mgr.set_profile(prof))
                row_p.add_suffix(btn_p)
                group_profiles.add(row_p)
            page_power.add(group_profiles)

            group_power_cfg = Adw.PreferencesGroup(title="Tùy Chọn Tần Số Quét")
            row_auto_60hz = Adw.SwitchRow(
                title="Tự động hạ màn hình xuống 60Hz khi rút sạc",
                subtitle="Khôi phục tần số quét cao khi cắm sạc",
                active=power_st.get("auto_60hz", True)
            )
            row_auto_60hz.connect("notify::active", lambda w, p: self.power_mgr.set_config(w.get_active()))
            group_power_cfg.add(row_auto_60hz)

            row_toggle_hz = Adw.ActionRow(
                title="Chuyển đổi tần số quét thủ công",
                subtitle="Chuyển đổi qua lại giữa 60Hz và tần số quét tối đa của màn hình"
            )
            btn_toggle_hz = Gtk.Button(label="Chuyển đổi Hz")
            btn_toggle_hz.connect("clicked", lambda b: self.power_mgr.toggle_hz())
            row_toggle_hz.add_suffix(btn_toggle_hz)
            group_power_cfg.add(row_toggle_hz)

            page_power.add(group_power_cfg)
            win.add(page_power)

            # -----------------------------------------------------------------
            # PAGE 3: Ứng dụng
            # -----------------------------------------------------------------
            page_apps = Adw.PreferencesPage(
                title="Ứng dụng",
                icon_name="system-run-symbolic"
            )
            group_apps = Adw.PreferencesGroup(title="Ứng Dụng Mặc Định")
            group_apps.add(Adw.ActionRow(title="Terminal ($term)", subtitle="Kitty"))
            group_apps.add(Adw.ActionRow(title="Trình quản lý tệp ($files)", subtitle="Thunar"))
            page_apps.add(group_apps)
            win.add(page_apps)

            # -----------------------------------------------------------------
            # PAGE 4: Sao lưu & Khôi phục
            # -----------------------------------------------------------------
            page_backup = Adw.PreferencesPage(
                title="Sao lưu & Khôi phục",
                icon_name="drive-harddisk-symbolic"
            )
            group_backup = Adw.PreferencesGroup(title="Lịch Sử Snapshots An Toàn")
            snaps = self.safety.list_snapshots()
            if snaps:
                for s in snaps[:5]:
                    row_s = Adw.ActionRow(
                        title=s.get("snapshot_id", ""),
                        subtitle=f"Thời gian: {s.get('created_at', '')} • {len(s.get('backed_up_files', []))} tệp"
                    )
                    btn_r = Gtk.Button(label="Khôi phục")
                    btn_r.connect("clicked", lambda b, sid=s.get("snapshot_id"): self.on_rollback_clicked(sid, win))
                    row_s.add_suffix(btn_r)
                    group_backup.add(row_s)
            else:
                group_backup.add(Adw.ActionRow(title="Chưa có bản snapshot nào", subtitle="Snapshot tự động tạo khi bấm Apply"))

            page_backup.add(group_backup)
            win.add(page_backup)

            win.present()

        def on_apply_clicked(self, button, category, item, parent_window):
            impact = self.safety.analyze_impact(category, item["id"], item["file_path"])
            files_desc = "\n".join([f"• {f['action'].upper()}: {f['target']}" for f in impact["affected_files"]])

            dialog = Adw.MessageDialog(
                transient_for=parent_window,
                heading=f"Xác nhận áp dụng: {item['name']}",
                body=f"Các file cấu hình sẽ được cập nhật:\n{files_desc}\n\nMột bản snapshot sao lưu sẽ tự động được tạo trước khi áp dụng."
            )
            dialog.add_response("cancel", "Hủy bỏ")
            dialog.add_response("apply", "Xác Nhận Áp Dụng")
            dialog.set_response_appearance("apply", Adw.ResponseAppearance.SUGGESTED)

            def handle_resp(d, response_id):
                if response_id == "apply":
                    res = self.safety.apply_change(category, item["id"], item["file_path"], confirmed=True)
                    toast = Adw.Toast(title=f"Đã áp dụng thành công {item['name']}!")
                    toast.set_button_label("Hoàn tác")
                    toast.connect("button-clicked", lambda t: self.safety.rollback(res.get("snapshot_id")))
                    parent_window.add_toast(toast)

            dialog.connect("response", handle_resp)
            dialog.present()

        def on_rollback_clicked(self, snapshot_id, parent_window):
            res = self.safety.rollback(snapshot_id)
            toast = Adw.Toast(title=f"Đã hoàn tác thành công snapshot {snapshot_id}!")
            parent_window.add_toast(toast)

    app = YuseiSettingsApp()
    return app.run(sys.argv)
