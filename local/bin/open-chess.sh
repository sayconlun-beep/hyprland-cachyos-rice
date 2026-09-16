#!/usr/bin/env bash
# Super+C: chess.com as a floating Chromium web app, centred on workspace 1.
#
# Launch or focus: if the window is already open - on any workspace - it is
# brought back to workspace 1 and re-centred rather than opened a second time.
# As with the media web apps, Chromium hands an --app launch to its running
# process, so the window is found by class, not pid (rule: chess-webapp in
# conf/rules.lua floats it as it maps, so it never flashes up as a tile).
set -uo pipefail

WS=1
CLASS='chrome-www.chess.com__-Default'
W=1600 H=1300          # board plus chess.com's side panel; shrunk to fit smaller monitors

# A Lua dispatcher, e.g. dsp 'hl.dsp.focus({ workspace = 1 })'.
dsp() { hyprctl dispatch "$1" >/dev/null; }

window() {   # -> "address workspace floating" of the chess.com window, or nothing
    hyprctl clients -j | python3 -c '
import json, sys
c = next((c for c in json.load(sys.stdin) if c["class"] == sys.argv[1]), None)
if c:
    print(c["address"], c["workspace"]["id"], c["floating"])' "$CLASS"
}

dsp "hl.dsp.focus({ workspace = $WS })"

addr="" ws="" fl=""
read -r addr ws fl <<< "$(window)"
if [[ -z "$addr" ]]; then
    setsid -f chromium --app=https://www.chess.com --no-first-run --no-default-browser-check >/dev/null 2>&1
    for _ in $(seq 1 80); do
        read -r addr ws fl <<< "$(window)"
        [[ -n "$addr" ]] && break
        sleep 0.25
    done
    if [[ -z "$addr" ]]; then
        notify-send -a Chess "chess.com did not open" "No chess.com window appeared within 20 seconds."
        exit 1
    fi
fi

[[ "$ws" != "$WS" ]] && dsp "hl.dsp.window.move({ workspace = $WS, follow = false, window = \"address:$addr\" })"
[[ "$fl" == True ]] || dsp "hl.dsp.window.float({ action = \"enable\", window = \"address:$addr\" })"

# Centre in the usable area (minus the bar) of the monitor holding workspace 1,
# in global logical px - what window.move's x/y and hyprctl's `at` both use.
read -r x y w h <<< "$(hyprctl monitors -j | python3 -c '
import json, sys
ws, W, H = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
ms = json.load(sys.stdin)
m = next((m for m in ms if m["activeWorkspace"]["id"] == ws), None) \
    or next(m for m in ms if m["focused"])
rl, rt, rr, rb = m["reserved"]
mw, mh = m["width"] / m["scale"], m["height"] / m["scale"]
uw, uh = mw - rl - rr, mh - rt - rb
w, h = min(W, int(uw) - 40), min(H, int(uh) - 40)
print(int(m["x"] + rl + (uw - w) / 2), int(m["y"] + rt + (uh - h) / 2), w, h)' "$WS" "$W" "$H")"

dsp "hl.dsp.window.resize({ x = $w, y = $h, window = \"address:$addr\" })"
dsp "hl.dsp.window.move({ x = $x, y = $y, window = \"address:$addr\" })"
dsp "hl.dsp.focus({ window = \"address:$addr\" })"
exit 0
