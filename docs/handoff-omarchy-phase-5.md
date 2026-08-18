# Handoff: Continue Phase 5 Omarchy VM testing

## Next-session focus

Continue Phase 5 validation from inside the disposable Omarchy Quattro VirtualBox VM. Do not make repository changes or use adoption until the existing configuration conflicts and installer failures are understood.

## Repository context

The migration plan and acceptance criteria are in:

- `docs/migration-overview.md`
- `docs/migration-tasks.md`
- `docs/handoff-macos-phase-4.md`

Phase 4 (WSL and macOS validation) has been completed by the user. The Phase 5 checklist is the next work. Previous implementation/review history is captured in Git commits and `docs/.reviews/`; do not duplicate it here.

## Current VM status

- Omarchy Quattro is installed in VirtualBox and boots.
- VirtualBox workaround that made boot usable: `VBoxVGA`, 3D acceleration disabled, and EFI disabled were recommended based on the community guide.
- Omarchy Quattro uses `~/.config/hypr/monitors.lua`, not the older `monitors.conf` instructions.
- The VM initially reported active `1024x768`, while `hyprctl monitors` showed `1920x1080@60` as an available mode.
- The local VM config was adjusted toward:
  - `local omarchy_gdk_scale = 1`
  - `local omarchy_monitor_scale = 1`
  - explicit `mode = "1920x1080@60"`
- Automatic VirtualBox resizing remains unreliable with the Omarchy/Hyprland/VirtualBox combination. The user is currently satisfied enough with the display and does not need more display troubleshooting unless it blocks testing.
- The VM should have a VirtualBox snapshot of the working state before risky deployment/adoption tests. Confirm that the user created one.

## Current Phase 5 findings

### GitHub CLI

Running `gh` triggered Omarchy's lazy installation of the GitHub CLI. This is expected Omarchy behavior. The user was instructed to run:

```bash
gh auth login
gh auth status
gh repo clone rdmm404/dotfiles ~/.dotfiles
```

Confirm authentication and cloning completed before continuing.

### Installer failures

The user reported that installation of `rtk` and `git-open` appeared to fail. Exact error output was not captured. Diagnose this first or capture it by rerunning the relevant plan/install command.

Relevant repository code:

- `installers/omarchy.sh` currently treats most logical IDs as both commands and package names; `rtk` and `git-open` therefore may be passed directly to `omarchy-install`/`pacman`.
- `manifests/development` lists `rtk` and `git-open`.
- `lib/install.sh` performs post-install `command -v` verification.
- `lib/apps.sh` maps only a few special application IDs.

Useful diagnostics inside the VM, from the repository root:

```bash
./dot plan
command -v rtk || true
command -v git-open || true
pacman -Ss '^(rtk|git-open)$' || true
```

Do not randomly install substitutes before understanding whether the repository's Omarchy mapping is wrong. This may require a focused code change and tests.

### Deployment conflicts

The user reported three conflicts during planning/bootstrap:

- Starship configuration
- VS Code configuration
- Ghostty configuration

The exact paths and plan output were not captured. Stop before `--adopt`. Ask the user to show the exact conflict paths and inspect the existing files. These are likely files already created/owned by Omarchy, so ownership must be decided deliberately:

1. repository-owned and safely replaceable;
2. Omarchy-owned and should remain untouched; or
3. requiring a platform-specific adapter/merge.

This is especially important because the migration design says Omarchy controls themes and fonts while the repository preserves personal settings such as Starship and VS Code custom CSS. Do not overwrite existing Omarchy files merely to make bootstrap pass.

Useful commands:

```bash
./dot plan
./dot doctor
```

Only use `./dot deploy --adopt` after reviewing the exact conflicts and receiving explicit user approval. If adoption is approved, verify the backup contents and be prepared to restore the VM snapshot.

## Recommended continuation order

1. Confirm the VM snapshot and repository clone.
2. Run `./dot doctor` and save the result.
3. Run `./dot plan`; capture all conflict paths and missing applications.
4. Diagnose `rtk` and `git-open` install behavior.
5. Resolve or explicitly classify the Starship, VS Code, and Ghostty conflicts before deployment.
6. Once the plan is safe, run bootstrap and validate idempotency with a second bootstrap.
7. Validate Omarchy shell foundations, commands/completions, autosuggestions, autopair, history search, `git-open`, FZF/eza ownership, Starship, zoxide, Ghostty, VS Code, menu, updater, and custom CSS.
8. Track only intentional Omarchy/Hyprland changes under `platforms/omarchy/`; do not commit VM-specific display workarounds without deciding whether they belong on the physical machine.
9. Run the final VM lifecycle and acceptance checks from `docs/migration-tasks.md`.

## Guardrails

- Work only in the disposable VM.
- Do not edit `docs/.reviews/INSTRUCTIONS.md`.
- Do not modify or commit repository files until a concrete fix is requested/approved.
- Do not use adoption automatically.
- Do not edit `/boot/limine.conf` for display testing unless all safer options fail and a snapshot exists.
- Record exact errors and classify findings as fix-before-physical-migration, intentional configuration, or Phase-5-only.

## Suggested skills

- `research`: verify current Omarchy Quattro package/install mechanisms and VirtualBox behavior when exact platform facts are needed.
- `code-review`: review any installer/configuration changes before committing them.
- `make-pr-easy-to-review`: use only after implementation is complete and the VM findings have been resolved, if the resulting PR needs cleanup.
