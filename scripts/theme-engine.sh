#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Dynamic Material 3 Theming Engine
# ==============================================================================
# Extracts Material You palettes dynamically from wallpapers using Matugen/Wallust
# or internal Python fallback extractor, and synchronizes across:
# 1. Waybar (~/.config/waybar/colors.css)
# 2. Rofi (~/.config/rofi/colors.rasi)
# 3. SwayNC (~/.config/swaync/colors.css)
# 4. Hyprland (~/.config/hypr/colors.conf)
# 5. Kitty (~/.config/kitty/theme.conf)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

WALLPAPER_INPUT="${1:-}"
NO_RELOAD=false
if [[ "${2:-}" == "--no-reload" || "${1:-}" == "--no-reload" ]]; then
    NO_RELOAD=true
    if [[ "${1:-}" == "--no-reload" ]]; then
        WALLPAPER_INPUT="${2:-}"
    fi
fi

# Target destination directories (respecting $HOME for mock test environments)
CONFIG_ROOT="${HOME}/.config"
if [[ -n "${XDG_CONFIG_HOME:-}" && "$XDG_CONFIG_HOME" == "$HOME"/* ]]; then
    CONFIG_ROOT="$XDG_CONFIG_HOME"
fi
CACHE_ROOT="${HOME}/.cache"
if [[ -n "${XDG_CACHE_HOME:-}" && "$XDG_CACHE_HOME" == "$HOME"/* ]]; then
    CACHE_ROOT="$XDG_CACHE_HOME"
fi
HYPR_DIR="${CONFIG_ROOT}/hypr"
WAYBAR_DIR="${CONFIG_ROOT}/waybar"
ROFI_DIR="${CONFIG_ROOT}/rofi"
SWAYNC_DIR="${CONFIG_ROOT}/swaync"
KITTY_DIR="${CONFIG_ROOT}/kitty"
WALLUST_DIR="${CONFIG_ROOT}/wallust"

mkdir -p "$HYPR_DIR" "$WAYBAR_DIR" "$ROFI_DIR" "$SWAYNC_DIR" "$KITTY_DIR"

# 1. Resolve Wallpaper Path
TARGET_WALL=""
if [[ -n "$WALLPAPER_INPUT" && -f "$WALLPAPER_INPUT" ]]; then
    TARGET_WALL="$(readlink -f "$WALLPAPER_INPUT" 2>/dev/null || realpath "$WALLPAPER_INPUT")"
elif [[ -L "$HYPR_DIR/.current_wallpaper" && -f "$HYPR_DIR/.current_wallpaper" ]]; then
    TARGET_WALL="$(readlink -f "$HYPR_DIR/.current_wallpaper")"
elif [[ -f "$HYPR_DIR/.current_wallpaper" && -s "$HYPR_DIR/.current_wallpaper" ]]; then
    SAVED_WALL="$(head -n 1 "$HYPR_DIR/.current_wallpaper" 2>/dev/null | tr -d '\0\r' || true)"
    if [[ -n "$SAVED_WALL" && -f "$SAVED_WALL" ]]; then
        TARGET_WALL="$SAVED_WALL"
    fi
elif [[ -f "$HYPR_DIR/wallpaper.jpg" ]]; then
    TARGET_WALL="$HYPR_DIR/wallpaper.jpg"
elif [[ -f "$PROJECT_ROOT/assets/wallpapers/default.jpg" ]]; then
    TARGET_WALL="$PROJECT_ROOT/assets/wallpapers/default.jpg"
fi

# 2. Extract Palette (Wallust + Python PIL / stdlib Fallback)
echo ":: [Theme-Engine] Processing wallpaper: ${TARGET_WALL:-fallback}"

mkdir -p "$HYPR_DIR/wallust"
WALLUST_WROTE_HYPR=false
WALLUST_PALETTE_STR=""

if command -v wallust >/dev/null 2>&1 && [[ -n "$TARGET_WALL" && -f "$TARGET_WALL" ]]; then
    if [[ -f "$WALLUST_DIR/wallust.toml" ]] && grep -q 'wallust-hyprland\.conf' "$WALLUST_DIR/wallust.toml" 2>/dev/null; then
        mkdir -p "$CONFIG_ROOT/ghostty" "$WAYBAR_DIR/wallust" "$ROFI_DIR/wallust" "$KITTY_DIR/kitty-themes" 2>/dev/null || true
        if HOME="$HOME" XDG_CONFIG_HOME="$CONFIG_ROOT" XDG_CACHE_HOME="$CACHE_ROOT" wallust run -d "$WALLUST_DIR" -s -q "$TARGET_WALL" >/dev/null 2>&1 && [[ -s "$HYPR_DIR/wallust/wallust-hyprland.conf" ]]; then
            WALLUST_WROTE_HYPR=true
        fi
    fi

    # Extract 16-color scheme from wallust (either from freshly generated wallust-hyprland.conf or --print-scheme)
    if [[ "$WALLUST_WROTE_HYPR" = "true" ]]; then
        WALLUST_PALETTE_STR="$(awk '
            /^\$color[0-9]+[[:space:]]*=/ {
                if (match($0, /^\$color([0-9]+)[[:space:]]*=.*rgb\(([0-9A-Fa-f]{6})\)/, m)) {
                    c[m[1]+0] = "#" m[2]
                }
            }
            END {
                ok = 1
                for (i = 0; i < 16; i++) {
                    if (!(i in c)) { ok = 0; break }
                }
                if (ok) {
                    for (i = 0; i < 16; i++) print c[i]
                }
            }
        ' "$HYPR_DIR/wallust/wallust-hyprland.conf" 2>/dev/null || true)"
    fi

    if [[ -z "$WALLUST_PALETTE_STR" ]]; then
        WALLUST_PALETTE_STR="$(HOME="$HOME" XDG_CONFIG_HOME="$CONFIG_ROOT" XDG_CACHE_HOME="$CACHE_ROOT" wallust run -N -s -q -p dark16 --print-scheme "$TARGET_WALL" 2>/dev/null | grep -E '^#[0-9A-Fa-f]{6}$' | head -n 16 || true)"
    fi
fi

# We provide native integration with wallust if installed,
# backed by an ultra-fast Python PIL + stdlib Material 3 tone normalizer.
EXTRACTED_JSON=$(python3 -c "
import sys, json, os, colorsys

wall = sys.argv[1] if len(sys.argv) > 1 else ''
wallust_lines = [line.strip().lstrip('#') for line in (sys.argv[2] if len(sys.argv) > 2 else '').splitlines() if len(line.strip().lstrip('#')) == 6]

colors = {
    'primary': '#a8c7fa',
    'on_primary': '#042f65',
    'primary_container': '#254b73',
    'secondary': '#d3bbff',
    'surface': 'rgba(28, 27, 31, 0.72)',
    'surface_variant': 'rgba(44, 43, 48, 0.85)',
    'text': '#e3e2e6',
    'text_muted': '#8c9099',
    'border': 'rgba(255, 255, 255, 0.08)',
    'error': '#f2b8b5',
    'warning': '#fce788',
    'success': '#b4e09f',
    'palette': [
        '141316', 'f2b8b5', 'a8dab5', 'fde293',
        'a8c7fa', 'd3bbff', '99e7eb', 'e3e2e6',
        '44474f', 'f2b8b5', 'a8dab5', 'fde293',
        'a8c7fa', 'd3bbff', '99e7eb', 'ffffff'
    ]
}

if len(wallust_lines) >= 16:
    colors['palette'] = wallust_lines[:16]

def tone80_hex(hex_str):
    r = int(hex_str[0:2], 16) / 255.0
    g = int(hex_str[2:4], 16) / 255.0
    b = int(hex_str[4:6], 16) / 255.0
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    l = max(0.74, min(0.86, l))
    s = max(0.45, min(0.90, s))
    nr, ng, nb = colorsys.hls_to_rgb(h, l, s)
    return f'#{int(nr*255):02x}{int(ng*255):02x}{int(nb*255):02x}'

pil_done = False
if wall and os.path.isfile(wall):
    try:
        from PIL import Image
        img = Image.open(wall).convert('RGB')
        img.thumbnail((150, 150))
        palette = img.convert('P', palette=Image.ADAPTIVE, colors=8)
        color_counts = sorted(palette.getcolors(), reverse=True)
        palette_rgb = palette.getpalette()

        best_hls = None
        best_score = -1.0
        for count, idx in color_counts:
            r = palette_rgb[idx * 3] / 255.0
            g = palette_rgb[idx * 3 + 1] / 255.0
            b = palette_rgb[idx * 3 + 2] / 255.0
            h, l, s = colorsys.rgb_to_hls(r, g, b)
            score = (s + 0.15) * (1.0 - abs(l - 0.55))
            if score > best_score:
                best_score = score
                best_hls = (h, l, s)

        if best_hls:
            h, l, s = best_hls
            l = max(0.74, min(0.86, l))
            s = max(0.45, min(0.90, s))
            nr, ng, nb = colorsys.hls_to_rgb(h, l, s)
            colors['primary'] = f'#{int(nr*255):02x}{int(ng*255):02x}{int(nb*255):02x}'
            pil_done = True
    except Exception:
        pass

if len(wallust_lines) >= 16:
    if not pil_done:
        colors['primary'] = tone80_hex(colors['palette'][4])
    colors['secondary'] = tone80_hex(colors['palette'][5])
else:
    hex_p = colors['primary'].lstrip('#')
    colors['palette'][4] = hex_p
    colors['palette'][12] = hex_p

print(json.dumps(colors))
" "${TARGET_WALL:-}" "$WALLUST_PALETTE_STR" 2>/dev/null || echo "{}")

eval "$(python3 -c '
import sys, json, re
try:
    d = json.loads(sys.argv[1])
except Exception:
    d = {}
p = d.get("primary", "#a8c7fa")
s = d.get("secondary", "#d3bbff")
if not re.match(r"^#[0-9A-Fa-f]{6}$", str(p)): p = "#a8c7fa"
if not re.match(r"^#[0-9A-Fa-f]{6}$", str(s)): s = "#d3bbff"
pal = d.get("palette", [])
if not isinstance(pal, list) or len(pal) < 16:
    pal = ["141316","f2b8b5","a8dab5","fde293",p.lstrip("#"),"d3bbff","99e7eb","e3e2e6","44474f","f2b8b5","a8dab5","fde293",p.lstrip("#"),"d3bbff","99e7eb","ffffff"]
pal = [x if re.match(r"^[0-9A-Fa-f]{6}$", str(x)) else "a8c7fa" for x in pal[:16]]
print(f"PRIMARY={p}")
print(f"SECONDARY={s}")
for i, c in enumerate(pal):
    print(f"C{i}={c}")
' "$EXTRACTED_JSON")"

# 3. Generate Waybar colors (colors.css)
cat <<EOF > "$WAYBAR_DIR/colors.css"
/* Auto-generated by yusei-hypr theme-engine */
@define-color primary $PRIMARY;
@define-color on_primary #042f65;
@define-color primary_container #254b73;
@define-color secondary $SECONDARY;
@define-color surface rgba(28, 27, 31, 0.72);
@define-color surface_variant rgba(44, 43, 48, 0.85);
@define-color surface_hover rgba(58, 57, 63, 0.95);
@define-color text #e3e2e6;
@define-color text_muted #8c9099;
@define-color border rgba(255, 255, 255, 0.08);
@define-color error #f2b8b5;
@define-color warning #fce788;
@define-color success #b4e09f;
EOF

# 4. Generate Rofi colors (colors.rasi)
cat <<EOF > "$ROFI_DIR/colors.rasi"
/* Auto-generated by yusei-hypr theme-engine */
* {
    bg-col: rgba(28, 27, 31, 0.88);
    bg-card: rgba(44, 43, 48, 0.75);
    border-col: rgba(255, 255, 255, 0.12);
    selected-col: $PRIMARY;
    selected-fg: #042f65;
    fg-col: #e3e2e6;
    fg-muted: #8c9099;
}
EOF

# 5. Generate SwayNC colors (colors.css)
cat <<EOF > "$SWAYNC_DIR/colors.css"
/* Auto-generated by yusei-hypr theme-engine */
@define-color primary $PRIMARY;
@define-color on_primary #042f65;
@define-color secondary $SECONDARY;
@define-color surface rgba(28, 27, 31, 0.88);
@define-color surface_variant rgba(44, 43, 48, 0.75);
@define-color surface_hover rgba(58, 57, 63, 0.9);
@define-color text #e3e2e6;
@define-color text_muted #8c9099;
@define-color border rgba(255, 255, 255, 0.1);
@define-color error #f2b8b5;
@define-color on_error #601410;
EOF

# 6. Generate Hyprland colors (colors.conf)
HEX_STR="${PRIMARY#'#'}"
SEC_HEX_STR="${SECONDARY#'#'}"
cat <<EOF > "$HYPR_DIR/colors.conf"
# Auto-generated by yusei-hypr theme-engine
\$primary = rgba(${HEX_STR}ee)
\$primary_container = rgba(254b73ee)
\$on_primary = rgba(063258ee)
\$secondary = rgba(${SEC_HEX_STR}ee)
\$surface = rgba(141316ee)
\$surface_variant = rgba(2b292fee)
\$on_surface = rgba(e3e2e6ee)
\$outline = rgba(8c9099ee)
\$error = rgba(f2b8b5ee)

\$color0  = rgb(${C0})
\$color1  = rgb(${C1})
\$color2  = rgb(${C2})
\$color3  = rgb(${C3})
\$color4  = rgb(${C4})
\$color5  = rgb(${C5})
\$color6  = rgb(${C6})
\$color7  = rgb(${C7})
\$color8  = rgb(${C8})
\$color9  = rgb(${C9})
\$color10 = rgb(${C10})
\$color11 = rgb(${C11})
\$color12 = rgb(${C12})
\$color13 = rgb(${C13})
\$color14 = rgb(${C14})
\$color15 = rgb(${C15})
EOF

# 6b. Always regenerate Wallust-compatible Hyprland colors unless wallust templates just updated it
mkdir -p "$HYPR_DIR/wallust"
if [[ "$WALLUST_WROTE_HYPR" != "true" ]]; then
    cat <<EOF > "$HYPR_DIR/wallust/wallust-hyprland.conf"
# Auto-generated by yusei-hypr theme-engine for Wallust compatibility
\$background = rgb(${C0})
\$foreground = rgb(${C7})
\$color0  = rgb(${C0})
\$color1  = rgb(${C1})
\$color2  = rgb(${C2})
\$color3  = rgb(${C3})
\$color4  = rgb(${C4})
\$color5  = rgb(${C5})
\$color6  = rgb(${C6})
\$color7  = rgb(${C7})
\$color8  = rgb(${C8})
\$color9  = rgb(${C9})
\$color10 = rgb(${C10})
\$color11 = rgb(${C11})
\$color12 = rgb(${C12})
\$color13 = rgb(${C13})
\$color14 = rgb(${C14})
\$color15 = rgb(${C15})
EOF
fi

# 7. Generate Kitty theme (theme.conf)
cat <<EOF > "$KITTY_DIR/theme.conf"
# Auto-generated by yusei-hypr theme-engine
background #${C0}
foreground #${C7}
selection_background $PRIMARY
selection_foreground #042f65

color0 #${C0}
color8 #${C8}
color1 #${C1}
color9 #${C9}
color2 #${C2}
color10 #${C10}
color3 #${C3}
color11 #${C11}
color4 $PRIMARY
color12 $PRIMARY
color5 #${C5}
color13 #${C13}
color6 #${C6}
color14 #${C14}
color7 #${C7}
color15 #${C15}
EOF

# 8. Record State Persistence
if [[ -n "$TARGET_WALL" ]]; then
    ln -sf "$TARGET_WALL" "$HYPR_DIR/.current_wallpaper"
fi
echo "material-3" > "$HYPR_DIR/.current_theme"

# 9. Non-Destructive Live Reload Signals
# Gracefully signal running daemons if active (skip when called with --no-reload)
if [[ "$NO_RELOAD" != "true" ]]; then
    swaync-client -rs 2>/dev/null || true
    pkill -SIGUSR2 waybar 2>/dev/null || true
    pkill -SIGUSR1 kitty 2>/dev/null || true
    hyprctl reload config-only 2>/dev/null || hyprctl reload 2>/dev/null || true
fi

echo ":: [Theme-Engine] Successfully synchronized colors across all desktop components."
