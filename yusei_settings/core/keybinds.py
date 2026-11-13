"""
Keybinds Cheat Sheet Parser & Normalizer
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Parses Hyprland keybinding configurations (bindd, bindeld, bindmd, binded,
bindlnd, bindld, bind, and Hyprland Lua configs) into structured JSON with
category groupings, normalized UI key badges, and command metadata.
"""

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Any, Optional, Set, Tuple

SECTION_MAP = {
    1: "Standard Application Shortcuts",
    2: "Features & Utility Menus",
    3: "Window States, Floating & Scratchpads",
    4: "Bar & Notification Controls",
    5: "System, Session & Power Management",
    6: "Layout Dispatches",
    7: "Window Focus, Cycling & Movement",
    8: "Workspaces",
    9: "Mouse Controls",
    10: "Multimedia & Fn Audio Keys",
    11: "Screenshots",
    12: "Laptop & Hardware Addendums",
}

SECTION_ID_MAP = {
    1: "standard_application_shortcuts",
    2: "features_utility_menus",
    3: "window_states_floating_scratchpads",
    4: "bar_notification_controls",
    5: "system_session_power_management",
    6: "layout_dispatches",
    7: "window_focus_cycling_movement",
    8: "workspaces",
    9: "mouse_controls",
    10: "multimedia_fn_audio_keys",
    11: "screenshots",
    12: "laptop_hardware_addendums",
}

DESCRIPTION_DIRECTIVES = {
    "bindd",
    "bindld",
    "binded",
    "bindmd",
    "bindrd",
    "bindnd",
    "bindod",
    "bindpd",
    "bindtd",
    "bindeld",
    "bindled",
    "bindlnd",
}

CODE_KEY_MAP = {f"code:{10 + i}": str(i + 1) if i < 9 else "0" for i in range(10)}

SPECIAL_KEY_MAP = {
    "mouse:272": "LMB",
    "mouse:273": "RMB",
    "mouse_down": "Scroll Down",
    "mouse_up": "Scroll Up",
    "Return": "Enter",
    "SPACE": "Space",
    "tab": "Tab",
    "TAB": "Tab",
    "left": "Left",
    "right": "Right",
    "up": "Up",
    "down": "Down",
    "bracketleft": "[",
    "bracketright": "]",
    "period": ".",
    "comma": ",",
    "Delete": "Delete",
    "Print": "Print",
    "XF86AudioRaiseVolume": "Volume +",
    "XF86AudioLowerVolume": "Volume -",
    "XF86AudioMute": "Mute",
    "XF86AudioMicMute": "Mic Mute",
    "XF86AudioPlay": "Play/Pause",
    "XF86AudioPause": "Play/Pause",
    "XF86AudioPlayPause": "Play/Pause",
    "XF86AudioNext": "Next Track",
    "XF86AudioPrev": "Prev Track",
    "XF86AudioStop": "Stop",
    "XF86MonBrightnessUp": "Brightness +",
    "XF86MonBrightnessDown": "Brightness -",
    "XF86KbdBrightnessUp": "Kbd Brightness +",
    "XF86KbdBrightnessDown": "Kbd Brightness -",
    "XF86TouchpadToggle": "Touchpad",
    "XF86Sleep": "Sleep",
    "XF86Rfkill": "Airplane Mode",
    "XF86RFKill": "Airplane Mode",
    "XF86Launch1": "ROG Control",
    "XF86Launch3": "Aura RGB",
    "XF86Launch4": "Fan Mode",
}

_UNRESOLVED = object()
_LUA_BLOCK_OPENERS = {"function", "if", "for", "while", "do"}
_LUA_STMT_KEYWORDS = {
    "local",
    "function",
    "if",
    "then",
    "elseif",
    "else",
    "for",
    "while",
    "do",
    "repeat",
    "until",
    "end",
    "return",
    "break",
}
_LUA_BINARY_OPS = {"..", "+", "-", "*", "/", "%", "==", "~=", "<=", ">=", "<", ">", "and", "or"}


@dataclass
class _LuaToken:
    kind: str
    text: str
    line: int
    value: Any = None


def _tokenize_lua(source: str) -> List[_LuaToken]:
    """Tokenize Lua source while preserving comments, strings, long strings, and line numbers."""
    tokens: List[_LuaToken] = []
    n = len(source)
    i = 0
    line = 1

    long_bracket_re = re.compile(r"\[(=*)\[")
    number_re = re.compile(r"(?:0[xX][0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)")
    ident_re = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

    while i < n:
        ch = source[i]

        if ch in " \t\r":
            i += 1
            continue
        if ch == "\n":
            line += 1
            i += 1
            continue

        # Comments: --[=*[...]=*] or --...
        if ch == "-" and i + 1 < n and source[i + 1] == "-":
            start_line = line
            m = long_bracket_re.match(source, i + 2)
            if m:
                closer = "]" + m.group(1) + "]"
                end_pos = source.find(closer, m.end())
                if end_pos == -1:
                    raw = source[i:]
                    line += raw.count("\n")
                    tokens.append(_LuaToken("COMMENT", raw, start_line))
                    break
                end_idx = end_pos + len(closer)
                raw = source[i:end_idx]
                line += raw.count("\n")
                tokens.append(_LuaToken("COMMENT", raw, start_line))
                i = end_idx
            else:
                nl = source.find("\n", i + 2)
                if nl == -1:
                    raw = source[i:]
                    tokens.append(_LuaToken("COMMENT", raw, start_line))
                    break
                raw = source[i:nl]
                tokens.append(_LuaToken("COMMENT", raw, start_line))
                i = nl
            continue

        # Long string: [=*[...]=*]
        m = long_bracket_re.match(source, i)
        if m:
            start_line = line
            closer = "]" + m.group(1) + "]"
            content_start = m.end()
            end_pos = source.find(closer, content_start)
            if end_pos == -1:
                raw = source[i:]
                val = source[content_start:]
                line += raw.count("\n")
                tokens.append(_LuaToken("STRING", raw, start_line, val))
                break
            end_idx = end_pos + len(closer)
            raw = source[i:end_idx]
            val = source[content_start:end_pos]
            if val.startswith("\r\n"):
                val = val[2:]
            elif val.startswith("\n"):
                val = val[1:]
            line += raw.count("\n")
            tokens.append(_LuaToken("STRING", raw, start_line, val))
            i = end_idx
            continue

        # Short strings: "..." or '...'
        if ch in ('"', "'"):
            start_line = line
            quote = ch
            j = i + 1
            chars: List[str] = []
            escape_map = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'"}
            while j < n:
                c = source[j]
                if c == "\\":
                    if j + 1 < n:
                        nxt = source[j + 1]
                        if nxt == "\n":
                            line += 1
                            chars.append("\n")
                        else:
                            chars.append(escape_map.get(nxt, nxt))
                        j += 2
                        continue
                    j += 1
                    break
                if c == quote:
                    j += 1
                    break
                if c == "\n":
                    line += 1
                chars.append(c)
                j += 1
            tokens.append(_LuaToken("STRING", source[i:j], start_line, "".join(chars)))
            i = j
            continue

        # Numbers
        if ch.isdigit():
            m = number_re.match(source, i)
            if m:
                raw = m.group(0)
                if raw.lower().startswith("0x"):
                    val: Any = int(raw, 16)
                elif any(c in raw for c in ".eE"):
                    val = float(raw)
                else:
                    val = int(raw)
                tokens.append(_LuaToken("NUMBER", raw, line, val))
                i = m.end()
                continue

        # Identifiers / keywords
        if ch.isalpha() or ch == "_":
            m = ident_re.match(source, i)
            if m:
                tokens.append(_LuaToken("IDENT", m.group(0), line))
                i = m.end()
                continue

        # Two-character operators
        two = source[i : i + 2]
        if two in ("..", "==", "~=", "<=", ">=", "::", "//"):
            tokens.append(_LuaToken("OP", two, line))
            i += 2
            continue

        tokens.append(_LuaToken("OP", ch, line))
        i += 1

    return tokens


def _find_matching_delim(tokens: List[_LuaToken], open_idx: int) -> int:
    """Return index of matching ), }, or ] for tokens[open_idx], or len(tokens)-1."""
    open_ch = tokens[open_idx].text
    close_ch = {")": "(", "}": "{", "]": "["}
    target_close = {"(": ")", "{": "}", "[": "]"}[open_ch]
    depth = 0
    for idx in range(open_idx, len(tokens)):
        tok = tokens[idx]
        if tok.kind == "OP":
            if tok.text == open_ch:
                depth += 1
            elif tok.text == target_close:
                depth -= 1
                if depth == 0:
                    return idx
            elif tok.text in close_ch and depth <= 0:
                return idx
    return len(tokens) - 1


def _find_matching_end(tokens: List[_LuaToken], open_idx: int) -> int:
    """Return index of matching 'end'/'until' for a Lua block opener at open_idx."""
    stack: List[str] = []
    idx = open_idx
    n = len(tokens)
    while idx < n:
        tok = tokens[idx]
        if tok.kind == "OP" and tok.text in ("(", "{", "["):
            idx = _find_matching_delim(tokens, idx) + 1
            continue
        if tok.kind == "IDENT":
            if tok.text in ("for", "while"):
                stack.append("loop_hdr")
            elif tok.text == "do":
                if stack and stack[-1] == "loop_hdr":
                    stack[-1] = "block"
                else:
                    stack.append("block")
            elif tok.text in ("function", "if"):
                stack.append("block")
            elif tok.text == "repeat":
                stack.append("repeat")
            elif tok.text == "end":
                if stack:
                    stack.pop()
                    if not stack:
                        return idx
            elif tok.text == "until":
                if stack and stack[-1] == "repeat":
                    stack.pop()
                    if not stack:
                        return idx
        idx += 1
    return n - 1


def _split_top_level_commas(tokens: List[_LuaToken]) -> List[List[_LuaToken]]:
    """Split tokens on top-level commas, respecting (), {}, [] and function..end."""
    non_comment = [t for t in tokens if t.kind != "COMMENT"]
    if not non_comment:
        return []

    args: List[List[_LuaToken]] = []
    cur: List[_LuaToken] = []
    idx = 0
    n = len(non_comment)
    while idx < n:
        tok = non_comment[idx]
        if tok.kind == "OP" and tok.text in ("(", "{", "["):
            close_idx = _find_matching_delim(non_comment, idx)
            cur.extend(non_comment[idx : close_idx + 1])
            idx = close_idx + 1
            continue
        if tok.kind == "IDENT" and tok.text in _LUA_BLOCK_OPENERS:
            end_idx = _find_matching_end(non_comment, idx)
            cur.extend(non_comment[idx : end_idx + 1])
            idx = end_idx + 1
            continue
        if tok.kind == "OP" and tok.text == ",":
            args.append(cur)
            cur = []
            idx += 1
            continue
        cur.append(tok)
        idx += 1
    if cur or args:
        args.append(cur)
    return args


def _format_lua_literal(val: Any) -> str:
    """Format a resolved Python scalar back to clean Lua syntax."""
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, (int, float)):
        return str(val)
    if isinstance(val, str):
        escaped = val.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    return str(val)


def _format_lua_tokens(tokens: List[_LuaToken], env: Dict[str, Any]) -> str:
    """Reconstruct a Lua token slice with known variable/field values substituted."""
    filtered = [t for t in tokens if t.kind != "COMMENT"]
    if not filtered:
        return ""

    out: List[str] = []
    idx = 0
    n = len(filtered)
    while idx < n:
        tok = filtered[idx]
        # Replace var.field when var resolves to a dict (e.g. delta.x -> -50)
        if (
            tok.kind == "IDENT"
            and idx + 2 < n
            and filtered[idx + 1].kind == "OP"
            and filtered[idx + 1].text == "."
            and filtered[idx + 2].kind == "IDENT"
            and tok.text in env
            and isinstance(env[tok.text], dict)
            and filtered[idx + 2].text in env[tok.text]
        ):
            out.append(_format_lua_literal(env[tok.text][filtered[idx + 2].text]))
            idx += 3
            continue

        # Replace bare identifier if it's a bound scalar (not a table key or member name)
        if tok.kind == "IDENT" and tok.text in env:
            prev_op = filtered[idx - 1].text if idx > 0 and filtered[idx - 1].kind == "OP" else ""
            next_op = filtered[idx + 1].text if idx + 1 < n and filtered[idx + 1].kind == "OP" else ""
            is_member = prev_op in (".", ":")
            is_table_key = next_op == "="
            val = env[tok.text]
            if not is_member and not is_table_key and isinstance(val, (str, int, float, bool)):
                out.append(_format_lua_literal(val))
                idx += 1
                continue

        out.append(tok.text)
        idx += 1

    # Rejoin tokens cleanly with minimal Lua spacing
    joined = " ".join(out)
    joined = re.sub(r"\s*([.:])\s*", r"\1", joined)
    joined = re.sub(r"\.\.", " .. ", joined)
    joined = re.sub(r"\(\s+", "(", joined)
    joined = re.sub(r"\s+\)", ")", joined)
    joined = re.sub(r"\s+\(", "(", joined)
    joined = re.sub(r"\s+,", ",", joined)
    joined = re.sub(r"\{\s+", "{ ", joined)
    joined = re.sub(r"\s+\}", " }", joined)
    return joined.strip()


def _tokens_reference_unbound(tokens: List[_LuaToken], unbound: Set[str]) -> bool:
    """Return True if tokens reference any unresolved template/loop variable."""
    if not unbound:
        return False
    filtered = [t for t in tokens if t.kind != "COMMENT"]
    n = len(filtered)
    for idx, tok in enumerate(filtered):
        if tok.kind != "IDENT" or tok.text not in unbound:
            continue
        prev_op = filtered[idx - 1].text if idx > 0 and filtered[idx - 1].kind == "OP" else ""
        next_op = filtered[idx + 1].text if idx + 1 < n and filtered[idx + 1].kind == "OP" else ""
        if prev_op in (".", ":") or next_op == "=":
            continue
        return True
    return False


def _eval_lua_expr(tokens: List[_LuaToken], env: Dict[str, Any]) -> Any:
    """Safely evaluate simple Lua expressions (strings, numbers, tables, .., +, -, index)."""
    filtered = [t for t in tokens if t.kind != "COMMENT"]
    if not filtered:
        return _UNRESOLVED

    pos = 0
    n = len(filtered)

    def parse_expr(min_prec: int = 0) -> Any:
        nonlocal pos
        lhs = parse_unary()
        while pos < n:
            tok = filtered[pos]
            op = tok.text if tok.kind in ("OP", "IDENT") else ""
            if op == "..":
                prec = 2
            elif op in ("+", "-"):
                prec = 3
            elif op in ("*", "/", "%"):
                prec = 4
            else:
                break
            if prec < min_prec:
                break
            pos += 1
            rhs = parse_expr(prec + (0 if op == ".." else 1))
            if lhs is _UNRESOLVED or rhs is _UNRESOLVED:
                lhs = _UNRESOLVED
            elif op == "..":
                if isinstance(lhs, (str, int, float)) and isinstance(rhs, (str, int, float)):
                    lhs = f"{lhs}{rhs}"
                else:
                    lhs = _UNRESOLVED
            elif isinstance(lhs, (int, float)) and isinstance(rhs, (int, float)):
                if op == "+":
                    lhs = lhs + rhs
                elif op == "-":
                    lhs = lhs - rhs
                elif op == "*":
                    lhs = lhs * rhs
                elif op == "/" and rhs != 0:
                    lhs = lhs / rhs
                elif op == "%" and rhs != 0:
                    lhs = lhs % rhs
                else:
                    lhs = _UNRESOLVED
            else:
                lhs = _UNRESOLVED
        return lhs

    def parse_unary() -> Any:
        nonlocal pos
        if pos < n and filtered[pos].kind == "OP" and filtered[pos].text == "-":
            pos += 1
            val = parse_unary()
            return -val if isinstance(val, (int, float)) else _UNRESOLVED
        return parse_postfix()

    def parse_postfix() -> Any:
        nonlocal pos
        val = parse_primary()
        while pos < n:
            tok = filtered[pos]
            if tok.kind == "OP" and tok.text == ".":
                if pos + 1 < n and filtered[pos + 1].kind == "IDENT":
                    field = filtered[pos + 1].text
                    pos += 2
                    if isinstance(val, dict) and field in val:
                        val = val[field]
                    elif val == ("__builtin__", "os") and field == "getenv":
                        val = ("__builtin__", "os.getenv")
                    else:
                        val = _UNRESOLVED
                    continue
                break
            if tok.kind == "OP" and tok.text == "[":
                close_idx = _find_matching_delim(filtered, pos)
                key_val = _eval_lua_expr(filtered[pos + 1 : close_idx], env)
                pos = close_idx + 1
                if isinstance(val, dict) and key_val is not _UNRESOLVED and key_val in val:
                    val = val[key_val]
                elif isinstance(val, list) and isinstance(key_val, int) and 1 <= key_val <= len(val):
                    val = val[key_val - 1]
                else:
                    val = _UNRESOLVED
                continue
            if tok.kind == "OP" and tok.text == "(":
                close_idx = _find_matching_delim(filtered, pos)
                call_args = _split_top_level_commas(filtered[pos + 1 : close_idx])
                pos = close_idx + 1
                if val == ("__builtin__", "os.getenv") and len(call_args) >= 1:
                    arg_val = _eval_lua_expr(call_args[0], env)
                    if arg_val == "HOME":
                        val = "~"
                    elif isinstance(arg_val, str):
                        val = ""
                    else:
                        val = _UNRESOLVED
                elif val == ("__builtin__", "tostring") and len(call_args) >= 1:
                    arg_val = _eval_lua_expr(call_args[0], env)
                    if arg_val is _UNRESOLVED:
                        val = _UNRESOLVED
                    elif arg_val is None:
                        val = "nil"
                    elif isinstance(arg_val, bool):
                        val = "true" if arg_val else "false"
                    else:
                        val = str(arg_val)
                else:
                    val = _UNRESOLVED
                continue
            break
        return val

    def parse_primary() -> Any:
        nonlocal pos
        if pos >= n:
            return _UNRESOLVED
        tok = filtered[pos]
        if tok.kind in ("STRING", "NUMBER"):
            pos += 1
            return tok.value
        if tok.kind == "IDENT":
            pos += 1
            if tok.text == "true":
                return True
            if tok.text == "false":
                return False
            if tok.text == "nil":
                return None
            if tok.text in env:
                return env[tok.text]
            if tok.text == "os":
                return ("__builtin__", "os")
            if tok.text == "tostring":
                return ("__builtin__", "tostring")
            return _UNRESOLVED
        if tok.kind == "OP" and tok.text == "(":
            close_idx = _find_matching_delim(filtered, pos)
            inner = _eval_lua_expr(filtered[pos + 1 : close_idx], env)
            pos = close_idx + 1
            return inner
        if tok.kind == "OP" and tok.text == "{":
            close_idx = _find_matching_delim(filtered, pos)
            items = _split_top_level_commas(filtered[pos + 1 : close_idx])
            pos = close_idx + 1
            return parse_table(items)
        return _UNRESOLVED

    def parse_table(items: List[List[_LuaToken]]) -> Any:
        if not items:
            return {}
        has_keys = False
        has_seq = False
        dict_res: Dict[Any, Any] = {}
        list_res: List[Any] = []
        for entry in items:
            if not entry:
                continue
            if len(entry) >= 3 and entry[0].kind == "IDENT" and entry[1].kind == "OP" and entry[1].text == "=":
                has_keys = True
                val = _eval_lua_expr(entry[2:], env)
                if val is _UNRESOLVED:
                    return _UNRESOLVED
                dict_res[entry[0].text] = val
            elif entry[0].kind == "OP" and entry[0].text == "[":
                c_idx = _find_matching_delim(entry, 0)
                if c_idx + 1 < len(entry) and entry[c_idx + 1].kind == "OP" and entry[c_idx + 1].text == "=":
                    has_keys = True
                    k_val = _eval_lua_expr(entry[1:c_idx], env)
                    v_val = _eval_lua_expr(entry[c_idx + 2 :], env)
                    if k_val is _UNRESOLVED or v_val is _UNRESOLVED:
                        return _UNRESOLVED
                    dict_res[k_val] = v_val
                    continue
                has_seq = True
                val = _eval_lua_expr(entry, env)
                if val is _UNRESOLVED:
                    return _UNRESOLVED
                list_res.append(val)
            else:
                has_seq = True
                val = _eval_lua_expr(entry, env)
                if val is _UNRESOLVED:
                    return _UNRESOLVED
                list_res.append(val)
        if has_keys and not has_seq:
            return dict_res
        if has_seq and not has_keys:
            return list_res
        return dict_res if has_keys else list_res

    result = parse_expr(0)
    if pos != n:
        return _UNRESOLVED
    return result


class KeybindParser:
    def __init__(self, config_path: Optional[str] = None, target_home: Optional[str] = None):
        self.target_home = Path(target_home) if target_home else None
        if config_path:
            self.config_path = Path(config_path)
        elif self.target_home is not None:
            hypr_dir = self.target_home / ".config" / "hypr"
            lua_path = hypr_dir / "hyprland.lua"
            conf_path = hypr_dir / "keybinds.conf"
            if lua_path.exists():
                self.config_path = lua_path
            elif conf_path.exists():
                self.config_path = conf_path
            else:
                workspace_root = Path(__file__).resolve().parent.parent.parent
                self.config_path = workspace_root / "config" / "hypr" / "keybinds.conf"
        else:
            workspace_root = Path(__file__).resolve().parent.parent.parent
            self.config_path = workspace_root / "config" / "hypr" / "keybinds.conf"

    @classmethod
    def from_home(cls, home_dir: str) -> "KeybindParser":
        """Construct a KeybindParser resolving Hyprland configs under home_dir."""
        return cls(target_home=home_dir)

    @staticmethod
    def normalize_mods(mods_str: str) -> List[str]:
        if not mods_str or not mods_str.strip():
            return []
        tokens = mods_str.strip().split()
        normalized = []
        for token in tokens:
            t = token.strip()
            if t in ("$mainMod", "SUPER"):
                normalized.append("Super")
            elif t in ("SHIFT", "SHIFT_L"):
                normalized.append("Shift")
            elif t in ("CTRL", "CONTROL"):
                normalized.append("Ctrl")
            elif t in ("ALT", "ALT_L"):
                normalized.append("Alt")
            else:
                normalized.append(t)
        return normalized

    @staticmethod
    def normalize_key(key_str: str) -> str:
        k = key_str.strip()
        if k in CODE_KEY_MAP:
            return CODE_KEY_MAP[k]
        if k in SPECIAL_KEY_MAP:
            return SPECIAL_KEY_MAP[k]
        return k

    @staticmethod
    def _is_description_directive(directive: str) -> bool:
        if directive in DESCRIPTION_DIRECTIVES:
            return True
        return bool(
            re.fullmatch(r"bind[lrenmtisopucgd]+", directive)
            and "d" in directive[4:]
        )

    def _split_lua_key_combo(self, combo_str: str) -> Tuple[str, str, List[str], List[str], str]:
        """Split and normalize a Lua key combo string into mods, key, all_keys, combo_display."""
        raw = combo_str.strip()
        if "," in raw:
            mod_part, key_part = raw.split(",", 1)
            raw_mods = mod_part.strip().split()
            raw_key = key_part.strip()
        else:
            plus_parts = [p.strip() for p in raw.split("+") if p.strip()]
            if not plus_parts:
                return "", "", [], [], ""
            raw_mods = []
            for part in plus_parts[:-1]:
                raw_mods.extend(part.split())
            last_tokens = plus_parts[-1].split()
            if len(last_tokens) > 1:
                raw_mods.extend(last_tokens[:-1])
                raw_key = last_tokens[-1]
            else:
                raw_key = plus_parts[-1]

        norm_mods = self.normalize_mods(" ".join(raw_mods))
        norm_key = self.normalize_key(raw_key)
        all_keys = norm_mods + ([norm_key] if norm_key else [])
        combo_display = " + ".join(all_keys)
        return " ".join(raw_mods), raw_key, norm_mods, all_keys, combo_display

    def parse(self) -> List[Dict[str, Any]]:
        target_path = self.config_path
        if not target_path.exists():
            lua_fallback = target_path.parent / "hyprland.lua"
            if lua_fallback.exists():
                target_path = lua_fallback
            else:
                return []

        content = target_path.read_text(encoding="utf-8", errors="ignore")
        lines = content.splitlines()

        if target_path.suffix == ".lua":
            return self._parse_lua(lines)

        current_category = "General"
        current_cat_id = "general"
        parsed_binds: List[Dict[str, Any]] = []

        for line_idx, line in enumerate(lines, 1):
            stripped = line.strip()
            if not stripped:
                continue

            # Check section headers: e.g. # 1. Standard Application Shortcuts
            sec_match = re.match(r"^#\s*([0-9]+)\.\s*(.+)", stripped)
            if sec_match:
                sec_num = int(sec_match.group(1))
                current_category = SECTION_MAP.get(sec_num, sec_match.group(2).split("(")[0].strip())
                current_cat_id = SECTION_ID_MAP.get(
                    sec_num,
                    re.sub(r"[^a-z0-9]+", "_", current_category.lower()).strip("_"),
                )
                continue

            if stripped.startswith("#"):
                continue

            if "=" not in stripped:
                continue

            directive, rest = stripped.split("=", 1)
            directive = directive.strip()
            if not re.fullmatch(r"bind[a-z]*", directive):
                continue

            # Split comma separated parameters
            parts = [p.strip() for p in rest.split(",")]

            if self._is_description_directive(directive):
                # bindd = MODS, KEY, DESCRIPTION, DISPATCHER, [ARGS...]
                mods = parts[0] if len(parts) > 0 else ""
                key = parts[1] if len(parts) > 1 else ""
                desc = parts[2] if len(parts) > 2 else ""
                dispatcher = parts[3] if len(parts) > 3 else ""
                args = ", ".join(parts[4:]).strip() if len(parts) > 4 else ""
            else:
                # bind = MODS, KEY, DISPATCHER, [ARGS...]
                mods = parts[0] if len(parts) > 0 else ""
                key = parts[1] if len(parts) > 1 else ""
                desc = ""
                dispatcher = parts[2] if len(parts) > 2 else ""
                args = ", ".join(parts[3:]).strip() if len(parts) > 3 else ""

            norm_mods = self.normalize_mods(mods)
            norm_key = self.normalize_key(key)
            all_keys = norm_mods + ([norm_key] if norm_key else [])
            combo_display = " + ".join(all_keys)

            parsed_binds.append({
                "category": current_category,
                "category_id": current_cat_id,
                "directive": directive,
                "type": directive,
                "mods": mods,
                "key": key,
                "keys": all_keys,
                "combo_display": combo_display,
                "description": desc,
                "dispatcher": dispatcher,
                "args": args,
                "command": args,
                "raw_line": stripped,
                "line_number": line_idx,
            })

        return parsed_binds

    def _parse_lua(self, lines: List[str]) -> List[Dict[str, Any]]:
        tokens = _tokenize_lua("\n".join(lines))
        parsed_binds: List[Dict[str, Any]] = []
        state: Dict[str, Any] = {
            "category": "General",
            "category_id": "general",
            "in_keybindings": False,
        }

        def update_category_from_comment(comment_text: str) -> None:
            stripped = comment_text.strip()
            if not stripped.startswith("--") or stripped.startswith("---"):
                return
            sec_match = re.match(r"^--\s*([0-9]+)\.\s*(.+)", stripped)
            if sec_match:
                sec_num = int(sec_match.group(1))
                sec_title = sec_match.group(2).split("(")[0].strip()
                if sec_title.upper() == "KEYBINDINGS":
                    state["category"] = "Keybindings"
                    state["category_id"] = "keybindings"
                    state["in_keybindings"] = True
                else:
                    state["in_keybindings"] = False
                    cat_name = SECTION_MAP.get(sec_num, sec_title)
                    state["category"] = cat_name
                    state["category_id"] = SECTION_ID_MAP.get(
                        sec_num,
                        re.sub(r"[^a-z0-9]+", "_", cat_name.lower()).strip("_"),
                    )
                return

            if state["in_keybindings"] and not stripped.startswith("--["):
                sub_title = stripped[2:].split("(")[0].strip()
                if sub_title and not any(ch in sub_title for ch in ("=", "{", "}")):
                    state["category"] = sub_title
                    state["category_id"] = re.sub(r"[^a-z0-9]+", "_", sub_title.lower()).strip("_")

        def raw_line_range(start_line: int, end_line: int) -> str:
            s_idx = max(0, start_line - 1)
            e_idx = min(len(lines), end_line)
            return " ".join(l.strip() for l in lines[s_idx:e_idx] if l.strip())

        def emit_bind(
            directive: str,
            combo_str: str,
            dispatcher: str,
            args: str,
            command: str,
            start_line: int,
            end_line: int,
        ) -> None:
            if not combo_str or not combo_str.strip():
                return
            mods, key, _norm_mods, all_keys, combo_display = self._split_lua_key_combo(combo_str)
            if not all_keys:
                return
            parsed_binds.append({
                "category": state["category"],
                "category_id": state["category_id"],
                "directive": directive,
                "type": directive,
                "mods": mods,
                "key": key,
                "keys": all_keys,
                "combo_display": combo_display,
                "description": "",
                "dispatcher": dispatcher,
                "args": args,
                "command": command,
                "raw_line": raw_line_range(start_line, end_line),
                "line_number": start_line,
            })

        def handle_bind_call(
            directive: str,
            arg_lists: List[List[_LuaToken]],
            env: Dict[str, Any],
            unbound: Set[str],
            start_line: int,
            end_line: int,
        ) -> None:
            if len(arg_lists) < 2:
                return
            key_tokens = arg_lists[0]
            action_tokens = arg_lists[1]
            if _tokens_reference_unbound(key_tokens, unbound) or _tokens_reference_unbound(action_tokens, unbound):
                return

            keys_val = _eval_lua_expr(key_tokens, env)
            if not isinstance(keys_val, str) or not keys_val.strip():
                return

            if directive == "bindCommand":
                cmd_val = _eval_lua_expr(action_tokens, env)
                if isinstance(cmd_val, str):
                    cmd_str = cmd_val.strip()
                elif cmd_val is _UNRESOLVED:
                    cmd_str = _format_lua_tokens(action_tokens, env)
                else:
                    cmd_str = str(cmd_val)
                emit_bind("bindCommand", keys_val, "exec", cmd_str, cmd_str, start_line, end_line)
                return

            # hl.bind(keys, action, [flags])
            clean_act = [t for t in action_tokens if t.kind != "COMMENT"]
            if (
                len(clean_act) >= 7
                and clean_act[0].kind == "IDENT"
                and clean_act[0].text == "hl"
                and clean_act[1].text == "."
                and clean_act[2].text == "dsp"
                and clean_act[3].text == "."
                and clean_act[4].text == "exec_cmd"
                and clean_act[5].text == "("
                and _find_matching_delim(clean_act, 5) == len(clean_act) - 1
            ):
                inner = clean_act[6:-1]
                cmd_val = _eval_lua_expr(inner, env)
                cmd_str = cmd_val.strip() if isinstance(cmd_val, str) else _format_lua_tokens(inner, env)
                emit_bind("hl.bind", keys_val, "exec", cmd_str, cmd_str, start_line, end_line)
                return

            # hl.dsp.<dotted_method>(...)
            if (
                len(clean_act) >= 6
                and clean_act[0].kind == "IDENT"
                and clean_act[0].text == "hl"
                and clean_act[1].text == "."
                and clean_act[2].text == "dsp"
            ):
                p_idx = 3
                parts = ["hl", "dsp"]
                while p_idx + 1 < len(clean_act) and clean_act[p_idx].text == "." and clean_act[p_idx + 1].kind == "IDENT":
                    parts.append(clean_act[p_idx + 1].text)
                    p_idx += 2
                if p_idx < len(clean_act) and clean_act[p_idx].text == "(" and _find_matching_delim(clean_act, p_idx) == len(clean_act) - 1:
                    dispatcher = ".".join(parts)
                    inner = clean_act[p_idx + 1 : -1]
                    inner_fmt = _format_lua_tokens(inner, env)
                    cmd_str = f"{dispatcher}({inner_fmt})"
                    emit_bind("hl.bind", keys_val, dispatcher, inner_fmt, cmd_str, start_line, end_line)
                    return

            # Anonymous callback: function(...) ... end
            if (
                len(clean_act) >= 4
                and clean_act[0].kind == "IDENT"
                and clean_act[0].text == "function"
                and clean_act[1].text == "("
            ):
                paren_end = _find_matching_delim(clean_act, 1)
                body_end = _find_matching_end(clean_act, 0)
                body_tokens = clean_act[paren_end + 1 : body_end]
                body_fmt = _format_lua_tokens(body_tokens, env)
                emit_bind("hl.bind", keys_val, "function", body_fmt, body_fmt, start_line, end_line)
                return

            fallback_disp = _format_lua_tokens(clean_act, env)
            emit_bind("hl.bind", keys_val, fallback_disp, "", fallback_disp, start_line, end_line)

        def consume_expr_end(tok_list: List[_LuaToken], start_idx: int) -> int:
            """Advance from start_idx across one Lua expression, returning the index after it."""
            n = len(tok_list)
            idx = start_idx

            def skip_comments(pos: int) -> int:
                while pos < n and tok_list[pos].kind == "COMMENT":
                    pos += 1
                return pos

            while True:
                idx = skip_comments(idx)
                if idx >= n:
                    return idx
                tok = tok_list[idx]
                if tok.kind == "OP" and tok.text in ("-", "#"):
                    idx += 1
                    continue
                if tok.kind == "IDENT" and tok.text == "not":
                    idx += 1
                    continue
                if tok.kind == "IDENT" and tok.text == "function":
                    idx = _find_matching_end(tok_list, idx) + 1
                elif tok.kind == "OP" and tok.text in ("(", "{"):
                    idx = _find_matching_delim(tok_list, idx) + 1
                elif tok.kind in ("STRING", "NUMBER", "IDENT"):
                    idx += 1
                else:
                    return idx

                # Postfix chain (do not advance idx past comments unless continuation matches)
                while True:
                    nxt = skip_comments(idx)
                    if nxt >= n:
                        return idx
                    ntok = tok_list[nxt]
                    if ntok.kind == "OP" and ntok.text in (".", ":"):
                        after = skip_comments(nxt + 1)
                        if after < n and tok_list[after].kind == "IDENT":
                            idx = after + 1
                            continue
                        return idx
                    if ntok.kind == "OP" and ntok.text in ("(", "{", "["):
                        idx = _find_matching_delim(tok_list, nxt) + 1
                        continue
                    if ntok.kind == "STRING":
                        idx = nxt + 1
                        continue
                    break

                # Binary continuation (only consume comments if binary op follows)
                nxt = skip_comments(idx)
                if nxt < n and tok_list[nxt].text in _LUA_BINARY_OPS:
                    idx = nxt + 1
                    continue
                return idx

        def execute_block(tok_list: List[_LuaToken], env: Dict[str, Any], unbound: Set[str]) -> None:
            idx = 0
            n = len(tok_list)

            def next_non_comment(pos: int) -> int:
                while pos < n and tok_list[pos].kind == "COMMENT":
                    pos += 1
                return pos

            while idx < n:
                tok = tok_list[idx]
                if tok.kind == "COMMENT":
                    update_category_from_comment(tok.text)
                    idx += 1
                    continue
                if tok.kind == "OP" and tok.text == ";":
                    idx += 1
                    continue

                # Skip named function definitions: [local] function ... end
                if tok.kind == "IDENT" and tok.text == "local":
                    nxt = next_non_comment(idx + 1)
                    if nxt < n and tok_list[nxt].kind == "IDENT" and tok_list[nxt].text == "function":
                        idx = _find_matching_end(tok_list, nxt) + 1
                        continue
                    # local var1 [, var2 ...] [= expr1 ...]
                    if nxt < n and tok_list[nxt].kind == "IDENT":
                        var_names = [tok_list[nxt].text]
                        cur = next_non_comment(nxt + 1)
                        while cur < n and tok_list[cur].kind == "OP" and tok_list[cur].text == ",":
                            v_idx = next_non_comment(cur + 1)
                            if v_idx < n and tok_list[v_idx].kind == "IDENT":
                                var_names.append(tok_list[v_idx].text)
                                cur = next_non_comment(v_idx + 1)
                            else:
                                break
                        if cur < n and tok_list[cur].kind == "OP" and tok_list[cur].text == "=":
                            expr_start = next_non_comment(cur + 1)
                            expr_end = consume_expr_end(tok_list, expr_start)
                            if len(var_names) == 1:
                                val = _eval_lua_expr(tok_list[expr_start:expr_end], env)
                                if val is not _UNRESOLVED:
                                    env[var_names[0]] = val
                                elif var_names[0] in env:
                                    del env[var_names[0]]
                            idx = expr_end
                            while idx < n and tok_list[idx].kind == "OP" and tok_list[idx].text == ",":
                                e_end = consume_expr_end(tok_list, idx + 1)
                                idx = e_end
                            continue
                        idx = cur
                        continue

                if tok.kind == "IDENT" and tok.text == "function":
                    idx = _find_matching_end(tok_list, idx) + 1
                    continue

                if tok.kind == "IDENT" and tok.text == "do":
                    end_idx = _find_matching_end(tok_list, idx)
                    execute_block(tok_list[idx + 1 : end_idx], dict(env), set(unbound))
                    idx = end_idx + 1
                    continue

                if tok.kind == "IDENT" and tok.text == "for":
                    end_idx = _find_matching_end(tok_list, idx)
                    # Find matching 'do' at top level of this for-header
                    do_idx = idx + 1
                    while do_idx < end_idx:
                        dt = tok_list[do_idx]
                        if dt.kind == "OP" and dt.text in ("(", "{", "["):
                            do_idx = _find_matching_delim(tok_list, do_idx) + 1
                            continue
                        if dt.kind == "IDENT" and dt.text == "do":
                            break
                        do_idx += 1

                    header = [t for t in tok_list[idx + 1 : do_idx] if t.kind != "COMMENT"]
                    body = tok_list[do_idx + 1 : end_idx]

                    expanded = False
                    # 1. Numeric for: var = start, stop [, step]
                    if len(header) >= 4 and header[0].kind == "IDENT" and header[1].kind == "OP" and header[1].text == "=":
                        loop_var = header[0].text
                        bounds = _split_top_level_commas(header[2:])
                        if len(bounds) in (2, 3):
                            start_v = _eval_lua_expr(bounds[0], env)
                            stop_v = _eval_lua_expr(bounds[1], env)
                            step_v = _eval_lua_expr(bounds[2], env) if len(bounds) == 3 else 1
                            if (
                                isinstance(start_v, int)
                                and not isinstance(start_v, bool)
                                and isinstance(stop_v, int)
                                and not isinstance(stop_v, bool)
                                and isinstance(step_v, int)
                                and not isinstance(step_v, bool)
                                and step_v != 0
                            ):
                                count = 0
                                cur_i = start_v
                                while (cur_i <= stop_v if step_v > 0 else cur_i >= stop_v) and count < 500:
                                    child_env = dict(env)
                                    child_env[loop_var] = cur_i
                                    execute_block(body, child_env, set(unbound))
                                    cur_i += step_v
                                    count += 1
                                expanded = True

                    # 2. Generic for: v1 [, v2] in ipairs(tbl) / pairs(tbl)
                    if not expanded:
                        in_pos = next((k for k, t in enumerate(header) if t.kind == "IDENT" and t.text == "in"), -1)
                        if in_pos > 0 and in_pos + 1 < len(header):
                            var_tokens = [t.text for t in header[:in_pos] if t.kind == "IDENT"]
                            iter_tokens = header[in_pos + 1 :]
                            if (
                                len(iter_tokens) >= 4
                                and iter_tokens[0].kind == "IDENT"
                                and iter_tokens[0].text in ("ipairs", "pairs")
                                and iter_tokens[1].kind == "OP"
                                and iter_tokens[1].text == "("
                                and _find_matching_delim(iter_tokens, 1) == len(iter_tokens) - 1
                            ):
                                iter_fn = iter_tokens[0].text
                                tbl_val = _eval_lua_expr(iter_tokens[2:-1], env)
                                if iter_fn == "ipairs" and isinstance(tbl_val, list):
                                    for i_num, item_val in enumerate(tbl_val, 1):
                                        child_env = dict(env)
                                        if len(var_tokens) >= 1 and var_tokens[0] != "_":
                                            child_env[var_tokens[0]] = i_num
                                        if len(var_tokens) >= 2 and var_tokens[1] != "_":
                                            child_env[var_tokens[1]] = item_val
                                        execute_block(body, child_env, set(unbound))
                                    expanded = True
                                elif iter_fn == "pairs" and isinstance(tbl_val, dict):
                                    for k_val, v_val in tbl_val.items():
                                        child_env = dict(env)
                                        if len(var_tokens) >= 1 and var_tokens[0] != "_":
                                            child_env[var_tokens[0]] = k_val
                                        if len(var_tokens) >= 2 and var_tokens[1] != "_":
                                            child_env[var_tokens[1]] = v_val
                                        execute_block(body, child_env, set(unbound))
                                    expanded = True

                            if not expanded:
                                child_unbound = set(unbound) | {v for v in var_tokens if v != "_"}
                                execute_block(body, dict(env), child_unbound)
                                expanded = True

                    idx = end_idx + 1
                    continue

                if tok.kind == "IDENT" and tok.text == "while":
                    end_idx = _find_matching_end(tok_list, idx)
                    idx = end_idx + 1
                    continue

                if tok.kind == "IDENT" and tok.text in ("if", "elseif"):
                    # Advance across if/elseif condition to 'then' so inner statements still parse
                    then_idx = idx + 1
                    while then_idx < n and not (tok_list[then_idx].kind == "IDENT" and tok_list[then_idx].text == "then"):
                        if tok_list[then_idx].kind == "OP" and tok_list[then_idx].text in ("(", "{", "["):
                            then_idx = _find_matching_delim(tok_list, then_idx) + 1
                            continue
                        then_idx += 1
                    idx = then_idx + 1
                    continue

                if tok.kind == "IDENT" and tok.text == "until":
                    idx = consume_expr_end(tok_list, idx + 1)
                    continue

                if tok.kind == "IDENT" and tok.text in ("else", "end", "return", "break", "repeat"):
                    idx += 1
                    continue

                # Check bindCommand(...) call
                if tok.kind == "IDENT" and tok.text == "bindCommand":
                    p_idx = next_non_comment(idx + 1)
                    if p_idx < n and tok_list[p_idx].kind == "OP" and tok_list[p_idx].text == "(":
                        close_idx = _find_matching_delim(tok_list, p_idx)
                        arg_lists = _split_top_level_commas(tok_list[p_idx + 1 : close_idx])
                        handle_bind_call(
                            "bindCommand",
                            arg_lists,
                            env,
                            unbound,
                            tok.line,
                            tok_list[close_idx].line,
                        )
                        idx = close_idx + 1
                        continue

                # Check hl.bind(...) call
                if tok.kind == "IDENT" and tok.text == "hl":
                    dot_idx = next_non_comment(idx + 1)
                    if dot_idx < n and tok_list[dot_idx].kind == "OP" and tok_list[dot_idx].text == ".":
                        meth_idx = next_non_comment(dot_idx + 1)
                        if meth_idx < n and tok_list[meth_idx].kind == "IDENT" and tok_list[meth_idx].text == "bind":
                            p_idx = next_non_comment(meth_idx + 1)
                            if p_idx < n and tok_list[p_idx].kind == "OP" and tok_list[p_idx].text == "(":
                                close_idx = _find_matching_delim(tok_list, p_idx)
                                arg_lists = _split_top_level_commas(tok_list[p_idx + 1 : close_idx])
                                handle_bind_call(
                                    "hl.bind",
                                    arg_lists,
                                    env,
                                    unbound,
                                    tok.line,
                                    tok_list[close_idx].line,
                                )
                                idx = close_idx + 1
                                continue

                # Track plain top-level assignments (e.g. foo = "bar")
                if tok.kind == "IDENT":
                    nxt = next_non_comment(idx + 1)
                    if nxt < n and tok_list[nxt].kind == "OP" and tok_list[nxt].text == "=":
                        expr_start = next_non_comment(nxt + 1)
                        expr_end = consume_expr_end(tok_list, expr_start)
                        val = _eval_lua_expr(tok_list[expr_start:expr_end], env)
                        if val is not _UNRESOLVED:
                            env[tok.text] = val
                        idx = expr_end
                        continue

                # Skip any other call/expression safely
                next_idx = consume_expr_end(tok_list, idx)
                idx = next_idx if next_idx > idx else idx + 1

        execute_block(tokens, {}, set())
        return parsed_binds

    def get_categories(self) -> List[Dict[str, Any]]:
        binds = self.parse()
        seen = {}
        for b in binds:
            cat_id = b["category_id"]
            if cat_id not in seen:
                seen[cat_id] = {
                    "id": cat_id,
                    "name": b["category"],
                    "count": 0,
                }
            seen[cat_id]["count"] += 1
        return list(seen.values())

    def get_grouped(self) -> Dict[str, List[Dict[str, Any]]]:
        binds = self.parse()
        grouped: Dict[str, List[Dict[str, Any]]] = {}
        for b in binds:
            cat_id = b["category_id"]
            if cat_id not in grouped:
                grouped[cat_id] = []
            grouped[cat_id].append(b)
        return grouped
