---
name: using-worktrees
description: Use when you need a git worktree, an isolated checkout of a branch, or to work on a branch in parallel. Covers creating, reusing and removing worktrees with herdr. Never use raw `git worktree add`.
---

# Using worktrees

Create worktrees with `herdr worktree`, not `git worktree add`. Herdr also opens a workspace for the checkout, so Robert can see the work.

Checkouts land in `~/worktrees/<repo>/<branch-slug>`.

## Create

```sh
herdr worktree create --cwd <main-checkout> --branch <name> [--base <ref>] --no-focus
```

- Always pass `--no-focus`, so you don't steal Robert's focus.
- `--base <ref>` only applies to a new branch. Default is the repo's current `HEAD`.
- If the branch already exists, it is checked out as is.
- Output is JSON. The checkout path is `.result.worktree.path`. `cd` there and work from it.

```sh
herdr worktree create --cwd . --branch feat-x --no-focus | jq -r '.result.worktree.path'
```

## `--cwd` must be the main checkout

Running from inside a linked worktree fails with `linked_worktree_source`. Use the repo's main checkout path instead (first line of `git worktree list`).

## Reuse an existing worktree

Git allows a branch in one checkout only. For a worktree made outside herdr (or whose workspace was closed), open it:

```sh
herdr worktree open --cwd <main-checkout> --path <worktree-path> --no-focus
```

`herdr worktree list --cwd <main-checkout>` shows all worktrees, their branches and `open_workspace_id`.

## Remove

```sh
herdr worktree remove --workspace <workspace_id>
```

- Get the id from `create`/`list` output (`.result.workspace.workspace_id` or `open_workspace_id`).
- It removes the checkout but keeps the branch. Use `--force` only if Robert agreed to discarding uncommitted changes.
- Delete the branch yourself with `git branch -d` if it should go.

## Verified

Checked against herdr 0.9.3 in a scratch repo: create, `--base`, existing branch, open, remove, list, and the linked-worktree error.
