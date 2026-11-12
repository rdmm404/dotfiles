# Set up the Herdr app on a Mac

A task for an agent on Robert's work Mac. Goal: the Herdr app runs with the flat layout,
its mods, the launcher (prefix+a), the shared theme and `herdr-worktree`, as on his Omarchy
machine. Background: [the flat layout reference](herdr-flat.md), especially "On macOS".

Work through the steps in order. Each ends on a check; a step is done when its check passes.
Ask Robert before anything that needs his password or a System Settings click, and before
installing anything not named here.

## 1. Dotfiles

`git pull` in `~/.dotfiles`, then `./dot deploy`. If the app was opened before, quit it
first and use `--replace`: its own `keys.json` and `settings.json` conflict, and a running app
writes them back straight away.

Check: `readlink ~/.config/herdr-app/keys.json` ends in
`platforms/macos/.config/herdr-app/keys.json`, and `command -v herdr-worktree` finds it.

## 2. Herdr app

If `herdr-app --version` fails, install the app (macOS releases need Apple Silicon). An
installed bundle makes its own `~/.local/bin/herdr-app` link on first launch. Open it once.

Check: `herdr-app status` answers and lists no file or mod errors.

## 3. Tools

Install what's missing with Homebrew: `fd`, `zoxide`, `jq`, and the font
(`brew install --cask font-jetbrains-mono`). `python3` and `git` come with the Xcode command
line tools.

Check: `fd --version`, `zoxide --version`, `jq --version` and `python3 --version` all work.

## 4. Worktree folder

The terminal Herdr on this Mac may already put worktrees somewhere other than `~/worktrees`:
read `worktrees.directory` in `~/.config/herdr/config.toml`. If it differs, add
`export WORKTREES_DIR=<that folder>` to this Mac's local shell config (not a tracked dotfile),
and open a new shell.

Check: `herdr-worktree dir` prints the folder Robert's existing worktrees are in.

## 5. Theme

`herdr-app do layout.switch '{"name":"flat"}'`, then
`herdr-app do app.theme '{"name":"omarchy"}'` (the theme file comes from the dotfiles). The
theme applies to the layout showing, so switch first. Bring the window to the front before
`herdr-app shot`: a background window doesn't redraw, so the shot can be stale.

Check: the command prints `{"ok": true}`, and `herdr-app shot` shows the window in the theme's
dark blue-grey, not Herdr's default.

## 6. Mods and launcher

- `herdr-app check ~/.config/herdr-app/mods/<name>` for each `flat-*` mod and `prefix`.
- `python3 ~/.config/herdr-app/mods/flat-launch/sessions.py 5` prints JSON (an empty list is
  fine on a machine with no Claude or pi sessions).
- `herdr-worktree create test-wt` in a scratch repo, then `herdr-worktree remove <its path>`.
  This is the script's first run on macOS: watch for `sed`, `awk` or `readlink` errors.

Check: every mod checks clean, and the worktree is made, opened as a space, and removed.

## 7. With Robert

These need his hands or eyes:

- **Prefix key:** macOS may use Ctrl+Space to switch input source. He turns it off in System
  Settings → Keyboard → Keyboard Shortcuts → Input Sources. Then Ctrl+Space shows the prefix
  bar, and prefix+a opens the launcher.
- **Keys:** Cmd+C/V copy and paste in a terminal, Cmd+T new tab, Alt+Shift+←/→ switch tabs,
  Option+←/→ jump words in the shell, Cmd+, opens the flat settings.

## Fixes

A problem in a tracked file is fixed in `~/.dotfiles`. Keep Linux working: a change to
`platforms/macos/.config/herdr-app/keys.json` that also applies to Linux goes in
`global/.config/herdr-app/keys.json` too. Run `tests/run` before committing. Note anything
learned about the Mac in the "On macOS" section of `herdr-flat.md`.

Done when steps 1 to 6 pass and Robert has confirmed step 7. Report what you changed and
anything left open.
