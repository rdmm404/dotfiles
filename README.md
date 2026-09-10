# Dotfiles

This repository uses `dot` to install applications and link shared and
platform-specific configuration on macOS, WSL, and Omarchy.

## Quick start

From a clone of the repository:

```bash
./dot doctor
./dot install
./dot deploy --dry-run --verbose
./dot deploy
```

For first-time setup, the combined command installs the selected applications
and then deploys configuration:

```bash
./dot bootstrap --dry-run --verbose
./dot bootstrap
```

Optional applications can be included with `--include optional`. Deployment
conflicts are reported; use `--replace` only when the existing paths should be
backed up and replaced. There are no routine confirmation prompts. See the
[current CLI specification](docs/dot-cli-spec.md) for deployment, import,
and backup workflows.

## Everyday use

```bash
./dot deploy                              # reconcile links; quiet when unchanged
./dot add ~/.config/my-tool --platform     # import a directory for this platform
./dot add ~/.some-config --global          # import a shared file
./dot deploy --replace                     # back up conflicts, then link repo versions
./dot backups list
./dot backups restore latest
```

`add` imports recursively and links files back into place. It never overwrites
tracked files or stages anything in Git. Preview changes with `--dry-run`.

Run `bash tests/run` for the test suite (requires Python, Stow, and ripgrep).

## Dependencies

- Bash 3.2 or newer
- Python 3.7 or newer, using only the standard library, for filesystem
  commands such as `doctor`, `deploy`, `add`, `undeploy`, and `backups`
- GNU Stow for deployment

`dot install` installs Stow from the core manifest, or install it manually with
`brew install stow` on macOS or your Linux package manager. Install Python
separately if needed; `dot install` itself does not require Python.

The command detects the active platform and deploys `global/` followed by its
platform layer. Automated filesystem tests use a temporary `HOME`.
