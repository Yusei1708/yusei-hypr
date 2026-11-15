"""
yusei_settings.core.decorations
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Hyprland decoration, frosted-glass opacity, and Dual-pass Kawase Blur engine.

Supports:
- Reading merged live compositor state (`hyprctl getoption`) + user configs
- Strict type & finite-range validation (HTTP 400 safe)
- Surgical atomic updates to `UserConfigs/UserDecorations.conf` (preserving comments & unrelated options)
- Managed `UserConfigs/yusei-decorations.lua` for persistent global window opacity override across reloads/reboots
- Fast 0.57+ Lua (`hyprctl eval`) live application with legacy `hyprctl --batch keyword` fallback
- Full `target_home` / `XDG_CONFIG_HOME` sandbox isolation for safe testing
"""

import math
import os
import re
import stat
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


_TRUE_STRINGS = {"true", "1", "yes", "on"}
_FALSE_STRINGS = {"false", "0", "no", "off"}

# Tuple format:
# (field_type, min_val, max_val, step, decimals, hypr_option, conf_block, conf_key, default_val, label)
DECORATION_SCHEMA: Dict[str, Tuple[type, Any, Any, Any, int, Optional[str], Optional[str], Optional[str], Any, str]] = {
    "rounding": (int, 0, 30, 1, 0, "decoration:rounding", "decoration", "rounding", 10, "Bo góc cửa sổ"),
    "active_opacity": (float, 0.30, 1.00, 0.01, 2, "decoration:active_opacity", "decoration", "active_opacity", 0.90, "Độ mờ cửa sổ Active"),
    "inactive_opacity": (float, 0.30, 1.00, 0.01, 2, "decoration:inactive_opacity", "decoration", "inactive_opacity", 0.90, "Độ mờ cửa sổ Inactive"),
    "fullscreen_opacity": (float, 0.30, 1.00, 0.01, 2, "decoration:fullscreen_opacity", "decoration", "fullscreen_opacity", 1.00, "Độ mờ toàn màn hình"),
    "override_all_apps": (bool, False, True, 1, 0, None, None, None, True, "Ghi đè toàn bộ ứng dụng"),
    "blur_enabled": (bool, False, True, 1, 0, "decoration:blur:enabled", "blur", "enabled", True, "Bật làm mờ nền (Blur)"),
    "blur_size": (int, 1, 20, 1, 0, "decoration:blur:size", "blur", "size", 5, "Độ rộng vùng mờ (Size)"),
    "blur_passes": (int, 1, 6, 1, 0, "decoration:blur:passes", "blur", "passes", 2, "Số lớp lọc mịn (Passes)"),
    "blur_brightness": (float, 0.30, 1.50, 0.01, 2, "decoration:blur:brightness", "blur", "brightness", 1.00, "Độ sáng nền mờ"),
    "blur_contrast": (float, 0.30, 1.50, 0.01, 2, "decoration:blur:contrast", "blur", "contrast", 0.89, "Độ tương phản mờ"),
    "blur_vibrancy": (float, 0.00, 1.00, 0.01, 2, "decoration:blur:vibrancy", "blur", "vibrancy", 0.17, "Độ rực màu kính mờ"),
    "blur_noise": (float, 0.000, 0.100, 0.005, 3, "decoration:blur:noise", "blur", "noise", 0.012, "Hạt nhiễu kính (Noise)"),
    "blur_xray": (bool, False, True, 1, 0, "decoration:blur:xray", "blur", "xray", True, "Xuyên thấu wallpaper (X-Ray)"),
    "blur_ignore_opacity": (bool, False, True, 1, 0, "decoration:blur:ignore_opacity", "blur", "ignore_opacity", True, "Blur bỏ qua alpha cửa sổ"),
}

OPACITY_PRESETS: List[Dict[str, Any]] = [
    {"id": "glass_deep", "label": "0.70 (Kính sâu)", "value": 0.70},
    {"id": "glass_frosted", "label": "0.80 (Mờ rõ)", "value": 0.80},
    {"id": "glass_balanced", "label": "0.85 (Cân bằng)", "value": 0.85},
    {"id": "glass_default", "label": "0.90 (Mặc định)", "value": 0.90},
    {"id": "glass_subtle", "label": "0.95 (Nhẹ)", "value": 0.95},
    {"id": "opaque", "label": "1.00 (Đặc)", "value": 1.00},
]

BLUR_PRESETS: List[Dict[str, Any]] = [
    {"id": "blur_light", "label": "Nhẹ (2×1)", "blur_size": 2, "blur_passes": 1},
    {"id": "blur_default", "label": "Mặc định (5×2)", "blur_size": 5, "blur_passes": 2},
    {"id": "blur_smooth", "label": "Mịn (6×3)", "blur_size": 6, "blur_passes": 3},
    {"id": "blur_deep", "label": "Sâu (10×4)", "blur_size": 10, "blur_passes": 4},
]

_CONF_BLOCK_LOOKUP: Dict[Tuple[str, str], str] = {
    (spec[6], spec[7]): key
    for key, spec in DECORATION_SCHEMA.items()
    if spec[6] is not None and spec[7] is not None
}

_ANY_BLOCK_OPEN_RE = re.compile(r"^([ \t]*)([A-Za-z0-9_.:-]+)\s*\{(.*)$")
_KEY_VAL_RE = re.compile(r"^([ \t]*)([A-Za-z0-9_.:-]+)(\s*=\s*)([^\s#]+)(.*)$")


def split_line_comment(line: str) -> Tuple[str, str, str]:
    """Splits a config line into (code_part, comment_part, newline)."""
    nl = "\n" if line.endswith("\n") else ""
    raw = line[:-1] if nl else line
    if "#" in raw:
        idx = raw.index("#")
        return raw[:idx], raw[idx:], nl
    return raw, "", nl


def atomic_write_text(path: Path, content: str) -> None:
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


def get_default_state() -> Dict[str, Any]:
    """Returns a fresh copy of the default decoration configuration."""
    return {key: spec[8] for key, spec in DECORATION_SCHEMA.items()}


def get_schema_bounds() -> Dict[str, Dict[str, Any]]:
    """Returns UI/API metadata (min, max, step, decimals, type, default, label) per field."""
    bounds: Dict[str, Dict[str, Any]] = {}
    for key, (ftype, mn, mx, step, dec, _hopt, _blk, _ckey, default, label) in DECORATION_SCHEMA.items():
        type_name = "bool" if ftype is bool else ("int" if ftype is int else "float")
        bounds[key] = {
            "type": type_name,
            "min": mn,
            "max": mx,
            "step": step,
            "decimals": dec,
            "default": default,
            "label": label,
        }
    return bounds


def _coerce_field_value(key: str, value: Any) -> Any:
    """Validates and normalizes a single schema field value; raises ValueError on invalid input."""
    if key not in DECORATION_SCHEMA:
        raise ValueError(f"Tham số không được hỗ trợ: '{key}'")
    ftype, mn, mx, _step, dec, _hopt, _blk, _ckey, _default, _label = DECORATION_SCHEMA[key]

    if ftype is bool:
        if isinstance(value, bool):
            return value
        if isinstance(value, str):
            norm = value.strip().lower()
            if norm in _TRUE_STRINGS:
                return True
            if norm in _FALSE_STRINGS:
                return False
        raise ValueError(f"Giá trị boolean không hợp lệ cho '{key}': {value!r}")

    if ftype is int:
        if isinstance(value, bool):
            raise ValueError(f"Giá trị số nguyên không hợp lệ cho '{key}': {value!r}")
        if isinstance(value, int):
            num = value
        elif isinstance(value, float):
            if not math.isfinite(value) or not value.is_integer():
                raise ValueError(f"'{key}' yêu cầu số nguyên, nhận {value!r}")
            num = int(value)
        elif isinstance(value, str):
            s = value.strip()
            try:
                num = int(s)
            except ValueError as exc:
                raise ValueError(f"Giá trị số nguyên không hợp lệ cho '{key}': {value!r}") from exc
        else:
            raise ValueError(f"Giá trị số nguyên không hợp lệ cho '{key}': {value!r}")

        if num < mn or num > mx:
            raise ValueError(f"'{key}' phải nằm trong khoảng [{mn}, {mx}], nhận {num}")
        return num

    # float field
    if isinstance(value, bool):
        raise ValueError(f"Giá trị số thực không hợp lệ cho '{key}': {value!r}")
    try:
        num_f = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"Giá trị số thực không hợp lệ cho '{key}': {value!r}") from exc

    if not math.isfinite(num_f):
        raise ValueError(f"'{key}' phải là số hữu hạn")
    if num_f < mn or num_f > mx:
        raise ValueError(f"'{key}' phải nằm trong khoảng [{mn:.2f}, {mx:.2f}], nhận {num_f}")
    return round(num_f, dec)


def format_conf_value(key: str, value: Any) -> str:
    """Formats a normalized schema value for Hyprland .conf/.lua syntax."""
    spec = DECORATION_SCHEMA[key]
    ftype, dec = spec[0], spec[4]
    if ftype is bool:
        return "true" if value else "false"
    if ftype is int:
        return str(int(value))
    return f"{float(value):.{dec}f}"


def parse_hypr_bool_option(out: str) -> Optional[bool]:
    """Parses Hyprland getoption output across 0.57+ (`bool: true/false`) and legacy (`int: 1/0`)."""
    m_bool = re.search(r"\bbool:\s*(true|false|yes|no|1|0)\b", out, re.IGNORECASE)
    if m_bool:
        return m_bool.group(1).lower() in _TRUE_STRINGS
    m_int = re.search(r"\bint:\s*(\d+)\b", out)
    if m_int:
        return int(m_int.group(1)) != 0
    return None


def parse_hypr_number_option(out: str, is_int: bool) -> Optional[Any]:
    """Parses Hyprland getoption numeric output (`int:` or `float:`)."""
    if is_int:
        m = re.search(r"\bint:\s*(-?\d+)\b", out)
        return int(m.group(1)) if m else None
    m_f = re.search(r"\bfloat:\s*(-?\d+(?:\.\d+)?)\b", out)
    if m_f:
        val = float(m_f.group(1))
        return val if math.isfinite(val) else None
    m_i = re.search(r"\bint:\s*(-?\d+)\b", out)
    if m_i:
        return float(int(m_i.group(1)))
    return None


def _parse_inline_kv(inside: str, block_name: str, parsed: Dict[str, Any]) -> None:
    """Parses key=value pairs from a single-line Hyprland block like `blur { enabled = false }`."""
    for seg in inside.replace(";", "\n").splitlines():
        m = _KEY_VAL_RE.match(seg.strip())
        if not m:
            continue
        ckey = m.group(2)
        cval = m.group(4)
        schema_key = _CONF_BLOCK_LOOKUP.get((block_name, ckey))
        if schema_key:
            try:
                parsed[schema_key] = _coerce_field_value(schema_key, cval)
            except ValueError:
                pass


def parse_decorations_text(text: str) -> Dict[str, Any]:
    """Extracts all recognized decoration and blur keys from Hyprland config text."""
    parsed: Dict[str, Any] = {}
    stack: List[str] = []

    for line in text.splitlines():
        code, _comment, _nl = split_line_comment(line)
        stripped = code.strip()
        if not stripped:
            continue

        if stripped == "}":
            if stack:
                stack.pop()
            continue

        m_blk = _ANY_BLOCK_OPEN_RE.match(code)
        if m_blk:
            blk_name = m_blk.group(2)
            rest = m_blk.group(3)
            delta = code.count("{") - code.count("}")
            if delta <= 0 and "}" in rest:
                inside = rest.split("}", 1)[0]
                if blk_name == "blur" and stack == ["decoration"]:
                    _parse_inline_kv(inside, "blur", parsed)
                elif blk_name == "decoration" and not stack:
                    _parse_inline_kv(inside, "decoration", parsed)
            else:
                stack.append(blk_name)
            continue

        m_kv = _KEY_VAL_RE.match(code)
        if m_kv:
            ckey = m_kv.group(2)
            cval = m_kv.group(4)
            cur_blk = stack[-1] if stack else ""
            if stack == ["decoration"] and cur_blk == "decoration":
                schema_key = _CONF_BLOCK_LOOKUP.get(("decoration", ckey))
            elif stack == ["decoration", "blur"]:
                schema_key = _CONF_BLOCK_LOOKUP.get(("blur", ckey))
            else:
                schema_key = None

            if schema_key:
                try:
                    parsed[schema_key] = _coerce_field_value(schema_key, cval)
                except ValueError:
                    pass

        for _ in range(max(0, code.count("}") - code.count("{"))):
            if stack:
                stack.pop()

    return parsed


def _append_inside_block(text: str, target_stack: Tuple[str, ...], inner_lines: List[str]) -> str:
    """Inserts lines cleanly before the closing brace of the first matching block, or creates it."""
    if not inner_lines:
        return text

    lines = text.splitlines(keepends=True)
    stack: List[str] = []
    match_depth: Optional[int] = None
    match_indent = ""
    child_indent: Optional[str] = None

    for idx, line in enumerate(lines):
        code, comment, nl = split_line_comment(line)
        stripped = code.strip()

        if match_depth is None:
            m_blk = _ANY_BLOCK_OPEN_RE.match(code)
            if m_blk:
                blk_indent = m_blk.group(1)
                blk_name = m_blk.group(2)
                rest = m_blk.group(3)
                cand_stack = tuple(stack + [blk_name])
                delta = code.count("{") - code.count("}")

                if cand_stack == target_stack:
                    if delta <= 0 and "}" in rest:
                        before_close, close_and_after = rest.split("}", 1)
                        extra = before_close.strip()
                        indent = f"{blk_indent}    "
                        body = "".join(f"{indent}{item}\n" for item in inner_lines)
                        if extra:
                            body = f"{indent}{extra}\n{body}"
                        lines[idx] = f"{blk_indent}{blk_name} {{\n{body}{blk_indent}}}{close_and_after}{comment}{nl}"
                        return "".join(lines)
                    match_depth = len(stack)
                    match_indent = blk_indent
                    stack.append(blk_name)
                    continue

                if delta > 0:
                    stack.append(blk_name)
                continue

            if stripped == "}" and stack:
                stack.pop()
                continue
            if "}" in code or "{" in code:
                for _ in range(max(0, code.count("{") - code.count("}"))):
                    stack.append("_anon")
                for _ in range(max(0, code.count("}") - code.count("{"))):
                    if stack:
                        stack.pop()
                continue
        else:
            if child_indent is None and stripped and not stripped.startswith("}"):
                child_indent = code[: len(code) - len(code.lstrip())]
            if stripped == "}":
                stack.pop()
            else:
                m_sub = _ANY_BLOCK_OPEN_RE.match(code)
                if m_sub and (code.count("{") - code.count("}")) > 0:
                    stack.append(m_sub.group(2))
                else:
                    for _ in range(max(0, code.count("}") - code.count("{"))):
                        if stack:
                            stack.pop()

            if len(stack) <= match_depth:
                indent = child_indent or f"{match_indent}    "
                inserted = [f"{indent}{item}\n" for item in inner_lines]
                lines[idx:idx] = inserted
                return "".join(lines)

    if len(target_stack) == 2 and target_stack[0] == "decoration":
        nested = [f"{target_stack[1]} {{"] + [f"    {item}" for item in inner_lines] + ["}"]
        return _append_inside_block(text, ("decoration",), nested)

    sep = "" if (not text or text.endswith("\n\n")) else ("\n" if text.endswith("\n") else "\n\n")
    blk = target_stack[0]
    body = "".join(f"    {item}\n" for item in inner_lines)
    return f"{text}{sep}{blk} {{\n{body}}}\n"


def _upsert_block_kv(text: str, target_stack: Tuple[str, ...], conf_updates: Dict[str, str]) -> str:
    """Replaces existing key=value lines in `target_stack` in-place and appends missing ones."""
    if not conf_updates:
        return text

    remaining = dict(conf_updates)
    lines = text.splitlines(keepends=True)
    stack: List[str] = []

    for idx, line in enumerate(lines):
        if not remaining:
            break
        code, comment, nl = split_line_comment(line)
        stripped = code.strip()
        if not stripped:
            continue

        m_blk = _ANY_BLOCK_OPEN_RE.match(code)
        if m_blk:
            blk = m_blk.group(2)
            rest = m_blk.group(3)
            delta = code.count("{") - code.count("}")
            if delta <= 0 and "}" in rest and tuple(stack + [blk]) == target_stack:
                before_close, close_and_after = rest.split("}", 1)
                replaced_inline = before_close
                for ckey in list(remaining.keys()):
                    pattern = re.compile(rf"(\b{re.escape(ckey)}\s*=\s*)[^\s;}}#]+", re.IGNORECASE)
                    if pattern.search(replaced_inline):
                        cval = remaining.pop(ckey)
                        replaced_inline = pattern.sub(rf"\g<1>{cval}", replaced_inline, count=1)
                lines[idx] = f"{m_blk.group(1)}{blk} {{{replaced_inline}}}{close_and_after}{comment}{nl}"
            elif delta > 0:
                stack.append(blk)
            continue

        if stripped == "}":
            if stack:
                stack.pop()
            continue

        if tuple(stack) == target_stack:
            m_kv = _KEY_VAL_RE.match(code)
            if m_kv and m_kv.group(2) in remaining:
                ckey = m_kv.group(2)
                cval = remaining.pop(ckey)
                lines[idx] = f"{m_kv.group(1)}{ckey}{m_kv.group(3)}{cval}{m_kv.group(5)}{comment}{nl}"
                continue

        for _ in range(max(0, code.count("}") - code.count("{"))):
            if stack:
                stack.pop()

    updated = "".join(lines)
    if remaining:
        missing_lines = [f"{k} = {v}" for k, v in conf_updates.items() if k in remaining]
        updated = _append_inside_block(updated, target_stack, missing_lines)
    return updated


def update_decorations_text(text: str, updates: Dict[str, Any]) -> str:
    """Surgically updates requested schema keys inside `UserDecorations.conf` text."""
    dec_kv: Dict[str, str] = {}
    blur_kv: Dict[str, str] = {}
    for key, val in updates.items():
        if key not in DECORATION_SCHEMA or val is None:
            continue
        spec = DECORATION_SCHEMA[key]
        block, ckey = spec[6], spec[7]
        if block == "decoration" and ckey is not None:
            dec_kv[ckey] = format_conf_value(key, val)
        elif block == "blur" and ckey is not None:
            blur_kv[ckey] = format_conf_value(key, val)

    result = _upsert_block_kv(text, ("decoration",), dec_kv)
    result = _upsert_block_kv(result, ("decoration", "blur"), blur_kv)
    return result


class DecorationsManager:
    """Coordinates Hyprland glass blur/opacity state, persistence, and live application."""

    def __init__(self, workspace_root: Optional[str] = None, target_home: Optional[str] = None):
        self.workspace_root = workspace_root or str(Path(__file__).resolve().parent.parent.parent)
        self.target_home = str(Path(target_home).resolve()) if target_home else None

    def get_home_dir(self) -> Path:
        if self.target_home:
            return Path(self.target_home)
        return Path(os.environ.get("HOME", str(Path.home()))).resolve()

    def _get_hypr_dir(self) -> Path:
        if self.target_home:
            return Path(self.target_home) / ".config" / "hypr"
        xdg_config = os.environ.get("XDG_CONFIG_HOME")
        if xdg_config:
            return Path(xdg_config) / "hypr"
        return Path.home() / ".config" / "hypr"

    def get_user_decorations_path(self) -> Path:
        return self._get_hypr_dir() / "UserConfigs" / "UserDecorations.conf"

    def get_override_lua_path(self) -> Path:
        return self._get_hypr_dir() / "UserConfigs" / "yusei-decorations.lua"

    def _is_live_session(self) -> bool:
        try:
            home_matches = self.get_home_dir() == Path.home().resolve()
        except Exception:
            home_matches = False
        return home_matches and bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"))

    def _read_override_lua_mode(self) -> Optional[bool]:
        """Reads explicit override_all_apps flag from yusei-decorations.lua if present."""
        lua_path = self.get_override_lua_path()
        if not lua_path.exists():
            return None
        try:
            txt = lua_path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            return None
        m = re.search(r"override_all_apps\s*=\s*(true|false)", txt, re.IGNORECASE)
        if m:
            return m.group(1).lower() == "true"
        if "global-opacity-override" in txt and "hl.window_rule" in txt:
            return True
        return None

    def _read_persisted_state(self) -> Dict[str, Any]:
        """Reads base decorations.conf + UserDecorations.conf + yusei-decorations.lua."""
        state = get_default_state()
        hypr_dir = self._get_hypr_dir()
        for cfg in (hypr_dir / "decorations.conf", self.get_user_decorations_path()):
            if not cfg.exists():
                continue
            try:
                parsed = parse_decorations_text(cfg.read_text(encoding="utf-8", errors="ignore"))
                state.update(parsed)
            except Exception:
                pass
        lua_override = self._read_override_lua_mode()
        if lua_override is not None:
            state["override_all_apps"] = lua_override
        return state

    def _read_live_hypr_overrides(self, state: Dict[str, Any]) -> Dict[str, Any]:
        """Merges live runtime `hyprctl getoption` values when running on an active session."""
        if not self._is_live_session():
            return state
        merged = dict(state)
        for key, spec in DECORATION_SCHEMA.items():
            ftype, mn, mx, _step, dec, hypr_opt, _blk, _ckey, _default, _label = spec
            if not hypr_opt:
                continue
            try:
                out = subprocess.check_output(
                    ["hyprctl", "getoption", hypr_opt],
                    text=True,
                    stderr=subprocess.DEVNULL,
                    timeout=1.5,
                )
            except Exception:
                continue

            if ftype is bool:
                val = parse_hypr_bool_option(out)
                if val is not None:
                    merged[key] = val
            else:
                val = parse_hypr_number_option(out, is_int=(ftype is int))
                if val is not None:
                    clamped = max(mn, min(mx, val))
                    merged[key] = int(round(clamped)) if ftype is int else round(float(clamped), dec)
        return merged

    def get_state(self) -> Dict[str, Any]:
        """Returns complete validated decoration state and UI metadata."""
        state = self._read_persisted_state()
        live = self._read_live_hypr_overrides(state)
        return {
            "success": True,
            "state": live,
            "defaults": get_default_state(),
            "bounds": get_schema_bounds(),
            "opacity_presets": OPACITY_PRESETS,
            "blur_presets": BLUR_PRESETS,
            "capabilities": {
                "live_session": self._is_live_session(),
                "user_decorations_file": str(self.get_user_decorations_path()),
                "override_lua_file": str(self.get_override_lua_path()),
            },
        }

    @classmethod
    def validate_patch(cls, patch: Dict[str, Any]) -> Dict[str, Any]:
        """Validates a partial/full update payload, raising ValueError for any bad field."""
        if not isinstance(patch, dict):
            raise ValueError("Dữ liệu cấu hình phải là đối tượng JSON.")
        cleaned: Dict[str, Any] = {}
        for key, raw_val in patch.items():
            if key in ("persist", "link_opacity", "sync_opacity"):
                continue
            if raw_val is None:
                continue
            cleaned[key] = _coerce_field_value(key, raw_val)
        return cleaned

    @staticmethod
    def build_live_lua_expr(state: Dict[str, Any], include_window_rule: bool = True) -> str:
        """Builds Hyprland 0.57+ `hyprctl eval` Lua snippet for decoration + global opacity rule."""
        blur_parts = [
            f"enabled = {'true' if state['blur_enabled'] else 'false'}",
            f"size = {int(state['blur_size'])}",
            f"passes = {int(state['blur_passes'])}",
            f"brightness = {float(state['blur_brightness']):.2f}",
            f"contrast = {float(state['blur_contrast']):.2f}",
            f"vibrancy = {float(state['blur_vibrancy']):.2f}",
            f"noise = {float(state['blur_noise']):.3f}",
            f"xray = {'true' if state['blur_xray'] else 'false'}",
            f"ignore_opacity = {'true' if state['blur_ignore_opacity'] else 'false'}",
        ]
        dec_parts = [
            f"rounding = {int(state['rounding'])}",
            f"active_opacity = {float(state['active_opacity']):.2f}",
            f"inactive_opacity = {float(state['inactive_opacity']):.2f}",
            f"fullscreen_opacity = {float(state['fullscreen_opacity']):.2f}",
            f"blur = {{ {', '.join(blur_parts)} }}",
        ]
        lua_expr = f"hl.config({{ decoration = {{ {', '.join(dec_parts)} }} }})"

        if include_window_rule:
            if state.get("override_all_apps", True):
                op_expr = (
                    f"{float(state['active_opacity']):.2f} override "
                    f"{float(state['inactive_opacity']):.2f} override "
                    f"{float(state['fullscreen_opacity']):.2f} override"
                )
                lua_expr += (
                    "; hl.window_rule({ name = 'global-opacity-override', "
                    f"match = {{ class = '.*' }}, opacity = '{op_expr}' }})"
                )
            else:
                lua_expr += (
                    "; hl.window_rule({ name = 'global-opacity-override', "
                    "enabled = false, match = { class = '.*' } })"
                )
        return lua_expr

    @staticmethod
    def build_keyword_batch(state: Dict[str, Any]) -> str:
        """Builds fallback `hyprctl --batch` keyword string for non-Lua Hyprland builds."""
        cmds: List[str] = []
        for key, spec in DECORATION_SCHEMA.items():
            hypr_opt = spec[5]
            if not hypr_opt or key not in state:
                continue
            cmds.append(f"keyword {hypr_opt} {format_conf_value(key, state[key])}")
        return " ; ".join(cmds)

    @staticmethod
    def render_override_lua_file(state: Dict[str, Any]) -> str:
        """Generates persistent `UserConfigs/yusei-decorations.lua` contents."""
        if state.get("override_all_apps", True):
            op_expr = (
                f"{float(state['active_opacity']):.2f} override "
                f"{float(state['inactive_opacity']):.2f} override "
                f"{float(state['fullscreen_opacity']):.2f} override"
            )
            return (
                "-- Auto-generated by yusei-settings (preserved across updates).\n"
                "-- override_all_apps = true\n"
                "hl.window_rule({\n"
                "    name = \"global-opacity-override\",\n"
                "    match = { class = \".*\" },\n"
                f"    opacity = \"{op_expr}\",\n"
                "})\n"
            )
        return (
            "-- Auto-generated by yusei-settings (preserved across updates).\n"
            "-- override_all_apps = false (using per-tag opacity rules in hyprland.lua)\n"
        )

    def _apply_live_compositor(
        self,
        state: Dict[str, Any],
        override_transitioned_off: bool = False,
    ) -> str:
        """Applies `state` to the live Hyprland session. Returns method used (`lua`, `keyword`, or `offline`)."""
        if not self._is_live_session():
            return "offline"

        lua_expr = self.build_live_lua_expr(state, include_window_rule=True)
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
                if override_transitioned_off:
                    subprocess.run(
                        ["hyprctl", "reload", "config-only"],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=3,
                        check=False,
                    )
                return "lua"
        except Exception:
            pass

        batch_cmd = self.build_keyword_batch(state)
        if batch_cmd:
            try:
                subprocess.run(
                    ["hyprctl", "--batch", batch_cmd],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=2,
                    check=False,
                )
                return "keyword"
            except Exception:
                pass
        return "none"

    def persist_state(self, state: Dict[str, Any], updated_keys: Optional[List[str]] = None) -> Dict[str, Path]:
        """Atomically writes `UserDecorations.conf` and `yusei-decorations.lua`."""
        dec_path = self.get_user_decorations_path()
        existing = dec_path.read_text(encoding="utf-8", errors="ignore") if dec_path.exists() else ""

        if updated_keys:
            updates = {k: state[k] for k in updated_keys if k in state and DECORATION_SCHEMA[k][6] is not None}
        else:
            updates = {k: v for k, v in state.items() if k in DECORATION_SCHEMA and DECORATION_SCHEMA[k][6] is not None}

        new_conf = update_decorations_text(existing, updates)
        atomic_write_text(dec_path, new_conf)

        lua_path = self.get_override_lua_path()
        atomic_write_text(lua_path, self.render_override_lua_file(state))
        return {"user_decorations": dec_path, "override_lua": lua_path}

    def apply(self, patch: Dict[str, Any], *, persist: bool = True, live: bool = True) -> Dict[str, Any]:
        """Validates `patch`, merges into active state, applies live and/or persists cleanly."""
        cleaned = self.validate_patch(patch)
        persisted_state = self._read_persisted_state()

        if all(k in cleaned for k in DECORATION_SCHEMA):
            prev_state = persisted_state
        else:
            prev_state = self._read_live_hypr_overrides(persisted_state)

        new_state = dict(prev_state)
        new_state.update(cleaned)

        override_transitioned_off = (
            bool(persisted_state.get("override_all_apps", True))
            and not bool(new_state.get("override_all_apps", True))
            and persist
        )

        if persist:
            # Always persist complete state on user changes so opacity & blur remain in sync on reboot.
            self.persist_state(new_state)

        applied_via = "skipped"
        if live:
            applied_via = self._apply_live_compositor(
                new_state,
                override_transitioned_off=override_transitioned_off,
            )

        return {
            "success": True,
            "persisted": bool(persist),
            "applied_via": applied_via,
            "state": new_state,
        }

    def reset_defaults(self, *, persist: bool = True, live: bool = True) -> Dict[str, Any]:
        """Resets all decoration/blur/opacity fields back to defaults."""
        defaults = get_default_state()
        return self.apply(defaults, persist=persist, live=live)
