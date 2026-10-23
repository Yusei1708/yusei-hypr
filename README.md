<div align="center">

```
  ██╗   ██╗██╗   ██╗███████╗███████╗██╗    ██╗  ██╗██╗   ██╗██████╗ ██████╗ 
  ╚██╗ ██╔╝██║   ██║██╔════╝██╔════╝██║    ██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗
   ╚████╔╝ ██║   ██║███████╗█████╗  ██║    ███████║ ╚████╔╝ ██████╔╝██████╔╝
    ╚██╔╝  ██║   ██║╚════██║██╔══╝  ██║    ██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══██╗
     ██║   ╚██████╔╝███████║███████╗██║    ██║  ██║   ██║   ██║     ██║  ██║
     ╚═╝    ╚═════╝ ╚══════╝╚══════╝╚═╝    ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝
```

# ✨ yusei-hypr ✨
### Universal Material 3 Desktop Suite & Automated Installer for Arch Linux
*Fusing End-4's Modern Material 3 (Material You) Design System with JaKooLit's Battle-Tested Operational Backbone*

<br/>

[![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=for-the-badge&logo=archlinux&logoColor=white)](https://archlinux.org/)
[![Hyprland](https://img.shields.io/badge/Hyprland-00a8ff?style=for-the-badge&logo=wayland&logoColor=white)](https://hyprland.org/)
[![Design Language](https://img.shields.io/badge/Design-End--4_Material_3-d3bbff?style=for-the-badge)](https://github.com/end-4/dots-hyprland)
[![Operational Core](https://img.shields.io/badge/Core-JaKooLit_Backbone-ff79c6?style=for-the-badge)](https://github.com/JaKooLit/Arch-Hyprland)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue?style=for-the-badge)](LICENSE)

<br/>

[![GitHub Stars](https://img.shields.io/github/stars/Yusei1708/yusei-hypr?style=flat-square&logo=github&color=86dbd7&labelColor=1e1e2e)](https://github.com/Yusei1708/yusei-hypr/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/Yusei1708/yusei-hypr?style=flat-square&logo=github&color=8ad7eb&labelColor=1e1e2e)](https://github.com/Yusei1708/yusei-hypr/network/members)
[![Last Commit](https://img.shields.io/github/last-commit/Yusei1708/yusei-hypr?style=flat-square&logo=git&color=b4befe&labelColor=1e1e2e)](https://github.com/Yusei1708/yusei-hypr/commits/main)
[![Repository Size](https://img.shields.io/github/repo-size/Yusei1708/yusei-hypr?style=flat-square&logo=github&color=cdd6f4&labelColor=1e1e2e)](https://github.com/Yusei1708/yusei-hypr)

<br/>

[🌟 Highlights](#-highlights) •
[🚀 What's New in v1.5.0](#-whats-new-in-v150-release-highlights) •
[🏛️ Architecture](#-system-architecture) •
[🧩 Components](#-component-matrix) •
[⚙️ Settings App](#-yusei-settings-control-center) •
[🧰 Optional Apps](#-optional-applications--system-tools) •
[🚀 Installation](#-installation-guide) •
[🔄 Updates](#-system-updates-updatesh) •
[🗑️ Uninstall](#-clean-uninstallation-uninstallsh) •
[🎨 Theming](#-dynamic-theming-engine-material-you) •
[⌨️ Keybindings](#-keybindings-reference) •
[🛡️ Safety & Rollback](#-safety-backups--instant-rollback) •
[🔧 FAQ](#-troubleshooting--faq) •
[📜 License](#-license)

</div>

---

## 💡 Overview & Philosophy

**yusei-hypr** is an enterprise-grade, universal Hyprland desktop suite engineered for **Arch Linux**. It is specifically designed to eliminate the historic dilemma faced by Wayland rice enthusiasts:

> **Choose between jaw-dropping aesthetics with fragile scripts, OR rock-solid stability with dated visuals.**

By separating the visual presentation layer from the core operational layer, **yusei-hypr** delivers the best of both worlds:

- **Aesthetics (End-4)**: Pure Material 3 design philosophy, uniform 16px corner rounding, floating pill module docks, controlled dual-pass Kawase blur, physics-based bezier animations, and dynamic wallpaper color extraction (Material You).
- **Functionality (JaKooLit)**: 100% keybinding parity (131+ annotated actions), 64 battle-tested system scripts, zero-collision singleton daemons, robust multi-monitor auto-detection, comprehensive laptop optimizations, and out-of-the-box NVIDIA graphics support.

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                 yusei-hypr DESKTOP SUITE                               │
├───────────────────────────────────────────┬────────────────────────────────────────────┤
│         VISUAL SYSTEM (End-4 Inspired)    │      OPERATIONAL CORE (JaKooLit Backbone)  │
├───────────────────────────────────────────┼────────────────────────────────────────────┤
│ • Material 3 Floating Pill Dock (Waybar)  │ • 100% Keybinding Parity (131 bindd rules) │
│ • Centered Floating App Launcher (Rofi)   │ • 64 Hardened Operational System Scripts   │
│ • Control Center & Toggles (SwayNC)       │ • Semantic Window Tagging & PiP Rules      │
│ • Expressive Physics Curves (Animations)  │ • Zero-Collision Singleton Daemon Guards   │
│ • Dynamic Wallpaper Theming (Material You)│ • Dual-GPU & NVIDIA Driver Auto Config     │
│ • 16px Rounded Corners & Kawase Blur      │ • Universal Multi-Monitor Dynamic Scaling  │
└───────────────────────────────────────────┴────────────────────────────────────────────┘
```

---

## 🌟 Highlights

- 🎨 **End-4 Material 3 (Material You) Design System**:
  - Consistent 16px corner radius across Waybar, Rofi, SwayNC, Hyprlock, and Kitty.
  - Floating pill-island architecture with subtle borders and ambient drop shadows.
  - Controlled transparency and Kawase blur without GPU frame-dropping or visual artifacts.
- 🔄 **Real-Time Dynamic Theming Pipeline (`scripts/theme-engine.sh`)**:
  - Select any wallpaper to automatically generate harmonic Material You color tokens via Matugen, Wallust, or Python fallback.
  - Synchronously updates Waybar (`colors.css`), Rofi (`colors.rasi`), SwayNC (`colors.css`), Hyprland (`colors.conf`), and Kitty (`theme.conf`).
  - Seamless hot-reloading with zero session disruption; settings persist across reboots.
- ⌨️ **100% JaKooLit Keybinding Parity**:
  - Preserves every window navigation, scratchpad, floating toggle, grouping, and Fn multimedia shortcut.
  - Standardized on hardware-independent keycodes (`code:10..19`) for full international keyboard layout compatibility.
- 🛡️ **Zero-Conflict Singleton Daemon Supervisor (`scripts/launch-daemons.sh`)**:
  - Strict lifecycle management ensuring exactly one Waybar bar, one SwayNC notification center, and one SWWW wallpaper daemon run at any time.
  - Prevents zombie process accumulation, D-Bus lockups, and CPU spikes.
- ⚡ **Zero-Touch Hardware Detection (`scripts/01-detect.sh`)**:
  - Auto-identifies NVIDIA, Intel, and AMD GPUs.
  - Automatically activates optimized Wayland driver environments (`GBM_BACKEND,nvidia-drm`, `LIBVA_DRIVER_NAME,nvidia`).
  - Dynamic laptop battery, backlight, and touchpad gesture integration.
- 🇻🇳 **Vietnamese IME Out of the Box**:
  - Native Wayland input method configuration for `Fcitx5` (Bamboo & Unikey engines).
  - Pre-configured across Qt, GTK, SDL, and Chromium/Electron desktop applications.
- 👾 **Pokemon Fastfetch Terminal Greeting**:
  - Automatically displays randomized pixel-art Pokemon alongside clean system metrics upon opening Kitty or any terminal shell.
  - Native integration with `pokemon-colorscripts` and optimized `config-pokemon.jsonc`.
- 🧰 **Interactive Post-Install App Store (`scripts/05-optional-apps.sh`)**:
  - Interactive TUI checklist (Whiptail/Dialog with pure-Bash fallback) to easily select and install popular apps: Google Chrome, Brave, Mission Center, GParted, Timeshift, UFW, SDDM with Sugar Candy theme, Git, VS Code, Btop.
  - Automatically identifies pre-existing software, supports `--dry-run` safe simulations, and triggers system service setups (SDDM login theme & UFW firewall).
- 🔒 **Enterprise-Grade Backup & Rollback Protocol**:
  - Automated timestamped snapshots with `manifest.json` before any configuration file is modified.
  - 1-command idempotent `scripts/rollback.sh` restores your exact pre-installation state in seconds.

---

## 🚀 What's New in v1.5.0 (Release Highlights)

The **v1.5.0** release delivers significant compositor upgrades, gaming latency optimizations, security polish, portable config parsing, and dedicated daily driver power tools:

| Feature / Subsystem | Configuration & Implementation | Highlights & Capabilities |
| :--- | :--- | :--- |
| **Window Swallowing** | `misc:enable_swallow = true`<br/>`misc:swallow_regex = ^(kitty\|Alacritty)$` | Launching GUI applications directly from `kitty` or `Alacritty` automatically swallows the parent terminal window, seamlessly restoring it when the child process exits. |
| **Gaming Low-Latency Tearing** | `general:allow_tearing = true`<br/>`windowrule = match:tag games, immediate on`<br/>Modernized `GameMode.sh` | Immediate tearing mode enabled for designated gaming window tags without compositor latency penalty; atomic batch execution in `GameMode.sh` dynamically toggles tearing, animations, and blur without syntax errors. |
| **Hyprlock Security & Polish** | `general { grace = 5; hide_cursor = true }`<br/>`capslock_color = rgba(255, 180, 0, 0.8)`<br/>Laptop battery telemetry label | 5-second grace period (`--grace 5`) allows instantaneous unlock upon accidental lock triggers; auto-hides cursor; amber visual cue on active CapsLock; dynamic hardware battery telemetry on laptops (`/sys/class/power_supply/BAT*`). |
| **Screen Recording Tool** | `config/hypr/scripts/ScreenRecord.sh`<br/>Keybinds: `$mainMod ALT, R` & `$mainMod SHIFT ALT, R` | Comprehensive screen recording supporting `--toggle`, `--region`, `--fullscreen`, `--audio`, and `--status` using `wf-recorder`/`wl-screenrec`, with interactive SwayNC notifications and automatic storage in `~/Videos/Recordings/`. |
| **OCR Text Grabber** | `config/hypr/scripts/OcrGrab.sh`<br/>Keybind: `$mainMod SHIFT, O` | High-speed optical character recognition pipeline combining `grim` + `slurp` + `tesseract` + `wl-copy` with multi-language fallback (`eng+vie`), desktop notification preview, and audio feedback. |
| **Dedicated Scratchpads** | `special:music` on `$mainMod SHIFT, M`<br/>`special:monitor` on `$mainMod SHIFT, B` | Instant dropdown scratchpad workspaces with automated launching (`on-created-empty`) for Spotify music and Btop system monitor. |
| **Relative Config Sourcing** | `source = ./userprefs.conf`<br/>`source = ./colors.conf` | Replaces legacy `~/.config` absolute paths with relative imports, enabling 100% standalone headless verification (`Hyprland -c config/hypr/hyprland.conf --verify-config`) in CI and portable sandboxes. |

---

## 🏛️ System Architecture

The codebase enforces an 8-layer decoupled design pattern where each domain maintains zero direct cyclic dependencies:

```text
yusei-hypr/
├── LICENSE                     # GNU General Public License v3.0 text
├── install.sh                  # Interactive CLI entrypoint & non-interactive flags (-y)
├── update.sh                   # Root updater: git sync, pre-backup & config sync (userprefs.conf protected)
├── uninstall.sh                # Root uninstaller: curses radiolist snapshot picker & system cleanup
├── README.md                   # Technical reference & user manual
├── .gitignore                  # Git development exclusions
├── assets/
│   └── wallpapers/             # Bundled 4K high-resolution wallpapers
├── bin/
│   ├── yusei-settings          # Control Center CLI/GUI/Web launcher
│   └── theme-engine.sh         # Dynamic Material You color extraction CLI wrapper
├── yusei_settings/             # Zero-dependency Control Center (Python standard library)
│   ├── core/                   # Discovery, 5-stage Safety, Keybind Parser, State engines
│   ├── ui/                     # Windows 11 Fluent Web UI & GTK4 Adwaita frontend
│   └── server.py               # Local HTTP API server (/api/keybinds, /api/system/*)
├── scripts/                    # Automation & Lifecycle Management
│   ├── power-optimizer.sh      # Core power optimizer & dynamic refresh rate engine (eco, balanced, turbo)
│   ├── hardware-detect.sh      # Standalone hardware detection subsystem (GPU, Chassis, Audio)
│   ├── 01-detect.sh            # Distro, GPU (NVIDIA/Intel/AMD), and chassis probe compatibility shim
│   ├── 02-packages.sh          # Dependency resolver using pacman and yay/paru
│   ├── 03-backup.sh            # Standardized snapshot generator (~/.config/yusei-hypr-backup-<timestamp>/ with manifest.json)
│   ├── 04-install-configs.sh   # Layered deployment & config/hypr/userprefs.conf preservation
│   ├── 05-optional-apps.sh     # Optional curated app checklist & TUI installer
│   ├── rollback.sh             # Idempotent 1-command rollback engine (restores backup snapshots)
│   ├── theme-engine.sh         # Dynamic Material You color extractor & dispatcher
│   └── launch-daemons.sh       # Singleton daemon lifecycle supervisor
├── tests/                           # Comprehensive automated test suite
│   ├── test_syntax.sh               # Shell syntax (bash -n) and JSON validation
│   ├── test_docs_and_licensing.sh   # GPL-3.0 licensing & documentation checks
│   ├── test_config_isolation.sh     # userprefs.conf preservation & backups
│   ├── test_hardware_detect.sh      # Hardware detection subsystem test harness
│   ├── test_management_scripts.sh   # update.sh & uninstall.sh lifecycle tests
│   ├── test_power_optimizer.sh      # Power optimizer & dynamic refresh rate tests
│   └── run-all-tests.sh             # Master test runner (all 7 suites)
└── config/
    ├── hypr/                   # Compositor Layer (Hyprland Core)
    │   ├── hyprland.conf       # 8-layer modular configuration loader (sources userprefs.conf)
    │   ├── userprefs.conf      # Layer 8: Isolated user customization (Monitors, env, autostart, custom binds)
    │   ├── keybinds.conf       # 159 annotated shortcuts with hardware keycodes & bindd
    │   ├── rules.conf          # Semantic window tags, floating dialogs, PiP rules
    │   ├── autostart.conf      # D-Bus, systemd environment, Polkit, daemons
    │   ├── animations.conf     # Physics-based expressive bezier curves
    │   ├── decorations.conf    # 16px rounding, Kawase blur passes, shadows & dynamic border tokens
    │   ├── env.conf            # Toolkit environments, Wayland flags & Fcitx5 IME
    │   ├── monitors.conf       # Universal multi-monitor auto-resolution
    │   ├── nvidia.conf         # Dedicated NVIDIA driver parameters
    │   ├── colors.conf         # Dynamically generated Hyprland color tokens ($primary $secondary)
    │   ├── hypridle.conf       # 4-stage idle power listener
    │   ├── hyprlock.conf       # Modern pill input lockscreen
    │   ├── scripts/            # 66 verified operational utility scripts (including ScreenRecord.sh & OcrGrab.sh)
    │   ├── UserScripts/        # Custom user extension scripts
    │   ├── UserConfigs/        # JaKooLit modular user override configs
    │   └── wallpaper_effects/  # Shader & ImageMagick effect definitions
    ├── waybar/                 # Status Bar & Multi-Layout Ecosystem
    │   ├── config.jsonc        # End-4 Material 3 responsive floating island layout (Default)
    │   ├── style.css           # End-4 Material 3 16px rounded pill style (Default)
    │   ├── configs/            # 40+ JaKooLit Waybar layouts ([TOP], [BOT], [LEFT], [RIGHT], split)
    │   ├── style/              # 40+ JaKooLit Waybar CSS styles (Translucent, Neon, Catppuccin, etc.)
    │   ├── Modules*            # Modular Waybar module blocks & groups
    │   └── colors.css          # Dynamic color tokens
    ├── rofi/                   # App Launcher & Utility Dialog Suite
    │   ├── config.rasi         # End-4 centered card launcher (Default)
    │   ├── themes/             # 20+ alternate Rofi themes (Win11, Solarized, Fullscreen, etc.)
    │   ├── config-*.rasi       # 16 dedicated utility dialogs (Clipboard, Animations, Beats, etc.)
    │   └── colors.rasi         # Dynamic color tokens
    ├── swaync/                 # Notification & Control Center
    │   ├── config.json         # Widgets with buttons-grid (DND, Wi-Fi, Bluetooth)
    │   ├── style.css           # Material 3 control center styling
    │   ├── colors.css          # Dynamic color tokens
    │   └── icons/              # 21 bundled system notification icons
    ├── kitty/                  # Terminal Workstation & Theme Library
    │   ├── kitty.conf          # Decoupled terminal setup with remote reload
    │   ├── kitty-themes/       # 170+ curated Kitty themes (Catppuccin, Gruvbox, TokyoNight, etc.)
    │   └── theme.conf          # Dynamic color palette tokens
    ├── wlogout/                # Material 3 Power & Session Menu
    │   ├── layout              # Lock, Logout, Suspend, Hibernate, Reboot, Shutdown
    │   ├── style.css           # Glassmorphism & dynamic colors
    │   └── icons/              # Session action vector icons
    ├── Kvantum/                # Kvantum SVG-based Qt widget theme engine
    ├── qt5ct/ & qt6ct/         # Qt5 & Qt6 configuration tool palettes (Catppuccin, etc.)
    ├── fastfetch/              # System Telemetry & Pokemon banner configs
    ├── btop/                   # GPU & CPU System Resource Monitor
    ├── cava/                   # Real-Time Desktop Audio Visualizer
    ├── swappy/                 # Screenshot Annotation & Editor Tool
    └── wallust/                # Universal Color Palette Templates
```

---

## 🧩 Component Matrix

| Category | Component | Upstream Project | Visual Style & Role |
| :--- | :--- | :--- | :--- |
| **Settings Center** | Yusei Settings | Built-in | Windows 11-style Fluent Control Center & Theme Gallery with 5-stage safe apply engine |
| **Compositor** | Hyprland | [hyprwm/hyprland](https://github.com/hyprwm/hyprland) | Dynamic Wayland compositor, Dwindle layout, physics animations |
| **Status Bar** | Waybar | [Alexays/Waybar](https://github.com/Alexays/Waybar) | Floating pill islands, workspace pill indicators, reactive notification bell |
| **App Launcher** | Rofi (Wayland) | [lbonn/rofi](https://github.com/lbonn/rofi) | Centered 16px card layout, dual-column grid, search pill input |
| **Notifications** | SwayNC | [ErikReider/SwayNC](https://github.com/ErikReider/SwayNotificationCenter) | Material 3 Control Center, quick toggles, volume & brightness sliders |
| **Terminal** | Kitty | [kovidgoyal/kitty](https://github.com/kovidgoyal/kitty) | GPU-accelerated terminal, background blur, dynamic theme sourcing |
| **Power Menu** | Wlogout | [Hjdskes/wlogout](https://github.com/Hjdskes/wlogout) | Material 3 card grid for Lock, Reboot, Suspend, Shutdown, Exit |
| **Wallpaper** | SWWW | [LGFae/swww](https://github.com/LGFae/swww) | Zero-overhead animated Wayland wallpaper daemon (20 curated wallpapers) |
| **Lock Screen** | Hyprlock | [hyprwm/hyprlock](https://github.com/hyprwm/hyprlock) | Modern pill input field, digital clock, date, dynamic theme sourcing |
| **Power Management** | Hypridle | [hyprwm/hypridle](https://github.com/hyprwm/hypridle) | 4-stage timeout: backlight dim $\rightarrow$ lock $\rightarrow$ DPMS off $\rightarrow$ suspend |
| **System Info** | Fastfetch | [fastfetch-cli](https://github.com/fastfetch-cli/fastfetch) | Instant system logo and hardware diagnostic display |
| **System Monitor** | Btop | [aristocratos/btop](https://github.com/aristocratos/btop) | Terminal-based interactive process, CPU, GPU, memory monitor |
| **Audio Visualizer** | Cava | [karlstav/cava](https://github.com/karlstav/cava) | Low-latency audio spectrum visualizer integrated into Waybar/terminal |
| **Pokemon Fetch** | Pokemon Colorscripts | [phisch/pokemon-colorscripts](https://gitlab.com/phisch/pokemon-colorscripts) | CLI tool providing randomized pixel-art Pokemon for terminal greeting |
| **Screen Capture** | Grim + Slurp + Swappy | [emersion/grim](https://github.com/emersion/grim) | Fullscreen and interactive snipping directly to clipboard and editor |
| **Vietnamese IME** | Fcitx5 | [fcitx/fcitx5](https://github.com/fcitx/fcitx5) | Vietnamese typing (Unikey/Bamboo), Wayland text-input-v3 support |
| **Audio Server** | PipeWire | [PipeWire](https://pipewire.org/) | Low-latency audio server with WirePlumber session manager |

---

## ⚙️ Yusei Settings (Control Center)

**yusei-settings** is a modern, extensible Control Center application built specifically for `yusei-hypr`. Designed with the familiarity and intuitive navigation of Windows 11 Settings, it allows you to explore, preview, and switch between dozens of layouts, themes, and system configurations with guaranteed safety.

```
┌────────────────────────────────────────────────────────────────────────┐
│  ⚙️  Yusei Settings                                    —  □  ✕         │
├───────────────┬────────────────────────────────────────────────────────┤
│ 🔍 Search     │  Giao diện & Layout                                    │
│               │  ───────────────────────────────────────────────────  │
│ 🎨 Giao diện  │  [All (310)] [Waybar (46)] [Rofi (22)] [Kitty (171)]  │
│ 🪟 Hyprland   │                                                        │
│ 📱 Ứng dụng   │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│ ⚙️ Hệ thống   │  │ [SVG Mockup] │  │ [SVG Mockup] │  │ [Swatches]   │  │
│ 🛡️ Sao lưu    │  │ Waybar: Top  │  │ Waybar: Bot  │  │ Kitty: Tokyo │  │
│               │  │ Active ✓     │  │ [Apply]      │  │ [Apply]      │  │
│               │  └──────────────┘  └──────────────┘  └──────────────┘  │
└───────────────┴────────────────────────────────────────────────────────┘
```

### 🌟 Key Features
- **Extensible Layout & Theme Catalog**:
  - **Waybar**: 46 layouts (Top, Bottom, Left, Right, Split) & 54 styles with dynamic SVG placement mockups.
  - **Rofi**: 22 launcher & dialog themes with live card previews.
  - **Kitty**: 171 curated color themes with dynamic 8-color palette swatches.
  - **Hyprland**: 17 physics-based animation presets & decoration styles.
  - **Wallpapers**: 21 high-definition curated backgrounds with thumbnail gallery.
- **🎨 Dynamic Theming Integration**:
  - Selecting any wallpaper automatically triggers `scripts/theme-engine.sh` / `bin/theme-engine.sh` to extract harmonic Material You palette tokens.
  - Concurrently updates Hyprland (`colors.conf` with `$primary` and `$secondary`), Waybar (`colors.css`), Rofi (`colors.rasi`), SwayNC (`colors.css`), and Kitty (`theme.conf`).
  - Seamless hot-reloads running components without session disruption; active state persists across reboots.
- **⌨️ Keybinds Cheat Sheet View (`/api/keybinds`)**:
  - Real-time parser reads `config/hypr/keybinds.conf` and extracts 159+ active shortcuts across 12 functional categories (Window Focus, Workspaces, Screenshots, Multimedia Fn Keys, Mouse Controls, etc.).
  - Instant client-side search filtering by key combination, description, or dispatcher with tokenized visual `<kbd>` badges.
- **🔧 System Maintenance Tab (`/api/system/*`)**:
  - Live system telemetry: Git branch, commit hash, repository clean/dirty status, and `userprefs.conf` integrity verification.
  - 1-Click Backup Snapshot: Generates standardized backup directories (`~/.config/yusei-hypr-backup-<timestamp>/` with `manifest.json`) via `scripts/03-backup.sh`.
  - System Update Integration: Checks upstream repository status and executes `./update.sh` with safe `--dry-run` or live apply modes.
- **Dual Frontend Architecture**:
  - **Web / Fluent UI** (`--web`): Windows 11 Fluent Design / dark Mica theme with acrylic effects, responsive sidebar, and search filtering.
  - **Native GTK4 / Libadwaita** (`--gui`): True native Linux desktop window leveraging `Adw.PreferencesWindow` and `Gtk.FlowBox`.
  - **CLI Mode** (`--list`): Instant terminal catalog overview and scripting interface.
- **🛡️ 5-Stage Safe Apply Engine**:
  Never modifies active configurations blindly. Every layout or theme change follows a strict 5-stage safety workflow:
  1. **Pre-Apply Summary**: Displays chosen item, domain, and target paths.
  2. **Impact Analysis**: Exact listing of all configuration files and symlinks that will be touched before any write occurs.
  3. **Automated Backup Snapshot**: Automatically creates a timestamped snapshot in `~/.config/hypr/backup_settings/` with a complete `manifest.json`.
  4. **Strict Confirmation Barrier**: Explicit user consent required (`PermissionError` raised if attempted without confirmation).
  5. **Surgical Modification & 1-Click Rollback**: Modifies only the selected component while preserving all unrelated user customizations, with an instant 1-click Undo/Rollback button.

### 🚀 Launching Settings
Launch directly from the repository or your application launcher:

```bash
# Launch Windows 11-style Web Interface (Default: http://localhost:8999)
./bin/yusei-settings --web

# Launch Native Linux GTK4 / Libadwaita Window
./bin/yusei-settings --gui

# List all discovered themes and layouts in terminal
./bin/yusei-settings --list
```

---

## 🧰 Optional Applications & System Tools

Near the end of the installation process, **yusei-hypr** launches an interactive, user-friendly **Optional Applications Selector** (`scripts/05-optional-apps.sh`). It presents a curated catalog of 13 popular software packages and system management utilities, allowing you to check/uncheck apps with the spacebar and automatically install and configure them.

```
┌────────────────────────────────────────────────────────────────────────┐
│             ✨ GỢI Ý CÀI ĐẶT ỨNG DỤNG TÙY CHỌN (yusei-hypr) ✨          │
├────────────────────────────────────────────────────────────────────────┤
│ Chọn các ứng dụng bổ sung bạn muốn cài đặt thêm cho hệ thống:          │
│                                                                        │
│  [ ] chrome               Google Chrome (Trình duyệt phổ biến)        │
│  [ ] brave                Brave Browser (Bảo mật & chặn quảng cáo)    │
│  [*] mission-center       Mission Center (Task Manager kiểu Win 11)   │
│  [*] gparted              GParted (Quản lý phân vùng ổ đĩa)           │
│  [*] timeshift            Timeshift (Sao lưu & khôi phục hệ thống)    │
│  [ ] ufw                  UFW Firewall (Tường lửa & giao diện GUFW)   │
│  [*] sddm                 SDDM + Sugar Candy (Màn hình đăng nhập đẹp) │
│  [*] git                  Git & Git-LFS (Quản lý mã nguồn)            │
│  [ ] vscode               Visual Studio Code                          │
│  [*] btop                 Btop++ (Giám sát tài nguyên CPU/RAM/GPU)    │
│  [*] pokemon-colorscripts Pokemon Colorscripts (Trang trí Terminal)   │
│  [*] cava                 Cava Audio Visualizer (Sóng nhạc sống động) │
│                                                                        │
│                    < Cài Đặt >          < Bỏ Qua >                     │
└────────────────────────────────────────────────────────────────────────┘
```

### 🌟 Key Capabilities
- **Adaptive TUI / CLI Execution**: Automatically scales to 80% terminal width/height via `whiptail` or `dialog`, with a robust interactive pure-Bash numbered fallback menu (`[X]` toggles) for constrained environments.
- **Pre-Installation Detection**: Instantly scans your system via cached `pacman -Qq` to identify already installed applications (`[Đã có]`), unchecking them by default to prevent redundant downloads.
- **Post-Install Automation Triggers**:
  - **SDDM**: Writes Sugar Candy theme config to `/etc/sddm.conf.d/10-theme.conf` and enables `sddm.service`.
  - **UFW**: Automatically enables `ufw.service` for instant out-of-the-box firewall protection.
- **Package Manager Fallback Hierarchy**: Automatically orchestrates `yay` $\rightarrow$ `paru` $\rightarrow$ `sudo pacman -S --needed`.

### 🚀 Standalone Usage & Simulation
You can run the app selector at any time independently of the main installer:

```bash
# View all 13 catalog apps and their local installation status:
./scripts/05-optional-apps.sh --list-apps

# Safe dry-run simulation (no packages installed, no system changes):
./scripts/05-optional-apps.sh --dry-run

# Force interactive CLI numbered menu:
./scripts/05-optional-apps.sh --cli
```

---

## 🚀 Installation Guide

### Prerequisites
- **Operating System**: Arch Linux (or derivatives: EndeavourOS, CachyOS, Archcraft).
- **Architecture**: `x86_64`.
- **Privileges**: User with standard `sudo` access.
- **Session**: TTY, Display Manager (SDDM, Greetd, Ly), or existing Wayland/X11 session.

### Option 1: Express Interactive Installation (Recommended)

Clone the repository and run the setup wizard:

```bash
git clone https://github.com/Yusei1708/yusei-hypr.git
cd yusei-hypr
chmod +x install.sh
./install.sh
```

### Option 2: Automated Non-Interactive Mode (For VM / CI / Fresh Scripts)

To bypass prompts and automatically answer "yes" to all installation steps:

```bash
./install.sh -y
```

### Installation Workflow Breakdown:
1. **🔍 Hardware & Environment Inspection (`01-detect.sh`)**:
   - Detects GPU (NVIDIA / Intel / AMD), active Linux kernel package (`linux`, `linux-zen`, `linux-lts`, `linux-hardened`) to fetch matching `${KERNEL}-headers`, laptop chassis, and ASUS ROG hardware.
2. **📦 Dependency Resolution & Conflict Fix (`02-packages.sh`)**:
   - Resolves PulseAudio vs PipeWire conflicts (safely removes conflicting legacy pulseaudio packages).
   - Installs PipeWire audio stack, Bluetooth (`bluez`, `bluez-utils`, `blueman`), complete fonts (`ttf-font-awesome`, `noto-fonts-emoji`), cursor/icon themes (`bibata-cursor-theme`, `papirus-icon-theme`), and Thunar thumbnailer utilities (`tumbler`, `ffmpegthumbnailer`, `thunar-archive-plugin`, `gvfs`, `xarchiver`).
   - Automatically appends kernel headers and NVIDIA DKMS or ASUS ROG tools (`asusctl`, `supergfxctl`).
3. **⚡ NVIDIA Kernel & Bootloader Setup (`setup-nvidia.sh`)**:
   - Injects Early KMS modules (`nvidia nvidia_modeset nvidia_uvm nvidia_drm`) into `/etc/mkinitcpio.conf` and rebuilds initramfs (`mkinitcpio -P`).
   - Generates `/etc/modprobe.d/nvidia.conf` with `options nvidia_drm modeset=1 fbdev=1`.
   - Appends `nvidia_drm.modeset=1` to GRUB (`/etc/default/grub` + `grub-mkconfig`) or systemd-boot entries.
4. **🔌 System & User Services Orchestration (`setup-services.sh`)**:
   - Enables and starts `bluetooth.service`, ASUS ROG `supergfxd.service` (if applicable), and PipeWire/WirePlumber user services.
5. **🔐 Display Manager Provisioning (`setup-sddm.sh`)**:
   - Disables competing display managers (GDM, LightDM, LXDM).
   - Installs `sddm`, Qt6 libraries, deploys `simple-sddm-2` theme into `/usr/share/sddm/themes/`, and enables `sddm.service`.
6. **🛡️ Automated Snapshot Backup (`03-backup.sh`)**:
   - Safely archives existing `~/.config/{hypr,waybar,rofi,swaync,kitty,...}` directories into `~/.config/yusei-hypr-backup-<timestamp>/` with `manifest.json`.
7. **🚀 Safe Layer Deployment (`04-install-configs.sh`)**:
   - Non-destructive deployment: preserves user-customized `UserConfigs/` and `UserScripts/` without data loss, and protects `config/hypr/userprefs.conf`.
   - Automatically uncomments `source = ./nvidia.conf` in `hyprland.conf` if NVIDIA is detected.
   - Enforces `chmod +x` across all utility scripts.
8. **🩺 System Verification & Health Check (`05-verify.sh`)**:
   - Live diagnostics reporting status of GPU drivers, PipeWire audio, Bluetooth, SDDM, XDG Portals, Fonts, and desktop configs with clear color-coded statuses (`[OK]`, `[CẢNH BÁO]`, `[LỖI]`).
9. **🧰 Optional Curated Applications Catalog (`05-optional-apps.sh`)**:
   - Interactive TUI checklist (Whiptail/Dialog with pure-Bash fallback) for web browsers (Google Chrome, Brave, Chromium), system administration (Mission Center, GParted, Timeshift, UFW firewall), login manager (SDDM + Sugar Candy theme), dev tools (Git, VS Code), and system monitoring / aesthetics (Btop, Pokemon Colorscripts, Cava).
   - Automatically detects pre-installed applications to avoid duplicate installation, supports `--dry-run`, `--list-apps`, and post-install triggers.
10. **🗑️ Clean System Uninstaller & Rollback (`uninstall.sh`)**:
    - Reverts `~/.config` to the selected pre-install backup snapshot via `rollback.sh`, cleans up created modprobe configs, and disables system services.

---

## 🔄 System Updates (update.sh)

`yusei-hypr` includes an automated, non-destructive root maintenance tool (`./update.sh`) to keep your configuration, scripts, and system components up to date (cập nhật) with upstream repository improvements while guaranteeing that your custom tweaks (`~/.config/hypr/userprefs.conf`) are strictly preserved.

```bash
# Run interactive system update (default)
./update.sh

# Non-interactive automated update (auto-accepts all prompts)
./update.sh -y

# Safe dry-run simulation (verifies changes without modifying files or git pulling)
./update.sh --dry-run

# Local config sync only (skips git pull)
./update.sh --skip-git

# Update configs without reloading the compositor or active daemons
./update.sh --no-reload
```

### 📋 Update Workflow & Execution Stages:
1. **🔍 Git Synchronization**:
   - Checks the active branch against remote upstream.
   - Fast-forwards commits cleanly (can be skipped with `--skip-git` for offline or local testing).
2. **🛡️ Automated Pre-Backup Snapshot**:
   - Immediately creates an isolated snapshot backup directory at `~/.config/yusei-hypr-backup-<timestamp>/` containing `manifest.json`.
   - Updates `~/.config/yusei-hypr-backup-latest` symlink for instant 1-click restore (khôi phục).
3. **🚀 Safe Configuration Sync**:
   - Synchronizes updated compositor scripts, layouts, and system configurations.
   - **Guaranteed Isolation**: Never overwrites, alters, or replaces your `~/.config/hypr/userprefs.conf`, keeping custom monitors, keybindings, autostart programs, and environment overrides completely untouched.
4. **🔄 Conditional Session Reload**:
   - Automatically detects whether Hyprland or Wayland daemons (`waybar`, `swaync`) are actively running.
   - Dispatches non-intrusive reloads (`hyprctl reload`, `kill -SIGUSR2 waybar`, `swaync-client -rs`) without disrupting your open applications (can be disabled with `--no-reload`).

---

## 🗑️ Clean Uninstallation (uninstall.sh)

If you ever wish to completely remove `yusei-hypr`, revert your desktop configurations back to their exact pre-installation state, and cleanly deactivate related background services, execute the root uninstallation wizard:

```bash
# Launch interactive curses uninstaller (Whiptail / Dialog)
./uninstall.sh

# Force pure-bash text CLI fallback mode (no curses or dialog needed)
./uninstall.sh --cli

# Safe dry-run simulation (verifies actions without modifying system)
./uninstall.sh --dry-run

# Non-interactive removal with auto-selected latest backup snapshot
./uninstall.sh -y
```

### 🌟 Key Uninstallation Capabilities:
- **🎛️ Interactive Curses Radiolist Snapshot Picker**:
  - Dynamically discovers all backup snapshot archives in `~/.config/` matching `yusei-hypr-backup-*`.
  - Presents a graphical radiolist menu (via `whiptail` or `dialog`) allowing you to pick precisely which pre-install backup snapshot you wish to restore.
  - Automatically falls back to a clean, numbered pure-Bash terminal menu (`--cli`) if curses dialog tools are unavailable.
- **🛡️ Full Snapshot Restoration (`rollback.sh`)**:
  - Automatically restores your chosen snapshot backup via `scripts/rollback.sh`, reinstates original symlinks and files, and purges all installed dotfiles.
- **🧹 System Services & Config Cleanup Checklist**:
  - Prompts to deactivate and disable systemd services installed during setup (`sddm.service`, `ufw.service`, `supergfxd.service`).
  - Reverts NVIDIA Early KMS modules in `/etc/mkinitcpio.conf` and cleans up `/etc/modprobe.d/nvidia.conf` if configured.

---

## 🎨 Dynamic Theming Engine (Material You)

**yusei-hypr** includes a real-time, non-intrusive Material You theming engine located at `scripts/theme-engine.sh`.

```
                    ┌────────────────────────────┐
                    │      Target Wallpaper      │
                    └─────────────┬──────────────┘
                                  │
                                  ▼
                    ┌────────────────────────────┐
                    │   Color Extraction Engine  │
                    │  (Matugen / Wallust / PIL) │
                    └─────────────┬──────────────┘
                                  │
         ┌──────────────┬─────────┴────────┬──────────────┬──────────────┐
         ▼              ▼                  ▼              ▼              ▼
   ┌───────────┐  ┌───────────┐      ┌───────────┐  ┌───────────┐  ┌───────────┐
   │  Waybar   │  │   Rofi    │      │  SwayNC   │  │ Hyprland  │  │   Kitty   │
   │colors.css │  │colors.rasi│      │colors.css │  │colors.conf│  │theme.conf │
   └───────────┘  └───────────┘      └───────────┘  └───────────┘  └───────────┘
```

### Applying a New Wallpaper:
```bash
./scripts/theme-engine.sh /path/to/your/wallpaper.jpg
```

### What Happens Automatically:
1. Dominant harmonic color tokens (`primary`, `surface`, `on_surface`, `accent`, `outline`) are extracted.
2. Synchronous palette files are updated:
   - `~/.config/waybar/colors.css`
   - `~/.config/rofi/colors.rasi`
   - `~/.config/swaync/colors.css`
   - `~/.config/hypr/colors.conf`
   - `~/.config/kitty/theme.conf`
3. Targeted non-destructive reload signals are sent:
   - `kill -SIGUSR2 $(pidof waybar)` (smooth CSS hot-reload)
   - `swaync-client -rs` (reloads notification styling)
   - `kitty @ set-colors` or `kill -SIGUSR1 $(pidof kitty)` (hot-swaps terminal palette)
4. State is saved to `~/.config/hypr/.current_wallpaper` and `~/.config/hypr/.current_theme`, ensuring settings persist across logins.

---

## ⚡ Power & Battery Management (power-optimizer.sh)

`yusei-hypr` integrates an automated, comprehensive energy profile and refresh rate optimizer tailored for modern laptops. It balances high-refresh rate fluidity when plugged in with battery preservation when on the go.

### 🌟 Key Capabilities

1. **3 Dynamic Energy Profiles**:
   -  **Eco (`eco`)**: Switches to `power-saver` governor, throttles background power draw, and drops screen refresh rate to **60Hz** to maximize battery longevity.
   -  **Balanced (`balanced`)**: Dynamic power distribution suitable for everyday workflows. Restores high refresh rate when plugged in, drops to 60Hz when unplugged.
   -  **Turbo (`turbo`)**: Locks CPU scaling to `performance` mode, unleashes full clock speeds, and maintains maximum display refresh rate (120/144/165Hz).

2. **Automated Display Refresh Rate Coordination**:
   - Seamlessly queries display capabilities via `hyprctl monitors -j`.
   - Automatically drops refresh rate to **60Hz** on battery disconnection to conserve up to 30-40% display power.
   - Automatically restores full native high refresh rate (**120Hz / 144Hz / 165Hz**) when connected to AC power.
   - Manual toggle support via CLI (`--toggle-hz`) and Waybar widget.

3. **Background Daemon & Event Listener**:
   - Starts automatically in `config/hypr/autostart.conf` on laptop chassis detection.
   - Listens to AC plug/unplug power supply events from `/sys/class/power_supply/`.
   - Emits visual desktop notifications via `notify-send` with accurate power status and active profile.

4. **Advanced Waybar Integration**:
   - `power-profiles-daemon`: Displays active profile icon ( Eco,  Balanced,  Turbo). Left-click cycles through profiles; right-click opens power settings menu (`--menu`).
   - `battery`: High-visibility status format with detailed tooltip showing current battery capacity (%), real-time power draw (**Watts**), and estimated remaining runtime. Left-click toggles refresh rate (60Hz vs Max Hz); right-click opens power menu (`--menu`).

5. **Settings Control Center Integration (`yusei_settings`)**:
   - Dedicated **"Nguồn điện & Pin"** page in both Web UI and GTK4 app.
   - Visual battery gauge with real-time discharge/charge wattage telemetry.
   - One-click energy profile switching buttons (Eco / Balanced / Turbo).
   - "Tự động hạ màn hình xuống 60Hz khi rút sạc" toggle switch with persistent configuration.

### 🚀 CLI Usage & Commands

```bash
# Query detailed battery, profile, and screen refresh rate status
power-optimizer.sh --status
power-optimizer.sh --status --json
power-optimizer.sh --status --notify

# Open interactive quick power & refresh rate settings menu (Rofi)
power-optimizer.sh --menu

# Set specific power profile
power-optimizer.sh --set-profile=eco
power-optimizer.sh --set-profile=balanced
power-optimizer.sh --set-profile=turbo

# Cycle to next power profile (eco -> balanced -> turbo -> eco)
power-optimizer.sh --cycle-profile

# Toggle display refresh rate between 60Hz and max native rate
power-optimizer.sh --toggle-hz

# Run auto-optimization based on current power source
power-optimizer.sh --auto

# Start the background AC event listener daemon
power-optimizer.sh --daemon

# Safe simulation without modifying hardware or display settings
power-optimizer.sh --dry-run --auto
```

### ⚙️ User Customization (`~/.config/hypr/userprefs.conf`)

Configure power optimization preferences non-destructively in your `userprefs.conf`:

```bash
# ------------------------------------------------------------------------------
# 6. Power & Battery Management Preferences
# ------------------------------------------------------------------------------
# Automatically lower display refresh rate to 60Hz when on battery (1 = Enabled, 0 = Disabled)
env = YUSEI_AUTO_60HZ,1

# Preferred energy profile when connected to AC power (balanced or turbo)
env = YUSEI_AC_PROFILE,balanced

# Preferred energy profile when running on battery (eco or balanced)
env = YUSEI_BAT_PROFILE,eco

# Enable background power-optimizer daemon (1 = Enabled, 0 = Disabled)
env = YUSEI_POWER_DAEMON,1
```

---

## ⌨️ Keybindings Reference

The default `$mainMod` is the **Super** key (Windows key). All keybindings use hardware-independent keycodes where appropriate to guarantee international keyboard layout compatibility.

### ⚡ Keybinding Cheat Sheet (Quick Reference)

Quickly navigate the desktop using **Super + Tab** (cycle next workspace), **Super + Shift + Tab** (previous workspace), and **Alt + Tab** (cycle next window & bring to top):

| Key Combination | Action / Dispatcher | Description | Category |
| :--- | :--- | :--- | :--- |
| <kbd>Super</kbd> + <kbd>Tab</kbd> (`Super + Tab`) | `workspace, m+1` | Switch to next workspace | Workspace Cycling |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>Tab</kbd> (`Super + Shift + Tab`) | `workspace, m-1` | Switch to previous workspace | Workspace Cycling |
| <kbd>Alt</kbd> + <kbd>Tab</kbd> (`Alt + Tab`) | `cyclenext` | Cycle focus to next window & bring active to top | Window Cycling |
| <kbd>Super</kbd> + <kbd>D</kbd> | `exec, rofi -show drun ...` | Open application launcher (Rofi) | Application Launchers |
| <kbd>Super</kbd> + <kbd>Return</kbd> | `exec, kitty` | Open default GPU terminal (Kitty) | Application Launchers |
| <kbd>Super</kbd> + <kbd>Q</kbd> | `killactive` | Close currently focused window | Window Control |
| <kbd>Super</kbd> + <kbd>Space</kbd> | `togglefloating` | Toggle floating mode for active window | Window Control |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>F</kbd> | `fullscreen, 0` | Toggle true fullscreen state | Window Control |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>F</kbd> | `fullscreen, 1` | Maximize window (preserves bar visibility) | Window Control |
| <kbd>Super</kbd> + <kbd>M</kbd> (Split Ratio) | `splitratio 0.3` | Adjust split ratio to 0.3 | Layout Dispatches |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>I</kbd> | `layoutmsg, togglesplit` | Toggle split layout orientation (dwindle) | Layout Dispatches |
| <kbd>Super</kbd> + <kbd>P</kbd> | `pseudo` | Toggle Dwindle pseudotiling mode | Window Control |
| <kbd>Super</kbd> + <kbd>G</kbd> | `togglegroup` | Group/tab windows together in single container | Window Control |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>Arrow Keys</kbd> | `movewindow` | Move active window position in tiling tree | Window Movement |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>Arrow Keys</kbd> | `resizeactive` | Resize active window dimensions (-50/+50 px) | Window Resizing |
| <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>Arrow Keys</kbd> | `swapwindow` | Swap active window with neighbor window | Window Swapping |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>N</kbd> | `exec, swaync-client -t -sw` | Toggle SwayNC Control Center & notification panel | Bar & Notifications |
| <kbd>Super</kbd> + <kbd>N</kbd> (Night Light) | `exec, Hyprsunset.sh toggle` | Toggle Night Light (Hyprsunset) | Bar & Notifications |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>L</kbd> | `exec, LockScreen.sh` | Lock screen with Hyprlock | System & Session |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>P</kbd> | `exec, Wlogout.sh` | Open Wlogout Power & Session exit menu | System & Session |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>P</kbd> | `exec, power-optimizer.sh --toggle-hz` | Toggle display refresh rate (60Hz vs Max native rate) | Hardware & Power |
| <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>V</kbd> | `exec, ClipManager.sh` | Open Clipboard History Manager (Cliphist) | Features & Utilities |
| <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>R</kbd> | `exec, ScreenRecord.sh --toggle` | Toggle fullscreen screen recording | Power Tools |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>Alt</kbd> + <kbd>R</kbd> | `exec, ScreenRecord.sh --region` | Record interactive selected screen region | Power Tools |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>O</kbd> | `exec, OcrGrab.sh` | Grab text from screen selection (OCR to clipboard) | Power Tools |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>M</kbd> | `exec, RofiBeats.sh` | Open online music radio station selector | Media & Music |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>R</kbd> | `exec, Refresh.sh` | Refresh Waybar, SwayNC, and desktop menus | System & Session |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>O</kbd> | `exec, ZshChangeTheme.sh` | Change Oh-My-Zsh terminal prompt theme | Features & Utilities |
| <kbd>Super</kbd> + <kbd>Print</kbd> | `exec, ScreenShot.sh --now` | Capture fullscreen screenshot to file & clipboard | Screenshots |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>Print</kbd> | `exec, ScreenShot.sh --area` | Capture interactive selection area screenshot | Screenshots |
| <kbd>Alt</kbd> + <kbd>Print</kbd> | `exec, ScreenShot.sh --active` | Capture active window screenshot to clipboard | Screenshots |
| <kbd>Super</kbd> + <kbd>LMB</kbd> | `movewindow` | Click & drag with mouse to move window position | Mouse Controls |
| <kbd>Super</kbd> + <kbd>RMB</kbd> | `resizewindow` | Click & drag with mouse to resize window dimensions | Mouse Controls |
| <kbd>Super</kbd> + <kbd>1..0</kbd> (`code:10..19`) | `workspace, 1..10` | Switch directly to Workspace 1 through 10 | Workspaces |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>1..0</kbd> (`code:10..19`) | `movetoworkspace, 1..10` | Move focused window to Workspace 1 through 10 | Workspaces |
| <kbd>Super</kbd> + <kbd>U</kbd> | `togglespecialworkspace` | Toggle dropdown scratchpad workspace | Workspaces |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>U</kbd> | `movetoworkspace, special` | Move active window into scratchpad | Workspaces |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>M</kbd> | `togglespecialworkspace, music` | Toggle dedicated music scratchpad (`special:music`, Spotify) | Workspaces |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>B</kbd> | `togglespecialworkspace, monitor` | Toggle dedicated system monitor scratchpad (`special:monitor`, Btop) | Workspaces |
| <kbd>XF86AudioRaiseVolume</kbd> | `exec, Volume.sh --inc` | Increase audio volume (+5%) | Multimedia Fn |
| <kbd>XF86AudioLowerVolume</kbd> | `exec, Volume.sh --dec` | Decrease audio volume (-5%) | Multimedia Fn |
| <kbd>XF86AudioMute</kbd> | `exec, Volume.sh --toggle` | Toggle mute / unmute audio output | Multimedia Fn |
| <kbd>XF86AudioPlay</kbd> / <kbd>XF86AudioPause</kbd> | `exec, MediaCtrl.sh --pause` | Play or pause active media playback | Multimedia Fn |
| <kbd>XF86AudioNext</kbd> | `exec, MediaCtrl.sh --nxt` | Next audio track | Multimedia Fn |
| <kbd>XF86AudioPrev</kbd> | `exec, MediaCtrl.sh --prv` | Previous audio track | Multimedia Fn |
| <kbd>XF86MonBrightnessUp</kbd> | `exec, Brightness.sh --inc` | Increase screen backlight brightness (+5%) | Hardware Fn |
| <kbd>XF86MonBrightnessDown</kbd> | `exec, Brightness.sh --dec` | Decrease screen backlight brightness (-5%) | Hardware Fn |

### 🖥️ Window & Layout Control
| Shortcut | Action | Description |
| :--- | :--- | :--- |
| <kbd>Super</kbd> + <kbd>Q</kbd> | `killactive` | Close currently focused window |
| <kbd>Super</kbd> + <kbd>Space</kbd> | `togglefloating` | Toggle floating mode for active window |
| <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>Space</kbd> | `workspaceopt allfloat` | Toggle floating mode for all windows on workspace |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>F</kbd> | `fullscreen, 0` | Toggle true fullscreen state |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>F</kbd> | `fullscreen, 1` | Maximize window (preserves bar visibility) |
| <kbd>Super</kbd> + <kbd>M</kbd> (Split Ratio) | `splitratio 0.3` | Set split ratio to 0.3 (does not exit session) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>I</kbd> | `layoutmsg, togglesplit` | Toggle split layout orientation (dwindle) |
| <kbd>Super</kbd> + <kbd>P</kbd> | `pseudo` | Toggle Dwindle pseudotiling mode |
| <kbd>Super</kbd> + <kbd>G</kbd> | `togglegroup` | Group/tab windows together in single container |
| <kbd>Alt</kbd> + <kbd>Tab</kbd> | `cyclenext` | Cycle next window & bring active to top |
| <kbd>Super</kbd> + <kbd>Left</kbd> / <kbd>Right</kbd> / <kbd>Up</kbd> / <kbd>Down</kbd> | `movefocus` | Shift focus to adjacent window in direction |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>Arrow Keys</kbd> | `movewindow` | Move active window position in tiling tree |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>Arrow Keys</kbd> | `resizeactive` | Resize active window dimensions (-50/+50 px) |
| <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>Arrow Keys</kbd> | `swapwindow` | Swap active window with neighbor window |

### 🖱️ Mouse Controls
| Shortcut | Action | Description |
| :--- | :--- | :--- |
| <kbd>Super</kbd> + <kbd>LMB</kbd> | `movewindow` | Move floating or tiled window by dragging left mouse button |
| <kbd>Super</kbd> + <kbd>RMB</kbd> | `resizewindow` | Resize active window by dragging right mouse button |
| <kbd>Super</kbd> + <kbd>Scroll Down</kbd> / <kbd>Up</kbd> | `workspace, e+1 / e-1` | Cycle next / previous workspace with mouse scroll wheel |
| <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>Scroll Up</kbd> / <kbd>Down</kbd> | `cursor:zoom_factor` | Zoom desktop magnifier in / out |

### 🚀 Application & System Launchers
| Shortcut | Action | Target Component / Application |
| :--- | :--- | :--- |
| <kbd>Super</kbd> + <kbd>D</kbd> | Application Launcher | `Rofi` (`rofi -show drun -modi drun,filebrowser,run,window`) |
| <kbd>Super</kbd> + <kbd>Return</kbd> | Terminal Emulator | `Kitty` (GPU accelerated, blurred) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>Return</kbd> | Dropdown Scratchpad Terminal | `Dropterminal.sh` (Kitty dropdown) |
| <kbd>Super</kbd> + <kbd>B</kbd> | Default Web Browser | `xdg-open "https://"` |
| <kbd>Super</kbd> + <kbd>E</kbd> | File Manager | `Thunar` (or system default file manager) |
| <kbd>Super</kbd> + <kbd>A</kbd> | Desktop Overview | `OverviewToggle.sh` |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>N</kbd> | Control Center | `SwayNC` (Quick Toggles, DND, Volume, Brightness) |
| <kbd>Super</kbd> + <kbd>N</kbd> (Night Light) | Night Light | `Hyprsunset.sh toggle` (Color temperature toggle) |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>L</kbd> | Screen Lock | `Hyprlock` (`LockScreen.sh`) |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>P</kbd> | Power Exit Menu | `Wlogout.sh` (Lock, Logout, Suspend, Reboot, Shutdown) |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>Delete</kbd> | Exit Hyprland | `hyprctl dispatch exit 0` (Clean session logout) |
| <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>V</kbd> | Clipboard History | `ClipManager.sh` (Cliphist fuzzy search) |
| <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>R</kbd> | Screen Recorder | `ScreenRecord.sh --toggle` (Toggle fullscreen screen recording) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>Alt</kbd> + <kbd>R</kbd> | Region Recorder | `ScreenRecord.sh --region` (Record selected screen area) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>O</kbd> | OCR Text Grabber | `OcrGrab.sh` (Extract text from selection via Tesseract) |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>M</kbd> | Online Music Radio | `RofiBeats.sh` (Online radio stream player) |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>R</kbd> | Refresh Desktop | `Refresh.sh` (Restart Waybar, SwayNC & menus) |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>O</kbd> | Zsh Theme Switcher | `ZshChangeTheme.sh` (Select Oh-My-Zsh theme) |
| <kbd>Super</kbd> + <kbd>W</kbd> | Wallpaper Selector | `WallpaperSelect.sh` |
| <kbd>Super</kbd> + <kbd>T</kbd> | Global Theme Switcher | `ThemeChanger.sh` (Wallust color sync) |
| <kbd>Super</kbd> + <kbd>H</kbd> | Keybinding Hints | `KeyHints.sh` (Interactive keybind cheat sheet) |

### 📸 Screenshot Workflows
| Shortcut | Action | Destination / Behavior |
| :--- | :--- | :--- |
| <kbd>Super</kbd> + <kbd>Print</kbd> | Fullscreen Screenshot | `ScreenShot.sh --now` (Saved to `~/Pictures/Screenshots/` & clipboard) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>Print</kbd> | Area / Selection Screenshot | `ScreenShot.sh --area` (Interactive selection via `slurp` + `grim`) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>S</kbd> | Snipping & Annotation Tool | `ScreenShot.sh --swappy` (Area selection directly into `swappy` editor) |
| <kbd>Alt</kbd> + <kbd>Print</kbd> | Active Window Capture | `ScreenShot.sh --active` (Captures currently active window boundary) |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>Print</kbd> | Delayed Screenshot (5s) | `ScreenShot.sh --in5` (5-second countdown timer) |

### 🎥 Screen Recording & OCR Power Tools (v1.5.0)
| Shortcut | Action | Destination / Behavior |
| :--- | :--- | :--- |
| <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>R</kbd> | Toggle Fullscreen Recording | `ScreenRecord.sh --toggle` (Saved to `~/Videos/Recordings/` & SwayNC notification) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>Alt</kbd> + <kbd>R</kbd> | Region Screen Recording | `ScreenRecord.sh --region` (Interactive region selection via `slurp`) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>O</kbd> | OCR Screen Text Grabber | `OcrGrab.sh` (Extracts text via Tesseract eng+vie directly to clipboard) |


### 🔢 Workspace Navigation (Hardware Keycodes: code:10..19)
| Shortcut | Action | Target Workspace |
| :--- | :--- | :--- |
| <kbd>Super</kbd> + <kbd>Tab</kbd> | `workspace, m+1` | Switch to next workspace |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>Tab</kbd> | `workspace, m-1` | Switch to previous workspace |
| <kbd>Super</kbd> + <kbd>period</kbd> / <kbd>comma</kbd> | `workspace, e+1 / e-1` | Cycle next / previous workspace sequentially |
| <kbd>Super</kbd> + <kbd>1..0</kbd> (`code:10..19`) | `workspace, 1..10` | Switch directly to Workspace 1 through 10 |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>1..0</kbd> (`code:10..19`) | `movetoworkspace, 1..10` | Move focused window to Workspace 1..10 and follow |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>1..0</kbd> (`code:10..19`) | `movetoworkspacesilent, 1..10` | Move focused window silently to Workspace 1..10 |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>[</kbd> / <kbd>]</kbd> | `movetoworkspace, -1 / +1` | Move active window to relative previous / next workspace |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>[</kbd> / <kbd>]</kbd> | `movetoworkspacesilent, -1 / +1` | Move window silently to relative previous / next workspace |
| <kbd>Super</kbd> + <kbd>U</kbd> | `togglespecialworkspace` | Toggle scratchpad dropdown workspace |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>U</kbd> | `movetoworkspace, special` | Send active window to scratchpad workspace |
| <kbd>Super</kbd> + <kbd>Z</kbd> | `togglespecialworkspace, magic` | Toggle magic scratchpad workspace |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>M</kbd> | `togglespecialworkspace, music` | Toggle music scratchpad (`special:music`, Spotify) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>B</kbd> | `togglespecialworkspace, monitor` | Toggle system monitor scratchpad (`special:monitor`, Btop) |

### 🔊 Multimedia & Hardware Controls (Fn Keys)
| Key Name | Dispatcher & Command | Action |
| :--- | :--- | :--- |
| <kbd>XF86AudioPlay</kbd> / <kbd>XF86AudioPause</kbd> | `exec, MediaCtrl.sh --pause` | Toggle Play / Pause active media |
| <kbd>XF86AudioNext</kbd> | `exec, MediaCtrl.sh --nxt` | Skip to next audio track |
| <kbd>XF86AudioPrev</kbd> | `exec, MediaCtrl.sh --prv` | Skip to previous audio track |
| <kbd>XF86AudioStop</kbd> | `exec, MediaCtrl.sh --stop` | Stop audio playback |
| <kbd>XF86AudioRaiseVolume</kbd> | `exec, Volume.sh --inc` | Raise volume (+5%) |
| <kbd>XF86AudioLowerVolume</kbd> | `exec, Volume.sh --dec` | Lower volume (-5%) |
| <kbd>XF86AudioMute</kbd> | `exec, Volume.sh --toggle` | Mute / unmute audio output |
| <kbd>XF86AudioMicMute</kbd> | `exec, Volume.sh --toggle-mic` | Mute / unmute microphone input |
| <kbd>XF86MonBrightnessUp</kbd> | `exec, Brightness.sh --inc` | Increase screen backlight brightness (+5%) |
| <kbd>XF86MonBrightnessDown</kbd> | `exec, Brightness.sh --dec` | Decrease screen backlight brightness (-5%) |
| <kbd>XF86KbdBrightnessUp</kbd> | `exec, BrightnessKbd.sh --inc` | Increase keyboard backlight brightness |
| <kbd>XF86KbdBrightnessDown</kbd> | `exec, BrightnessKbd.sh --dec` | Decrease keyboard backlight brightness |
| <kbd>XF86TouchpadToggle</kbd> | `exec, TouchPad.sh` | Toggle laptop touchpad on / off |

---

## 🛡️ Safety, Backups & Instant Rollback

Your operating system and dotfiles safety is our first priority.

### Automated Snapshot Architecture
Whenever `./install.sh` or `./update.sh` runs, `scripts/03-backup.sh` generates an isolated, standardized snapshot before touching your files:
```text
~/.config/
├── yusei-hypr-backup-20261014_120000/
│   ├── hypr/
│   ├── waybar/
│   ├── rofi/
│   ├── kitty/
│   ├── swaync/
│   └── manifest.json
└── yusei-hypr-backup-latest -> yusei-hypr-backup-20261014_120000
```

### 1-Command Instant Rollback
If you ever want to revert back to your exact pre-installation configuration:
```bash
# Restore latest snapshot automatically:
./scripts/rollback.sh

# Or restore an explicit snapshot directory:
./scripts/rollback.sh ~/.config/yusei-hypr-backup-20261014_120000
```
`rollback.sh` parses `manifest.json`, validates directory paths, safely restores all pre-existing configurations, and cleanly purges newly created components. You can also use `./uninstall.sh` to choose snapshots via an interactive curses TUI menu.

---

## 🔧 Troubleshooting & FAQ

<details>
  <summary><b>1. NVIDIA Graphics & Proprietary Drivers</b></summary>
  <br/>

  `scripts/01-detect.sh` automatically uncomments `source = ~/.config/hypr/nvidia.conf` when an NVIDIA GPU is detected.
  
  Ensure you have the required NVIDIA Wayland packages installed:
  ```bash
  sudo pacman -S nvidia-dkms nvidia-utils libva-nvidia-driver
  ```
  Ensure modesetting is enabled in `/etc/modprobe.d/nvidia.conf`:
  ```ini
  options nvidia-drm modeset=1 fbdev=1
  ```
  And rebuild your initramfs:
  ```bash
  sudo mkinitcpio -P
  ```
</details>

<details>
  <summary><b>2. Vietnamese Input Method (Fcitx5 / Bamboo / Unikey)</b></summary>
  <br/>

  All necessary environment variables are pre-configured in `config/hypr/env.conf`:
  ```ini
  env = XMODIFIERS,@im=fcitx
  env = GTK_IM_MODULE,fcitx
  env = QT_IM_MODULE,fcitx
  env = SDL_IM_MODULE,fcitx
  ```
  If Vietnamese typing is inactive in Chromium or Electron apps (Discord, VSCode), launch them with:
  ```bash
  --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations
  ```
</details>

<details>
  <summary><b>3. Multi-Monitor Setup & Screen Scaling</b></summary>
  <br/>

  The default configuration uses universal automatic resolution in `~/.config/hypr/monitors.conf`:
  ```ini
  monitor = , preferred, auto, 1
  ```
  For custom multi-monitor arrangements (e.g. 144Hz primary + 60Hz secondary + 1.25x scaling):
  ```ini
  monitor = DP-1, 2560x1440@144, 0x0, 1.25
  monitor = HDMI-A-1, 1920x1080@60, 2048x0, 1
  ```
</details>

<details>
  <summary><b>4. Audio & Media Controls (PipeWire / WirePlumber)</b></summary>
  <br/>

  Ensure PipeWire and WirePlumber user services are enabled:
  ```bash
  systemctl --user enable --now pipewire pipewire-pulse wireplumber
  ```
  Test volume keys or invoke the volume script directly:
  ```bash
  ~/.config/hypr/scripts/Volume.sh --inc
  ~/.config/hypr/scripts/Volume.sh --dec
  ```
</details>

---

## 📜 License

This project is licensed under the terms of the **GNU General Public License v3.0 (GPL-3.0)**.

```
                    GNU GENERAL PUBLIC LICENSE
                       Version 3, 29 June 2007

 Copyright (C) 2026 yusei-hypr contributors <https://github.com/Yusei1708/yusei-hypr>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.
```

You are free to run, study, modify, and redistribute this software under the terms and conditions of the GNU General Public License as published by the Free Software Foundation.
For the complete legal text and terms, please consult the [LICENSE](LICENSE) file in the repository root.

---

<div align="center">

**Maintained with ❤️ by [yusei1708](https://github.com/Yusei1708)**

*If you enjoy this project, consider giving it a ⭐ star on GitHub!*

</div>
