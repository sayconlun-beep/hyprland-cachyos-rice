-- The shell layer, one tool per job:
--   rice-wallpaper restore   starts awww-daemon, shows the last wallpaper and
--                            derives the palette from it (matugen)
--   waybar                   bar
--   qs -c rice               Quickshell: notifications, OSD, control centre, clock,
--                            visualiser, overlays
--   hyprpolkitagent          polkit password dialogs
--   hypridle -> hyprlock     idle and lock
--
-- hyprland.start fires once per session, never on `hyprctl reload`.
-- RICE_NO_AUTOSTART=1 skips it all - for trying the config in a nested Hyprland
-- without a second bar and shell.
if os.getenv("RICE_NO_AUTOSTART") then
    return
end

hl.on("hyprland.start", function()
    hl.exec_cmd("~/.local/bin/rice-wallpaper restore")
    hl.exec_cmd("waybar")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("wl-paste --type text  --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("qs -c rice -n -d")
end)
