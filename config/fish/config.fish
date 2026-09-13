if test -f /usr/share/cachyos-fish-config/cachyos-config.fish
    source /usr/share/cachyos-fish-config/cachyos-config.fish
end

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end

# Greeting: see local/bin/rice-fetch.sh. It picks the logo size from the
# CURRENT window width, animates the logo when ~/.config/fastfetch/logo.gif
# exists, and falls back to a still image or text art otherwise.
function fish_greeting
    ~/.local/bin/rice-fetch.sh
end

# `fetch` redraws it at the window's present size. fastfetch prints once and
# cannot reflow, so a window resized after the greeting stays wrong until
# something prints it again - this is that something.
function fetch
    ~/.local/bin/rice-fetch.sh
end
