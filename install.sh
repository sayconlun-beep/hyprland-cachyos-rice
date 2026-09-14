#!/usr/bin/env bash
# New Rice installer.
#
#   ./install.sh                        dry run: missing packages, what would change
#   ./install.sh --apply                link everything into place, make a first palette
#   ./install.sh --uninstall            dry run of the reverse
#   ./install.sh --uninstall --apply    remove the links, put moved-aside files back
#
# Every file in config/ and local/bin/ is SYMLINKED into ~/.config and
# ~/.local/bin one at a time, so this checkout is your live config: edit it
# here, `git pull` for updates. Directories are never linked wholesale -
# ~/.config/gtk-3.0, kitty, btop and friends also hold things of yours.
#
# Nothing is deleted. A file already in the way is moved aside as
# <name>.pre-newrice-<date>, and --uninstall puts the newest one back.
# The few files containing @HOME@ need an absolute path, so those are COPIED
# with it filled in instead of linked.
#
# Paths listed in ~/.config/rice/local-overrides (one per line, relative to ~)
# are left alone - for files you keep your own version of.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mode=install
apply=0
for arg in "$@"; do
    case "$arg" in
        --apply)     apply=1 ;;
        --uninstall) mode=uninstall ;;
        -h|--help)   sed -n '2,20s/^# \{0,1\}//p' "$0"; exit 0 ;;
        *)           echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done
stamp="$(date +%Y%m%d-%H%M%S)"
overrides="$HOME/.config/rice/local-overrides"

say() { printf '  %-13s %s\n' "$1" "${2/#$HOME/\~}"; }

rendered() { sed "s|@HOME@|$HOME|g" -- "$1"; }

move_aside() {
    if [[ -e "$1" || -L "$1" ]]; then
        mv -- "$1" "$1.pre-newrice-$stamp"
        say "moved aside" "$1.pre-newrice-$stamp"
    fi
}

place() {   # place <repo file> <destination>
    local src="$1" dst="$2"
    if [[ -f "$overrides" ]] && grep -qxF -- "${dst#"$HOME/"}" "$overrides"; then
        say "kept yours" "$dst"
        return 0
    fi
    if grep -qF '@HOME@' -- "$src"; then
        if [[ -f "$dst" && ! -L "$dst" && "$(<"$dst")" == "$(rendered "$src")" ]]; then
            return 0
        fi
        if (( apply == 0 )); then
            say "would write" "$dst"
            return 0
        fi
        move_aside "$dst"
        mkdir -p -- "$(dirname -- "$dst")"
        rendered "$src" > "$dst"
        say "wrote" "$dst"
        return 0
    fi
    if [[ -L "$dst" && "$(readlink -- "$dst")" == "$src" ]]; then
        return 0
    fi
    if (( apply == 0 )); then
        say "would link" "$dst"
        return 0
    fi
    move_aside "$dst"
    mkdir -p -- "$(dirname -- "$dst")"
    ln -s -- "$src" "$dst"
    say "linked" "$dst"
}

unplace() {   # unplace <repo file> <destination>
    local src="$1" dst="$2" prev
    if [[ -L "$dst" && "$(readlink -- "$dst")" == "$src" ]]; then
        :
    elif grep -qF '@HOME@' -- "$src" && [[ -f "$dst" && ! -L "$dst" ]] \
            && [[ "$(<"$dst")" == "$(rendered "$src")" ]]; then
        :
    else
        return 0                        # not ours (any more) - leave it
    fi
    prev="$(compgen -G "$dst.pre-newrice-*" | sort | tail -n1 || true)"
    if (( apply == 0 )); then
        say "would remove" "$dst"
        if [[ -n "$prev" ]]; then say "would restore" "$prev"; fi
        return 0
    fi
    rm -f -- "$dst"
    say "removed" "$dst"
    if [[ -n "$prev" ]]; then
        mv -- "$prev" "$dst"
        say "restored" "$dst"
    fi
}

each() {   # each <function>: run it on every file the rice installs
    local f
    while IFS= read -r -d '' f; do
        "$1" "$f" "$HOME/.config/${f#"$root/config/"}"
    done < <(find "$root/config" -type f -print0 | sort -z)
    while IFS= read -r -d '' f; do
        "$1" "$f" "$HOME/.local/bin/${f##*/}"
    done < <(find "$root/local/bin" -maxdepth 1 -type f -print0 | sort -z)
}

# ------------------------------------------------------------- uninstall --
if [[ "$mode" == uninstall ]]; then
    echo "Files:"
    each unplace
    echo
    if (( apply == 0 )); then
        echo "Dry run. Re-run with --uninstall --apply."
    else
        echo "Done. Generated colour files (hypr/colors.lua, waybar/colors.css, ...) and"
        echo "~/.cache/rice were left in place. Log out of Hyprland before logging back in"
        echo "with your old config."
    fi
    exit 0
fi

# -------------------------------------------------------------- packages --
echo "Packages:"
if command -v pacman >/dev/null; then
    pkgs=(hyprland hypridle hyprlock hyprpolkitagent xdg-desktop-portal-hyprland
          waybar rofi awww matugen quickshell
          kitty grim slurp satty wl-clipboard cliphist brightnessctl playerctl wireplumber
          pavucontrol nm-connection-editor hyprsunset gpu-screen-recorder
          jq curl socat imagemagick libnotify python python-gobject gtk-layer-shell
          cava fastfetch btop dolphin upower power-profiles-daemon github-cli
          adw-gtk-theme qt6ct papirus-icon-theme)
    mapfile -t missing < <(pacman -T "${pkgs[@]}" || true)
    command -v fc-list >/dev/null || missing+=(fontconfig)
    if ! fc-list 2>/dev/null | grep -q "JetBrainsMono Nerd Font"; then missing+=(ttf-jetbrains-mono-nerd); fi
    if ! fc-list 2>/dev/null | grep -q "Inter Variable"; then missing+=(inter-font); fi
    if (( ${#missing[@]} )); then
        echo "  missing:  sudo pacman -S --needed ${missing[*]}"
    else
        echo "  all there"
    fi
    if [[ ! -d /usr/share/icons/Bibata-Modern-Ice && ! -d "$HOME/.local/share/icons/Bibata-Modern-Ice" ]]; then
        echo "  missing:  bibata-cursor-theme-bin from the AUR (or change XCURSOR_THEME in hypr/conf/env.lua)"
    fi
else
    echo "  no pacman here - check PACKAGES.md for what to install"
fi
for d in mako dunst swaync; do
    if pgrep -x "$d" >/dev/null; then
        echo "  !! $d is running. Quickshell is the notification daemon in this rice -"
        echo "     stop $d and take it out of your autostart."
    fi
done
echo

# ------------------------------------------------------------------ files --
echo "Files:"
each place
echo
if (( apply == 0 )); then
    echo "Dry run. Re-run with --apply."
    exit 0
fi

mkdir -p "$HOME/.cache/rice" "$HOME/.config/qt6ct/colors" "$HOME/.config/btop/themes" \
         "$HOME/.local/share/color-schemes" "$HOME/Pictures/Wallpapers"

# A palette straight away, so nothing starts without its colours file: from a
# wallpaper if there is one, else from a colour (cyan) until you pick one.
walls="$HOME/Pictures/Wallpapers"
first_wall="$(find -L "$walls" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' \
    -o -iname '*.png' -o -iname '*.webp' \) -print -quit 2>/dev/null || true)"
echo "Palette:"
if [[ -n "$first_wall" ]]; then
    if "$HOME/.local/bin/rice-wallpaper" theme; then
        echo "  from ${first_wall/#$HOME/\~}"
    else
        echo "  !! matugen could not make a palette - run rice-wallpaper theme once it works"
    fi
elif matugen color hex "#7dcfff" -m dark -t scheme-tonal-spot -q; then
    echo "  from #7dcfff - add wallpapers to ~/Pictures/Wallpapers and pick one with Super+Shift+W"
else
    echo "  !! matugen could not make a palette - is it installed?"
fi

# btop keeps its theme choice in the same file as all its other settings, so
# that one line is edited rather than the file being linked.
if [[ -f "$HOME/.config/btop/btop.conf" ]]; then
    sed -i 's/^color_theme = .*/color_theme = "matugen"/' "$HOME/.config/btop/btop.conf"
fi

if command -v gsettings >/dev/null; then
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    if [[ -d /usr/share/themes/adw-gtk3-dark ]]; then
        gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark
    fi
    if [[ -d /usr/share/icons/Papirus-Dark ]]; then
        gsettings set org.gnome.desktop.interface icon-theme Papirus-Dark
    fi
    if [[ -d /usr/share/icons/Bibata-Modern-Ice || -d "$HOME/.local/share/icons/Bibata-Modern-Ice" ]]; then
        gsettings set org.gnome.desktop.interface cursor-theme Bibata-Modern-Ice
    fi
fi

echo
if command -v Hyprland >/dev/null; then
    if out="$(Hyprland --verify-config --config "$HOME/.config/hypr/hyprland.lua" 2>&1)"; then
        echo "Hyprland config: OK"
    else
        printf '%s\n' "$out" | tail -n 20
        echo "!! Hyprland reported problems with the config (above)"
    fi
fi

cat <<'EOF'

Done. Log in to Hyprland (or `hyprctl reload` if you are in it), then:
  - Super+/            every keybind, and rebinding
  - Super+Shift+W      wallpapers (add images to ~/Pictures/Wallpapers first)
  - Super+Shift+D      monitors: mode, scale, position, VRR
  - keyboard layout    ~/.config/hypr/conf/input.lua
  - your apps          term / files / browser at the top of hypr/conf/binds.lua
EOF
