#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Screenshots scripts

# variables
time=$(date "+%d-%b_%H-%M-%S")
PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
dir="$PICTURES_DIR/Screenshots"
file="Screenshot_${time}_${RANDOM}.png"

iDIR="$HOME/.config/swaync/icons"
iDoR="$HOME/.config/swaync/images"
sDIR="$HOME/.config/hypr/scripts"

active_window_class=$(hyprctl -j activewindow | jq -r '(.class)')
active_window_file="Screenshot_${time}_${active_window_class}.png"
active_window_path="${dir}/${active_window_file}"

notify_cmd_base="notify-send -t 10000 -A action1=Open -A action2=Delete -h string:x-canonical-private-synchronous:shot-notify"
notify_cmd_shot="${notify_cmd_base} -i ${iDIR}/picture.png "
notify_cmd_shot_win="${notify_cmd_base} -i ${iDIR}/picture.png "
notify_cmd_NOT="notify-send -u low -t 3000 -i ${iDoR}/note.png "

tmpfile=""
cleanup() {
    if [[ -n "${tmpfile:-}" && -e "$tmpfile" ]]; then
        rm -f -- "$tmpfile"
    fi
}
trap cleanup EXIT

capture_and_save() {
    local dest="$1"
    shift
    rm -f -- "${tmpfile:-}"
    tmpfile=$(mktemp --suffix=.png)
    if grim "$@" "$tmpfile" && [[ -s "$tmpfile" ]]; then
        cp -- "$tmpfile" "$dest"
        wl-copy <"$tmpfile"
        return 0
    fi
    return 1
}

# notify and view screenshot
notify_view() {
    if [[ "$1" == "active" ]]; then
        if [[ -s "${active_window_path}" ]]; then
			"${sDIR}/Sounds.sh" --screenshot        
            resp=$(timeout 10 ${notify_cmd_shot_win} " Screenshot of:" " ${active_window_class} Saved.")
            case "$resp" in
				action1)
					xdg-open "${active_window_path}" &
					;;
				action2)
					rm -f -- "${active_window_path}" &
					;;
			esac
        else
            ${notify_cmd_NOT} " Screenshot of:" " ${active_window_class} NOT Saved."
            "${sDIR}/Sounds.sh" --error
        fi

    elif [[ "$1" == "swappy" ]]; then
		"${sDIR}/Sounds.sh" --screenshot
		resp=$(timeout 10 ${notify_cmd_shot} " Screenshot:" " Captured by Swappy")
		case "$resp" in
			action1)
				swappy -f - <"$tmpfile"
				;;
			action2)
				rm -f -- "$tmpfile"
				;;
		esac

    else
        local check_file="${dir}/${file}"
        if [[ -s "$check_file" ]]; then
            "${sDIR}/Sounds.sh" --screenshot
            resp=$(timeout 10 ${notify_cmd_shot} " Screenshot" " Saved")
			case "$resp" in
				action1)
					xdg-open "${check_file}" &
					;;
				action2)
					rm -f -- "${check_file}" &
					;;
			esac
        else
            ${notify_cmd_NOT} " Screenshot" " NOT Saved"
            "${sDIR}/Sounds.sh" --error
        fi
    fi
}

# countdown
countdown() {
	for sec in $(seq $1 -1 1); do
		notify-send -h string:x-canonical-private-synchronous:shot-notify -t 1000 -i "$iDIR"/timer.png  " Taking shot" " in: $sec secs"
		sleep 1
	done
}

# take shots
shotnow() {
	capture_and_save "${dir}/${file}" || true
	notify_view
}

shot5() {
	countdown '5'
	sleep 1
	capture_and_save "${dir}/${file}" || true
	sleep 1
	notify_view
}

shot10() {
	countdown '10'
	sleep 1
	capture_and_save "${dir}/${file}" || true
	sleep 1
	notify_view
}

shotwin() {
	w_pos=$(hyprctl activewindow | grep 'at:' | cut -d':' -f2 | tr -d ' ' | tail -n1)
	w_size=$(hyprctl activewindow | grep 'size:' | cut -d':' -f2 | tr -d ' ' | tail -n1 | sed s/,/x/g)
	if [[ -n "$w_pos" && -n "$w_size" ]]; then
		capture_and_save "${dir}/${file}" -g "$w_pos $w_size" || true
	fi
	notify_view
}

shotarea() {
	local geom
	if geom=$(slurp) && [[ -n "$geom" ]]; then
		capture_and_save "${dir}/${file}" -g "$geom" || true
	fi
	notify_view
}

shotactive() {
    local geom
    active_window_class=$(hyprctl -j activewindow | jq -r '(.class // empty)')
    active_window_class="${active_window_class//\//_}"
    active_window_file="Screenshot_${time}_${active_window_class:-none}.png"
    active_window_path="${dir}/${active_window_file}"

    geom=$(hyprctl -j activewindow | jq -r 'select(.at and .size) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
    if [[ -n "$geom" ]]; then
        capture_and_save "${active_window_path}" -g "$geom" || true
    fi
    notify_view "active"
}

shotswappy() {
	local geom
	rm -f -- "${tmpfile:-}"
	tmpfile=$(mktemp --suffix=.png)
	if geom=$(slurp) && [[ -n "$geom" ]] && grim -g "$geom" "$tmpfile" && [[ -s "$tmpfile" ]]; then
		wl-copy <"$tmpfile"
		notify_view "swappy"
	fi
}

if [[ ! -d "$dir" ]]; then
	mkdir -p "$dir"
fi

if [[ "$1" == "--now" ]]; then
	shotnow
elif [[ "$1" == "--in5" ]]; then
	shot5
elif [[ "$1" == "--in10" ]]; then
	shot10
elif [[ "$1" == "--win" ]]; then
	shotwin
elif [[ "$1" == "--area" ]]; then
	shotarea
elif [[ "$1" == "--active" ]]; then
	shotactive
elif [[ "$1" == "--swappy" ]]; then
	shotswappy
else
	echo -e "Available Options : --now --in5 --in10 --win --area --active --swappy"
fi

exit 0
