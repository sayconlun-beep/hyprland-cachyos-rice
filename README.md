# New Rice

A Hyprland desktop themed end to end from the wallpaper. Pick an image and
[matugen](https://github.com/InioX/matugen) derives a Material You palette
that the bar, the shell, terminals, GTK and Qt apps, window borders, the lock
screen and the visualiser all follow - live, no restart.

It is built from small single-purpose pieces: Waybar for the bar, rofi for
quick menus, and a [Quickshell](https://quickshell.org) layer for everything
else.

## What's in it

- **Wallpaper carousel** (`Super+Shift+W`). Thumbnails with a full-screen
  preview that cross-fades as you browse; the bar and window borders recolour
  with it. Enter applies, Esc puts the old one back.
- **Dashboard** (`Super+D`, or click the clock). Overview, media with album
  art, 7-day weather, notifications, system gauges, tasks with a focus timer,
  and a GitHub tab for repos, PRs and issues.
- **Control centre** (click the network or volume pill). Wi-Fi, Bluetooth,
  sound devices, dark/light mode, Do Not Disturb, Night Light, power profiles.
- **Notifications and OSD.** Quickshell is the notification daemon: popups,
  a history centre (`Super+N`), and an on-screen display for volume, media
  and keyboard layout.
- **Lock screen.** Built on ext-session-lock with PAM, and falls back to
  hyprlock if Quickshell is not running.
- **Capture menu** (`Super+Shift+S`). Screenshot the screen, a window or an
  area; record with gpu-screen-recorder.
- **Keybind menu** (`Super+/`). A searchable cheatsheet that can also rebind.
- **Settings hub** (`Super+,`). Look (gaps, borders, rounding, blur) and
  displays (mode, scale, position, VRR) apply live, plus shortcuts to every
  system settings panel.
- **On the desktop:** a clock, a cava visualiser and synced lyrics, each
  switchable from the settings hub.
- **Wallhaven** search and download (`Super+Ctrl+W`).
- **TTS Reader:** an audiobook-style reader for EPUB, PDF, DOCX and Markdown
  with per-paragraph voices, which can save a book as an `.m4b` for your phone.
- **Extras:** read-aloud with a subtitle tile, focus mode, Do Not Disturb
  while gaming, and a replay buffer on `F8`.

| job | tool | lives in |
|-----|------|----------|
| compositor | Hyprland | `config/hypr` |
| bar | Waybar | `config/waybar` |
| launcher, clipboard, session, Wi-Fi menus | rofi + `rice-*` scripts | `config/rofi`, `local/bin` |
| everything else above | Quickshell (`qs -c rice`) | `config/quickshell/rice` |
| wallpaper | awww, driven by `rice-wallpaper` | `local/bin` |
| palette | matugen | `config/matugen` |
| idle, lock fallback | hypridle, hyprlock | `config/hypr` |

## Requirements

- An Arch-based distro for the package names (it was built on CachyOS). Other
  distros work if you find the equivalents.
- Hyprland 0.55 or newer (the config is Lua), Quickshell 0.3, Waybar 0.15, matugen 4, rofi 2.
- Fonts: JetBrainsMono Nerd Font and Inter.

The full list is in [PACKAGES.md](PACKAGES.md).

## Install

```bash
git clone https://github.com/sayconlun-beep/hyprland-cachyos-rice ~/hyprland-cachyos-rice
cd ~/hyprland-cachyos-rice
./install.sh            # dry run: lists missing packages and every file it would touch
./install.sh --apply
```

Every file is **symlinked** into `~/.config` and `~/.local/bin`, one file at a
time, so the clone is your live config. Edit it in place, and `git pull` for
updates. Anything already in the way is moved aside as
`<name>.pre-newrice-<date>`; nothing is deleted.

`--apply` also makes a first palette (from `#7dcfff` until you have a
wallpaper), points btop at the generated theme, sets the GTK, icon and cursor
themes, and runs `Hyprland --verify-config`.

To undo it: `./install.sh --uninstall` (dry run), then
`./install.sh --uninstall --apply`, which removes the links and restores
whatever was moved aside.

**Upgrading from the hyprlang version** (before September 2026, when the
Hyprland config was `hyprland.conf`): `git pull`, then `./install.sh --apply`
links the new `.lua` files. Hyprland reads `hyprland.lua` in preference to the
old file, so the leftover `.conf` links do nothing - delete them at leisure.
Changes made in the settings or keybind menus lived in `conf.d/*.conf`, which
is no longer read: make them again, and they are saved as `conf.d/*.lua`.

> **Using mako, dunst or swaync?** Stop it and remove it from your autostart.
> Quickshell needs the notification name for itself. swaync can also be
> started by D-Bus on its own, so `systemctl --user mask swaync.service` too.

## After installing

1. **Wallpapers.** None are included. Put images in `~/Pictures/Wallpapers`,
   or search wallhaven with `Super+Ctrl+W`, then choose one with
   `Super+Shift+W`.
2. **Monitors.** Every output starts at its preferred mode. Use
   `Super+Shift+D`, or add `hl.monitor({ ... })` lines in `config/hypr/hyprland.lua`;
   there are examples there.
3. **Keyboard layout.** `kb_layout` in `config/hypr/conf/input.lua` (set to `us`).
4. **Your apps.** `term`, `files` and `browser` at the top of
   `config/hypr/conf/binds.lua`. `Super+Enter` opens Steam.
5. **Weather location.** It is looked up from your IP. To set it yourself,
   write `~/.config/rice/location.json`:
   `{"name": "Somewhere", "lat": 51.5, "lon": -0.12}`.
6. **Lock-screen avatar.** `~/.face`.

## Keys

| key | does |
|-----|------|
| `Super+Space` | app launcher |
| `Super+T` / `Super+E` / `Super+B` | terminal / files / browser |
| `Super+Enter` | Steam |
| `Super+Q` / `Super+Shift+Q` | close window / exit Hyprland |
| `Super+G` / `Super+S` / `Super+A` | float / fullscreen / flip the split |
| `Super+H J K L` or arrows | move focus (`+Ctrl` swap, `+Shift` resize) |
| `Super+1..0` / `Super+Shift+1..0` | go to / move to workspace |
| `Super+M` / `Super+Tab` | previous workspace / next window |
| `Super+D` | dashboard |
| `Super+N` | notification centre |
| `Super+,` | settings hub |
| `Super+/` | keybind cheatsheet and rebinding |
| `Super+Shift+W` / `Super+Alt+W` / `Super+Ctrl+W` | wallpaper carousel / next wallpaper / search wallhaven |
| `Super+Shift+S` | screenshot and record menu |
| `Print` / `Shift+Print` | area / whole screen to the clipboard |
| `Super+Print` / `Ctrl+Print` | area to `~/Pictures` / area into satty |
| `F8` | save the replay buffer (needs `gsr-replay-start` running) |
| `Super+V` | clipboard history |
| `Super+C` / `Super+Shift+C` | chess.com (floating, workspace 1) / GNOME Chess against the bot |
| `Super+X` | session menu |
| `Super+Esc` | lock |
| `Super+Shift+A` / `Super+Shift+D` | look / display settings |
| `Super+Shift+B` / `Super+Shift+V` | hide the bar / toggle the visualiser |
| `Super+F` | focus mode |
| `Super+P`, `Super+[` `]`, `Super+Shift+R`, `Super+Shift+P` | read aloud: play/pause, back/forward, read selection, stop |
| `Ctrl+Alt+Del` | btop |

Changes made in the keybind menu are saved to
`~/.config/hypr/conf.d/30-binds.lua`; `binds.lua` itself is never
rewritten. Delete that file to reset every bind.

## How the theming works

```
rice-wallpaper set <image>
  ├─ awww img            shows it
  ├─ matugen image       -t scheme-tonal-spot --prefer saturation
  │    └─ templates      Hyprland, Waybar, rofi, Quickshell, kitty, foot,
  │                      GTK 3/4, qt6ct, KDE colours, btop, cava, fastfetch
  └─ rice-theme-reload   tells each running app to re-read its colours
```

- `rice-wallpaper` also does `next`, `prev`, `random`, `pick` (rofi grid),
  `mode dark|light|toggle` and `theme` (palette only).
- **`--prefer saturation` matters.** Without it, matugen stops to ask which
  colour to use when an image has several, and with no terminal it fails.
- No template has a `post_hook`: `rice-theme-reload` runs once afterwards
  instead of fifteen reloads. Run it yourself if you call matugen by hand.
- Hyprland's colours are pushed live with `hyprctl eval` from
  `~/.cache/rice/hypr-colors.lua`. A reload would also reset state such as
  focus mode.
- The cache is literally `~/.cache/rice`, not `$XDG_CACHE_HOME`, because
  matugen's config writes there by `~`.

## Where things live

```
config/hypr/hyprland.lua      monitors and look (the settings engines read these)
config/hypr/conf/             env, input, workspaces, window rules, binds, autostart
config/hypr/conf.d/           generated overrides from the settings and keybind menus
config/quickshell/rice/       the shell: shell.qml wires every component together
config/waybar/                bar config, style and its scripts
config/matugen/               palette templates
local/bin/                    rice-* scripts and the settings engines
```

The Quickshell layer is driven over IPC, which is handy for your own binds
and scripts:

```bash
qs -c rice ipc call <target> <function>
#   wallpaper      toggle | open | close | apply | next | prev
#   dashboard      toggle | tab <overview|media|weather|alerts|system|productivity|github>
#   controlcenter  toggle | page <wifi|bluetooth|ethernet|sound>
#   notifications  toggle | clear | dnd | setDnd <true|false> | toggleDnd
#   capture        menu | screenshot <screen|window|area> | record <screen|area> | stop
#   settings, binds                       toggle | open | close
#   clock, visualiser, lyrics             toggle | show | hide
#   lyrics         offset <seconds> | reload | status
#   lock           lock | preview | status
```

## Optional extras

- **Read-aloud** (`Super+P`) and **TTS Reader** need piper TTS; see [PACKAGES.md](PACKAGES.md).
- **Replay buffer:** run `gsr-replay-start` from your autostart; `F8` saves
  the last 3 minutes to `~/Videos/Replays`. `GSR_MONITOR` and `GSR_MIC`
  choose what it records.
- **GameMode:** `config/gamemode.ini` turns on Do Not Disturb while a game
  runs. You need to be in the `gamemode` group.
- **Wallhaven:** `Super+Ctrl+W` opens a panel with search, filters and sorting;
  they are saved to `~/.config/rice/wallhaven.json`. Add `"apikey": "..."`
  there to unlock NSFW.
- **Terminal greeting** (fish): `rice-fetch.sh` sizes the logo to the window.
  Put a `logo.gif` or `logo.png` (kitty), or `logo-large.txt` and
  `logo-small.txt` (text art), in `~/.config/fastfetch`. Otherwise it shows
  your distro's logo.
- **GitHub tab:** `gh auth login` once. The local repo list works without it.

## Troubleshooting

- **Window borders stay cyan and purple whatever the wallpaper:** there is no
  `~/.config/hypr/colors.lua` yet, so Hyprland uses its built-in fallback. Run
  `rice-wallpaper theme`, or `./install.sh --apply` again.
- **Shell not showing up:** `qs -c rice log` shows the errors. Restart it with
  `pkill -x qs; qs -c rice -n -d`. Quickshell does not always pick up QML
  edits by itself.
- **Locked out after a lock-screen crash:** from a TTY,
  `hyprctl --instance 0 dispatch 'hl.dsp.exec_cmd("hyprlock")'`.
- **`hyprctl keyword` is refused, or `hyprctl dispatch workspace 2` is a syntax
  error:** this rice uses Hyprland's Lua config (0.55 or newer). Use
  `hyprctl eval '<lua>'` and `hyprctl dispatch 'hl.dsp.focus({ workspace = 2 })'`.
- **No notifications:** another daemon has the D-Bus name (see Install).
- **Visualiser flat:** cava follows the *default* output. Check it with
  `wpctl status`.
- **Bar GPU pill empty:** it reads AMD's sysfs files. NVIDIA cards show up in
  the dashboard's System tab instead.

## Credits

- [Nisfere](https://github.com/Nisfeight8/Nisfere) by Nisfeight8. The
  dashboard, control centre, notifications, OSD, lock screen, capture tools
  and desktop lyrics were modelled on its designs.
- [Lucide](https://lucide.dev) icons (ISC), see
  `config/quickshell/rice/icons/CREDITS.md`.
- The fragment shaders in `config/cava/shaders` are cava's own (MIT).
- The animation curves are flafy's.

## License

MIT, see [LICENSE](LICENSE). The icons keep their ISC licence.
