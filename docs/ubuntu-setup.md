# Ubuntu: SSH-first setup

This profile targets Ubuntu 26.04 / Xubuntu on `bebop`, while keeping the
platform files free of hostnames and hardware-specific settings. Other Ubuntu
versions are detected but their package availability has not been validated.
XFCE, LightDM, X11, monitor settings, SSH server configuration, and the current
login shell are not modified by `dot`.

## Application selection

`manifests/ubuntu/core` and `manifests/ubuntu/development` replace their shared
selection groups. macOS and Omarchy retain their existing selections.

- APT: Stow, Zsh, Starship, zoxide, FZF, fd-find, ripgrep, bat, eza, Git, gh.
- Zap and Zsh plugins: cloned into `~/.local/share/zap` (or `XDG_DATA_HOME`).
  Zsh installation includes Supercharge and syntax highlighting; eza installation
  includes the `zap-zsh/exa` plugin (which now uses eza). The other selected plugins
  are autosuggestions, autopair, and history-substring-search.
- git-open: cloned from `paulirish/git-open` into the Zap plugins directory;
  its executable directory is added to the interactive Zsh PATH.
- RTK: pinned upstream v0.49.0 binary archive.
- Herdr: pinned upstream v0.9.0 binary. The existing executable on this machine
  is reused, not overwritten or upgraded.

RTK/Herdr downloads support x86_64 and aarch64, verify pinned SHA-256 digests,
and install into `~/.local/bin`. The source repositories are
[rtk-ai/rtk](https://github.com/rtk-ai/rtk) and
[herdrdev/herdr](https://github.com/herdrdev/herdr). Versions, assets, and digests
are explicit in `installers/ubuntu.sh`; update them together after verification.
No downloaded setup scripts run, and RTK agent/shell hooks are not installed.
Zap follows the existing repo's release-v1 branch convention; plugin clones
follow upstream HEAD, rather than a fully pinned dependency lockfile.

APT requests sudo when necessary. It does not automatically refresh package
indexes, perform a distribution upgrade, add repositories, or change the
login shell. Refresh indexes separately before the first real install.

Ghostty, VS Code, and Nerd Fonts are not selected. Fonts must be configured
on the **SSH client's terminal** to render the shared Starship glyphs.
Global deployment still includes inactive Ghostty shared settings and VS Code
assets, but Ubuntu supplies neither an active Ghostty config nor a Code/User
settings link. No Omarchy/Hyprland/UWSM configuration is deployed.

## Shell behavior

The Ubuntu foundation uses `zap-zsh/supercharge` for completions, menu selection,
case-insensitive matching, history options, and convenience keybindings, matching
macOS. `zap-zsh/exa` provides directories-first/icon-aware listings and the `ll`,
`la`, and `tree` aliases. It also initializes the other installed Zsh plugins,
FZF, Starship, and zoxide. It uses only local plugin files
during startup; run `dot install` to obtain missing plugins. Syntax highlighting
loads last. FZF integration requires a version supporting `fzf --zsh` (the
Ubuntu 26.04 package does).

Ubuntu aliases map `fd` to `fdfind` and `bat` to `batcat`. The shared `cat` and
`catt` aliases then use bat too. These are **interactive aliases**, not shims
for scripts. Installer probes recognize the actual Ubuntu executable names.
The ripgrep probe requires `/usr/bin/rg` so Pi's private binary does not mask a
missing command in ordinary SSH sessions.

Existing fnm/Node is initialized from `~/.local/share/fnm` without hardcoding
a Node version. fnm and Node themselves are not installed by this profile.
The minimal `.zshenv` also exposes `~/.local/bin` to noninteractive SSH commands,
so `ssh bebop herdr` can resolve the executable after Zsh becomes the login shell.
Plugins, fnm, and prompt initialization stay in interactive `.zshrc` only.

Ubuntu preserves the inherited SSH agent environment. It does not start an
agent, add keys, or change `SSH_AUTH_SOCK`. Agent forwarding is not enabled by
this configuration; choose it separately on trusted connections if needed.

Existing shared convenience aliases for lazygit, Neovim, and bob remain, but
those applications (and the ffmpeg helper's dependency) are not selected.

## Herdr

`platforms/ubuntu/.config/herdr/config.toml` carries the personal Omarchy/tmux
bindings, terminal palette, pane preferences, and hostname-aware title.
It leaves system toast delivery and experimental Kitty graphics at defaults
instead of importing the desktop-specific overrides. Prefix bindings provide
alternatives for shortcuts that an SSH client cannot encode distinctly.

At inspection time the machine's config contained only `onboarding = false`.
The fuller repo config will therefore be a deployment conflict, **not silently
merged**. Review the diff before approving backup and replacement. Nothing
autostarts Herdr, changes its running server, or modifies XFCE shortcuts.

## Safe first installation

These steps are manual; implementing this profile does not execute them:

1. Keep the current SSH/Bash connection open.
2. Review `./dot install --dry-run --verbose`.
3. Refresh APT indexes with `sudo apt-get update`, then run `./dot install`.
4. Run `bash tests/run`. Real filesystem tests require Stow; the Ubuntu shell
   smoke test requires Zsh and uses isolated HOME/plugin/command fixtures.
5. Review `./dot deploy --dry-run --verbose`, especially the Herdr conflict.
6. Deploy after reviewing conflicts. Use `--replace` only after approving the
   files it will back up; do not use it blindly.
7. Run `./dot doctor --verbose` and test `zsh -il` in the existing connection:
   check `node --version`, `npm --version`, `fnm current`, `herdr --version`,
   `fd --version`, `bat --version`, completion, history, and the prompt.
8. Only after that works, optionally change the login shell manually with
   `chsh -s "$(command -v zsh)"`. Open a second SSH connection and test it before
   closing the first. Also test a noninteractive command such as
   `ssh bebop 'herdr --version'`.
9. Repeat deploy and install checks to confirm idempotency.

If an SSH client reports an unknown terminal type, install its appropriate
terminfo on the server rather than globally forcing `TERM` in shell startup.
