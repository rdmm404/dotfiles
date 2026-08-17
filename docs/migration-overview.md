# Dotfiles migration overview

## Summary

We are moving these dotfiles from Ubuntu in WSL to Omarchy 4 while keeping the same repository useful on two macOS machines and during the WSL transition.

The end result will have:

- one shared configuration layer;
- small macOS, WSL, and Omarchy layers;
- a simple `dot` command for setup and maintenance;
- GNU Stow for linking files into the home directory;
- a short universal list of applications;
- safe previews, backups, and rollback;
- tracked Omarchy and Hyprland preferences after they are tested in a VM.

## Why we are doing this

The current repository mixes macOS, WSL, and Linux paths inside the same packages. Its Makefile also assumes `apt`, `yum`, and macOS-style directories, so it cannot safely set up Omarchy.

This migration gives every operating system a clear place for its differences without copying shared settings. It also makes a fresh setup repeatable without trying to replace Omarchy's own setup tools.

## Objectives

1. Keep the repository working on WSL throughout the transition.
2. Keep supporting both macOS devices.
3. Make Omarchy the owner of system-wide choices such as themes and fonts.
4. Keep personal settings such as the Starship prompt and VS Code custom CSS.
5. Make setup safe to preview, repeat, and undo.
6. Use Omarchy commands when Omarchy provides them.
7. Keep the code small and easy to read.
8. Test the setup in a disposable Omarchy VM before using the physical machine.

## Not included right now

- Secret or credential migration
- VS Code extension installation
- Pi installation
- Automatic capture of Omarchy configuration
- Multiple Omarchy machine profiles
- Automatic application upgrades
- A fully automated graphical VM test

Secrets will be set up again manually. Deferred features can be added only if a real need appears.

## Repository shape

```text
dot
lib/
installers/
manifests/
global/
platforms/
  macos/
  wsl/
  omarchy/
tests/
```

Files are deployed in this order:

```text
global -> current platform
```

A platform layer may add a platform file, but it must not silently replace a file owned by `global/`. Shared entry files will load platform-specific fragments when needed.

## Decisions

### General approach

- Adopt Omarchy as the new base instead of recreating WSL exactly.
- Continue supporting macOS, WSL, and Omarchy from one repository.
- Restructure the repository rather than preserve the current package layout.
- Replace the Makefile with one root-level `dot` command.
- Keep GNU Stow as the file-linking tool.
- Start setup only after the repository has been cloned.
- Use a staged setup, plus one full `dot bootstrap` command.
- Show a plan and ask before making changes.

### Configuration layers

- `global/` contains settings shared by every system.
- `platforms/macos/`, `platforms/wsl/`, and `platforms/omarchy/` contain only platform differences.
- There is no machine-specific layer for now because there will be only one Omarchy machine.
- Files with the same contents but different home-directory paths use small platform adapter links to one canonical file.
- VS Code settings will have one canonical copy; the hard-coded Poetry virtualenv path will be removed.
- RTK will also have one canonical config instead of making Linux depend on a macOS `Library` path.

### Shell

- Zsh remains the main interactive shell everywhere.
- macOS and WSL keep Zap.
- Omarchy uses `omarchy-zsh` as its foundation.
- Omarchy owns FZF, eza, Starship startup, zoxide, syntax highlighting, and Omarchy shell integration.
- Omarchy also gets autosuggestions, autopair, and history substring search, installed without Zap.
- `git-open` remains available as a development tool.
- The custom SSH-agent plugin and Zap Supercharge are not used on Omarchy.
- Shared aliases, exports, and functions load after the platform shell foundation.
- The fnm-based `pi()` wrapper remains only on macOS and WSL.
- WSL-only commands such as `ollama.exe`, `/snap/bin`, and display forwarding move out of shared config.
- macOS-only Homebrew and `/Users/...` settings move out of shared config.
- `AWS_PROFILE` and similar personal defaults belong in ignored local files.
- Historical or broken aliases will be removed instead of preserved blindly.

### Applications

- Application choices live in universal plain-text manifests with one logical name per line.
- Small platform installers decide how each logical application is installed.
- Omarchy installers prefer supported `omarchy-*` commands, then use package tools only when needed.
- `core` and `development` are installed by default; `optional` requires an explicit choice.
- Installation only fills missing applications. It does not upgrade existing ones.
- Pi and VS Code extension installation are deferred.

Initial core applications:

```text
stow
zsh
starship
zoxide
fzf
fd
rg
bat
eza
nerd-font
zsh-autosuggestions
zsh-autopair
zsh-history-substring-search
```

Initial development applications:

```text
git
gh
ghostty
vscode
rtk
git-open
```

### Appearance

- Preserve the current Starship prompt.
- Let Omarchy control its system, terminal, and VS Code theme.
- Let Omarchy control the font on the Omarchy machine.
- Keep macOS font choices independent.
- Preserve the VS Code custom CSS.
- Test community Dracula themes in the VM before choosing, pinning, or forking one.

### Omarchy and Hyprland

- Wait for the VM before adding Omarchy-generated configuration.
- Track intentional changes under `~/.config/hypr` and `~/.config/omarchy`.
- Also track deliberate terminal selection, theme, hooks, and XCompose changes when used.
- Do not commit every untouched generated default just because it exists.
- Use live Stow links, so changes made by Omarchy are visible as Git changes.
- Capture the first set of Omarchy files manually; do not build a capture command yet.

### Safety

- A normal deploy refuses existing-file conflicts.
- `dot deploy --adopt` previews conflicts, backs up existing files, and then deploys tracked files.
- Do not use Stow's native `--adopt` behavior.
- Backups live under `~/.local/state/dot/backups/<timestamp>/` and keep home-relative paths.
- Backups are never deleted automatically.
- Provide commands to list, restore, remove, and prune backups.
- `dot undeploy` removes only links owned by these dotfiles. It does not uninstall applications or delete normal files.

### Implementation

- Write `dot` and its modules for Bash 3.2 so they run with the Bash bundled on macOS.
- Keep `dot` small and split behavior across focused files under `lib/`.
- Keep package-manager commands in `installers/`.
- Avoid clever shell code and avoid building a custom package manager.
- Leave the existing unrelated TDD skill changes alone.

### Testing

- Prefer test-driven development: write a failing behavior test, make it pass with the smallest change, then clean up.
- Test public `dot` commands and filesystem results instead of private shell functions.
- Avoid a large unit-test suite.
- Run real commands against a temporary home directory and the real Stow executable.
- Put fake package-manager commands first in `PATH` so automated tests never install software.
- Check exit status, resulting files and links, backup contents, and a few important output lines.
- Avoid brittle tests that compare all command output exactly.
- Keep fast checks for Bash and Zsh syntax, ShellCheck, manifests, config parsing, links, and unwanted absolute paths.
- Use real WSL and macOS smoke tests plus the Omarchy VM checklist for behavior that cannot be safely faked.

## Acceptance criteria

The migration is ready for the physical Omarchy machine when:

1. `dot` correctly detects macOS, WSL, and Omarchy.
2. `dot plan` clearly shows intended changes without making them.
3. `dot bootstrap` installs missing core and development tools, then deploys the right layers.
4. Running bootstrap a second time makes no unnecessary changes.
5. A normal deploy refuses conflicts without altering them.
6. Adoption creates a complete backup before replacing conflicts.
7. Backups can be listed, restored, removed, and pruned with confirmation.
8. Undeploy removes only dotfile-owned links.
9. Zsh starts without errors on WSL, macOS, and Omarchy.
10. Omarchy commands, completions, updates, menu, Ghostty, and VS Code still work.
11. The Starship prompt works with the selected Nerd Font.
12. Omarchy controls its font and theme, and VS Code custom CSS still works.
13. Shell checks, manifest tests, and fake-home deployment tests pass.
14. WSL and at least one macOS device pass a manual smoke test.
15. The full setup passes the agreed manual checklist in an Omarchy VM.
