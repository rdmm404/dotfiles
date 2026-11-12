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

-- Open Nautilus using Omarchy's standard floating-window treatment.
o.window("org.gnome.Nautilus", { tag = "+floating-window" })

-- Stop FreeCAD dialogs from reclaiming focus and warping the pointer back.
-- Retain Omarchy's maximize suppression; leave activation enabled for other apps.
o.window("^FreeCAD$", { suppress_event = "maximize activate activatefocus" })

-- Match Package > Install's centered floating-terminal treatment.
o.window("^local\\.python\\.Calculator$", { tag = "+floating-window" })
-- The local app ID isn't covered by Omarchy's stock terminal-ID matcher.
o.window("^local\\.python\\.Calculator$", { tag = "+terminal" })

-- The Herdr app is a terminal too: the tag makes Super+C/V send Ctrl+Shift+C/V
-- (terminal.copy/paste) instead of Ctrl+C/V, which Herdr reads as an interrupt
-- and an image paste.
o.window("^herdr-app$", { tag = "+terminal" })

-- Float only the Omarchy Spotify music window, not every Quickshell window.
-- Hyprland accepts one dynamic tag per rule. The panel's title is assigned
-- after its surface is created, so the title rule adds a second tag and the
-- later tag rule applies the size override after Omarchy's 875x600 default.
o.window({ class = "^org\\.quickshell$", title = "^Omarchy Spotify$" }, { tag = "+floating-window" })
o.window({ class = "^org\\.quickshell$", title = "^Omarchy Spotify$" }, { tag = "+spotify-window" })
o.window({ tag = "spotify-window" }, { size = { 1200, 823 } })

-- Open the WhatsApp web app on the secondary monitor's first workspace. From
-- Omarchy 4.5 each monitor owns a block of ten (DP-1 1-10, DP-2 11-20).
o.window("^.+-web\\.whatsapp\\.com__.*$", { workspace = "11" })


-- Don't let Chromium windows take focus when they open or request activation.
o.window("^chromium$", { no_initial_focus = true, focus_on_activate = false })

-- Added by hyprmoncfg: its generated monitor rules load last, so nothing before this can override the applied layout.
do local path = os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua"; local file = io.open(path, "r"); if file then file:close(); dofile(path) end end
