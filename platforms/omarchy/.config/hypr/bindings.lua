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
o.bind("SUPER + D", "Downloads", { launch = 'nautilus "$HOME/Downloads"' })

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Replace Omarchy's default ChatGPT web app binding with the native app.
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "ChatGPT (native)", { launch = "chatgpt" })

-- Replace Omacalc with the persistent Python calculator. Omarchy 4.5 moved
-- Omacalc to Super+Shift+Q; Super+Ctrl+Q stays as the familiar key.
o.rebind("SUPER + SHIFT + Q", "Calculator (Python)", "python-calculator")
o.rebind("XF86Calculator", "Calculator (Python)", "python-calculator")
o.bind("SUPER + CTRL + Q", "Calculator (Python)", "python-calculator")

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
-- Launch Bitwarden instead of Omarchy's default 1Password binding.
hl.unbind("SUPER + SHIFT + SLASH")
o.bind("SUPER + SHIFT + SLASH", "Passwords", { launch = "bitwarden-desktop" })

-- Show Focusd only while a focus session is active.
o.bind("SUPER + ALT + P", "Start Focusd", "focusctl start")
o.bind("SUPER + ALT + SHIFT + P", "Stop Focusd", "focusctl stop")

-- Open the Omarchy Spotify plugin instead of the default Music binding.
hl.unbind("SUPER + SHIFT + M")
o.bind("SUPER + SHIFT + M", "Spotify", { launch = "spotify" })

hl.unbind("SUPER + SHIFT + S")
o.bind("SUPER + SHIFT + S", "Screenshot", "omarchy-capture-screenshot")

hl.unbind("SUPER + SHIFT + C")
o.bind("SUPER + SHIFT + C", "Screenshot", "omarchy-menu toggle capture")

-- Dictation keys from before Alt + Space and Right Alt became the defaults.
-- Remove these lines to give the keys back to applications.
if o.dictation_installed and o.dictation_installed() then
  o.bind("SUPER + CTRL + X", "Toggle dictation", "omarchy-dictation toggle")
  o.bind_hold("F9", "Start dictation (push-to-talk)", "omarchy-dictation start", "Stop dictation (push-to-talk)", "omarchy-dictation stop")
end

-- Switch layouts between tiling and scrolling only; Omarchy's cycle also
-- includes floating. Super+Alt+L keeps Omarchy's full cycle.
o.rebind("SUPER + L", "Toggle tiling/scrolling", "workspace-layout-toggle")
