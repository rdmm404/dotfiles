# Dotfiles migration tasks

This checklist breaks the migration plan into small tasks. Complete the phases in order. Each task should leave the repository usable.

## How to work through the tasks

The checkboxes are grouped by topic, not strict implementation order. For each public behavior:

- [ ] Write a small test that uses the public `dot` command.
- [ ] Run it and confirm it fails for the expected reason.
- [ ] Add the smallest change that makes it pass.
- [x] Run all fast tests.
- [x] Clean up while the tests remain green.

Testing rules:

- [x] Prefer command and filesystem tests over unit tests of private functions.
- [x] Use a temporary `HOME` for every file-changing automated test.
- [x] Use real Stow in deployment tests.
- [x] Put recording fakes first in `PATH` for Homebrew, Pacman, and Omarchy commands.
- [x] Never install real software from the automated suite.
- [x] Assert exit status, resulting files and links, backup contents, and key output lines.
- [x] Do not compare complete output snapshots.
- [x] Reserve real installation and desktop checks for platform smoke tests and the Omarchy VM.

## Phase 1: Build the foundation

### Command structure

- [x] Add the root-level `dot` command.
- [x] Add `lib/cli.sh` for help, prompts, and common output.
- [x] Add `lib/platform.sh` for macOS, WSL, and Omarchy detection.
- [x] Add `lib/manifest.sh` for loading and checking plain-text manifests.
- [x] Add `lib/install.sh` for shared install planning and flow.
- [x] Add `lib/doctor.sh` for system and repository checks.
- [x] Keep all shell code compatible with Bash 3.2.
- [x] Add command-specific help and invalid-argument errors.
- [x] Add consistent `[plan]`, `[ok]`, `[skip]`, `[warn]`, and `[error]` output.

### Application manifests

- [x] Add `manifests/core`.
- [x] Add `manifests/development`.
- [x] Add `manifests/optional`.
- [x] Add the agreed core application IDs.
- [x] Add the agreed development application IDs.
- [x] Reject duplicate or unknown manifest entries.

### Platform installers

- [x] Add `installers/macos.sh`.
- [x] Add `installers/wsl.sh`.
- [x] Add `installers/omarchy.sh`.
- [x] Define how every application ID reports installed, missing, or unsupported.
- [x] Map macOS applications to Homebrew where appropriate.
- [x] Make the macOS `zsh` mapping check and install Zap as its shell foundation.
- [x] Map WSL applications to its native package tools.
- [x] Make the WSL `zsh` mapping check and install Zap as its shell foundation.
- [x] Prefer supported `omarchy-*` commands on Omarchy.
- [x] Make the Omarchy `zsh` mapping install and configure `omarchy-zsh`.
- [x] Fall back to Arch package tools only when Omarchy has no setup command.

### Commands

- [x] Implement `dot doctor`.
- [x] Implement `dot plan`.
- [x] Implement `dot install`.
- [x] Implement `dot bootstrap` planning without deployment.
- [x] Add `--include optional`.
- [x] Add `--yes` without allowing it to imply adoption.
- [x] Ensure install skips existing applications and never upgrades them.

### Test foundation and first TDD cycles

- [x] Add a small Bash test runner at `tests/run` before implementing command behavior.
- [x] Add temporary-home and assertion helpers.
- [x] Add recording package-manager fakes under `tests/fakes/bin/`.
- [x] Write a failing public-command test for platform detection, then implement it.
- [x] Write failing public-command tests for blank lines and comments in manifests, then implement them.
- [x] Write failing public-command tests for duplicate and unknown entries, then implement them.
- [x] Write failing public-command tests for installed, missing, and unsupported plans, then implement them.
- [x] Test that planning does not modify the system.
- [x] Run Bash and Zsh syntax checks.
- [x] Run ShellCheck where available.
- [x] Check config parsing, canonical links, and unwanted absolute paths.

### Phase exit

- [x] Confirm `dot help`, `doctor`, `plan`, and install planning work on WSL.
- [x] Confirm all tests use temporary paths and leave the real home directory alone.

## Phase 2: Add safe deployment

### Stow planning

- [x] Add `lib/deploy.sh`.
- [x] Plan the `global/` layer before the current platform layer.
- [x] List every target link before changing anything.
- [x] Detect normal files, unrelated links, broken links, and repository-owned links.
- [x] Treat old links into this repository as safe legacy links that can be replaced.
- [x] Ensure legacy-link replacement does not require adoption.
- [x] Refuse all unrelated conflicts during a normal deploy.
- [x] Verify that platform layers do not replace files owned by `global/`.

### Deployment commands

- [x] Implement `dot deploy`.
- [x] Implement `dot deploy --adopt`.
- [x] Implement `dot undeploy`.
- [x] Make repeated deployment produce no unnecessary changes.
- [x] Verify links after deployment.
- [x] Make undeploy remove only links owned by this repository.
- [x] Keep undeploy from uninstalling applications or deleting normal files.

### Adoption and backups

- [x] Add `lib/backups.sh`.
- [x] Store backups under `~/.local/state/dot/backups/<timestamp>/`.
- [x] Preserve paths relative to the home directory.
- [x] Show every conflict and backup destination before adoption.
- [x] Copy all conflicts successfully before changing any targets.
- [x] Never call Stow's native `--adopt` option.
- [x] Implement `dot backups list`.
- [x] Implement `dot backups restore <timestamp>`.
- [x] Implement `dot backups remove <timestamp>`.
- [x] Implement `dot backups prune --older-than <days>d`.
- [x] Require confirmation for restore, remove, and prune.
- [x] Refuse unrelated restore conflicts.
- [x] Keep restored backups until explicitly removed.

### Bootstrap

- [x] Connect successful installation to deployment in `dot bootstrap`.
- [x] Show one combined plan before bootstrap changes anything.
- [x] Ask for confirmation once.
- [x] Keep bootstrap from adopting files automatically.
- [x] Run final checks after bootstrap.

### Deployment TDD cycles

Write each failing fake-home test before implementing its behavior:

- [x] Test a clean fake-home deploy, then implement it.
- [x] Test a repeated deploy, then make it do no unnecessary work.
- [x] Test conflict refusal without partial changes, then implement it.
- [x] Test adoption and backup contents, then implement them.
- [x] Test backup restoration, then implement it.
- [x] Test backup removal and age-based pruning, then implement them.
- [x] Test undeployment, then implement it.
- [x] Test safe replacement of old repository-owned Stow links, then implement it.
- [x] Test refusal to remove unrelated links, then implement it.
- [x] Test command failure midway and prove it leaves no partial changes.

### Phase exit

- [x] Confirm the full deployment lifecycle passes against a temporary home directory.
- [x] Confirm a failed preflight leaves the target unchanged.

## Phase 3: Restructure the existing configuration

### Shared layout

- [ ] Create `global/`.
- [ ] Create `platforms/macos/`.
- [ ] Create `platforms/wsl/`.
- [ ] Create `platforms/omarchy/`.
- [ ] Move files with history-preserving Git moves where practical.
- [ ] Keep the old layout until the new fake-home deployment passes.

### Zsh

- [ ] Add a shared `.zshrc` entry point.
- [ ] Move shared aliases into `global/`.
- [ ] Move shared exports into `global/`.
- [ ] Move shared functions into `global/`.
- [ ] Add the macOS Zap foundation.
- [ ] Add the WSL Zap foundation.
- [ ] Add the `omarchy-zsh` foundation.
- [ ] Load shared personal settings after each platform foundation.
- [ ] Install or source autosuggestions on Omarchy.
- [ ] Install or source autopair on Omarchy.
- [ ] Install or source history substring search on Omarchy.
- [ ] Keep Omarchy as the owner of FZF, eza, zoxide, Starship startup, and syntax highlighting.
- [ ] Keep `git-open` available without duplicating other shell behavior.
- [ ] Keep the fnm-based `pi()` wrapper only on macOS and WSL.
- [ ] Remove the custom SSH-agent plugin from Omarchy.
- [ ] Remove Zap Supercharge from Omarchy.
- [ ] Remove the broken Zap plugin updater.
- [ ] Fix the broken zoxide aliases.
- [ ] Remove duplicate LazyGit aliases.
- [ ] Remove global Kitty-specific aliases.
- [ ] Move `ollama.exe`, `/snap/bin`, and display forwarding to WSL.
- [ ] Move Homebrew flags and paths to macOS.
- [ ] Move `AWS_PROFILE` and similar personal defaults to ignored local files.
- [ ] Remove hard-coded usernames and home directories.

### Starship

- [ ] Move the existing Starship config into `global/`.
- [ ] Validate the config with Starship.
- [ ] Verify the Arch symbol and required glyphs.
- [ ] Check Kubernetes detection behavior.
- [ ] Confirm acceptable shell startup time.

### VS Code

- [ ] Create one canonical shared settings file.
- [ ] Remove the hard-coded Poetry virtualenv path.
- [ ] Remove hard-coded macOS user paths.
- [ ] Add the macOS settings-path adapter link.
- [ ] Add the Omarchy/Linux settings-path adapter link.
- [ ] Preserve `styles.css` in a shared location.
- [ ] Verify the custom CSS extension's path rules on both platforms.
- [ ] Add the correct platform-specific CSS path only if one shared value cannot work.
- [ ] Keep VS Code extension installation deferred.

### RTK

- [ ] Make `global/.config/rtk/config.toml` canonical.
- [ ] Use the canonical Linux path directly.
- [ ] Add a macOS `Library/Application Support` adapter link.
- [ ] Stop creating a macOS `Library` tree on Linux.
- [ ] Validate the config with RTK.

### Ghostty and fonts

- [ ] Keep the current Ghostty config working on macOS.
- [ ] Prepare Omarchy Ghostty config to use Omarchy theme files.
- [ ] Let Omarchy control its Ghostty font.
- [ ] Remove explicit FiraCode settings from Omarchy-managed application config.
- [ ] Keep macOS font choices independent.
- [ ] Preserve intentional padding and key behavior unless VM testing rejects it.

### Cleanup

- [ ] Update `.gitignore` for local platform settings and runtime state.
- [ ] Remove the old Makefile after `dot` covers its needed behavior.
- [ ] Remove old package directories after the new layout is proven.
- [ ] Confirm unrelated TDD skill changes remain untouched.

### Phase exit

- [ ] Verify expected macOS, WSL, and Omarchy paths in fake homes.
- [ ] Confirm shared files have no platform-specific absolute paths.
- [ ] Confirm WSL still works before merging the restructure.

## Phase 4: Validate WSL and macOS

### WSL

- [ ] Run `dot doctor`.
- [ ] Run `dot plan` and review every change.
- [ ] Run the one-time legacy-link migration.
- [ ] Use adoption only for real conflicting files.
- [ ] Start a clean Zsh session.
- [ ] Check Zap and retained plugins.
- [ ] Check Starship, zoxide, FZF, aliases, RTK, and the Pi wrapper.
- [ ] Run bootstrap again and confirm a clean result.
- [ ] Test backup restore and redeploy.
- [ ] Test undeploy and redeploy.

### macOS

- [ ] Confirm Python is not required by `dot`.
- [ ] Pull the completed migration on one Mac.
- [ ] Run `dot doctor` and `dot plan`.
- [ ] Replace legacy links that point into this repository.
- [ ] Use adoption only for real conflicting files.
- [ ] Check Zap installation and startup.
- [ ] Check autosuggestions, autopair, history search, and `git-open`.
- [ ] Check Starship and zoxide.
- [ ] Check VS Code and RTK adapter paths.
- [ ] Check Homebrew application detection.
- [ ] Test backup restore, undeploy, and redeploy.
- [ ] Repeat on the second Mac after the first passes.

### Phase exit

- [ ] Run all shell, manifest, and fake-home tests.
- [ ] Record any manual follow-up that cannot be automated.
- [ ] Confirm WSL and at least one Mac pass their smoke tests.

## Phase 5: Test Omarchy in a VM

### Base setup

- [ ] Install the released Omarchy 4 image in a disposable VM.
- [ ] Clone this repository.
- [ ] Run `dot doctor`.
- [ ] Run `dot plan`.
- [ ] Run `dot bootstrap` after reviewing the plan.
- [ ] Fix any package mapping that bypasses a supported Omarchy command.
- [ ] Run bootstrap again and confirm no unnecessary work.

### Zsh

- [ ] Confirm `omarchy-zsh` is installed and active.
- [ ] Confirm Omarchy commands are available.
- [ ] Confirm Omarchy completions work.
- [ ] Confirm autosuggestions work.
- [ ] Confirm automatic pairing works.
- [ ] Confirm history substring search works.
- [ ] Confirm `git-open` works.
- [ ] Confirm FZF has only one owner.
- [ ] Confirm eza aliases have only one owner.
- [ ] Confirm syntax highlighting loads last and works.
- [ ] Confirm Zsh starts without errors.

### Desktop applications

- [ ] Install and select Ghostty through Omarchy.
- [ ] Install VS Code through Omarchy.
- [ ] Confirm Omarchy controls the terminal and VS Code colors.
- [ ] Confirm Omarchy controls the selected font.
- [ ] Confirm the Starship prompt renders correctly.
- [ ] Confirm VS Code custom CSS works.
- [ ] Confirm Omarchy's menu and updater still work.

### Dracula theme

- [ ] Test the established community Dracula themes.
- [ ] Check their Ghostty, VS Code, Hyprland, and shell coverage.
- [ ] Review their source before installation.
- [ ] Choose whether to use, pin, or fork one.
- [ ] Add only the selected theme setup to the repository.

### Omarchy and Hyprland configuration

- [ ] Customize monitors, input, bindings, look and feel, and autostart as needed.
- [ ] Customize the Omarchy shell settings as needed.
- [ ] Review user-owned files changed during setup.
- [ ] Add only intentional files to `platforms/omarchy/`.
- [ ] Add terminal selection if intentionally changed.
- [ ] Add theme, hooks, and XCompose only when intentionally changed.
- [ ] Leave untouched generated defaults untracked.
- [ ] Deploy the tracked Omarchy files as live links.
- [ ] Check whether an Omarchy update creates understandable Git changes.

### Full VM acceptance

- [ ] Reboot and confirm Omarchy starts normally.
- [ ] Confirm the menu and updater work.
- [ ] Confirm Zsh and Omarchy features work together.
- [ ] Confirm Ghostty and VS Code launch correctly.
- [ ] Confirm theme and font changes work through Omarchy.
- [ ] Confirm custom CSS remains active.
- [ ] Confirm `dot doctor` has no unexpected failures.
- [ ] Test adoption, restore, undeploy, and redeploy.
- [ ] Save the final manual VM checklist for the physical migration.

## Phase 6: Move to the physical Omarchy machine

### Before installation

- [ ] Back up important personal files separately.
- [ ] Confirm the dotfiles repository is pushed and clean.
- [ ] Keep the VM checklist available from another device.

### Installation

- [ ] Install Omarchy 4 on the physical machine.
- [ ] Clone this repository.
- [ ] Run `dot doctor`.
- [ ] Run `dot plan` and review it.
- [ ] Run `dot bootstrap`.
- [ ] Apply the tested Omarchy and Hyprland configuration.
- [ ] Reboot and run `dot doctor` again.

### Manual account setup

- [ ] Recreate or copy SSH keys manually.
- [ ] Authenticate GitHub CLI.
- [ ] Restore Git identity settings without committing secrets.
- [ ] Authenticate cloud and work tools as needed.
- [ ] Authenticate any agent tools already supplied by Omarchy.

### Final checks

- [ ] Run the full VM checklist on the physical machine.
- [ ] Confirm fonts, theme, Ghostty, VS Code, and custom CSS.
- [ ] Confirm Zsh and all retained behavior.
- [ ] Run bootstrap a second time and confirm a clean result.
- [ ] Confirm WSL and both Macs still use their correct platform layers.

## Deferred backlog

- [ ] Add VS Code extension installation if manual setup becomes annoying.
- [ ] Add Pi installation only if Omarchy stops providing it adequately.
- [ ] Add more GUI applications only when they are clearly part of every setup.
- [ ] Add machine-specific layers if a second Omarchy machine appears.
- [ ] Add Omarchy config capture only if manual tracking becomes repetitive.
- [ ] Add an application upgrade command only if there is a clear safe workflow.
