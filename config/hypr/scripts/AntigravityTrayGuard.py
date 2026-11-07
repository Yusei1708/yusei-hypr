#!/usr/bin/env python3
"""
Antigravity System Tray Guard (SNI Persistence Daemon)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Ensures the Antigravity IDE logo stays persistently visible in the Waybar
System Tray across Waybar restarts or Electron StatusNotifierWatcher drops,
matching ChatGPT's persistent tray icon behavior without duplicating icons.
"""

import os
import sys
import signal
import subprocess
import json
from pathlib import Path

try:
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("AppIndicator3", "0.1")
    from gi.repository import Gtk, GLib, AppIndicator3
except Exception:
    sys.exit(0)


class AntigravityTrayGuard:
    def __init__(self):
        self.home = Path.home()
        self.app_bin = str(self.home / "App/Antigravity-x64/antigravity")

        self.indicator = AppIndicator3.Indicator.new(
            "antigravity",
            "antigravity",
            AppIndicator3.IndicatorCategory.APPLICATION_STATUS,
        )
        self.indicator.set_title("Antigravity")

        self.menu = self._build_menu()
        self.indicator.set_menu(self.menu)

        # Immediately evaluate state and then poll cleanly every 2 seconds
        self._sync_tray_state()
        GLib.timeout_add_seconds(2, self._sync_tray_state)

    def _resolve_icon(self) -> str:
        candidates = [
            self.home / ".local/share/icons/hicolor/512x512/apps/antigravity.png",
            self.home / ".local/share/applications/antigravity.png",
            self.home / ".icons/antigravity.png",
        ]
        for c in candidates:
            if c.exists():
                return str(c)
        return "antigravity"

    def _build_menu(self) -> Gtk.Menu:
        menu = Gtk.Menu()

        item_open = Gtk.MenuItem(label="Open Antigravity")
        item_open.connect("activate", self._on_open_clicked)
        menu.append(item_open)

        sep = Gtk.SeparatorMenuItem()
        menu.append(sep)

        item_quit = Gtk.MenuItem(label="Quit")
        item_quit.connect("activate", self._on_quit_clicked)
        menu.append(item_quit)

        menu.show_all()
        # Bind middle/secondary activate target so clicking focuses window
        self.indicator.set_secondary_activate_target(item_open)
        return menu

    @staticmethod
    def _hypr_dispatch(lua_cmd: str, legacy_cmd: str = None) -> bool:
        """Dispatches command using Hyprland 0.57+ Lua syntax with legacy fallback."""
        try:
            res = subprocess.run(
                ["hyprctl", "dispatch", lua_cmd],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=1,
            )
            if "ok" in (res.stdout or "").lower():
                return True
        except Exception:
            pass

        if legacy_cmd:
            try:
                res_leg = subprocess.run(
                    ["hyprctl", "dispatch"] + legacy_cmd.split(),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                    timeout=1,
                )
                return "ok" in (res_leg.stdout or "").lower()
            except Exception:
                pass
        return False

    def _get_antigravity_windows(self) -> list:
        """Retrieves list of active Antigravity windows from Hyprland clients."""
        try:
            out = subprocess.check_output(["hyprctl", "-j", "clients"], timeout=1, text=True)
            clients = json.loads(out)
            return [c for c in clients if "antigravity" in c.get("class", "").lower()]
        except Exception:
            return []

    def _get_antigravity_main_pids(self) -> list:
        """Finds main Antigravity Electron process PIDs (excluding helper/worker processes)."""
        try:
            out = subprocess.check_output(["pgrep", "-f", "/Antigravity-x64/antigravity"], timeout=1, text=True)
            pids = [int(p) for p in out.strip().splitlines() if p.strip().isdigit()]
            main_pids = []
            for p in pids:
                try:
                    with open(f"/proc/{p}/cmdline", "rb") as f:
                        raw = f.read()
                        if b"--type=" not in raw:
                            main_pids.append(p)
                except Exception:
                    pass
            return main_pids
        except Exception:
            return []

    def _on_open_clicked(self, _widget=None):
        try:
            windows = self._get_antigravity_windows()
            if windows:
                win = windows[0]
                addr = win.get("address")
                ws_name = win.get("workspace", {}).get("name") or str(win.get("workspace", {}).get("id"))

                # Switch workspace first if needed
                if ws_name:
                    self._hypr_dispatch(f'hl.dsp.focus({{ workspace = "{ws_name}" }})', f"workspace {ws_name}")

                # Focus window
                if addr:
                    self._hypr_dispatch(f'hl.dsp.focus({{ window = "address:{addr}" }})', f"focuswindow address:{addr}")
                else:
                    self._hypr_dispatch("hl.dsp.focus({ window = 'class:antigravity' })", "focuswindow class:antigravity")
                return

            # No window found in clients; spawn binary or second instance
            if os.path.isfile(self.app_bin):
                env = os.environ.copy()
                subprocess.Popen([self.app_bin], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            if os.path.isfile(self.app_bin):
                subprocess.Popen([self.app_bin], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def _on_quit_clicked(self, _widget=None):
        try:
            # 1. Close active Antigravity windows in Hyprland
            for win in self._get_antigravity_windows():
                addr = win.get("address")
                if addr:
                    self._hypr_dispatch(f'hl.dsp.window.close({{ window = "address:{addr}" }})', f"closewindow address:{addr}")
                else:
                    self._hypr_dispatch("hl.dsp.window.close({ window = 'class:antigravity' })", "closewindow class:antigravity")

            # 2. Send SIGTERM to the main Electron processes to trigger app.quit() cleanly
            main_pids = self._get_antigravity_main_pids()
            for pid in main_pids:
                try:
                    os.kill(pid, signal.SIGTERM)
                except Exception:
                    pass
        except Exception:
            pass

    def _is_antigravity_running(self) -> bool:
        try:
            res = subprocess.run(
                ["pgrep", "-f", "/Antigravity-x64/antigravity"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=1,
            )
            return res.returncode == 0 and bool(res.stdout.strip())
        except Exception:
            return False

    def _has_native_electron_sni(self) -> bool:
        """Checks if Antigravity's own Electron process currently holds a live SNI item."""
        try:
            out = subprocess.check_output(
                [
                    "busctl",
                    "--user",
                    "get-property",
                    "org.kde.StatusNotifierWatcher",
                    "/StatusNotifierWatcher",
                    "org.kde.StatusNotifierWatcher",
                    "RegisteredStatusNotifierItems",
                ],
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=1,
            )
            my_pid = os.getpid()
            import re
            for match in re.finditer(r'":([0-9]+\.[0-9]+)/[^"]+"', out):
                conn = f":{match.group(1)}"
                st = subprocess.check_output(
                    ["busctl", "--user", "status", conn],
                    stderr=subprocess.DEVNULL,
                    text=True,
                    timeout=1,
                )
                pid_m = re.search(r"^PID=(\d+)", st, re.MULTILINE)
                if pid_m and int(pid_m.group(1)) != my_pid:
                    if "Comm=antigravity" in st:
                        return True
        except Exception:
            pass
        return False

    def _sync_tray_state(self) -> bool:
        running = self._is_antigravity_running()
        if not running:
            self.indicator.set_status(AppIndicator3.IndicatorStatus.PASSIVE)
        elif self._has_native_electron_sni():
            # Native Electron tray icon is already registered, stay passive to avoid duplicates
            self.indicator.set_status(AppIndicator3.IndicatorStatus.PASSIVE)
        else:
            # Antigravity is running but its Electron SNI icon dropped/missing -> activate guard icon
            self.indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
        return True


def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    AntigravityTrayGuard()
    Gtk.main()


if __name__ == "__main__":
    main()
