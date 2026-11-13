#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
# A bash script designed to run only once dotfiles installed

# THIS SCRIPT CAN BE DELETED ONCE SUCCESSFULLY BOOTED!! And also, edit ~/.config/hypr/configs/Settings.conf
# NOT necessary to do since this script is only designed to run only once as long as the marker exists
# marker file is located at ~/.config/hypr/.initial_startup_done
# However, I do highly suggest not to touch it since again, as long as the marker exist, script wont run

export PATH="$HOME/.local/bin:$PATH"

# Variables
scriptsDir="$HOME/.config/hypr/scripts"
state_wallpaper="$HOME/.config/hypr/.current_wallpaper"
default_wallpaper="$HOME/.config/hypr/wallpaper.jpg"
waybar_style="$HOME/.config/waybar/style/[Extra] Neon Circuit.css"
kvantum_theme="catppuccin-mocha-blue"
color_scheme="prefer-dark"
gtk_theme="Adwaita-dark"
icon_theme="Papirus-Dark"
cursor_theme="Bibata-Modern-Ice"

swww="swww img"
effect="--transition-bezier .43,1.19,1,.4 --transition-fps 30 --transition-type grow --transition-pos 0.925,0.977 --transition-duration 2"

# Check if a marker file exists.
if [ ! -f "$HOME/.config/hypr/.initial_startup_done" ]; then
    sleep 1

    # Resolve wallpaper from ~/.config/hypr/.current_wallpaper symlink or fallback to wallpaper.jpg
    wallpaper=""
    if [ -L "$state_wallpaper" ] || [ -f "$state_wallpaper" ]; then
        resolved_wall="$(readlink -f "$state_wallpaper" 2>/dev/null || true)"
        if [ -n "$resolved_wall" ] && [ -f "$resolved_wall" ]; then
            wallpaper="$resolved_wall"
        fi
    fi
    if [ -z "$wallpaper" ] && [ -f "$default_wallpaper" ]; then
        wallpaper="$default_wallpaper"
    fi

    # Initialize wallust and wallpaper
    if [ -n "$wallpaper" ] && [ -f "$wallpaper" ]; then
        if command -v wallust > /dev/null 2>&1; then
            wallust run -s "$wallpaper" > /dev/null 2>&1 || true
        fi

        if ! pidof swww-daemon > /dev/null 2>&1 && ! pgrep -x swww-daemon > /dev/null 2>&1; then
            swww-daemon --format xrgb > /dev/null 2>&1 &
        fi

        swww_ready=false
        for _ in $(seq 1 25); do
            if swww query > /dev/null 2>&1; then
                swww_ready=true
                break
            fi
            sleep 0.2
        done

        if [ "$swww_ready" = "true" ]; then
            $swww "$wallpaper" $effect > /dev/null 2>&1 || true
        fi

        if [ -x "$scriptsDir/WallustSwww.sh" ]; then
            "$scriptsDir/WallustSwww.sh" "$wallpaper" > /dev/null 2>&1 &
        fi
    fi

    # initiate GTK dark mode and apply icon and cursor theme
    if command -v gsettings > /dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface color-scheme "$color_scheme" > /dev/null 2>&1 &
        gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" > /dev/null 2>&1 &
        gsettings set org.gnome.desktop.interface icon-theme "$icon_theme" > /dev/null 2>&1 &
        gsettings set org.gnome.desktop.interface cursor-theme "$cursor_theme" > /dev/null 2>&1 &
        gsettings set org.gnome.desktop.interface cursor-size 24 > /dev/null 2>&1 &
    fi

    # NIXOS initiate GTK dark mode and apply icon and cursor theme
    if [ -f /etc/os-release ] && grep -qi nixos /etc/os-release; then
        if command -v gsettings > /dev/null 2>&1; then
            gsettings set org.gnome.desktop.interface color-scheme "'$color_scheme'" > /dev/null 2>&1 &
        fi
        if command -v dconf > /dev/null 2>&1; then
            dconf write /org/gnome/desktop/interface/gtk-theme "'$gtk_theme'" > /dev/null 2>&1 &
            dconf write /org/gnome/desktop/interface/icon-theme "'$icon_theme'" > /dev/null 2>&1 &
            dconf write /org/gnome/desktop/interface/cursor-theme "'$cursor_theme'" > /dev/null 2>&1 &
            dconf write /org/gnome/desktop/interface/cursor-size "24" > /dev/null 2>&1 &
        fi
    fi

    # initiate kvantum theme
    if command -v kvantummanager > /dev/null 2>&1; then
        kvantummanager --set "$kvantum_theme" > /dev/null 2>&1 &
    fi

    # Create a marker file to indicate that the script has been executed.
    mkdir -p "$HOME/.config/hypr"
    touch "$HOME/.config/hypr/.initial_startup_done"

    exit 0
fi
