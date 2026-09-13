#!/usr/bin/env bash
# Toggle a distraction-free writing mode: no bar, wide gaps, no borders.
#
# Entering saves the LIVE gaps/border/rounding and leaving puts exactly those
# back, so whatever rice-settings set survives the round trip. Hardcoding the
# "off" values silently undid it.
STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr-focus.on"
OPTS="general:gaps_out general:gaps_in general:border_size decoration:rounding"

# An option's value in the form `keyword` accepts: gaps come back as
# "8 8 8 8" and are passed on as 8,8,8,8.
get() {
    hyprctl getoption "$1" -j | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(str(d["custom"]).strip().replace(" ", ",") if "custom" in d else d["int"])'
}

if [[ -f "$STATE" ]]; then
    if [[ -s "$STATE" ]]; then
        batch=""
        while read -r opt val; do batch+="keyword $opt $val ; "; done < "$STATE"
        hyprctl --batch "$batch" >/dev/null
    else
        hyprctl reload >/dev/null     # no saved values: fall back to the config
    fi
    pkill -USR1 -x waybar             # SIGUSR1 toggles waybar's visibility
    rm -f "$STATE"; notify-send -t 1500 "Focus mode off" 2>/dev/null
else
    for o in $OPTS; do printf '%s %s\n' "$o" "$(get "$o")"; done > "$STATE"
    pkill -USR1 -x waybar
    hyprctl --batch "keyword general:gaps_out 140 ; keyword general:gaps_in 0 ; keyword general:border_size 0 ; keyword decoration:rounding 0" >/dev/null
    notify-send -t 1500 "Focus mode" "Bar hidden, wide margins" 2>/dev/null
fi
