# Herdr flat layout

Reference for agents changing how the Herdr app looks or follows the Omarchy theme. It covers
the `flat` layout, its `flat-*` mods, the design tokens, and the theme sync. Herdr's own API
docs are `~/.config/herdr-app/AGENTS.md` and `herdr.d.ts` (installed by Herdr, not tracked).
Written against Herdr app 0.1.15.

## What it is

- **Theme sync:** Herdr takes its colours from the active Omarchy theme.
- **Design:** the `flat` layout follows the `ui-taste` skill's design language, but not its
  colours: 1px corners, 1px lines, no shadows, JetBrains Mono, 13px text, 5px spacing unit.

Everything lives in this repo. `~/.config/herdr-app` holds only per-file symlinks into
`global/.config/herdr-app/`.

## Map

| Piece | Where |
|---|---|
| Theme template | `platforms/omarchy/.config/omarchy/themed/herdr.json.tpl` |
| Theme hook | `platforms/omarchy/.config/omarchy/hooks/theme-set.d/herdr-theme-sync` |
| Layout | `global/.config/herdr-app/layouts/flat.json` |
| Mods | `global/.config/herdr-app/mods/flat-*` (19) |
| Keys | `global/.config/herdr-app/keys.json`, section `layout:flat` |
| Prefix bar | `global/.config/herdr-app/mods/prefix/main.js` (the user's own mod) |
| Tokens | `lib/herdr_flat/flat.js`, copied in by `lib/herdr_flat/sync` |
| Reload | `lib/herdr_flat/reload` |
| Upstream diff | `lib/herdr_flat/upstream-diff` |
| Update check | `init()` in `mods/flat-workspace-status/main.js` |
| Tests | `tests/herdr_flat_test.sh`, `tests/herdr_flat_checks.py` (run by `tests/run`) |

Each script's header comment explains how it works; this doc doesn't repeat it.

## Theme sync

When the Omarchy theme changes, Omarchy renders `herdr.json.tpl` into the theme directory.
The hook then copies the result to `~/.config/herdr-app/themes/omarchy.json` and, if the app
is running, runs `herdr-app do app.theme '{"name":"omarchy"}'`. The layout's theme choice is
`{light: omarchy, dark: omarchy}`, set from the theme picker rather than in `flat.json`, so
the file stays portable.

Herdr still derives `popover`, `surface`, `hover`, `selected`, `input` and `solid` itself.
Pinning them in the template is an open option. The user said "good for now".

The same commit also tracks the Spotify and Discord templates and their hooks. These files
are deliberately left untracked:

- `10-owe-sync`: it belongs to the `owe` package.
- `post-update.d/setup-*.hook`: these are Omarchy's.

## The mods

- **Cloned mods:** 17 were made with `mod.clone`, so each `mod.json` records
  `cloned_from: {name, version: "0.1.15"}`.
- **Hand-copied mods:** `flat-settings` and `flat-palette` were copied by hand from
  `frame/settings` and `frame/palette`, which Herdr can't clone. Their `mod.json` records the
  frame as the source.

**Overlay frames:** overlays open with `frame: "none"` and draw their own box:
`.bg(t.popover).border(LINE).border_color(t.border).rounded(R)`.

**Routing:** while the flat layout is active, entry points go to the flat copies.

- **Keys:** `keys.json` `layout:flat` binds settings, the palette, help, the picker, and the
  rename and close keys. A mod command's key value is `"<mod>.<command>"`. A colon instead of
  the dot makes Herdr reject the whole file.
- **Rename and close:** `flat-tabs` owns them (see its header). Other mods call
  `setShared("flat-dialog", {action, kind, id})` and then `run("flat-tabs.dialog")`.
- **Palette:** `go()` in `flat-palette` maps Herdr's screens to the flat copies.
- **Prefix bar:** `mods/prefix` checks `shared("layout") === "flat"`.
- **Layout fields:** `flat.json` sets `terminal_menu: "flat-menu"` and `toast: "flat-toast"`.

**Known limit:** anything Herdr opens itself, outside these routes, still uses the shipped
mods. Feedback, Welcome and What's new were skipped on purpose, since the user rarely sees
them.

**Sizes that live outside the mod:**

- The terminal right-click menu's width is `overlay.width` in `flat-menu/mod.json` (372px).
  Herdr's default is 220px, and JetBrains Mono at 13px needs more room than that.
- Openers pass dialog sizes to `openOverlay`. For example, the new-worktree dialog is 460×225
  in `flat-menu` and `flat-new-menu`, and the remove dialog is 260px tall.
- Row heights were left as Herdr ships them, by agreement with the user.

**Toast:** Herdr wraps toasts in its own rounded, shadowed frame even with `"frame": "none"`.
So `flat-toast` closes Herdr's toast and opens the same props as an unframed
`kind: "window"` overlay, which closes itself after the timeout. A window's `at` is its
top-left corner and isn't clamped to the screen. The position therefore comes from
`window.viewport_size()` (the gpui-kit global, not herdr's `window()`): bottom right, above
the 28px status bar. If the status bar height in `flat.json` changes, change `STATUS` in the
toast too. Windows don't take the keyboard, which was checked on screen.

## Tokens

`lib/herdr_flat/flat.js` is the single source of truth. Put one `export const` on each line,
because `sync` copies those lines into the `// <flat-tokens>` block of every flat mod.

The test fails on:

- token blocks that have drifted from the source;
- bare numbers in corners, border widths, gaps, padding and text sizes;
- `border_2()` and similar shortcuts.

Arithmetic on a token is fine. `// flat: keep` exempts a line. Margins are exempt because the
shipped code uses them for optical alignment.

**A new flat mod:** write `mod.json` first, then `main.js` with an empty marker pair after the
imports. Then run `lib/herdr_flat/sync` and `lib/herdr_flat/reload`.

## Change loop

After each change:

1. Edit the file under `global/.config/herdr-app/`.
2. Run `herdr-app check ~/.config/herdr-app/mods/<mod>`.
3. Run `lib/herdr_flat/reload <path relative to ~/.config/herdr-app>`.
4. Run `herdr-app status`; `errors` should be empty.
5. Run `herdr-app shot <file>.png` twice, because the first frame can be stale. Look at the
   second one.
6. Run `bash tests/herdr_flat_test.sh`.

Pointer and key automation on the user's display is off limits. You can open overlays with
`herdr-app do`, show and hide panels, and change the Omarchy theme for a check (restore
Neon Cyberpunk City afterwards). Popups that only open from a real click, such as right-click
menus, the + menu and the worktree dialogs, need the user to open them and send a screenshot.
Leave the user's app and core running.

## Gotchas

- **Herdr watches the symlinks, not their targets.** An edit in the repo stays invisible until
  `reload` relinks the file. `touch -h` doesn't trigger a reload.
- **Edit files under `global/.config/herdr-app/`.** `sed -i`, `perl -i` or `mv` through
  `~/.config/herdr-app/...` replace the symlink with a plain file, and the repo silently goes
  stale.
- **A mod can't import through a symlink or from another folder.** That is why the tokens are
  copied into each mod instead of shared from one module.
- **Overlay mod without `mod.json`:** if Herdr sees an overlay mod's folder before its
  `mod.json` exists, `mod.open` adds it to the layout as a 320px block. It also writes that
  block into the tracked `flat.json`.
- **`layout.set` clears the layout's click state, including the theme choice.** Run
  `herdr-app do app.theme '{"name":"omarchy"}'` afterwards.
- **`cp`, `rm` and `mv` are interactive aliases in the user's shell.** Use `command cp -f` and
  so on.
- **zsh doesn't split words in `$VAR`.** Use arrays.
- **`tests/herdr_launch_test.sh` fails inside the agent sandbox** because it can't create
  `/tmp/opencode`. This has nothing to do with the flat layout.

## Porting a Herdr update

Herdr updates itself and never touches clones, so after an update the flat mods lag upstream
until they're ported. Herdr has no hooks, so the status bar mod checks on every start. When
`updates().app.version` differs from its own `cloned_from.version`, it posts a toast once per
version and shows "port flat mods <old> → <new>" in the status bar. Clicking either opens a
Claude tab in this repo with the porting task, which points here. The status bar item stays
until the port bumps the versions.

Steps for the porting agent:

1. **Branch:** create `herdr-port-<new>` from `main` with `git switch -c`. Use a branch in this
   checkout, not a worktree: the running app reads the files through this checkout's symlinks,
   and the checks need that.
2. **Diff:** run `lib/herdr_flat/upstream-diff > <scratch>/upstream.diff` and read all of it.
   It has one section per flat mod, plus `layouts/main.json`, mods added or removed upstream,
   and Herdr's API docs. Upstream is `herdrdev/herdr-app`, tags `v<version>`.
3. **Port:** compare each hunk with the flat copy first, since an earlier port or a flat
   change may already contain it. Apply the rest to the `flat-*` copy, keeping the flat styling (token
   names, `frame: "none"` with the mod's own box) and the routing to flat copies (`flat-tabs`
   dialogs, `flat-*` mod names in `openOverlay` and `run`). Apply `main.json` changes to
   `flat.json` where they fit the flat layout. If the API docs changed something a flat mod
   relies on, fix the mod. Report new upstream mods to the user rather than cloning them.
4. **Bump:** set `cloned_from.version` to the new version in every flat mod's `mod.json`,
   including mods with no upstream changes. This clears the status bar item.
5. **Check:** run the change loop above for every mod whose code changed, plus
   `lib/herdr_flat/sync --check`. Run `herdr-app check` on the `~/.config/herdr-app/mods/<mod>`
   path: on a repo folder it writes `gpui-kit.d.ts` and `jsconfig.json` into the repo. Ask the
   user to open the click-only screens whose code changed and send screenshots. A port that
   only bumps versions needs no screenshots.
6. **Hand back:** commit on the branch and summarise each mod's port for the user. The user
   merges.

## Open items

- **Derived colours:** optionally, pin `popover`, `hover`, `selected` and the other derived
  colours in the template. The user looked and said it can stay as it is.
- **Unchecked menus:** the tab and space right-click menus open at 200px. Their labels
  truncate and their shortcuts never shrink, but nobody has looked at them on screen yet.
