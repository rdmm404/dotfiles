-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Replace Omarchy's default ChatGPT web app binding with the native app.
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "ChatGPT (native)", { launch = "chatgpt" })

-- Launch Herdr with compact Ghostty padding while preserving the current directory.
hl.unbind("SUPER + CTRL + RETURN")
o.bind(
  "SUPER + CTRL + RETURN",
  "Herdr (compact)",
  'uwsm-app -- ghostty --gtk-single-instance=false --working-directory="$(omarchy-cmd-terminal-cwd)" --window-padding-x=2 --window-padding-y=1 -e herdr'
)

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")
-- BEGIN Waypaper Video background selector
-- Replaces the stock Omarchy Background switcher binding with the direct selector.
hl.unbind("SUPER + CTRL + SPACE")
o.bind("SUPER + CTRL + SPACE", "Waypaper Video backgrounds", "$HOME/.config/omarchy/plugins/io.github.gavidetdoliath.waypaper-video-background/background-selector.sh")
-- END Waypaper Video background selector

-- Launch Bitwarden instead of Omarchy's default 1Password binding.
hl.unbind("SUPER + SHIFT + SLASH")
o.bind("SUPER + SHIFT + SLASH", "Passwords", { launch = "bitwarden-desktop" })

-- Show Focusd only while a focus session is active.
o.bind("SUPER + ALT + P", "Start Focusd", "zsh -c 'source \"$HOME/.config/zsh/functions/omarchy.zsh\"; focusd_start'")
o.bind("SUPER + ALT + SHIFT + P", "Stop Focusd", "zsh -c 'source \"$HOME/.config/zsh/functions/omarchy.zsh\"; focusd_stop'")
