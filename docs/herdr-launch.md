# Herdr agent launcher

Press **prefix+a** (`ctrl+space a`) in Herdr. A popup asks where, then which
agent, then closes and focuses the new tab, where the agent starts up.

## Picking where

The first list holds open workspaces (marked `●`, the current one first and
preselected), then zoxide folders that have no open workspace.

| Action | Result |
| --- | --- |
| Enter on a workspace | New agent tab in that workspace, in its folder |
| Enter on a folder | New workspace named after the folder |
| Type a path that exists, then Enter | Same as a folder row |
| ctrl-w on a workspace or folder | Prompts for a branch, then a new git worktree workspace |
| Esc | Cancel |

So `prefix+a`, Enter, Enter means "another agent tab right here, same agent as
last time".

A workspace's folder is its git checkout path, or else its first pane's cwd.
Picking a folder whose workspace is already open reuses that workspace.

Worktrees use `herdr worktree create` from the folder's current `HEAD`. If the
branch already exists locally, Herdr checks it out. Checkouts land in
`~/worktrees/<repo>/<branch-slug>` (`worktrees.directory` in the Herdr
config), and the workspace is named after the branch.

## Picking the agent

The second list shows installed agents from `pi`, `claude`, `opencode`,
`codex`, `gemini`, with the last one used first. The agent gets the name
`<agent>-<n>` (the lowest free number), used as both the Herdr agent name and
the tab label. Tab labels count as taken, so quick back-to-back launches don't
collide.

If an agent fails to start, a Herdr notification shows the error.

## Files and dependencies

- `~/.local/bin/herdr-launch`: the script (from `global/`)
- `~/.config/herdr/config.toml`: the `prefix+a` popup binding and
  `worktrees.directory`
- `${XDG_STATE_HOME:-~/.local/state}/herdr-launch/last-agent`: last agent used

Requires fzf and jq. zoxide is optional; without it only open workspaces are
listed. Edits to the script apply on the next launch; binding changes need
`herdr server reload-config` (or `prefix+q`).

## Notes

- Closing a Herdr popup kills its process group. The script starts the agent in
  a detached session (perl fork + `setsid`) and waits until that child has left
  the group before exiting. A plain `setsid … &` loses that race and the agent
  never starts.
- Quitting the agent leaves its shell open; tabs and workspaces are not closed
  automatically.
- Test against a named session (`herdr --session test ...`), not with
  `HERDR_SESSION`: panes export `HERDR_SOCKET_PATH`, which wins over
  `HERDR_SESSION` and points commands at the live server.
