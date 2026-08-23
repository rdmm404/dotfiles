-- Hyprland window classes for games assigned to workspace 8.
local target_games = {
  "^steam_app_[0-9]+$",
  "^EscapeSimulator$",

  -- Add more game classes here:
  -- "^Hades$",
  -- "^SomeOtherGame$",

  -- Uncomment to include Steam's steam_app_* windows:
}

for _, game_class in ipairs(target_games) do
  o.window(game_class, {
    workspace = "8",
    idle_inhibit = "fullscreen",
  })
end
