"""
Visual Preview Generator Engine
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Renders card mockups, SVG badges, and structural previews for
Waybar layouts, Kitty color swatches, and Rofi launcher structures.
"""

from typing import Dict, Any

class PreviewEngine:
    @staticmethod
    def generate_waybar_svg(position: str = "TOP", title: str = "Pill Island") -> str:
        """Generates a clean vector SVG mockup of a Waybar layout."""
        pos = position.upper()
        if pos == "BOTTOM":
            bar_y = 66
            bar_x = 20
            bar_w = 260
            bar_h = 22
        elif pos == "LEFT":
            bar_y = 10
            bar_x = 10
            bar_w = 24
            bar_h = 76
        elif pos == "RIGHT":
            bar_y = 10
            bar_x = 266
            bar_w = 24
            bar_h = 76
        elif pos == "SPLIT":
            # Dual bar top and bottom
            return '''<svg width="300" height="96" viewBox="0 0 300 96" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="300" height="96" rx="8" fill="#1b1c20"/>
  <!-- Top Split Bar -->
  <rect x="25" y="8" width="250" height="18" rx="9" fill="#2d2f38" stroke="#454854" stroke-width="1"/>
  <circle cx="36" cy="17" r="4" fill="#a8c7fa"/>
  <rect x="46" y="14" width="30" height="6" rx="3" fill="#697386"/>
  <rect x="135" y="14" width="30" height="6" rx="3" fill="#d3bbff"/>
  <rect x="235" y="14" width="30" height="6" rx="3" fill="#b4e09f"/>
  <!-- Bottom Split Bar -->
  <rect x="25" y="70" width="250" height="18" rx="9" fill="#2d2f38" stroke="#454854" stroke-width="1"/>
  <rect x="36" y="76" width="40" height="6" rx="3" fill="#a8c7fa"/>
  <rect x="225" y="76" width="40" height="6" rx="3" fill="#f2b8b5"/>
</svg>'''
        else: # TOP
            bar_y = 8
            bar_x = 20
            bar_w = 260
            bar_h = 22

        if pos in ["LEFT", "RIGHT"]:
            return f'''<svg width="300" height="96" viewBox="0 0 300 96" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="300" height="96" rx="8" fill="#1b1c20"/>
  <!-- Screen Desktop Placeholder -->
  <rect x="42" y="10" width="216" height="76" rx="6" fill="#25272e" opacity="0.6"/>
  <!-- Vertical Bar -->
  <rect x="{bar_x}" y="{bar_y}" width="{bar_w}" height="{bar_h}" rx="10" fill="#2f313c" stroke="#484b59" stroke-width="1"/>
  <circle cx="{bar_x + 12}" cy="22" r="5" fill="#a8c7fa"/>
  <circle cx="{bar_x + 12}" cy="36" r="4" fill="#d3bbff"/>
  <circle cx="{bar_x + 12}" cy="48" r="4" fill="#b4e09f"/>
  <circle cx="{bar_x + 12}" cy="74" r="5" fill="#f2b8b5"/>
</svg>'''

        return f'''<svg width="300" height="96" viewBox="0 0 300 96" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="300" height="96" rx="8" fill="#1b1c20"/>
  <!-- Screen Desktop Area -->
  <rect x="20" y="36" width="260" height="50" rx="4" fill="#25272e" opacity="0.6"/>
  <!-- Floating Pill Island Bar -->
  <rect x="{bar_x}" y="{bar_y}" width="{bar_w}" height="{bar_h}" rx="11" fill="#2f313c" stroke="#484b59" stroke-width="1"/>
  <!-- Launcher Icon -->
  <circle cx="{bar_x + 12}" cy="{bar_y + 11}" r="5" fill="#a8c7fa"/>
  <!-- Workspaces -->
  <rect x="{bar_x + 24}" y="{bar_y + 8}" width="12" height="6" rx="3" fill="#a8c7fa"/>
  <circle cx="{bar_x + 44}" cy="{bar_y + 11}" r="3" fill="#585c6d"/>
  <circle cx="{bar_x + 54}" cy="{bar_y + 11}" r="3" fill="#585c6d"/>
  <!-- Center Clock -->
  <rect x="130" y="{bar_y + 7}" width="40" height="8" rx="4" fill="#d3bbff"/>
  <!-- Right Status Modules -->
  <rect x="{bar_x + bar_w - 65}" y="{bar_y + 7}" width="16" height="8" rx="4" fill="#b4e09f"/>
  <rect x="{bar_x + bar_w - 44}" y="{bar_y + 7}" width="16" height="8" rx="4" fill="#fce788"/>
  <rect x="{bar_x + bar_w - 23}" y="{bar_y + 7}" width="14" height="8" rx="4" fill="#f2b8b5"/>
</svg>'''

    @staticmethod
    def generate_kitty_svg(palette: Dict[str, Any]) -> str:
        """Generates a terminal preview with window buttons and palette swatches."""
        bg = palette.get("background", "#141316")
        fg = palette.get("foreground", "#e3e2e6")
        swatches = palette.get("swatches", ["#1f1f23", "#f2b8b5", "#b4e09f", "#fce788", "#a8c7fa", "#d3bbff", "#99e7eb", "#e3e2e6"])
        
        swatches_svg = ""
        for i, color in enumerate(swatches[:8]):
            x = 24 + (i * 32)
            swatches_svg += f'<rect x="{x}" y="56" width="24" height="20" rx="4" fill="{color}" />\n'

        return f'''<svg width="300" height="96" viewBox="0 0 300 96" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="300" height="96" rx="8" fill="{bg}" stroke="#3b3e4a" stroke-width="1"/>
  <!-- Terminal Window Titlebar Buttons -->
  <circle cx="20" cy="18" r="4" fill="#ff5f56"/>
  <circle cx="32" cy="18" r="4" fill="#ffbd2e"/>
  <circle cx="44" cy="18" r="4" fill="#27c93f"/>
  <rect x="60" y="15" width="60" height="6" rx="3" fill="#4d5162"/>
  <!-- Terminal Prompt line -->
  <text x="24" y="42" font-family="monospace" font-size="11" fill="{fg}">user@arch:~$ colors</text>
  <!-- Palette Swatches -->
  {swatches_svg}
</svg>'''

    @staticmethod
    def generate_rofi_svg(style_type: str = "Centered Card") -> str:
        """Generates a miniature Rofi launcher window diagram."""
        if "Fullscreen" in style_type:
            return '''<svg width="300" height="96" viewBox="0 0 300 96" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="300" height="96" rx="8" fill="#141318" stroke="#3d3e48" stroke-width="1"/>
  <!-- Top Search Bar -->
  <rect x="30" y="12" width="240" height="20" rx="10" fill="#282933" stroke="#484a58" stroke-width="1"/>
  <circle cx="44" cy="22" r="4" fill="#a8c7fa"/>
  <!-- Grid of App Tiles -->
  <rect x="30" y="42" width="52" height="38" rx="6" fill="#242630"/>
  <rect x="92" y="42" width="52" height="38" rx="6" fill="#242630"/>
  <rect x="154" y="42" width="52" height="38" rx="6" fill="#242630"/>
  <rect x="216" y="42" width="52" height="38" rx="6" fill="#a8c7fa" opacity="0.3"/>
</svg>'''
        else: # Centered Card
            return '''<svg width="300" height="96" viewBox="0 0 300 96" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="300" height="96" rx="8" fill="#18191f"/>
  <!-- Centered Modal Card -->
  <rect x="50" y="10" width="200" height="76" rx="12" fill="#282933" stroke="#4a4d5e" stroke-width="1"/>
  <!-- Search Pill -->
  <rect x="64" y="20" width="172" height="18" rx="9" fill="#1b1c23" stroke="#3b3d4a" stroke-width="1"/>
  <circle cx="76" cy="29" r="4" fill="#a8c7fa"/>
  <!-- App List rows -->
  <rect x="64" y="46" width="80" height="14" rx="4" fill="#a8c7fa" opacity="0.8"/>
  <rect x="156" y="46" width="80" height="14" rx="4" fill="#353745"/>
  <rect x="64" y="66" width="80" height="12" rx="4" fill="#353745"/>
  <rect x="156" y="66" width="80" height="12" rx="4" fill="#353745"/>
</svg>'''
