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
[![License: MIT](https://img.shields.io/badge/License-MIT-34d399?style=for-the-badge)](LICENSE)

<br/>

[![GitHub Stars](https://img.shields.io/github/stars/Yusei1708/yusei-hypr?style=flat-square&logo=github&color=86dbd7&labelColor=1e1e2e)](https://github.com/Yusei1708/yusei-hypr/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/Yusei1708/yusei-hypr?style=flat-square&logo=github&color=8ad7eb&labelColor=1e1e2e)](https://github.com/Yusei1708/yusei-hypr/network/members)
[![Last Commit](https://img.shields.io/github/last-commit/Yusei1708/yusei-hypr?style=flat-square&logo=git&color=b4befe&labelColor=1e1e2e)](https://github.com/Yusei1708/yusei-hypr/commits/main)
[![Repository Size](https://img.shields.io/github/repo-size/Yusei1708/yusei-hypr?style=flat-square&logo=github&color=cdd6f4&labelColor=1e1e2e)](https://github.com/Yusei1708/yusei-hypr)

<br/>

[🌟 Highlights](#-highlights) •
[🏛️ Architecture](#-system-architecture) •
[🧩 Components](#-component-matrix) •
[⚙️ Settings App](#-yusei-settings-control-center) •
[🚀 Installation](#-installation-guide) •
[🎨 Theming](#-dynamic-theming-engine-material-you) •
[⌨️ Keybindings](#-keybindings-reference) •
[🛡️ Safety & Rollback](#-safety-backups--instant-rollback) •
[🔧 FAQ](#-troubleshooting--faq)

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
- 🔒 **Enterprise-Grade Backup & Rollback Protocol**:
  - Automated timestamped snapshots with `manifest.json` before any configuration file is modified.
  - 1-command idempotent `scripts/rollback.sh` restores your exact pre-installation state in seconds.

---

## 🏛️ System Architecture

The codebase enforces a 6-layer decoupled design pattern where each domain maintains zero direct cyclic dependencies:

```text
yusei-hypr/
├── install.sh                  # Interactive CLI entrypoint & non-interactive flags (-y)
├── README.md                   # Technical reference & user manual
├── .gitignore                  # Git development exclusions
├── assets/
│   ├── wallpapers/             # Bundled 4K high-resolution wallpapers
│   └── icons/                  # Material vector glyphs and icons
├── scripts/                    # Automation & Lifecycle Management
│   ├── 01-detect.sh            # Distro, GPU (NVIDIA/Intel/AMD), and chassis probe
│   ├── 02-packages.sh          # Dependency resolver using pacman and yay/paru
│   ├── 03-backup.sh            # Hardened snapshot generator with manifest.json
│   ├── 04-install-configs.sh   # Layered deployment & permission supervisor
│   ├── 05-optional-apps.sh     # Optional curated app checklist & TUI installer
│   ├── rollback.sh             # Idempotent 1-command rollback engine
│   ├── theme-engine.sh         # Dynamic Material You color extractor & dispatcher
│   └── launch-daemons.sh       # Singleton daemon lifecycle supervisor
└── config/
    ├── hypr/                   # Compositor Layer (Hyprland Core)
    │   ├── hyprland.conf       # 6-layer modular configuration loader
    │   ├── keybinds.conf       # 131 annotated shortcuts with hardware keycodes
    │   ├── rules.conf          # Semantic window tags, floating dialogs, PiP rules
    │   ├── autostart.conf      # D-Bus, systemd environment, Polkit, daemons
    │   ├── animations.conf     # Physics-based expressive bezier curves
    │   ├── decorations.conf    # 16px rounding, Kawase blur passes, shadows
    │   ├── env.conf            # Toolkit environments, Wayland flags & Fcitx5 IME
    │   ├── monitors.conf       # Universal multi-monitor auto-resolution
    │   ├── nvidia.conf         # Dedicated NVIDIA driver parameters
    │   ├── colors.conf         # Dynamically generated Hyprland color tokens
    │   ├── hypridle.conf       # 4-stage idle power listener
    │   ├── hyprlock.conf       # Modern pill input lockscreen
    │   ├── scripts/            # 64 verified operational utility scripts
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
   - Safely archives existing `~/.config/{hypr,waybar,rofi,swaync,kitty,...}` directories into `~/.config/yusei-hypr-backups/backup_<timestamp>/` with `manifest.json`.
7. **🚀 Safe Layer Deployment (`04-install-configs.sh`)**:
   - Non-destructive deployment: preserves user-customized `UserConfigs/` and `UserScripts/` without data loss.
   - Automatically uncomments `source = ./nvidia.conf` in `hyprland.conf` if NVIDIA is detected.
   - Enforces `chmod +x` across all utility scripts.
8. **🩺 System Verification & Health Check (`05-verify.sh`)**:
   - Live diagnostics reporting status of GPU drivers, PipeWire audio, Bluetooth, SDDM, XDG Portals, Fonts, and desktop configs with clear color-coded statuses (`[OK]`, `[CẢNH BÁO]`, `[LỖI]`).
9. **🧰 Optional Curated Applications Catalog (`06-optional-apps.sh`)**:
   - Interactive TUI checklist for browsers, dev tools, and desktop enhancements.
10. **🗑️ Clean System Uninstaller & Rollback (`scripts/uninstall.sh`)**:
    - Reverts `~/.config` to the latest pre-install snapshot via `rollback.sh`, cleans up created modprobe configs, and disables system services.

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

## ⌨️ Keybindings Reference

The default `$mainMod` is the **Super** key (Windows key).

### 🖥️ Window & Layout Control
| Shortcut | Action | Description |
| :--- | :--- | :--- |
| <kbd>Super</kbd> + <kbd>Q</kbd> | `killactive` | Close currently focused window |
| <kbd>Super</kbd> + <kbd>V</kbd> | `togglefloating` | Toggle floating mode for active window |
| <kbd>Super</kbd> + <kbd>F</kbd> | `fullscreen, 0` | Toggle true fullscreen |
| <kbd>Super</kbd> + <kbd>P</kbd> | `pseudo` | Toggle Dwindle pseudotiling mode |
| <kbd>Super</kbd> + <kbd>J</kbd> | `togglesplit` | Toggle split orientation (horizontal/vertical) |
| <kbd>Super</kbd> + <kbd>G</kbd> | `togglegroup` | Group/tab windows together in single container |
| <kbd>Super</kbd> + <kbd>Left</kbd> / <kbd>Right</kbd> / <kbd>Up</kbd> / <kbd>Down</kbd> | `movefocus` | Shift focus to adjacent window |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>Arrows</kbd> | `movewindow` | Move active window position in tiling tree |
| <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>Arrows</kbd> | `resizewindow` | Resize active window dimensions |

### 🚀 Application & System Launchers
| Shortcut | Action | Target Component / Application |
| :--- | :--- | :--- |
| <kbd>Super</kbd> + <kbd>Return</kbd> | Terminal Emulator | `Kitty` (GPU accelerated, blurred) |
| <kbd>Super</kbd> + <kbd>Space</kbd> or <kbd>Super</kbd> + <kbd>R</kbd> | Application Launcher | `Rofi` (Material 3 centered floating card) |
| <kbd>Super</kbd> + <kbd>E</kbd> | File Manager | `Thunar` / `Dolphin` |
| <kbd>Super</kbd> + <kbd>N</kbd> | Control Center | `SwayNC` (Quick Toggles, DND, Volume, Brightness) |
| <kbd>Super</kbd> + <kbd>L</kbd> | Screen Lock | `Hyprlock` (Material pill input screen) |
| <kbd>Super</kbd> + <kbd>M</kbd> | Power Exit Menu | `Wlogout.sh` (Lock, Logout, Suspend, Reboot, Shutdown) |
| <kbd>Super</kbd> + <kbd>W</kbd> | Wallpaper Selector | `WallpaperSelect.sh` |
| <kbd>Super</kbd> + <kbd>V</kbd> (clipboard) | Clipboard History | `ClipManager.sh` (Cliphist fuzzy search) |

### 📸 Screenshot Workflows
| Shortcut | Action | Destination / Behavior |
| :--- | :--- | :--- |
| <kbd>Print</kbd> | Fullscreen Screenshot | Saved to `~/Pictures/Screenshots/` & copied to clipboard |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>S</kbd> | Area Snipping Tool | Interactive selection via `slurp` to clipboard |
| <kbd>Super</kbd> + <kbd>Print</kbd> | Active Window Capture | Captures current window boundary to clipboard |

### 🔢 Workspace Navigation (Hardware Keycodes)
| Shortcut | Action | Target Workspace |
| :--- | :--- | :--- |
| <kbd>Super</kbd> + <kbd>1..0</kbd> | `workspace, 1..10` | Switch to Workspace 1 through 10 |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>1..0</kbd> | `movetoworkspace, 1..10` | Move focused window to Workspace 1-10 |
| <kbd>Super</kbd> + <kbd>[</kbd> / <kbd>]</kbd> | `workspace, -1 / +1` | Cycle previous / next workspace |
| <kbd>Super</kbd> + <kbd>U</kbd> | `togglespecialworkspace` | Toggle scratchpad dropdown workspace |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>U</kbd> | `movetoworkspace, special` | Send active window to scratchpad |

---

## 🛡️ Safety, Backups & Instant Rollback

Your operating system and dotfiles safety is our first priority.

### Automated Snapshot Architecture
Whenever `./install.sh` runs, `scripts/03-backup.sh` generates an isolated snapshot before touching your files:
```text
~/.config/yusei-hypr-backups/
├── backup_20261012_001326/
│   ├── hypr/
│   ├── waybar/
│   ├── rofi/
│   ├── kitty/
│   ├── swaync/
│   └── manifest.json
└── latest -> backup_20261012_001326
```

### 1-Command Instant Rollback
If you ever want to revert back to your exact pre-installation configuration:
```bash
./scripts/rollback.sh
```
`rollback.sh` parses `manifest.json`, validates directory paths, safely restores all pre-existing configurations, and cleanly purges newly created components.

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

<div align="center">

**Maintained with ❤️ by [yusei1708](https://github.com/Yusei1708)**

*If you enjoy this project, consider giving it a ⭐ star on GitHub!*

</div>
