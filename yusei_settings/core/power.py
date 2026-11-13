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
from typing import Optional, Dict, Any, List, Tuple

VALID_PROFILES = ("eco", "balanced", "turbo")
_TRUE_STRINGS = {"true", "1", "yes", "on"}
_FALSE_STRINGS = {"false", "0", "no", "off"}


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

    @staticmethod
    def _parse_strict_bool(value: Any, field_name: str) -> bool:
        """Strictly parse bool or accepted boolean strings; reject anything else."""
        if isinstance(value, bool):
            return value
        if isinstance(value, str):
            norm = value.strip().lower()
            if norm in _TRUE_STRINGS:
                return True
            if norm in _FALSE_STRINGS:
                return False
        raise ValueError(f"Giá trị boolean không hợp lệ cho '{field_name}': {value!r}")

    def _build_env(self, config_file: Path, state_file: Path) -> Dict[str, str]:
        """Build subprocess environment, isolating paths and sysfs when target_home is set."""
        env = os.environ.copy()
        env["POWER_CONFIG_FILE"] = str(config_file)
        env["POWER_STATE_FILE"] = str(state_file)
        if self.target_home:
            home_path = Path(self.target_home)
            resolved_home = home_path.resolve()
            env["HOME"] = str(home_path)
            env["XDG_CONFIG_HOME"] = str(home_path / ".config")
            env["TARGET_USERPREFS"] = str(home_path / ".config" / "hypr" / "userprefs.conf")
            env["HYPRCTL_MONITORS_DATA"] = "none"
            env["POWER_DRY_RUN_PREFER_STATE"] = "1"
            env["POWER_PID_FILE"] = str(home_path / ".cache" / "yusei-power-optimizer.pid")

            for env_key, default_subpath in (
                ("SYSFS_POWER_DIR", home_path / ".sysfs" / "power_supply"),
                ("SYSFS_CPU_DIR", home_path / ".sysfs" / "cpu"),
            ):
                existing = env.get(env_key)
                keep_existing = False
                if existing:
                    try:
                        keep_existing = Path(existing).resolve().is_relative_to(resolved_home)
                    except Exception:
                        keep_existing = False
                if not keep_existing:
                    env[env_key] = str(default_subpath)
        return env

    def _read_config_explicit(self, config_file: Path) -> Dict[str, Any]:
        """Read explicitly configured valid fields from power.json."""
        explicit: Dict[str, Any] = {}
        if not config_file.exists():
            return explicit
        try:
            raw = json.loads(config_file.read_text(encoding="utf-8"))
        except Exception:
            return explicit
        if not isinstance(raw, dict):
            return explicit

        for b_key in ("auto_60hz", "power_daemon"):
            if b_key in raw:
                try:
                    explicit[b_key] = self._parse_strict_bool(raw[b_key], b_key)
                except ValueError:
                    pass
        for p_key in ("ac_profile", "bat_profile"):
            val = raw.get(p_key)
            if isinstance(val, str) and val.strip().lower() in VALID_PROFILES:
                explicit[p_key] = val.strip().lower()
        return explicit

    def _read_config_defaults(self, config_file: Path) -> Dict[str, Any]:
        """Read power.json safely with defaults for all supported config fields."""
        cfg_data: Dict[str, Any] = {
            "auto_60hz": True,
            "power_daemon": True,
            "ac_profile": "balanced",
            "bat_profile": "eco",
        }
        cfg_data.update(self._read_config_explicit(config_file))
        return cfg_data

    @staticmethod
    def _write_state_file(state_file: Path, updates: Dict[str, Any]) -> None:
        """Persist state keys into state_file JSON (used for fallback or sandbox simulation)."""
        state_file.parent.mkdir(parents=True, exist_ok=True)
        cur_state: Dict[str, Any] = {}
        if state_file.exists():
            try:
                loaded = json.loads(state_file.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    cur_state = loaded
            except Exception:
                cur_state = {}
        cur_state.update(updates)
        state_file.write_text(json.dumps(cur_state, indent=2), encoding="utf-8")

    def _run_script(
        self,
        args: List[str],
        config_file: Path,
        state_file: Path,
    ) -> Tuple[bool, str, str]:
        """Execute power-optimizer.sh and return (ok, message_or_empty, combined_log)."""
        cmd = [str(self.script_path), *args]
        if self.target_home:
            cmd.append("--dry-run")
        env = self._build_env(config_file, state_file)

        try:
            proc = subprocess.run(cmd, env=env, capture_output=True, text=True, check=False, timeout=5)
        except subprocess.TimeoutExpired as exc:
            out = exc.stdout.decode("utf-8", errors="ignore") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
            err = exc.stderr.decode("utf-8", errors="ignore") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
            log = (out + err).strip() or str(exc)
            return False, f"power-optimizer.sh quá thời gian thực thi (timeout): {exc}", log
        except Exception as exc:
            return False, f"Lỗi khi thực thi power-optimizer.sh: {exc}", str(exc)

        log = (proc.stdout or "") + (proc.stderr or "")
        if proc.returncode != 0:
            return False, f"power-optimizer.sh thất bại (mã thoát {proc.returncode}).", log
        return True, "", log

    def get_status(self) -> Dict[str, Any]:
        """Query real-time battery status, current profile, and display refresh rate."""
        config_file = self._get_config_file()
        state_file = self._get_state_file()
        cfg_defaults = self._read_config_defaults(config_file)

        if self.script_path.exists():
            cmd = [str(self.script_path), "--status", "--json"]
            if self.target_home:
                cmd.append("--dry-run")
            env = self._build_env(config_file, state_file)
            try:
                proc = subprocess.run(
                    cmd,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=5,
                )
                if proc.returncode == 0 and proc.stdout.strip():
                    data = json.loads(proc.stdout.strip())
                    if isinstance(data, dict):
                        explicit_cfg = self._read_config_explicit(config_file)
                        for key, val in explicit_cfg.items():
                            # Env var YUSEI_AUTO_60HZ overrides file config for auto_60hz in power-optimizer.sh
                            if key == "auto_60hz" and os.environ.get("YUSEI_AUTO_60HZ"):
                                continue
                            data[key] = val
                        data.setdefault("ac_profile", cfg_defaults["ac_profile"])
                        data.setdefault("bat_profile", cfg_defaults["bat_profile"])
                        return data
            except Exception:
                pass

        # Python fallback when script is absent or failed
        profile = "balanced"
        current_hz = 60
        max_hz = 60
        if state_file.exists():
            try:
                st = json.loads(state_file.read_text(encoding="utf-8"))
                if isinstance(st, dict):
                    st_prof = st.get("profile", "balanced")
                    if isinstance(st_prof, str) and st_prof.strip().lower() in VALID_PROFILES:
                        profile = st_prof.strip().lower()
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
            "auto_60hz": cfg_defaults["auto_60hz"],
            "power_daemon": cfg_defaults["power_daemon"],
            "ac_profile": cfg_defaults["ac_profile"],
            "bat_profile": cfg_defaults["bat_profile"],
            "dry_run": bool(self.target_home),
        }

    def set_profile(self, profile: str) -> Dict[str, Any]:
        """Apply a power profile (eco, balanced, turbo)."""
        if not isinstance(profile, str) or profile.strip().lower() not in VALID_PROFILES:
            raise ValueError(f"Profile không hợp lệ: '{profile}'. Vui lòng chọn 'eco', 'balanced', hoặc 'turbo'.")
        clean_profile = profile.strip().lower()

        config_file = self._get_config_file()
        state_file = self._get_state_file()

        if not self.script_path.exists():
            self._write_state_file(state_file, {"profile": clean_profile})
            return {
                "success": True,
                "profile": clean_profile,
                "fallback": True,
                "message": (
                    f"Đã lưu profile {clean_profile.capitalize()} "
                    "(fallback: không tìm thấy power-optimizer.sh, chỉ cập nhật state cục bộ)."
                ),
                "log": f"Fallback: script not found at {self.script_path}; updated state file {state_file}.",
            }

        ok, err_msg, log = self._run_script([f"--set-profile={clean_profile}"], config_file, state_file)
        if not ok:
            return {
                "success": False,
                "message": err_msg,
                "log": log,
            }

        # Under target_home (--dry-run), power-optimizer.sh skips writing state; persist sandbox state after success.
        if self.target_home:
            self._write_state_file(state_file, {"profile": clean_profile})

        return {
            "success": True,
            "profile": clean_profile,
            "message": f"Đã chuyển sang profile {clean_profile.capitalize()}.",
            "log": log,
        }

    def cycle_profile(self) -> Dict[str, Any]:
        """Cycle through power profiles: eco -> balanced -> turbo -> eco."""
        status = self.get_status()
        current = str(status.get("profile", "balanced")).lower()
        mapping = {
            "eco": "balanced",
            "balanced": "turbo",
            "turbo": "eco",
        }
        next_profile = mapping.get(current, "balanced")
        return self.set_profile(next_profile)

    def set_config(
        self,
        auto_60hz: Optional[Any] = None,
        power_daemon: Optional[Any] = None,
        ac_profile: Optional[str] = None,
        bat_profile: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Configure auto 60Hz on battery, daemon autostart, and default AC/battery profiles."""
        updates: Dict[str, Any] = {}
        try:
            if auto_60hz is not None:
                updates["auto_60hz"] = self._parse_strict_bool(auto_60hz, "auto_60hz")
            if power_daemon is not None:
                updates["power_daemon"] = self._parse_strict_bool(power_daemon, "power_daemon")
        except ValueError as exc:
            return {"success": False, "message": str(exc)}

        for field_name, prof_val in (("ac_profile", ac_profile), ("bat_profile", bat_profile)):
            if prof_val is not None:
                if not isinstance(prof_val, str) or prof_val.strip().lower() not in VALID_PROFILES:
                    return {
                        "success": False,
                        "message": (
                            f"Profile không hợp lệ cho '{field_name}': {prof_val!r}. "
                            "Vui lòng chọn 'eco', 'balanced', hoặc 'turbo'."
                        ),
                    }
                updates[field_name] = prof_val.strip().lower()

        config_file = self._get_config_file()
        config_file.parent.mkdir(parents=True, exist_ok=True)

        cur_cfg: Dict[str, Any] = {}
        if config_file.exists():
            try:
                loaded = json.loads(config_file.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    cur_cfg = loaded
            except Exception:
                cur_cfg = {}

        cur_cfg.update(updates)
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

        if not self.script_path.exists():
            self._write_state_file(state_file, {"current_hz": target_hz, "max_hz": max_hz})
            return {
                "success": True,
                "current_hz": target_hz,
                "max_hz": max_hz,
                "fallback": True,
                "message": (
                    f"Đã lưu tần số quét {target_hz}Hz "
                    "(fallback: không tìm thấy power-optimizer.sh, chỉ cập nhật state cục bộ)."
                ),
                "log": (
                    f"Fallback: script not found at {self.script_path}; "
                    f"updated current_hz={target_hz}, max_hz={max_hz} in {state_file}."
                ),
            }

        ok, err_msg, log = self._run_script(["--toggle-hz"], config_file, state_file)
        if not ok:
            return {
                "success": False,
                "message": err_msg,
                "log": log,
            }

        # Under target_home (--dry-run), power-optimizer.sh skips writing state; persist sandbox state after success.
        if self.target_home:
            self._write_state_file(state_file, {"current_hz": target_hz, "max_hz": max_hz})

        status = self.get_status()
        resolved_hz = int(status.get("current_hz", target_hz))
        resolved_max = int(status.get("max_hz", max_hz))
        return {
            "success": True,
            "current_hz": resolved_hz,
            "max_hz": resolved_max,
            "message": f"Đã chuyển đổi tần số quét sang {resolved_hz}Hz.",
            "log": log,
        }
