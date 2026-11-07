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

    def _on_open_clicked(self, _widget):
        try:
            res = subprocess.run(
                ["hyprctl", "dispatch", "focuswindow", "class:^(antigravity|Antigravity)$"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=2,
            )
            if "ok" not in (res.stdout or "").lower():
                if os.path.isfile(self.app_bin):
                    subprocess.Popen([self.app_bin], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

    def _on_quit_clicked(self, _widget):
        try:
            subprocess.run(
                ["hyprctl", "dispatch", "closewindow", "class:^(antigravity|Antigravity)$"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=2,
            )
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
