# Herdr agent launcher

Press **prefix+a** (`ctrl+space a`) in Herdr. A popup asks where, then which
agent, then closes and focuses the new tab. The agent command (and a clone,
if any) is typed into that tab's shell, so you watch it start there.

## Picking where

The first list holds open workspaces (marked `●`, the current one first and
preselected), then zoxide folders that have no open workspace, then GitHub
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

The list comes from `gh repo list achievers-internal` (archived repos skipped),
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
default `achievers-internal`), `HERDR_LAUNCH_CLONE_DIR`, `HERDR_LAUNCH_LOCAL_ROOT`.

## Picking the agent

The second list shows installed agents from `pi`, `claude`, `opencode`,
`codex`, `gemini`, with the last one used first. The agent gets the name
`<agent>-<n>` (the lowest free number) as its tab label. Tab labels count as
taken, so quick back-to-back launches don't collide. The Herdr agent itself is
unnamed (`herdr agent list` shows `null`); Herdr detects it on its own.

If the agent fails to start, the error is right there in its pane.

## Files and dependencies

- `~/.local/bin/herdr-launch`: the script (from `global/`)
- `~/.config/herdr/config.toml`: the `prefix+a` popup binding and
  `worktrees.directory`
- `${XDG_STATE_HOME:-~/.local/state}/herdr-launch/last-agent`: last agent used
- `${XDG_CACHE_HOME:-~/.cache}/herdr-launch/repos`: remote repo list

Requires fzf and jq. Optional: zoxide (folder rows), gh and fd (remote repo
rows, clones use SSH). Edits to the script apply on the next launch; binding changes need
`herdr server reload-config` (or `prefix+q`).

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
