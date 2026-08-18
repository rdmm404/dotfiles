# Handoff: macOS Phase 4 validation

You are taking over the **Phase 4 macOS smoke test** for this dotfiles repository.

## Current state

- Phase 3 configuration restructure is committed and pushed to `main`.
- WSL validation passed after deploying the new layout.
- WSL needed one local-only cleanup: an incompatible `~/.fzf.zsh` was moved to `~/.fzf.zsh.bak`. Do not assume the Mac has the same issue.
- This handoff is for validation, not for starting the Omarchy VM work (Phase 5).

## Guardrails

- Work on one check at a time and report the result clearly.
- Do not modify repository files or commit/push changes unless explicitly requested.
- Do not use adoption automatically.
- If a real conflict is found, stop, show the path, and ask before using `--adopt`.
- If a failure requires code or configuration changes, report it before changing anything.
- If a finding belongs to Omarchy VM testing, record it as Phase 5 rather than solving it during this Mac pass.

## Test sequence

Run these from the repository root.

### 1. Establish a clean baseline

```bash
git pull --ff-only origin main
git status --short --branch
```

The working tree should be clean before testing.

### 2. Run the doctor check

```bash
./dot doctor
```

Record any errors or warnings. ShellCheck being unavailable is not itself a failure.

### 3. Review the deployment plan

```bash
./dot plan
```

Review every planned link. Expected macOS-specific destinations include:

- `~/.config/zsh/...`
- `~/.config/starship.toml`
- `~/.config/ghostty/...`
- `~/Library/Application Support/Code/User/settings.json`
- `~/Library/Application Support/rtk/config.toml`
- `~/Library/Application Support/MTMR/items.json`

The plan may report replacement of old repository-owned links. That is expected for the one-time migration. Unrelated files must be reported as conflicts.

### 4. Perform the one-time deployment migration

If the plan contains only new links and repository-owned legacy links:

```bash
./dot deploy --yes
```

Do not use `--adopt` unless the plan shows real, unrelated conflicts and the user explicitly approves it.

### 5. Start a clean Zsh session

```bash
exec zsh
```

Check that startup is error-free and verify:

- `DOT_ZSH_FOUNDATION` is `zap`.
- Zap is installed and retained plugins load: autosuggestions, autopair, history substring search, and `git-open`.
- Starship starts correctly.
- zoxide works as the `cd` replacement.
- FZF integration works.
- Shared aliases, exports, and functions are present.
- The macOS-only `pi()` wrapper is present and works.
- WSL-only settings such as `ollama.exe`, `/snap/bin`, and display forwarding are absent.

Useful checks:

```zsh
print -r -- "$DOT_ZSH_FOUNDATION"
command -v starship zoxide fzf eza rtk git-open
whence -f pi
```

### 6. Verify macOS adapter links

Confirm that the deployed links resolve to the repository's canonical shared files:

```bash
readlink "$HOME/Library/Application Support/Code/User/settings.json"
readlink "$HOME/Library/Application Support/rtk/config.toml"
readlink "$HOME/Library/Application Support/MTMR/items.json"
```

Also check that VS Code, RTK, Ghostty, and MTMR launch or read their configuration normally. Confirm VS Code custom CSS still works if the extension is installed.

### 7. Repeat bootstrap

After deployment and manual checks:

```bash
./dot bootstrap --yes
```

It should skip already-installed applications and make no unnecessary deployment changes. Do not expect it to upgrade anything.

### 8. Test backup, undeploy, and redeploy

First inspect available backups:

```bash
./dot backups list
```

Only perform restore/remove/prune commands with explicit confirmation. If there is no suitable existing backup, report that rather than creating a risky real-file conflict casually.

For the lifecycle check:

```bash
./dot undeploy --yes
./dot deploy --yes
```

Confirm that undeploy removes only repository-owned links and that redeploy restores the expected links. Do not proceed if undeploy proposes removing normal files or unrelated links.

### 9. Final verification

```bash
./dot doctor
./tests/run
```

The tests should pass without touching the Mac's real configuration outside the deliberate smoke-test actions.

## Report format

Finish with:

- Commands run and their results
- Any manual checks that passed
- Any warnings or failures, including exact paths/messages
- Whether the Mac passes Phase 4
- Any issue that should be fixed before the second Mac
- Any finding deferred to Phase 5
