# Packages

Arch names. Everything is in the official repos except the Bibata cursors
(AUR). `./install.sh` without `--apply` lists what you are missing.

## Everything at once

```bash
sudo pacman -S --needed \
  hyprland hypridle hyprlock hyprpolkitagent xdg-desktop-portal-hyprland \
  waybar rofi awww matugen quickshell \
  kitty grim slurp satty wl-clipboard cliphist brightnessctl playerctl wireplumber \
  pavucontrol nm-connection-editor hyprsunset gpu-screen-recorder \
  jq curl socat imagemagick libnotify python python-gobject gtk-layer-shell \
  cava fastfetch btop dolphin upower power-profiles-daemon github-cli \
  adw-gtk-theme qt6ct nwg-look papirus-icon-theme ttf-jetbrains-mono-nerd inter-font
```

Plus `bibata-cursor-theme-bin` from the AUR, or change `XCURSOR_THEME` in
`config/hypr/conf/env.conf` to a cursor theme you have.

## What needs what

| package | used by |
|---------|---------|
| `hyprland` 0.53+ | the compositor - the configs use the named `windowrule { }` blocks |
| `quickshell` 0.3 | dashboard, control centre, notifications, OSD, lock screen, carousel, keybind menu, clock, visualiser, lyrics |
| `waybar` 0.15, `rofi` 2.0 | bar; launcher, clipboard, session and Wi-Fi menus |
| `awww` (formerly swww) | wallpaper |
| `matugen` 4.x | the palette from the wallpaper |
| `hypridle`, `hyprlock` | idle; lock-screen fallback and its PAM config |
| `hyprpolkitagent` | password prompts |
| `grim`, `slurp`, `satty`, `gpu-screen-recorder` | screenshots, annotation, recording, replay buffer |
| `wl-clipboard`, `cliphist` | clipboard history |
| `wireplumber`, `playerctl`, `brightnessctl` | media keys and the OSD |
| `hyprsunset` | Night Light |
| `upower`, `power-profiles-daemon` | Energy card and power profiles |
| `imagemagick` | carousel thumbnails |
| `jq`, `curl` | wallhaven search, settings menus, weather |
| `socat`, `python-gobject`, `gtk-layer-shell` | read-aloud and its subtitle tile |
| `cava` | desktop visualiser |
| `github-cli` | the dashboard's GitHub tab (`gh auth login` once) |
| `dolphin` | "show in folder" from screenshots and the GitHub tab |
| `adw-gtk-theme`, `qt6ct`, `nwg-look` | GTK and Qt apps following the palette |

Services the control centre expects: NetworkManager, bluetooth (`bluez`) and
power-profiles-daemon, all enabled.

## Optional

- `firefox` - `Super+B`. Change `$browser` in `binds.conf` for another browser.
- `steam` - `Super+Enter`, and games are sent to workspace 1.
- `fish` - the terminal greeting (`rice-fetch.sh`).
- `gamemode` - Do Not Disturb while a game runs. Add yourself to the
  `gamemode` group.
- `mpv`, `foot`.
- **piper TTS** for read-aloud (`Super+P`): download a release into
  `~/.local/share/piper-tts/piper/` and a voice into
  `~/.local/share/piper-tts/voices/` (default `en_GB-jenny_dioco-medium`, or
  set `PIPER_VOICE`). `/usr/bin/piper` on Arch is the Logitech mouse tool, not
  this.
- The settings hub's **CachyOS** section only works on CachyOS. Elsewhere,
  delete those entries from `config/quickshell/rice/SettingsMenu.qml`.

Qt note: `QT_QPA_PLATFORMTHEME=kde` looks like it should work but needs
plasma-integration, and without it Qt silently falls back to an unthemed
default. This rice uses qt6ct.
