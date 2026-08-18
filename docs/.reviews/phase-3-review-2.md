# Phase 3 review 2

## Must haves

- The moved Starship config was deployed at `~/.config/starship/starship.toml`, but Starship expects `~/.config/starship.toml` and startup did not set `STARSHIP_CONFIG`. Restore the default deployed path or initialize Starship with the custom path.
- Ghostty now uses `~/.config` semantics, but tests only checked that the platform config was a symlink. Add validation that the deployed shared file exists and the platform configs use the intended include.

## Nice to haves

- Verify `${userHome}` support for the VS Code custom-CSS extension before claiming the task complete.
- Consider loading zsh-syntax-highlighting after shared fragments.

## Summary

The cycle-1 fixes were addressed, but the Starship move caused a runtime regression and Ghostty include behavior still lacked meaningful test coverage.
