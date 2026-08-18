# Phase 3 review 3

## Must haves

- Verify the `${userHome}` variable mechanism used by `vscode_custom_css.imports`; the review considered arbitrary extension settings unsafe without explicit extension support.

## Nice to haves

- Load `zsh-syntax-highlighting` after the shared fragments and final keybindings so it can wrap the final widgets.

## Summary

Starship now uses the canonical `~/.config/starship.toml` path and Ghostty’s home-relative include has adequate deployment coverage. The only remaining blocker is verification of the VS Code custom-CSS variable expansion.
