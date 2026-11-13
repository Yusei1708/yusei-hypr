-- ==============================================================================
-- yusei-hypr: Universal Hyprland 0.57+ Lua Configuration (hyprland.lua)
-- Combining End-4 Material 3 Design System with JaKooLit Operational Backbone
-- Author: yusei1708
-- ==============================================================================

--------------------------------------------------------------------------------
-- 1. DIRECTORIES & DEFAULT APPLICATIONS
--------------------------------------------------------------------------------
local home        = os.getenv("HOME")
local scriptsDir  = home .. "/.config/hypr/scripts"
local userScripts = home .. "/.config/hypr/UserScripts"

local terminal    = "kitty"
local fileManager = "thunar"
local rofiMenu    = "pkill rofi || rofi -show drun -modi drun,filebrowser,run,window"

-- Palette loader: Reads both Wallust palette and yusei-hypr Material 3 colors.conf
local palette = {}
do
    local function parse_colors(path)
        local colors = io.open(path, "r")
        if colors then
            for line in colors:lines() do
                local name, value = line:match("^%$(color%d+)%s*=%s*(rgb%([^%)]+%))")
                if not name then
                    name, value = line:match("^%$(%w+)%s*=%s*(rgba?%([^%)]+%))")
                end
                if name and value then palette[name] = value end
            end
            colors:close()
        end
    end
    parse_colors(home .. "/.config/hypr/colors.conf")
    parse_colors(home .. "/.config/hypr/wallust/wallust-hyprland.conf")
end

--------------------------------------------------------------------------------
-- 2. ENVIRONMENT VARIABLES
--------------------------------------------------------------------------------
-- DRM / Aquamarine: Respect user AQ_DRM_DEVICES if provided, otherwise let Aquamarine
-- safely probe KMS devices to avoid "Skipping device ... not a KMS device" errors on hybrid GPUs.
local env_aq = os.getenv("AQ_DRM_DEVICES")
if env_aq and env_aq ~= "" then
    hl.env("AQ_DRM_DEVICES", env_aq)
end

-- XDG & Wayland session
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_QUICK_CONTROLS_STYLE", "org.hyprland.style")
hl.env("GDK_SCALE", "1")
hl.env("QT_SCALE_FACTOR", "1")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Fcitx 5 input method
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("QT_IM_MODULE", "fcitx")
hl.env("GLFW_IM_MODULE", "ibus")

-- PATH priority: ensure ~/.local/bin is first for wrappers and yusei CLI tools
local current_path = os.getenv("PATH") or "/usr/local/bin:/usr/bin:/bin"
local local_bin = home .. "/.local/bin"
if not current_path:find(local_bin, 1, true) then
    hl.env("PATH", local_bin .. ":" .. current_path)
end

-- Cursor
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_SIZE", "24")

-- User ENV Variables Bridge
local function load_custom_env(filepath)
    local f = io.open(filepath, "r")
    if not f then return end
    for line in f:lines() do
        local clean = line:gsub("#.*$", ""):match("^%s*(.-)%s*$")
        if clean and clean ~= "" then
            local k, v = clean:match("^env%s*=%s*([^,]+)%s*,%s*(.+)$")
            if k and v then
                pcall(function() hl.env(k:match("^%s*(.-)%s*$"), v:match("^%s*(.-)%s*$")) end)
            end
        end
    end
    f:close()
end
load_custom_env(home .. "/.config/hypr/UserConfigs/ENVariables.conf")

--------------------------------------------------------------------------------
-- 3. MONITORS & DYNAMIC WORKSPACE RULES
--------------------------------------------------------------------------------
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "1",
})

-- Dynamic Monitors Bridge: loads monitors.conf, Monitors.conf, and LaptopDisplay.conf
local function load_custom_monitors(filepath)
    local f = io.open(filepath, "r")
    if not f then return end
    for line in f:lines() do
        local clean = line:gsub("#.*$", ""):match("^%s*(.-)%s*$")
        if clean and clean ~= "" then
            local mon_args = clean:match("^monitor%s*=%s*(.+)$")
            if mon_args then
                local parts = {}
                for part in mon_args:gmatch("[^,]+") do
                    table.insert(parts, part:match("^%s*(.-)%s*$"))
                end
                if #parts >= 4 then
                    local out = parts[1]
                    local mode = parts[2]
                    local pos = parts[3]
                    local sc = parts[4]
                    pcall(function() hl.monitor({ output = out, mode = mode, position = pos, scale = sc }) end)
                elseif #parts >= 2 and parts[2] == "disable" then
                    pcall(function() hl.monitor({ output = parts[1], mode = "disable" }) end)
                end
            end
        end
    end
    f:close()
end
load_custom_monitors(home .. "/.config/hypr/monitors.conf")
load_custom_monitors(home .. "/.config/hypr/Monitors.conf")
load_custom_monitors(home .. "/.config/hypr/UserConfigs/LaptopDisplay.conf")

-- Dynamic Workspace Rules Bridge: loads workspaces.conf and WorkSpaceRules.conf
local function load_custom_workspaces(filepath)
    local f = io.open(filepath, "r")
    if not f then return end
    for line in f:lines() do
        local clean = line:gsub("#.*$", ""):match("^%s*(.-)%s*$")
        if clean and clean ~= "" then
            local ws_args = clean:match("^workspace%s*=%s*(.+)$")
            if ws_args then
                local ws_id, rest = ws_args:match("^([^,]+)%s*,%s*(.+)$")
                if ws_id and rest then
                    local mon = rest:match("monitor:([^,%s]+)")
                    if mon then
                        pcall(function() hl.workspace_rule({ workspace = ws_id, monitor = mon }) end)
                    end
                end
            end
        end
    end
    f:close()
end
load_custom_workspaces(home .. "/.config/hypr/workspaces.conf")
load_custom_workspaces(home .. "/.config/hypr/UserConfigs/WorkSpaceRules.conf")

--------------------------------------------------------------------------------
-- 4. AUTOSTART DAEMONS & SUPERVISOR
--------------------------------------------------------------------------------
hl.on("hyprland.start", function ()
    -- Environment activation
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")
    
    -- Core desktop daemons
    hl.exec_cmd("swww-daemon --format xrgb")
    hl.exec_cmd("waybar")
    hl.exec_cmd("swaync")
    hl.exec_cmd("qs -c overview")
    hl.exec_cmd("fcitx5 -d --replace")
    hl.exec_cmd("hypridle")
    hl.exec_cmd(scriptsDir .. "/Dropterminal.sh kitty &")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")
    
    -- Clipboard manager
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    
    -- Helper scripts
    hl.exec_cmd(scriptsDir .. "/Polkit.sh")
    hl.exec_cmd(scriptsDir .. "/PortalHyprland.sh")
    hl.exec_cmd(scriptsDir .. "/Hyprsunset.sh init")
    hl.exec_cmd(scriptsDir .. "/ChangeLayout.sh init")
    
    -- Laptop Power Optimizer daemon
    hl.exec_cmd("([ -d /sys/class/power_supply/BAT0 ] || ls /sys/class/power_supply/BAT* >/dev/null 2>&1) && " .. scriptsDir .. "/power-optimizer.sh --daemon &")

    -- User Startup Apps overlay
    local function exec_user_startup(filepath)
        local f = io.open(filepath, "r")
        if not f then return end
        for line in f:lines() do
            local clean = line:gsub("#.*$", ""):match("^%s*(.-)%s*$")
            if clean and clean ~= "" then
                local cmd = clean:match("^exec%-once%s*=%s*(.+)$") or clean:match("^exec%s*=%s*(.+)$")
                if cmd then
                    pcall(function() hl.exec_cmd(cmd) end)
                end
            end
        end
        f:close()
    end
    exec_user_startup(home .. "/.config/hypr/UserConfigs/Startup_Apps.conf")
end)

-- Dynamic J/K layout cycling and Rainbow Borders re-initialization on config reload
hl.on("config.reloaded", function()
    hl.exec_cmd(scriptsDir .. "/ChangeLayout.sh init")
    hl.exec_cmd("([ -f " .. userScripts .. "/RainbowBorders.sh ] && " .. userScripts .. "/RainbowBorders.sh &)")
end)

-- Specialized Scratchpad automatic window spawning (music: spotify, monitor: btop)
hl.on("workspace.created", function(ws)
    if ws.name == "special:music" and ws.is_empty then
        hl.exec_cmd("spotify")
    elseif ws.name == "special:monitor" and ws.is_empty then
        hl.exec_cmd("kitty -e btop")
    end
end)

--------------------------------------------------------------------------------
-- 5. GENERAL & CORE SETTINGS
--------------------------------------------------------------------------------
hl.config({
    general = {
        gaps_in          = 2,
        gaps_out         = 4,
        border_size      = 2,
        resize_on_border = true,
        allow_tearing    = true,
        layout           = "dwindle",
        col = {
            active_border   = palette.color12 or palette.primary or "rgb(975836)",
            inactive_border = palette.color10 or palette.outline or "rgb(45292A)",
        },
    },

    decoration = {
        rounding           = 10,
        rounding_power     = 2,
        active_opacity     = 0.9,
        inactive_opacity   = 0.9,
        fullscreen_opacity = 1.0,
        dim_inactive       = true,
        dim_strength       = 0.1,
        dim_special        = 0.8,

        shadow = {
            enabled        = true,
            range          = 3,
            render_power   = 1,
            color          = palette.color12 or "rgb(975836)",
            color_inactive = palette.color10 or "rgb(45292A)",
        },

        blur = {
            enabled           = true,
            size              = 5,
            passes            = 2,
            vibrancy          = 0.1696,
            xray              = true,
            ignore_opacity    = true,
            special           = true,
            popups            = true,
            new_optimizations = true,
        },
    },

    group = {
        col = { border_active = palette.color15 or "rgb(DEEBE6)" },
        groupbar = { col = { active = palette.color0 or "rgb(080000)" } },
    },

    animations = {
        enabled = true,
    },

    input = {
        kb_layout                   = "us",
        repeat_rate                 = 50,
        repeat_delay                = 300,
        numlock_by_default          = true,
        left_handed                 = false,
        follow_mouse                = 1,
        sensitivity                 = 0,
        float_switch_override_focus = false,
        touchpad = {
            natural_scroll          = true,
            tap_to_click            = true,
            disable_while_typing    = true,
            clickfinger_behavior    = false,
            middle_button_emulation = false,
            drag_lock               = false,
        },
        touchdevice = { enabled = true },
        tablet = { transform = 0, left_handed = 0 },
    },

    dwindle = {
        preserve_split       = true,
    },

    master = {
        new_status = "master",
        new_on_top = true,
        mfact      = 0.5,
    },

    misc = {
        disable_hyprland_logo      = true,
        disable_splash_rendering   = true,
        disable_watchdog_warning   = true,
        force_default_wallpaper    = 0,
        vrr                        = 0,
        mouse_move_enables_dpms    = true,
        key_press_enables_dpms     = true,
        enable_swallow             = true,
        swallow_regex              = "^(kitty|Alacritty)$",
        focus_on_activate          = true,
        initial_workspace_tracking = 0,
        middle_click_paste         = false,
        enable_anr_dialog          = true,
        anr_missed_pings           = 15,
        allow_session_lock_restore = true,
        on_focus_under_fullscreen  = 1,
    },

    xwayland = {
        enabled            = true,
        force_zero_scaling = true,
    },

    binds = {
        workspace_back_and_forth = true,
        allow_workspace_cycles   = true,
        pass_mouse_when_bound    = false,
    },

    render = { direct_scanout = 0 },

    cursor = {
        sync_gsettings_theme     = true,
        no_hardware_cursors      = 0,
        enable_hyprcursor        = true,
        warp_on_change_workspace = 2,
        no_warps                 = true,
        zoom_factor              = 1.0,
    },

    gestures = {
        workspace_swipe_distance           = 500,
        workspace_swipe_invert             = true,
        workspace_swipe_min_speed_to_force = 30,
        workspace_swipe_cancel_ratio       = 0.5,
        workspace_swipe_create_new         = true,
        workspace_swipe_forever            = true,
    },
})

-- Trackpad & touchscreen gestures
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "up", action = function() hl.exec_cmd(scriptsDir .. "/OverviewToggle.sh") end })
hl.gesture({ fingers = 4, direction = "up", action = function() hl.exec_cmd(scriptsDir .. "/ZoomCursor.sh in") end })
hl.gesture({ fingers = 4, direction = "down", action = function() hl.exec_cmd(scriptsDir .. "/ZoomCursor.sh out") end })

-- Enable common Dell touchpad if present
hl.device({ name = "dell0ab2:00-27c6:0d43-touchpad", enabled = true })

--------------------------------------------------------------------------------
-- 6. ANIMATIONS & CURVES (with dynamic bridge for animations.conf & UserAnimations.conf)
--------------------------------------------------------------------------------
-- Default Expressive Curves
hl.curve("wind",       { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })
hl.curve("winIn",      { type = "bezier", points = { {0.1, 1.1}, {0.1, 1.1} } })
hl.curve("winOut",     { type = "bezier", points = { {0.3, -0.3}, {0, 1} } })
hl.curve("liner",      { type = "bezier", points = { {1, 1}, {1, 1} } })
hl.curve("overshot",   { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })
hl.curve("smoothOut",  { type = "bezier", points = { {0.5, 0}, {0.99, 0.99} } })
hl.curve("smoothIn",   { type = "bezier", points = { {0.5, -0.5}, {0.68, 1.5} } })
hl.curve("expressive", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })
hl.curve("snappy",     { type = "bezier", points = { {0.35, 0.0}, {0.15, 1.0} } })
hl.curve("standard",   { type = "bezier", points = { {0.2, 0.0}, {0.0, 1.0} } })

hl.animation({ leaf = "global",         enabled = true, speed = 10,  bezier = "default" })
hl.animation({ leaf = "windows",        enabled = true, speed = 4.5, bezier = "wind",      style = "popin 75%" })
hl.animation({ leaf = "windowsIn",      enabled = true, speed = 5,   bezier = "winIn",     style = "slide" })
hl.animation({ leaf = "windowsOut",     enabled = true, speed = 3.5, bezier = "snappy",    style = "popin 80%" })
hl.animation({ leaf = "windowsMove",    enabled = true, speed = 4,   bezier = "wind",      style = "slide" })
hl.animation({ leaf = "border",         enabled = true, speed = 1,   bezier = "liner" })
hl.animation({ leaf = "borderangle",    enabled = true, speed = 100, bezier = "liner",     style = "loop" })
hl.animation({ leaf = "fade",           enabled = true, speed = 3,   bezier = "smoothOut" })
hl.animation({ leaf = "fadeDpms",       enabled = false })
hl.animation({ leaf = "workspaces",     enabled = true, speed = 5,   bezier = "overshot",  style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4.5, bezier = "expressive", style = "slidevert" })

-- Dynamic Animation Bridge: Parses animations.conf and UserAnimations.conf if found
local function load_custom_animations(filepath, depth)
    depth = depth or 0
    if depth > 3 then return end
    local f = io.open(filepath, "r")
    if not f then return end
    local dir = filepath:match("^(.*)/[^/]+$") or (home .. "/.config/hypr")
    for line in f:lines() do
        local clean = line:gsub("#.*$", ""):match("^%s*(.-)%s*$")
        if clean and clean ~= "" then
            local src = clean:match("^source%s*=%s*(.+)$")
            if src then
                src = src:gsub("^~", home):gsub("%$HOME", home)
                if src:sub(1, 2) == "./" then
                    src = dir .. "/" .. src:sub(3)
                elseif src:sub(1, 1) ~= "/" then
                    src = dir .. "/" .. src
                end
                load_custom_animations(src, depth + 1)
            else
                local anim_en = clean:match("^enabled%s*=%s*(%S+)")
                if anim_en then
                    local is_en = (anim_en == "1" or anim_en == "true" or anim_en == "yes" or anim_en == "on")
                    pcall(function()
                        hl.config({ animations = { enabled = is_en } })
                    end)
                else
                    local bez_name, x1, y1, x2, y2 = clean:match("^bezier%s*=%s*([%w_%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)")
                    if bez_name then
                        pcall(function()
                            hl.curve(bez_name, { type = "bezier", points = { {tonumber(x1), tonumber(y1)}, {tonumber(x2), tonumber(y2)} } })
                        end)
                    else
                        local leaf, en, spd, bez, extra = clean:match("^animation%s*=%s*([%w_%-]+)%s*,%s*([%d%a]+)%s*,%s*([%d%.]+)%s*,%s*([%w_%-]+)%s*,?%s*(.*)")
                        if leaf then
                            local style = extra and extra ~= "" and extra:match("^%s*(.-)%s*$") or nil
                            pcall(function()
                                local spd_num = tonumber(spd) or 5
                                if spd_num > 100 then spd_num = 100 end
                                if spd_num < 0.1 then spd_num = 0.1 end
                                local def = {
                                    leaf = leaf,
                                    enabled = (en == "1" or en == "true" or en == "yes" or en == "on"),
                                    speed = spd_num,
                                    bezier = bez
                                }
                                if style and style ~= "" then def.style = style end
                                hl.animation(def)
                            end)
                        else
                            local leaf_dis, en_dis = clean:match("^animation%s*=%s*([%w_%-]+)%s*,%s*(%w+)%s*$")
                            if leaf_dis and (en_dis == "0" or en_dis == "false" or en_dis == "no" or en_dis == "off") then
                                pcall(function()
                                    hl.animation({ leaf = leaf_dis, enabled = false })
                                end)
                            end
                        end
                    end
                end
            end
        end
    end
    f:close()
end
load_custom_animations(home .. "/.config/hypr/animations.conf")
load_custom_animations(home .. "/.config/hypr/UserConfigs/UserAnimations.conf")

--------------------------------------------------------------------------------
-- 7. KEYBINDINGS
--------------------------------------------------------------------------------
local mainMod = "SUPER"

local function bindCommand(keys, command, flags)
    hl.bind(keys, hl.dsp.exec_cmd(command), flags)
end

-- Core Applications and menus
bindCommand(mainMod .. " + Return", scriptsDir .. "/Dropterminal.sh kitty")
bindCommand(mainMod .. " + SHIFT + Return", terminal)
bindCommand(mainMod .. " + D", rofiMenu)
bindCommand(mainMod .. " + B", "xdg-open 'https://'")
bindCommand(mainMod .. " + A", scriptsDir .. "/OverviewToggle.sh")
bindCommand(mainMod .. " + E", fileManager)
bindCommand(mainMod .. " + T", scriptsDir .. "/ThemeChanger.sh")
bindCommand(mainMod .. " + H", scriptsDir .. "/KeyHints.sh")
bindCommand(mainMod .. " + ALT + R", scriptsDir .. "/Refresh.sh")
bindCommand(mainMod .. " + ALT + E", scriptsDir .. "/RofiEmoji.sh")
bindCommand(mainMod .. " + S", scriptsDir .. "/RofiSearch.sh")
bindCommand(mainMod .. " + CTRL + S", "rofi -show window")
bindCommand(mainMod .. " + ALT + O", scriptsDir .. "/ChangeBlur.sh")
bindCommand(mainMod .. " + SHIFT + G", scriptsDir .. "/GameMode.sh")
bindCommand(mainMod .. " + ALT + L", scriptsDir .. "/ChangeLayout.sh")
bindCommand(mainMod .. " + ALT + V", scriptsDir .. "/ClipManager.sh")
bindCommand(mainMod .. " + CTRL + R", scriptsDir .. "/RofiThemeSelector.sh")
bindCommand(mainMod .. " + CTRL + SHIFT + R", "pkill rofi || true; " .. scriptsDir .. "/RofiThemeSelector-modified.sh")
bindCommand(mainMod .. " + SHIFT + Y", "yusei-settings")

-- Media, Wallpapers & Tools
bindCommand(mainMod .. " + CTRL + M", userScripts .. "/RofiBeats.sh")
bindCommand(mainMod .. " + SHIFT + O", userScripts .. "/ZshChangeTheme.sh")
bindCommand(mainMod .. " + W", userScripts .. "/WallpaperSelect.sh")
bindCommand(mainMod .. " + SHIFT + W", userScripts .. "/WallpaperEffects.sh")
bindCommand("CTRL + ALT + W", userScripts .. "/WallpaperRandom.sh")
bindCommand(mainMod .. " + ALT + C", userScripts .. "/RofiCalc.sh")

-- Screen Recording & OCR Grabber (v1.5.0 Power Tools)
bindCommand(mainMod .. " + SHIFT + R", scriptsDir .. "/ScreenRecord.sh --toggle")
bindCommand(mainMod .. " + SHIFT + ALT + R", scriptsDir .. "/ScreenRecord.sh --region")
bindCommand(mainMod .. " + ALT + T", scriptsDir .. "/OcrGrab.sh")

-- Window & Layout Controls
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mainMod .. " + CTRL + F", hl.dsp.window.fullscreen({ action = "toggle", mode = "maximized" }))
hl.bind(mainMod .. " + Space", hl.dsp.window.float({ action = "toggle" }))
bindCommand(mainMod .. " + ALT + Space", scriptsDir .. "/ToggleAllFloating.sh")
bindCommand(mainMod .. " + CTRL + ALT + B", "pkill -SIGUSR1 waybar")
bindCommand(mainMod .. " + CTRL + B", scriptsDir .. "/WaybarStyles.sh")
bindCommand(mainMod .. " + ALT + B", scriptsDir .. "/WaybarLayout.sh")
bindCommand(mainMod .. " + N", scriptsDir .. "/Hyprsunset.sh toggle")
hl.bind(mainMod .. " + CTRL + O", hl.dsp.window.set_prop({ prop = "opaque", value = "toggle" }))
bindCommand(mainMod .. " + CTRL + SHIFT + O", scriptsDir .. "/ToggleOpacity.sh")
bindCommand(mainMod .. " + SHIFT + K", scriptsDir .. "/KeyBinds.sh")
bindCommand(mainMod .. " + SHIFT + A", scriptsDir .. "/Animations.sh")

-- Screenshots
bindCommand("ALT + Print", scriptsDir .. "/ScreenShot.sh --active")
bindCommand(mainMod .. " + Print", scriptsDir .. "/ScreenShot.sh --now")
bindCommand(mainMod .. " + SHIFT + Print", scriptsDir .. "/ScreenShot.sh --area")
bindCommand(mainMod .. " + CTRL + Print", scriptsDir .. "/ScreenShot.sh --in5")
bindCommand(mainMod .. " + CTRL + SHIFT + Print", scriptsDir .. "/ScreenShot.sh --in10")
bindCommand(mainMod .. " + F6", scriptsDir .. "/ScreenShot.sh --now")
bindCommand(mainMod .. " + SHIFT + F6", scriptsDir .. "/ScreenShot.sh --area")
bindCommand(mainMod .. " + CTRL + F6", scriptsDir .. "/ScreenShot.sh --in5")
bindCommand(mainMod .. " + ALT + F6", scriptsDir .. "/ScreenShot.sh --in10")
bindCommand("ALT + F6", scriptsDir .. "/ScreenShot.sh --active")
bindCommand(mainMod .. " + SHIFT + S", scriptsDir .. "/ScreenShot.sh --swappy")

-- Magnifier
bindCommand(mainMod .. " + ALT + mouse_down", scriptsDir .. "/ZoomCursor.sh in")
bindCommand(mainMod .. " + ALT + mouse_up", scriptsDir .. "/ZoomCursor.sh out")

-- Audio, Brightness, Laptop Controls
hl.bind("ALT_L + SHIFT_L", hl.dsp.exec_cmd(scriptsDir .. "/KeyboardLayout.sh switch"), { locked = true })
hl.bind("SHIFT_L + ALT_L", hl.dsp.exec_cmd(scriptsDir .. "/Tak0-Per-Window-Switch.sh"), { locked = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --inc"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --dec"), { locked = true, repeating = true })
hl.bind("ALT + XF86AudioRaiseVolume", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --inc-precise"), { locked = true, repeating = true })
hl.bind("ALT + XF86AudioLowerVolume", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --dec-precise"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --toggle-mic"), { locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --toggle"), { locked = true })
hl.bind("XF86Sleep", hl.dsp.exec_cmd(scriptsDir .. "/LockScreen.sh --lock-and-wait && systemctl suspend"), { locked = true })
hl.bind("XF86RFKill", hl.dsp.exec_cmd(scriptsDir .. "/AirplaneMode.sh"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(scriptsDir .. "/MediaCtrl.sh --pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(scriptsDir .. "/MediaCtrl.sh --pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd(scriptsDir .. "/MediaCtrl.sh --nxt"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd(scriptsDir .. "/MediaCtrl.sh --prv"), { locked = true })
hl.bind("XF86AudioStop", hl.dsp.exec_cmd(scriptsDir .. "/MediaCtrl.sh --stop"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(scriptsDir .. "/Brightness.sh --inc"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(scriptsDir .. "/Brightness.sh --dec"), { locked = true, repeating = true })
hl.bind("XF86TouchpadToggle", hl.dsp.exec_cmd(scriptsDir .. "/TouchPad.sh"), { locked = true })

-- Session & Power Management
hl.bind("CTRL + ALT + Delete", hl.dsp.exit())
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + C", hl.dsp.window.close())
bindCommand(mainMod .. " + SHIFT + Q", scriptsDir .. "/KillActiveProcess.sh")
bindCommand("CTRL + ALT + L", scriptsDir .. "/LockScreen.sh")
bindCommand("CTRL + ALT + P", scriptsDir .. "/Wlogout.sh")
bindCommand(mainMod .. " + SHIFT + N", "swaync-client -t -sw")
bindCommand(mainMod .. " + SHIFT + E", scriptsDir .. "/Kool_Quick_Settings.sh")
bindCommand(mainMod .. " + SHIFT + P", scriptsDir .. "/power-optimizer.sh --toggle-hz")

-- Layout Dispatches
hl.bind(mainMod .. " + CTRL + D", hl.dsp.layout("removemaster"))
hl.bind(mainMod .. " + I", hl.dsp.layout("addmaster"))
hl.bind(mainMod .. " + CTRL + Return", hl.dsp.layout("swapwithmaster"))
hl.bind(mainMod .. " + SHIFT + I", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + M", hl.dsp.layout("splitratio 0.3"))
hl.bind("ALT + TAB", function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top" }))
end)

-- Window Movement, Groups & Focus
for _, d in ipairs({"left", "right", "up", "down"}) do
    local delta = ({left={x=-50,y=0}, right={x=50,y=0}, up={x=0,y=-50}, down={x=0,y=50}})[d]
    hl.bind(mainMod .. " + SHIFT + " .. d, hl.dsp.window.resize({ x = delta.x, y = delta.y, relative = true }))
    hl.bind(mainMod .. " + CTRL + " .. d, hl.dsp.window.move({ direction = d }))
    hl.bind(mainMod .. " + ALT + " .. d, hl.dsp.window.swap({ direction = d }))
    hl.bind(mainMod .. " + " .. d, hl.dsp.focus({ direction = d }))
end
hl.bind(mainMod .. " + G", hl.dsp.group.toggle())
hl.bind(mainMod .. " + CTRL + TAB", hl.dsp.group.next())
hl.bind(mainMod .. " + CTRL + SHIFT + TAB", hl.dsp.group.prev())
hl.bind(mainMod .. " + CTRL + K", hl.dsp.window.move({ into_group = "left" }))
hl.bind(mainMod .. " + CTRL + L", hl.dsp.window.move({ into_group = "right" }))
hl.bind(mainMod .. " + CTRL + H", hl.dsp.window.move({ out_of_group = true }))

-- Workspace Navigation
hl.bind(mainMod .. " + TAB", hl.dsp.focus({ workspace = "m+1" }))
hl.bind(mainMod .. " + SHIFT + TAB", hl.dsp.focus({ workspace = "m-1" }))

-- Scratchpads
hl.bind(mainMod .. " + Z", hl.dsp.workspace.toggle_special())
hl.bind(mainMod .. " + SHIFT + Z", hl.dsp.window.move({ workspace = "special" }))
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.workspace.toggle_special("music"))
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.workspace.toggle_special("monitor"))

-- Workspace Numbered Binds (1..10)
for i = 1, 10 do
    local code = i + 9
    hl.bind(mainMod .. " + code:" .. code, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + code:" .. code, hl.dsp.window.move({ workspace = i }))
    hl.bind(mainMod .. " + CTRL + code:" .. code, hl.dsp.window.move({ workspace = i, follow = false }))
end
hl.bind(mainMod .. " + SHIFT + bracketleft", hl.dsp.window.move({ workspace = "-1" }))
hl.bind(mainMod .. " + SHIFT + bracketright", hl.dsp.window.move({ workspace = "+1" }))
hl.bind(mainMod .. " + CTRL + bracketleft", hl.dsp.window.move({ workspace = "-1", follow = false }))
hl.bind(mainMod .. " + CTRL + bracketright", hl.dsp.window.move({ workspace = "+1", follow = false }))
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + period", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + comma", hl.dsp.focus({ workspace = "e-1" }))
for key, direction in pairs({F9="left", F10="right", F11="up", F12="down"}) do
    hl.bind(mainMod .. " + CTRL + " .. key, hl.dsp.workspace.move({ monitor = direction }))
end

-- Mouse Window Drag / Resize
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

--------------------------------------------------------------------------------
-- 8. WINDOW RULES & LAYER RULES
--------------------------------------------------------------------------------
hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})
hl.window_rule({
    name = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

-- JaKooLit tags
hl.window_rule({ match = { class = [==[^([Ff]irefox|org.mozilla.firefox|[Ff]irefox-esr|[Ff]irefox-bin)$]==] }, tag = [==[+browser]==] })
hl.window_rule({ match = { class = [==[^([Gg]oogle-chrome(-beta|-dev|-unstable)?)$]==] }, tag = [==[+browser]==] })
hl.window_rule({ match = { class = [==[^(chrome-.+-Default)$]==] }, tag = [==[+browser]==] })
hl.window_rule({ match = { class = [==[^([Cc]hromium)$]==] }, tag = [==[+browser]==] })
hl.window_rule({ match = { class = [==[^([Mm]icrosoft-edge(-stable|-beta|-dev|-unstable))$]==] }, tag = [==[+browser]==] })
hl.window_rule({ match = { class = [==[^(Brave-browser(-beta|-dev|-unstable)?)$]==] }, tag = [==[+browser]==] })
hl.window_rule({ match = { class = [==[^([Tt]horium-browser|[Cc]achy-browser)$]==] }, tag = [==[+browser]==] })
hl.window_rule({ match = { class = [==[^(zen-alpha|zen)$]==] }, tag = [==[+browser]==] })
hl.window_rule({ match = { class = [==[^(swaync-control-center|swaync-notification-window|swaync-client|class)$]==] }, tag = [==[+notif]==] })
hl.window_rule({ match = { title = [==[^(KooL Quick Cheat Sheet)$]==] }, tag = [==[+KooL_Cheat]==] })
hl.window_rule({ match = { title = [==[^(KooL Hyprland Settings)$]==] }, tag = [==[+KooL_Settings]==] })
hl.window_rule({ match = { class = [==[^(nwg-displays|nwg-look)$]==] }, tag = [==[+KooL-Settings]==] })
hl.window_rule({ match = { class = [==[^(Alacritty|kitty|kitty-dropterm)$]==] }, tag = [==[+terminal]==] })
hl.window_rule({ match = { class = [==[^([Tt]hunderbird|org.mozilla.Thunderbird)$]==] }, tag = [==[+email]==] })
hl.window_rule({ match = { class = [==[^(eu.betterbird.Betterbird)$]==] }, tag = [==[+email]==] })
hl.window_rule({ match = { class = [==[^(org.gnome.Evolution)$]==] }, tag = [==[+email]==] })
hl.window_rule({ match = { class = [==[^(codium|codium-url-handler|VSCodium)$]==] }, tag = [==[+projects]==] })
hl.window_rule({ match = { class = [==[^(VSCode|code|code-url-handler)$]==] }, tag = [==[+projects]==] })
hl.window_rule({ match = { class = [==[^(jetbrains-.+)$]==] }, tag = [==[+projects]==] })
hl.window_rule({ match = { class = [==[^(dev.zed.Zed|antigravity)$]==] }, tag = [==[+projects]==] })
hl.window_rule({ match = { class = [==[^(com.obsproject.Studio)$]==] }, tag = [==[+screenshare]==] })
hl.window_rule({ match = { class = [==[^([Dd]iscord|[Ww]ebCord|[Vv]esktop)$]==] }, tag = [==[+im]==] })
hl.window_rule({ match = { class = [==[^([Ff]erdium)$]==] }, tag = [==[+im]==] })
hl.window_rule({ match = { class = [==[^([Ww]hatsapp-for-linux)$]==] }, tag = [==[+im]==] })
hl.window_rule({ match = { class = [==[^(org.telegram.desktop|io.github.tdesktop_x64.TDesktop)$]==] }, tag = [==[+im]==] })
hl.window_rule({ match = { class = [==[^(teams-for-linux)$]==] }, tag = [==[+im]==] })
hl.window_rule({ match = { class = [==[^(im.riot.Riot|Element)$]==] }, tag = [==[+im]==] })
hl.window_rule({ match = { class = [==[^(gamescope)$]==] }, tag = [==[+games]==] })
hl.window_rule({ match = { class = [==[^(steam_app_\\d+)$]==] }, tag = [==[+games]==] })
hl.window_rule({ match = { class = [==[^([Ss]team)$]==] }, tag = [==[+gamestore]==] })
hl.window_rule({ match = { title = [==[^([Ll]utris)$]==] }, tag = [==[+gamestore]==] })
hl.window_rule({ match = { class = [==[^(com.heroicgameslauncher.hgl)$]==] }, tag = [==[+gamestore]==] })
hl.window_rule({ match = { class = [==[^([Tt]hunar|org.gnome.Nautilus|[Pp]cmanfm-qt)$]==] }, tag = [==[+file-manager]==] })
hl.window_rule({ match = { class = [==[^(app.drey.Warp)$]==] }, tag = [==[+file-manager]==] })
hl.window_rule({ match = { class = [==[^([Ww]aytrogen)$]==] }, tag = [==[+wallpaper]==] })
hl.window_rule({ match = { class = [==[^([Aa]udacious)$]==] }, tag = [==[+multimedia]==] })
hl.window_rule({ match = { class = [==[^([Mm]pv|vlc)$]==] }, tag = [==[+multimedia_video]==] })
hl.window_rule({ match = { title = [==[^(ROG Control)$]==] }, tag = [==[+settings]==] })
hl.window_rule({ match = { class = [==[^(wihotspot(-gui)?)$]==] }, tag = [==[+settings]==] })
hl.window_rule({ match = { class = [==[^([Bb]aobab|org.gnome.[Bb]aobab)$]==] }, tag = [==[+settings]==] })
hl.window_rule({ match = { class = [==[^(gnome-disks|wihotspot(-gui)?)$]==] }, tag = [==[+settings]==] })
hl.window_rule({ match = { title = [==[(Kvantum Manager)]==] }, tag = [==[+settings]==] })
hl.window_rule({ match = { class = [==[^(file-roller|org.gnome.FileRoller)$]==] }, tag = [==[+settings]==] })
hl.window_rule({ match = { class = [==[^(nm-applet|nm-connection-editor|blueman-manager)$]==] }, tag = [==[+settings]==] })
hl.window_rule({ match = { class = [==[^(pavucontrol|org.pulseaudio.pavucontrol|com.saivert.pwvucontrol)$]==] }, tag = [==[+settings]==] })
hl.window_rule({ match = { class = [==[^(qt5ct|qt6ct)$]==] }, tag = [==[+settings]==] })
hl.window_rule({ match = { class = [==[(xdg-desktop-portal-gtk)]==] }, tag = [==[+settings]==] })
hl.window_rule({ match = { class = [==[^(org.kde.polkit-kde-authentication-agent-1)$]==] }, tag = [==[+settings]==] })
hl.window_rule({ match = { class = [==[^([Rr]ofi)$]==] }, tag = [==[+settings]==] })
hl.window_rule({ match = { class = [==[^(btrfs-assistant)$]==] }, tag = [==[+settings]==] })
hl.window_rule({ match = { class = [==[^(timeshift-gtk)$]==] }, tag = [==[+settings]==] })
hl.window_rule({ match = { class = [==[^(gnome-system-monitor|org.gnome.SystemMonitor|io.missioncenter.MissionCenter)$]==] }, tag = [==[+viewer]==] })
hl.window_rule({ match = { class = [==[^(evince)$]==] }, tag = [==[+viewer]==] })
hl.window_rule({ match = { class = [==[^(eog|org.gnome.Loupe)$]==] }, tag = [==[+viewer]==] })

-- Multimedia specific rules (no blur, 100% opaque for videos)
hl.window_rule({ match = { tag = [==[multimedia_video]==] }, no_blur = true, opacity = "1.0" })
hl.window_rule({ match = { tag = [==[multimedia]==] }, no_blur = true, opacity = "1.0" })

-- Gaming rules (immediate tearing)
hl.window_rule({ match = { tag = [==[games]==] }, no_blur = true, immediate = true })

-- Centering & Floating rules
hl.window_rule({ match = { tag = [==[KooL_Cheat]==] }, center = true, float = true, size = [==[(monitor_w*0.65) (monitor_h*0.9)]==] })
hl.window_rule({ match = { tag = [==[KooL-Settings]==] }, center = true, float = true, size = [==[(monitor_w*0.7) (monitor_h*0.7)]==] })
hl.window_rule({ match = { tag = [==[wallpaper]==] }, center = true, float = true, size = [==[(monitor_w*0.7) (monitor_h*0.7)]==] })
hl.window_rule({ match = { tag = [==[settings]==] }, center = true, float = true, size = [==[(monitor_w*0.7) (monitor_h*0.7)]==] })
hl.window_rule({ match = { tag = [==[viewer]==] }, center = true, float = true })
hl.window_rule({ match = { class = [==[([Zz]oom|onedriver|onedriver-launcher)]==] }, float = true })
hl.window_rule({ match = { class = [==[(org.gnome.Calculator|qalculate-gtk)]==] }, float = true })
hl.window_rule({ match = { class = [==[^(mpv|com.github.rafostar.Clapper)$]==] }, float = true })
hl.window_rule({ match = { title = [==[^(Authentication Required)$]==] }, float = true, center = true })

-- Specific App Opacities
hl.window_rule({ match = { tag = [==[browser]==] }, opacity = [==[0.99 0.85]==] })
hl.window_rule({ match = { tag = [==[projects]==] }, opacity = [==[0.92 0.82]==] })
hl.window_rule({ match = { tag = [==[terminal]==] }, opacity = [==[0.92 0.75]==] })

-- Dropdown terminal rule (prevent initial center-screen flash before slide-down)
hl.window_rule({ match = { class = [==[^(kitty-dropterm)$]==] }, float = true, no_anim = true })

-- Layer rules for Rofi, SwayNC, and Quickshell overview
hl.layer_rule({ match = { namespace = [==[rofi]==] }, blur = true })
hl.layer_rule({ match = { namespace = [==[notifications]==] }, blur = true })
hl.layer_rule({ match = { namespace = [==[quickshell:overview]==] }, blur = true, ignore_alpha = 0.5 })

-- User's preferred global opacity override (90% uniform transparency across windows)
hl.window_rule({
    match = { class = ".*" },
    opacity = "0.9 override 0.9 override 0.9 override",
})

--------------------------------------------------------------------------------
-- 9. USER OVERRIDES (userprefs.lua / userprefs.conf)
--------------------------------------------------------------------------------
local user_lua = home .. "/.config/hypr/userprefs.lua"
local f_lua = io.open(user_lua, "r")
if f_lua then
    f_lua:close()
    pcall(dofile, user_lua)
end
