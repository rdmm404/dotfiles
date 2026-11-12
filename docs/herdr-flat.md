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

## Open items

- **Herdr updates (on hold; discuss with the user first):** the idea is a hook that runs when
  Herdr updates. For each clone, it would diff the upstream source between
  `cloned_from.version` and the new version and hand the diff to an agent to apply. The
  upstream source is `herdrdev/herdr-app` (tags `v<version>`), under `defaults/mods/<name>/`,
  `defaults/layouts/` and presumably `defaults/frame/`. No baselines are stored: upstream is
  public and tagged, and the clones were checked byte-identical to `v0.1.15`.
- **Derived colours:** optionally, pin `popover`, `hover`, `selected` and the other derived
  colours in the template.
- **Unchecked menus:** the tab and space right-click menus open at 200px. Their labels
  truncate and their shortcuts never shrink, but nobody has looked at them on screen yet.
