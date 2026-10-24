#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Media Control & Playback Subsystem (MediaCtrl.sh)
# Architecture: MPRIS D-Bus Controller via playerctl | SwayNC Visual OSD
# ==============================================================================

set -euo pipefail

music_icon="$HOME/.config/swaync/icons/music.png"
if [[ ! -f "$music_icon" ]]; then
  music_icon="audio-x-generic"
fi

if ! command -v playerctl >/dev/null 2>&1; then
  notify-send -u low "Media Control" "playerctl is not installed."
  exit 1
fi


# Play the next track
play_next() {
  playerctl next
  show_music_notification
}

# Play the previous track
play_previous() {
  playerctl previous
  show_music_notification
}

# Toggle play/pause
toggle_play_pause() {
  playerctl play-pause
  sleep 0.1
  show_music_notification
}

# Stop playback
stop_playback() {
  playerctl stop
  notify-send -e -u low -i $music_icon " Playback:" " Stopped"
}

# Display notification with song information
show_music_notification() {
  status=$(playerctl status 2>/dev/null || echo "NoPlayer")
  if [[ "$status" == "Playing" ]]; then
    song_title=$(playerctl metadata title 2>/dev/null || echo "Unknown Title")
    song_artist=$(playerctl metadata artist 2>/dev/null || echo "Unknown Artist")
    notify-send -e -u low -i "$music_icon" "Now Playing:" "$song_title by $song_artist"
  elif [[ "$status" == "Paused" ]]; then
    notify-send -e -u low -i "$music_icon" "Playback:" "Paused"
  fi
}


# Get media control action from command line argument
case "$1" in
"--nxt")
  play_next
  ;;
"--prv")
  play_previous
  ;;
"--pause")
  toggle_play_pause
  ;;
"--stop")
  stop_playback
  ;;
*)
  echo "Usage: $0 [--nxt|--prv|--pause|--stop]"
  exit 1
  ;;
esac
