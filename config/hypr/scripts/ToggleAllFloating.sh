#!/usr/bin/env bash
# ==============================================================================
# yusei-hypr: Toggle All Floating Windows on Active Workspace
# Dual-Compatible: Hyprland 0.57+ Lua API (hl.dsp) & Legacy dispatch fallback
# ==============================================================================

set -euo pipefail

workspace=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty')
[[ -z "$workspace" ]] && exit 0

clients=$(hyprctl clients -j 2>/dev/null || echo "[]")
mapfile -t addresses < <(jq -r --argjson ws "$workspace" '.[] | select(.workspace.id == $ws and .workspace.type == "normal" and .mapped == true) | .address' <<<"$clients")
((${#addresses[@]})) || exit 0

all_floating=$(jq -r --argjson ws "$workspace" '[.[] | select(.workspace.id == $ws and .workspace.type == "normal" and .mapped == true)] | all(.[]; .floating == true)' <<<"$clients")
if [[ "$all_floating" == "true" ]]; then
    action="off"
else
    action="on"
fi

for address in "${addresses[@]}"; do
    if ! hyprctl dispatch "hl.dsp.window.float({ window = 'address:$address', action = '$action' })" >/dev/null 2>&1; then
        hyprctl dispatch togglefloating "address:$address" >/dev/null 2>&1 || true
    fi
done
