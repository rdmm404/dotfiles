---
name: orchestrator-mode
description: Manage visible child OpenCode agents across Herdr tabs and worktrees via hc.
disable-model-invocation: true
---

# Orchestrator mode

Coordinate work through visible child OpenCode agents in Herdr tabs using `scripts/herdr-agent` (relative to this skill's directory) and `herdr-worktree`. Keep code edits in child agents rather than editing repos directly from the orchestrator.

> **Experimental.** This skill and its scripts are new. If `herdr-agent`, `herdr-worktree` or these instructions misbehave, fix them directly in `~/.dotfiles` (the skill lives in `global/.agents/skills/orchestrator-mode/`) rather than working around the problem, then tell the user what you changed.

## Worktrees

Create a branch worktree and its Herdr space without stealing focus:

```sh
herdr-worktree create <branch> [--base <ref>] [--cwd <repo>]
```

Returns JSON `{"path": "...", "space": "<id|null>"}`. Clean up merged worktrees and close their space with `herdr-worktree remove <path> [--force]`.

## Spawn child agents

```sh
scripts/herdr-agent spawn \
  --dir <dir> \
  --name <name> \
  [--space <space_id>] \
  [--model <provider/id#variant>] \
  [--agent <opencode_agent>] \
  --prompt-file <file>
```

- Omit `--space` to open a new tab in your current space; pass `space` from `herdr-worktree create` to open in the worktree's space.
- Pass the first task in `--prompt` or `--prompt-file` (sending to a booting agent can drop input). `spawn` appends the `hc send $HC_TERMINAL_ID` report-back instruction automatically.
- Children inherit your `$HC_TERMINAL_ID` as parent and exit when the orchestrator exits.
- Returns JSON `{"terminal", "name", "session", "space"}`. Use `terminal` (e.g. `t7`) or `name` as `<t>` in subsequent calls.
- To reopen a killed child, pass `--session <ses_id>` (from the original `spawn` output) to resume that session in a new terminal; `--prompt` is optional then.

## Wait and monitor

```sh
scripts/herdr-agent wait --children any   # next child news or report (or --children all)
scripts/herdr-agent wait <t>              # wait on one terminal
scripts/herdr-agent status [t]            # hc get <t> or hc ls
scripts/herdr-agent read <t> [--lines 80] # screen + history
```

Wait with `wait` instead of `sleep` loops. When `wait` returns `reason: timeout`, check in or wait again.

## Steer and unblock

```sh
scripts/herdr-agent send <t> "<message>"           # or --prompt-file <file>; supports --wait, --if idle|working
scripts/herdr-agent interrupt <t>                  # stop current turn without killing
scripts/herdr-agent keys <t> down enter            # resolve a startup/trust dialog
```

When a child reports `blocked`, read its screen and ask the user before passing `--force` to `send`. If a child's `first_message.sent` is `false` in `status`, read its screen first before resending.

## Cleanup

```sh
scripts/herdr-agent kill <t>
```

Kills and removes a child terminal you started once its work is accepted.
