# Herdr agent launcher

Press **prefix+a** (`ctrl+space a`) in Herdr. A popup asks where, then which
agent, then closes and focuses the new tab. The agent command (and a clone,
if any) is typed into that tab's shell, so you watch it start there.

**prefix+s** (`herdr-launch --shell`) is the same popup without the agent step:
you get a plain shell tab in the picked place, with herdr's default tab label.
Everything below (worktrees, remote repos, ranking) works the same. It
replaces herdr's default `prefix+s` (settings), which moved to `prefix+shift+s`.

## Picking where

If Herdr has enabled saved machines, a **machine** picker comes first. Choose
**This machine** for the existing local flow, or a saved SSH machine to run the
whole launcher there. With no saved machines, this step is skipped.

Remote selection runs `herdr-launch` over SSH in an interactive login shell,
targeting the profile's saved Herdr session. It uses that host's zoxide history,
fzf, folders, Git worktrees, GitHub credentials/cache, installed agents and last
agent setting. Deploy these dotfiles on each host and install the same launcher
dependencies there. Herdr's remote server must already be running. SSH failures
are shown rather than silently launching locally. This does not install anything
remotely or change machine profiles. The remote tab is focused on its server;
you may still need to select that machine in the local Herdr sidebar to view it.

The first list holds open workspaces (marked `●`, the current one first and
preselected), then zoxide folders that have no open workspace, then folders
found by scanning `~` with `fd` (hidden ones like `~/.config` included; the
picker shows a yellow notice if `fd` is missing), then GitHub
repos you haven't cloned (marked `↓`).

While you type, rows are ranked by match quality, with extra weight on the
last folder name (fzf `--scheme=path`). Local rows always stay above remote
repos. Without that, remote names win short queries a lot: they're made of
short dashed words, and there are hundreds. Ties keep the order above.
The branch and agent pickers rank the same way, minus the tiers.

| Action | Result |
| --- | --- |
| Enter on a workspace | New agent tab in that workspace, in its folder |
| Enter on a folder | New workspace named after the folder |
| Type a path that exists, then Enter | Same as a folder row |
| Enter on a remote repo | Clones it into `~/Documents/work/repos/<repo>`, agent in it |
| ctrl-w on any row | Opens the branch picker for that repo (see below) |
| ctrl-r | Refreshes the remote repo list from GitHub |
| Esc | Back to the previous step. On the first step, cancel |

So `prefix+a`, Enter, Enter means "another agent tab right here, same agent as
last time".

A workspace's folder is its git checkout path, or else its first pane's cwd.
Picking a folder whose workspace is already open reuses that workspace.

### Worktrees (ctrl-w)

The branch picker lists local branches (newest first), then branches that only
exist on `origin`. Branches already checked out somewhere show their folder.
`ctrl-r` fetches origin and refreshes the list. Typing a name that matches
nothing and pressing Enter (or `alt-enter` to force the typed name) uses it as is.

| Branch | Result |
| --- | --- |
| Already checked out in a worktree | Reuses that checkout: a new tab if a workspace is open there, else `herdr worktree open` |
| Local, not checked out | `herdr worktree create` checks it out in a new worktree |
| Only on origin (e.g. someone's PR) | Makes a local branch tracking `origin/<branch>`, then a new worktree |
| New name | New branch from the repo's current `HEAD`, new worktree |

Git only lets a branch be checked out in one place, which is why the first row
reuses the checkout instead of failing. New checkouts land in
`~/worktrees/<repo>/<branch-slug>` (`worktrees.directory` in the Herdr
config), and the workspace is named after the branch. It works from a linked
worktree too: herdr wants the repo's main checkout, so the script passes that.

### Remote repos

The list comes from `gh repo list` for each owner in `HERDR_LAUNCH_OWNERS`
(archived repos skipped),
minus repos already cloned anywhere under `~/Documents/work` (matched by their
`origin` URL). It's cached in `~/.cache/herdr-launch/repos` because `gh` takes
5 to 15s; the first run builds it, after that only `ctrl-r` refreshes it. A failed refresh keeps the old list.

Picking one makes a workspace named after the repo in `~/Documents/work/repos`
and types `git clone --filter=blob:none <ssh-url> <repo> && cd <repo> && <agent>`
into it. If the clone fails, the error stays in the pane and no agent starts.

With ctrl-w, the branch picker lists the repo's branches straight from GitHub
(GitHub API, no clone needed): default branch first, then newest commit first.
If the API call fails it falls back to `git ls-remote`, in name order:

- Default branch: same as Enter, the agent runs in the clone.
- Any other branch: after the clone, the pane runs `herdr-launch --after-clone`,
  which makes the worktree workspace for that branch (as in the table above)
  and starts the agent there. Then the clone's shell exits, which closes the
  temporary clone workspace. The clone stays on disk as the repo's main checkout.

Settings (env vars, read by the popup): `HERDR_LAUNCH_OWNERS` (space separated,
no default; set globally to `rdmm404`), `HERDR_LAUNCH_CLONE_DIR`,
`HERDR_LAUNCH_LOCAL_ROOT`, `HERDR_LAUNCH_HOME_DEPTH` (how deep the `~` scan
goes, default 3).

## Picking the agent

The second list shows installed agents from `pi`, `claude`, `opencode`,
`codex`, `gemini`, `agy`, with the last one used first. The tab keeps Herdr's default
numeric label, so the goto navigator (`prefix+g`) shows the session title the
agent reports. The Herdr agent itself is unnamed (`herdr agent list` shows
`null`); Herdr detects it on its own.

If the agent fails to start, the error is right there in its pane.

## Session titles

Keep Herdr's built-in OpenCode and Pi integrations installed: they own agent
identity, state and resume commands. The separate dotfiles title plugins only
report presentation metadata (`title`, `$title`, `$kind`). OpenCode's plugin runs
in the V2 TUI, so a shared server cannot attribute another client's title to your
pane; it reports the selected root session's existing auto-generated/manual title.

Pi generates a title once on the first agent turn of an unnamed session, without
blocking the turn or changing its main model. Manual names (including one set
while generation is running) are preserved. The setting is
`~/.pi/agent/extensions/herdr-title/settings.json` (distributed by Pi-sync):

```json
{"provider":"openai-codex","model":"gpt-6-luna","reasoningEffort":"none"}
```

This uses Pi's existing authentication. There is no model discovery or fallback;
a missing model/authentication or failed request produces a warning and leaves
the session unnamed. It sends the first prompt (up to 6,000 characters) to the
configured title model. Publish settings changes with `/pisync push`.
Both plugins refresh metadata while running and follow session/name changes.
Remote agents show their machine in the sidebar's second row; `Local` is hidden.

## Files and dependencies

- `~/.local/bin/herdr-launch`: the script (from `global/`)
- `~/.config/herdr/config.toml`: the `prefix+a` and `prefix+s` popup bindings and
  `worktrees.directory`
- `~/.config/herdr/title-report.mjs`: shared presentation-only socket reporter
- `~/.pi/agent/extensions/herdr-title/`: Pi-sync-managed title plugin and model settings
- `~/.config/opencode/plugins/herdr-title/`: auto-discovered OpenCode V2 title plugin
- `${XDG_STATE_HOME:-~/.local/state}/herdr-launch/last-agent`: last agent used
- `${XDG_CACHE_HOME:-~/.cache}/herdr-launch/repos`: remote repo list

Requires fzf and jq. Optional: zoxide (folder rows), fd (`~` scan), gh (remote repo
rows, clones use SSH). Edits to the script apply on the next launch; binding changes need
`herdr server reload-config` (or `prefix+q`).
Run `./dot deploy` after pulling to link dotfiles-managed plugins and regenerate
merged Herdr configuration. Pi's title extension is distributed separately by
Pi-sync through the `harness` repository, not by dotfiles. Reload agent plugins
(`/reload`) in existing sessions after updating them.

## Notes

- Closing a Herdr popup kills its process group, so nothing can keep running
  from the popup. That's why the agent is typed into the pane (`herdr pane run`)
  instead of started with `herdr agent start` in the background. The shell
  queues the text until it's ready, so a slow shell startup or a long clone
  doesn't matter.
- herdr won't `workspace close` a repo's main workspace while it has worktree
  workspaces, which is why the clone workspace closes by exiting its shell.
- Quitting the agent leaves its shell open; tabs and workspaces are not closed
  automatically.
- Test against a named session (`herdr --session test ...`), not with
  `HERDR_SESSION`: panes export `HERDR_SOCKET_PATH`, which wins over
  `HERDR_SESSION` and points commands at the live server.
