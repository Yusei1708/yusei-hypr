#!/usr/bin/env python3
import os
import re
import sys

# Preserve existing executable usage while adding Hyprland 0.57+ Lua support.


def normalize_combo(combo):
    if "," in combo:
        mods_part, key_part = combo.split(",", 1)
        mods_norm = mods_part.replace("$mainMod", "SUPER").replace("+", " ")
        mods = "+".join(sorted(m.strip().lower() for m in mods_norm.split() if m.strip()))
        key = key_part.strip().lower()
        return f"{mods},{key}"
    return combo.replace("$mainMod", "SUPER").replace(" ", "").replace("\t", "").lower()


def extract_combo(line):
    # Remove comments and whitespace
    line = re.sub(r"\s*#.*$", "", line).strip()

    if "=" not in line:
        return None

    try:
        rhs = line.split("=", 1)[1]
        parts = [p.strip() for p in rhs.split(",")]
        if len(parts) < 2:
            return None

        mods = parts[0]
        key = parts[1]
        return f"{mods},{key}"
    except Exception:
        return None


def find_user_conf_path(files):
    """Explicitly locate UserConfigs/UserKeybinds.conf instead of blindly using files[-1]."""
    for fp in files:
        norm = os.path.normpath(fp)
        if norm.endswith(os.path.join("UserConfigs", "UserKeybinds.conf")) or os.path.basename(norm) == "UserKeybinds.conf":
            return fp
    return None


def _strip_lua_comments(text):
    """Strip Lua -- and --[[ ... ]] comments while preserving strings and long brackets."""
    out = []
    i = 0
    n = len(text)

    while i < n:
        ch = text[i]
        # String literal '...' or "..."
        if ch in ('"', "'"):
            quote = ch
            out.append(ch)
            i += 1
            while i < n:
                c = text[i]
                out.append(c)
                if c == "\\" and i + 1 < n:
                    out.append(text[i + 1])
                    i += 2
                    continue
                if c == quote:
                    i += 1
                    break
                i += 1
            continue

        # Long bracket string [=*[ ... ]=*]
        if ch == "[":
            m = re.match(r"\[(=*)\[", text[i:])
            if m:
                eq = m.group(1)
                close_tok = "]" + eq + "]"
                end_idx = text.find(close_tok, i + len(m.group(0)))
                if end_idx == -1:
                    out.append(text[i:])
                    break
                end_idx += len(close_tok)
                out.append(text[i:end_idx])
                i = end_idx
                continue

        # Comment -- or --[=*[ ... ]=*]
        if ch == "-" and i + 1 < n and text[i + 1] == "-":
            m = re.match(r"--\[(=*)\[", text[i:])
            if m:
                eq = m.group(1)
                close_tok = "]" + eq + "]"
                end_idx = text.find(close_tok, i + len(m.group(0)))
                if end_idx == -1:
                    break
                i = end_idx + len(close_tok)
                out.append(" ")
                continue
            newline = text.find("\n", i)
            if newline == -1:
                break
            i = newline
            continue

        out.append(ch)
        i += 1

    return "".join(out)


def _find_matching_paren(text, open_idx):
    """Find matching ')' starting at '(' index open_idx, respecting strings and brackets."""
    depth = 0
    i = open_idx
    n = len(text)
    while i < n:
        ch = text[i]
        if ch in ('"', "'"):
            quote = ch
            i += 1
            while i < n:
                if text[i] == "\\" and i + 1 < n:
                    i += 2
                    continue
                if text[i] == quote:
                    i += 1
                    break
                i += 1
            continue
        if ch == "[":
            m = re.match(r"\[(=*)\[", text[i:])
            if m:
                close_tok = "]" + m.group(1) + "]"
                end_idx = text.find(close_tok, i + len(m.group(0)))
                if end_idx == -1:
                    return -1
                i = end_idx + len(close_tok)
                continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def _split_top_level_args(arg_str):
    """Split Lua function call arguments on top-level commas."""
    args = []
    cur = []
    depth_paren = 0
    depth_brace = 0
    depth_bracket = 0
    i = 0
    n = len(arg_str)

    while i < n:
        ch = arg_str[i]
        if ch in ('"', "'"):
            quote = ch
            cur.append(ch)
            i += 1
            while i < n:
                c = arg_str[i]
                cur.append(c)
                if c == "\\" and i + 1 < n:
                    cur.append(arg_str[i + 1])
                    i += 2
                    continue
                if c == quote:
                    i += 1
                    break
                i += 1
            continue
        if ch == "[":
            m = re.match(r"\[(=*)\[", arg_str[i:])
            if m:
                close_tok = "]" + m.group(1) + "]"
                end_idx = arg_str.find(close_tok, i + len(m.group(0)))
                if end_idx != -1:
                    end_idx += len(close_tok)
                    cur.append(arg_str[i:end_idx])
                    i = end_idx
                    continue
        if ch == "(":
            depth_paren += 1
        elif ch == ")":
            depth_paren -= 1
        elif ch == "{":
            depth_brace += 1
        elif ch == "}":
            depth_brace -= 1
        elif ch == "[":
            depth_bracket += 1
        elif ch == "]":
            depth_bracket -= 1
        elif ch == "," and depth_paren == 0 and depth_brace == 0 and depth_bracket == 0:
            args.append("".join(cur).strip())
            cur = []
            i += 1
            continue
        cur.append(ch)
        i += 1

    tail = "".join(cur).strip()
    if tail:
        args.append(tail)
    return args


def _split_concat_parts(expr):
    """Split a Lua string concatenation expression on top-level '..'."""
    parts = []
    cur = []
    i = 0
    n = len(expr)
    depth = 0
    while i < n:
        ch = expr[i]
        if ch in ('"', "'"):
            quote = ch
            cur.append(ch)
            i += 1
            while i < n:
                c = expr[i]
                cur.append(c)
                if c == "\\" and i + 1 < n:
                    cur.append(expr[i + 1])
                    i += 2
                    continue
                if c == quote:
                    i += 1
                    break
                i += 1
            continue
        if ch in "({[":
            depth += 1
        elif ch in ")}]":
            depth -= 1
        elif depth == 0 and ch == "." and i + 1 < n and expr[i + 1] == ".":
            parts.append("".join(cur).strip())
            cur = []
            i += 2
            continue
        cur.append(ch)
        i += 1
    tail = "".join(cur).strip()
    if tail:
        parts.append(tail)
    return parts


def _eval_lua_expr(expr, env):
    """Resolve simple Lua string/var concatenations. Returns (value, fully_resolved)."""
    expr = expr.strip()
    if not expr:
        return "", False

    pieces = []
    fully_resolved = True
    for part in _split_concat_parts(expr):
        if len(part) >= 2 and ((part[0] == '"' and part[-1] == '"') or (part[0] == "'" and part[-1] == "'")):
            pieces.append(part[1:-1])
        elif re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", part):
            if part in env:
                pieces.append(str(env[part]))
            else:
                fully_resolved = False
                pieces.append(part)
        elif re.fullmatch(r"-?\d+", part):
            pieces.append(part)
        else:
            fully_resolved = False
            pieces.append(part)

    return "".join(pieces), fully_resolved


def _parse_lua_table(table_str, env):
    """Parse flat key=value pairs inside '{ ... }'."""
    inner = table_str.strip()
    if inner.startswith("{") and inner.endswith("}"):
        inner = inner[1:-1].strip()
    if not inner:
        return {}
    result = {}
    for entry in _split_top_level_args(inner):
        if "=" not in entry:
            continue
        k, v = entry.split("=", 1)
        k = k.strip()
        v = v.strip()
        if v in ("true", "false"):
            result[k] = (v == "true")
        elif re.fullmatch(r"-?\d+", v):
            result[k] = int(v)
        else:
            val, ok = _eval_lua_expr(v, env)
            result[k] = val if ok else v
    return result


def _format_lua_dsp(action_expr, env):
    """Translate hl.dsp.* / function() calls into (binder, dispatcher, params)."""
    expr = action_expr.strip()

    # Check inline function closure: function() ... end
    if expr.startswith("function"):
        dispatches = re.findall(r"hl\.dsp\.([A-Za-z0-9_.]+)\s*\(([^)]*)\)", expr)
        if dispatches:
            names = []
            for dpath, dargs in dispatches:
                short = dpath.split(".")[-1]
                dargs_clean = dargs.strip()
                if dargs_clean.startswith("{"):
                    tbl = _parse_lua_table(dargs_clean, env)
                    if tbl:
                        summary = " ".join(f"{k}={v}" for k, v in tbl.items())
                        names.append(f"{short}({summary})")
                        continue
                names.append(short)
            return "bind", " + ".join(names), ""
        return "bind", "lua-function", ""

    m_exec = re.fullmatch(r"hl\.dsp\.exec_cmd\((.*)\)", expr, flags=re.DOTALL)
    if m_exec:
        cmd, _ = _eval_lua_expr(m_exec.group(1), env)
        return "bind", "exec", cmd

    m_dsp = re.fullmatch(r"hl\.dsp\.([A-Za-z0-9_.]+)\((.*)\)", expr, flags=re.DOTALL)
    if not m_dsp:
        val, ok = _eval_lua_expr(expr, env)
        return "bind", "exec", val if ok else expr

    path = m_dsp.group(1)
    raw_args = m_dsp.group(2).strip()
    tbl = _parse_lua_table(raw_args, env) if raw_args.startswith("{") else {}

    if path == "window.close":
        return "bind", "killactive", ""
    if path == "window.fullscreen":
        if tbl.get("mode") == "maximized":
            return "bind", "fullscreen", "1"
        return "bind", "fullscreen", ""
    if path == "window.float":
        return "bind", "togglefloating", ""
    if path == "window.pseudo":
        return "bind", "pseudo", ""
    if path == "window.drag":
        return "bindm", "movewindow", ""
    if path == "window.resize":
        if not raw_args:
            return "bindm", "resizewindow", ""
        x_val = tbl.get("x", "")
        y_val = tbl.get("y", "")
        if x_val != "" or y_val != "":
            return "bind", "resizeactive", f"{x_val} {y_val}".strip()
        return "bind", "resizeactive", raw_args
    if path == "window.set_prop":
        prop = tbl.get("prop", "")
        val = tbl.get("value", "")
        return "bind", "setprop", f"active {prop} {val}".strip()
    if path == "window.move":
        if "direction" in tbl:
            return "bind", "movewindow", str(tbl["direction"])
        if "into_group" in tbl:
            return "bind", "moveintogroup", str(tbl["into_group"])
        if tbl.get("out_of_group"):
            return "bind", "moveoutofgroup", ""
        if "workspace" in tbl:
            ws = str(tbl["workspace"])
            disp = "movetoworkspacesilent" if tbl.get("follow") is False else "movetoworkspace"
            return "bind", disp, ws
        return "bind", "movewindow", raw_args
    if path == "window.swap":
        return "bind", "swapwindow", str(tbl.get("direction", raw_args))
    if path == "focus":
        if "direction" in tbl:
            return "bind", "movefocus", str(tbl["direction"])
        if "workspace" in tbl:
            return "bind", "workspace", str(tbl["workspace"])
        return "bind", "focus", raw_args
    if path == "workspace.toggle_special":
        arg_val, ok = _eval_lua_expr(raw_args, env) if raw_args else ("", True)
        return "bind", "togglespecialworkspace", arg_val if ok else raw_args
    if path == "workspace.move":
        return "bind", "movecurrentworkspacetomonitor", str(tbl.get("monitor", raw_args))
    if path == "group.toggle":
        return "bind", "togglegroup", ""
    if path == "group.next":
        return "bind", "changegroupactive", "f"
    if path == "group.prev":
        return "bind", "changegroupactive", "b"
    if path == "layout":
        arg_val, ok = _eval_lua_expr(raw_args, env) if raw_args else ("", True)
        return "bind", "layoutmsg", arg_val if ok else raw_args
    if path == "exit":
        return "bind", "exit", ""

    if tbl:
        summary = " ".join(f"{k}={v}" for k, v in tbl.items())
        return "bind", path, summary
    arg_val, ok = _eval_lua_expr(raw_args, env) if raw_args else ("", True)
    return "bind", path, arg_val if ok else raw_args


def _extract_calls_in_block(block, env):
    """Extract bind/unbind entries from a Lua code block under variable environment env."""
    events = []
    call_pattern = re.compile(r"\b(hl\.bind|hl\.unbind|bindCommand)\s*\(")
    pos = 0
    while True:
        m = call_pattern.search(block, pos)
        if not m:
            break
        callee = m.group(1)
        prefix = block[max(0, m.start() - 32):m.start()]
        # Skip function declarations such as `local function bindCommand(...)`
        if re.search(r"\bfunction\s+$", prefix):
            pos = m.end()
            continue

        open_paren = m.end() - 1
        close_paren = _find_matching_paren(block, open_paren)
        if close_paren == -1:
            pos = m.end()
            continue

        args = _split_top_level_args(block[open_paren + 1:close_paren])
        pos = close_paren + 1

        if not args:
            continue

        key_str, resolved = _eval_lua_expr(args[0], env)
        if not resolved or not key_str.strip():
            continue

        tokens = [t.strip() for t in key_str.split("+") if t.strip()]
        if not tokens:
            continue
        key = tokens[-1]
        mods = " ".join(tokens[:-1])

        if callee == "hl.unbind":
            events.append(("unbind", f"unbind = {mods}, {key}"))
            continue

        if len(args) < 2:
            continue

        desc = ""
        if callee == "bindCommand":
            cmd_str, ok = _eval_lua_expr(args[1], env)
            params = cmd_str if ok else args[1].strip()
            binder = "bind"
            dispatcher = "exec"
        else:
            binder, dispatcher, params = _format_lua_dsp(args[1], env)
            if len(args) >= 3:
                flags_tbl = _parse_lua_table(args[2], env)
                if flags_tbl.get("mouse") and not binder.endswith("m"):
                    binder = "bindm"
                if isinstance(flags_tbl.get("description"), str) and flags_tbl["description"]:
                    desc = flags_tbl["description"]
                    if "d" not in binder[4:]:
                        binder = f"{binder}d"

        if desc:
            if params:
                line = f"{binder} = {mods}, {key}, {desc}, {dispatcher}, {params}"
            else:
                line = f"{binder} = {mods}, {key}, {desc}, {dispatcher}"
        elif params:
            line = f"{binder} = {mods}, {key}, {dispatcher}, {params}"
        else:
            line = f"{binder} = {mods}, {key}, {dispatcher}"
        events.append(("bind", line))

    return events


def _collect_lua_vars(clean_text):
    """Collect simple top-level local string variable definitions."""
    env = {
        "home": "$HOME",
        "HOME": "$HOME",
        "mainMod": "SUPER",
    }
    for m in re.finditer(r"^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$", clean_text, flags=re.MULTILINE):
        var_name = m.group(1)
        rhs = m.group(2).strip()
        if rhs.startswith("function") or rhs.startswith("{") or "os.getenv" in rhs:
            continue
        val, ok = _eval_lua_expr(rhs, env)
        if ok:
            env[var_name] = val
    return env


def _expand_lua_for_loops(clean_text, base_env):
    """Expand simple `for` loops (ipairs, numeric, pairs) and return (stripped_text, events)."""
    events = []
    consumed_spans = []

    # 1. `for _, var in ipairs({ ... }) do ... end`
    ipairs_re = re.compile(
        r"\bfor\s+[A-Za-z_][A-Za-z0-9_]*\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s+in\s+ipairs\(\s*\{([^}]*)\}\s*\)\s+do\b(.*?)\bend\b",
        flags=re.DOTALL,
    )
    for m in ipairs_re.finditer(clean_text):
        var_name = m.group(1)
        items = re.findall(r'["\']([^"\']+)["\']', m.group(2))
        body = m.group(3)
        consumed_spans.append((m.start(), m.end()))
        # Detect simple table lookup like `local delta = ({left={x=-50,y=0}, ...})[d]`
        delta_map = {}
        delta_m = re.search(r"local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\(\s*\{(.*?)\}\s*\)\s*\[" + re.escape(var_name) + r"\]", body, flags=re.DOTALL)
        delta_var = None
        if delta_m:
            delta_var = delta_m.group(1)
            for km in re.finditer(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{([^}]*)\}", delta_m.group(2)):
                sub_tbl = _parse_lua_table("{" + km.group(2) + "}", base_env)
                delta_map[km.group(1)] = sub_tbl

        for item in items:
            iter_env = dict(base_env)
            iter_env[var_name] = item
            iter_body = body
            if delta_var and item in delta_map:
                for dk, dv in delta_map[item].items():
                    iter_env[f"{delta_var}.{dk}"] = str(dv)
                    iter_body = iter_body.replace(f"{delta_var}.{dk}", str(dv))
            events.extend(_extract_calls_in_block(iter_body, iter_env))

    # 2. `for var = start, stop do ... end`
    numeric_re = re.compile(
        r"\bfor\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\d+)\s*,\s*(\d+)\s+do\b(.*?)\bend\b",
        flags=re.DOTALL,
    )
    for m in numeric_re.finditer(clean_text):
        var_name = m.group(1)
        start_i = int(m.group(2))
        stop_i = int(m.group(3))
        body = m.group(4)
        consumed_spans.append((m.start(), m.end()))
        arith_vars = re.findall(
            r"local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*" + re.escape(var_name) + r"\s*([+-])\s*(\d+)",
            body,
        )
        for val_i in range(start_i, stop_i + 1):
            iter_env = dict(base_env)
            iter_env[var_name] = str(val_i)
            for av, op, num_s in arith_vars:
                num = int(num_s)
                iter_env[av] = str(val_i + num if op == "+" else val_i - num)
            events.extend(_extract_calls_in_block(body, iter_env))

    # 3. `for kvar, vvar in pairs({ ... }) do ... end`
    pairs_re = re.compile(
        r"\bfor\s+([A-Za-z_][A-Za-z0-9_]*)\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s+in\s+pairs\(\s*\{([^}]*)\}\s*\)\s+do\b(.*?)\bend\b",
        flags=re.DOTALL,
    )
    for m in pairs_re.finditer(clean_text):
        k_var = m.group(1)
        v_var = m.group(2)
        body = m.group(4)
        consumed_spans.append((m.start(), m.end()))
        for pm in re.finditer(r'([A-Za-z0-9_]+)\s*=\s*["\']([^"\']*)["\']', m.group(3)):
            iter_env = dict(base_env)
            iter_env[k_var] = pm.group(1)
            iter_env[v_var] = pm.group(2)
            events.extend(_extract_calls_in_block(body, iter_env))

    if not consumed_spans:
        return clean_text, events

    # Remove loop spans from clean_text so template binds inside loops aren't double-parsed
    consumed_spans.sort()
    pieces = []
    last = 0
    for s, e in consumed_spans:
        if s >= last:
            pieces.append(clean_text[last:s])
            last = e
    pieces.append(clean_text[last:])
    return "".join(pieces), events


def parse_lua_file(file_path):
    """Parse hl.bind / bindCommand / hl.unbind entries from a Hyprland .lua config."""
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        raw_text = f.read()

    clean_text = _strip_lua_comments(raw_text)
    base_env = _collect_lua_vars(clean_text)
    remaining_text, loop_events = _expand_lua_for_loops(clean_text, base_env)
    direct_events = _extract_calls_in_block(remaining_text, base_env)
    return direct_events + loop_events


def parse_files(files):
    binding_map = {}        # combo -> effective line
    source_map = {}         # combo -> source file
    user_bind_map = {}      # combo -> user bind line
    unbound_user = {}       # combo -> True if explicitly unbound in user file
    seen_any_bind = {}      # combo -> True if seen
    default_seen = {}       # combo -> True if default bind exists

    if not files:
        return [], []

    user_conf_path = find_user_conf_path(files)

    for file_path in files:
        if not os.path.exists(file_path):
            continue

        try:
            is_user_file = (file_path == user_conf_path)
            if file_path.endswith(".lua"):
                events = parse_lua_file(file_path)
            else:
                events = []
                with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                    for raw_line in f:
                        line = re.sub(r"\s+#.*$", "", raw_line.rstrip("\n")).rstrip()
                        if not line or line.lstrip().startswith("#"):
                            continue
                        if re.match(r"^\s*bind[a-z]*\s*=", line):
                            events.append(("bind", line))
                        elif re.match(r"^\s*unbind\s*=", line):
                            events.append(("unbind", line))

            for kind, line in events:
                combo_raw = extract_combo(line)
                if not combo_raw:
                    continue
                combo = normalize_combo(combo_raw)

                if kind == "bind":
                    seen_any_bind[combo] = True
                    if not is_user_file:
                        default_seen[combo] = True

                    # Prefer user bind, else first seen
                    if combo not in source_map:
                        binding_map[combo] = line
                        source_map[combo] = file_path

                    if is_user_file:
                        user_bind_map[combo] = line
                        binding_map[combo] = line
                        source_map[combo] = file_path

                elif kind == "unbind":
                    if is_user_file:
                        unbound_user[combo] = True
                    binding_map.pop(combo, None)
                    source_map.pop(combo, None)

        except Exception as e:
            sys.stderr.write(f"Error reading {file_path}: {e}\n")
            continue

    raw_keybinds = []
    missing_unbind_suggestions = []

    for combo in seen_any_bind:
        eff_line = binding_map.get(combo)
        src = source_map.get(combo)

        if not eff_line:
            continue

        raw_keybinds.append(eff_line)

        if (
            user_conf_path is not None
            and src == user_conf_path
            and combo in default_seen
            and combo not in unbound_user
        ):
            suggest = re.sub(r"^\s*bind[a-z]*", "unbind", eff_line)
            missing_unbind_suggestions.append(suggest)

    return raw_keybinds, missing_unbind_suggestions


def format_for_rofi(raw_binds):
    formatted_lines = []

    for line in raw_binds:
        match = re.match(r"^\s*(bind[a-z]*)\s*=(.*)", line)
        if not match:
            continue

        binder = match.group(1).replace(" ", "").replace("\t", "")
        rhs = match.group(2).strip()

        has_desc = binder.startswith("bind") and "d" in binder[4:]

        parts = [p.strip() for p in rhs.split(",")]

        if len(parts) < 2:
            continue

        mods = parts[0]
        key = parts[1]

        desc = ""
        dispatcher = ""
        params = ""

        if has_desc:
            desc = parts[2] if len(parts) >= 3 else ""
            dispatcher = parts[3] if len(parts) >= 4 else ""
            start_idx = 4
        else:
            dispatcher = parts[2] if len(parts) >= 3 else ""
            start_idx = 3

        remaining_parts = []
        if start_idx < len(parts):
            for i in range(start_idx, len(parts)):
                if parts[i]:
                    remaining_parts.append(parts[i])

        if remaining_parts:
            params = ", ".join(remaining_parts)

        mods = mods.replace("$mainMod", "SUPER")
        mods = re.sub(r"[ \t]+", "+", mods)

        if mods and key:
            combo_str = f"{mods}+{key}"
        elif key:
            combo_str = key
        else:
            combo_str = mods

        if has_desc and desc:
            formatted_lines.append(f"{combo_str} — {desc}")
        elif dispatcher:
            if params:
                formatted_lines.append(f"{combo_str} — {dispatcher} {params}")
            else:
                formatted_lines.append(f"{combo_str} — {dispatcher}")
        else:
            formatted_lines.append(combo_str)

    return formatted_lines


def main():
    if len(sys.argv) < 2:
        sys.exit(0)

    config_files = sys.argv[1:]

    binds, suggestions = parse_files(config_files)

    if not binds:
        print("no keybinds found.")
        sys.exit(1)

    formatted = format_for_rofi(binds)

    for line in formatted:
        print(line)

    if suggestions:
        import tempfile
        try:
            with tempfile.NamedTemporaryFile(mode="w", delete=False, prefix="hypr-unbind-suggestions-", suffix=".conf") as tf:
                tf.write("\n".join(suggestions) + "\n")
                with open("/tmp/hypr_keybind_suggestions_file", "w") as sf:
                    sf.write(tf.name)
        except Exception:
            pass


if __name__ == "__main__":
    main()
