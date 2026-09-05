-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")
require("hypr.games")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.

-- Keep directional focus/swap commands on the current monitor.
hl.config({
  binds = {
    window_direction_monitor_fallback = false,
  },
})

-- Give monitor names local aliases for workspace rules.
local primary_monitor = "DP-1"
local secondary_monitor = "DP-2"

-- Keep workspaces 1-5 on the primary monitor.
for workspace = 1, 5 do
  hl.workspace_rule({
    workspace = tostring(workspace),
    monitor = primary_monitor,
  })
end

-- Keep workspaces 6-7 on the secondary monitor.
for workspace = 6, 7 do
  hl.workspace_rule({
    workspace = tostring(workspace),
    monitor = secondary_monitor,
  })
end

-- Open Nautilus using Omarchy's standard floating-window treatment.
o.window("org.gnome.Nautilus", { tag = "+floating-window" })

-- Float only the Omarchy Spotify music window, not every Quickshell window.
-- Hyprland accepts one dynamic tag per rule. The panel's title is assigned
-- after its surface is created, so the title rule adds a second tag and the
-- later tag rule applies the size override after Omarchy's 875x600 default.
o.window({ class = "^org\\.quickshell$", title = "^Omarchy Spotify$" }, { tag = "+floating-window" })
o.window({ class = "^org\\.quickshell$", title = "^Omarchy Spotify$" }, { tag = "+spotify-window" })
o.window({ tag = "spotify-window" }, { size = { 1200, 823 } })

-- Open the WhatsApp web app on workspace 6 (the secondary monitor).
o.window("^.+-web\\.whatsapp\\.com__.*$", { workspace = "6" })

-- Added by hyprmoncfg: its generated monitor rules load last, so nothing before this can override the applied layout.
do local path = os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua"; local file = io.open(path, "r"); if file then file:close(); dofile(path) end end
