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

-- Switch monitors without walking through windows the way Super+Arrow does.
-- Add Shift to take the focused window along.
o.bind("SUPER + Page_Up", "Focus previous monitor", hl.dsp.focus({ monitor = "-1" }))
o.bind("SUPER + Page_Down", "Focus next monitor", hl.dsp.focus({ monitor = "+1" }))
o.bind("SUPER + SHIFT + Page_Up", "Move window to previous monitor", hl.dsp.window.move({ monitor = "-1" }))
o.bind("SUPER + SHIFT + Page_Down", "Move window to next monitor", hl.dsp.window.move({ monitor = "+1" }))

-- Super+F<N> focuses monitor N, numbered in the order Omarchy gives monitors
-- their workspaces (monitor 1 owns 1-10, monitor 2 owns 11-20).
-- Super+Shift+F<N> moves the focused window there.
local function monitor_number(number)
  for _, monitor in ipairs(hl.get_monitors()) do
    local block = (o.workspaces.workspace_id(monitor, 1) - 1) // o.workspaces.slots
    if block == number - 1 then
      return monitor
    end
  end
end

local function focus_monitor(number)
  return function()
    local monitor = monitor_number(number)
    if monitor then
      hl.dispatch(hl.dsp.focus({ monitor = monitor.name }))
    end
  end
end

local function move_window_to_monitor(number)
  return function()
    local monitor = monitor_number(number)
    if monitor and hl.get_active_window() then
      hl.dispatch(hl.dsp.window.move({ monitor = monitor.name }))
    end
  end
end

for number = 1, 4 do
  o.bind("SUPER + F" .. number, "Focus monitor " .. number, focus_monitor(number))
  o.bind("SUPER + SHIFT + F" .. number, "Move window to monitor " .. number, move_window_to_monitor(number))
end
