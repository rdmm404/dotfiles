---
name: using-worktrees
description: Use when you need a git worktree, an isolated checkout of a branch, or to work on a branch in parallel. Covers creating, reusing and removing worktrees with herdr-worktree. Never use raw `git worktree add`.
---

# Using worktrees

Make and remove worktrees with `herdr-worktree`, not `git worktree`. It puts every checkout in one place and opens it as a space in the Herdr app, so Robert can see the work.

## Create

```sh
cd "$(herdr-worktree create <branch> [--base <ref>])"
```

It prints the checkout's path; work from there. It runs from any checkout of the repo (`--cwd <dir>` for another repo).

- A branch checked out somewhere already: you get that checkout. Git allows a branch in one checkout only.
- A local branch, or one only on `origin`: checked out as is (an `origin` one gets a local tracking branch).
- A new name: a new branch from `--base`, default the current `HEAD`.

Checkouts land in `$WORKTREES_DIR/<repo>/<branch-slug>`, default `~/worktrees`.

The new space opens in the background: Robert stays where he is. Pass `--focus` only when he asked to be taken there. A warning that no space opened (no app, app not running, no `jq`) is not a failure: the worktree is made, carry on.

## Remove

```sh
herdr-worktree remove <path> [--force]
```

It removes the checkout, then closes its space, which ends every terminal in it. Never remove the checkout your own session runs in. The branch stays: delete it with `git branch -d` if it should go. `--force` discards uncommitted changes; use it only if Robert agreed.
