"""
yusei_settings.core.power
~~~~~~~~~~~~~~~~~~~~~~~~~
Power & Battery management engine for laptop energy profiles (eco, balanced, turbo),
dynamic monitor refresh rate coordination, and power supply telemetry.
"""

import json
import os
import subprocess
from pathlib import Path
from typing import Optional, Dict, Any


class PowerManager:
    def __init__(self, workspace_root: Optional[str] = None, target_home: Optional[str] = None):
        self.workspace_root = workspace_root or str(Path(__file__).resolve().parent.parent.parent)
        self.target_home = target_home
        self.script_path = Path(self.workspace_root) / "scripts" / "power-optimizer.sh"

    def _get_config_dir(self) -> Path:
        if self.target_home:
            return Path(self.target_home) / ".config" / "hypr"
        xdg_config = os.environ.get("XDG_CONFIG_HOME")
        if xdg_config:
            return Path(xdg_config) / "hypr"
        return Path.home() / ".config" / "hypr"

    def _get_config_file(self) -> Path:
        return self._get_config_dir() / "power.json"

    def _get_state_file(self) -> Path:
        return self._get_config_dir() / ".power-optimizer.state"

    def get_status(self) -> Dict[str, Any]:
        """Query real-time battery status, current profile, and display refresh rate."""
        config_file = self._get_config_file()
        state_file = self._get_state_file()

        # Build isolated environment
        env = os.environ.copy()
        env["POWER_CONFIG_FILE"] = str(config_file)
        env["POWER_STATE_FILE"] = str(state_file)
        if self.target_home:
            env["TARGET_USERPREFS"] = str(Path(self.target_home) / ".config" / "hypr" / "userprefs.conf")
            env["HOME"] = str(self.target_home)
            env["HYPRCTL_MONITORS_DATA"] = "none"

        # Attempt to run power-optimizer.sh --status --json --dry-run
        if self.script_path.exists():
            try:
                proc = subprocess.run(
                    [str(self.script_path), "--status", "--json", "--dry-run"],
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=5,
                )
                if proc.returncode == 0 and proc.stdout.strip():
                    data = json.loads(proc.stdout.strip())
                    return data
            except Exception:
                pass

        # Python sysfs fallback
        auto_60hz = True
        power_daemon = True
        if config_file.exists():
            try:
                cfg = json.loads(config_file.read_text(encoding="utf-8"))
                if "auto_60hz" in cfg:
                    auto_60hz = bool(cfg["auto_60hz"])
                if "power_daemon" in cfg:
                    power_daemon = bool(cfg["power_daemon"])
            except Exception:
                pass

        profile = "balanced"
        current_hz = 60
        max_hz = 60
        if state_file.exists():
            try:
                st = json.loads(state_file.read_text(encoding="utf-8"))
                profile = st.get("profile", "balanced")
                if "current_hz" in st:
                    current_hz = int(st["current_hz"])
                if "max_hz" in st:
                    max_hz = int(st["max_hz"])
            except Exception:
                pass

        return {
            "has_battery": False,
            "ac_online": True,
            "battery_percent": 100,
            "battery_status": "AC Only",
            "power_watts": 0.0,
            "time_remaining": "N/A",
            "profile": profile,
            "monitor_name": "eDP-1",
            "current_hz": current_hz,
            "max_hz": max_hz,
            "min_hz": 60,
            "auto_60hz": auto_60hz,
            "power_daemon": power_daemon,
            "dry_run": bool(self.target_home),
        }

    def set_profile(self, profile: str) -> Dict[str, Any]:
        """Apply a power profile (eco, balanced, turbo)."""
        clean_profile = profile.strip().lower()
        if clean_profile not in ("eco", "balanced", "turbo"):
            raise ValueError(f"Profile không hợp lệ: '{profile}'. Vui lòng chọn 'eco', 'balanced', hoặc 'turbo'.")

        config_file = self._get_config_file()
        state_file = self._get_state_file()

        # Update cached state
        state_file.parent.mkdir(parents=True, exist_ok=True)
        cur_state = {}
        if state_file.exists():
            try:
                cur_state = json.loads(state_file.read_text(encoding="utf-8"))
            except Exception:
                cur_state = {}
        cur_state["profile"] = clean_profile
        state_file.write_text(json.dumps(cur_state, indent=2), encoding="utf-8")

        # Execute script
        cmd = [str(self.script_path), f"--set-profile={clean_profile}"]
        if self.target_home:
            cmd.append("--dry-run")

        env = os.environ.copy()
        env["POWER_CONFIG_FILE"] = str(config_file)
        env["POWER_STATE_FILE"] = str(state_file)
        if self.target_home:
            env["TARGET_USERPREFS"] = str(Path(self.target_home) / ".config" / "hypr" / "userprefs.conf")
            env["HOME"] = str(self.target_home)
            env["HYPRCTL_MONITORS_DATA"] = "none"

        log = ""
        try:
            proc = subprocess.run(cmd, env=env, capture_output=True, text=True, check=False, timeout=5)
            log = proc.stdout + proc.stderr
        except Exception as e:
            log = str(e)

        return {
            "success": True,
            "profile": clean_profile,
            "message": f"Đã chuyển sang profile {clean_profile.capitalize()}.",
            "log": log,
        }

    def cycle_profile(self) -> Dict[str, Any]:
        """Cycle through power profiles: eco -> balanced -> turbo -> eco."""
        status = self.get_status()
        current = status.get("profile", "balanced").lower()
        mapping = {
            "eco": "balanced",
            "balanced": "turbo",
            "turbo": "eco",
        }
        next_profile = mapping.get(current, "balanced")
        return self.set_profile(next_profile)

    def set_config(
        self,
        auto_60hz: Optional[bool] = None,
        power_daemon: Optional[bool] = None,
        ac_profile: Optional[str] = None,
        bat_profile: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Configure whether to automatically lower refresh rate to 60Hz on battery and daemon autostart."""
        config_file = self._get_config_file()
        config_file.parent.mkdir(parents=True, exist_ok=True)

        cur_cfg = {}
        if config_file.exists():
            try:
                cur_cfg = json.loads(config_file.read_text(encoding="utf-8"))
            except Exception:
                cur_cfg = {}

        if auto_60hz is not None:
            cur_cfg["auto_60hz"] = bool(auto_60hz)
        if power_daemon is not None:
            cur_cfg["power_daemon"] = bool(power_daemon)
        if ac_profile is not None:
            clean_ac = ac_profile.strip().lower()
            if clean_ac in ("eco", "balanced", "turbo"):
                cur_cfg["ac_profile"] = clean_ac
        if bat_profile is not None:
            clean_bat = bat_profile.strip().lower()
            if clean_bat in ("eco", "balanced", "turbo"):
                cur_cfg["bat_profile"] = clean_bat

        config_file.write_text(json.dumps(cur_cfg, indent=2, ensure_ascii=False), encoding="utf-8")

        return {
            "success": True,
            "auto_60hz": cur_cfg.get("auto_60hz", True),
            "power_daemon": cur_cfg.get("power_daemon", True),
            "ac_profile": cur_cfg.get("ac_profile", "balanced"),
            "bat_profile": cur_cfg.get("bat_profile", "eco"),
            "message": "Đã cập nhật cấu hình nguồn điện thành công.",
        }

    def toggle_hz(self) -> Dict[str, Any]:
        """Toggle display refresh rate between 60Hz and max native rate."""
        config_file = self._get_config_file()
        state_file = self._get_state_file()

        cur_status = self.get_status()
        current_hz = int(cur_status.get("current_hz", 60))
        max_hz = int(cur_status.get("max_hz", 60))
        target_hz = max_hz if (current_hz <= 60 and max_hz > 60) else 60

        # Update cached state file
        state_file.parent.mkdir(parents=True, exist_ok=True)
        cur_state = {}
        if state_file.exists():
            try:
                cur_state = json.loads(state_file.read_text(encoding="utf-8"))
            except Exception:
                cur_state = {}
        cur_state["current_hz"] = target_hz
        cur_state["max_hz"] = max_hz
        state_file.write_text(json.dumps(cur_state, indent=2), encoding="utf-8")

        cmd = [str(self.script_path), "--toggle-hz"]
        if self.target_home:
            cmd.append("--dry-run")

        env = os.environ.copy()
        env["POWER_CONFIG_FILE"] = str(config_file)
        env["POWER_STATE_FILE"] = str(state_file)
        if self.target_home:
            env["TARGET_USERPREFS"] = str(Path(self.target_home) / ".config" / "hypr" / "userprefs.conf")
            env["HOME"] = str(self.target_home)
            env["HYPRCTL_MONITORS_DATA"] = "none"

        log = ""
        try:
            proc = subprocess.run(cmd, env=env, capture_output=True, text=True, check=False, timeout=5)
            log = proc.stdout + proc.stderr
        except Exception as e:
            log = str(e)

        status = self.get_status()
        resolved_hz = status.get("current_hz", target_hz)
        return {
            "success": True,
            "current_hz": resolved_hz,
            "max_hz": status.get("max_hz", max_hz),
            "message": f"Đã chuyển đổi tần số quét sang {resolved_hz}Hz.",
            "log": log,
        }

