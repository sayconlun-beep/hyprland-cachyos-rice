#!/bin/sh
# Rebuild the .qsb files Quickshell loads. Run after editing a .frag, then
# restart the shell (kill $(pgrep -x qs); qs -c rice -n -d).
cd "$(dirname "$(readlink -f "$0")")" || exit 1
for f in *.frag; do
    /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o "$f.qsb" "$f" || exit 1
done
