# `dot` command specification

## Purpose

`dot` is the single command for checking, installing, deploying, and backing up these dotfiles. It wraps GNU Stow and the native setup tools for each supported platform.

It must run with Bash 3.2 and remain small enough to understand without special shell knowledge.

## Basic rules

- Detect macOS, WSL, or Omarchy automatically.
- Print the detected platform before a command that can make changes.
- Show planned work before doing it.
- Ask for confirmation before installing, adopting, restoring, removing, pruning, or running the full bootstrap.
- Never overwrite an existing file during a normal deploy.
- Be safe to run more than once.
- Return `0` on success, `1` on an operation failure, and `2` for invalid command usage.
- Use clear output labels:

```text
[plan] will install: rtk
[ok]   already installed: rg
[skip] unsupported on WSL: ghostty
[warn] existing file: ~/.zshrc
[error] deploy stopped; no files changed
```

## Commands

### `dot doctor`

Checks whether the current system is ready.

```bash
./dot doctor
```

Checks include:

- supported platform;
- required commands;
- readable manifests;
- valid repository layout;
- broken or unexpected links;
- deploy conflicts;
- shell syntax;
- required application status;
- dirty tracked configuration after an Omarchy update.

It does not change anything.

Output ends with either:

```text
[ok] doctor found no blocking problems
```

or a short list of problems and suggested next commands.

### `dot plan`

Shows what bootstrap would do without changing anything.

```bash
./dot plan
./dot plan --include optional
```

Arguments:

- `--include optional`: include the optional manifest.

Output includes:

- detected platform;
- selected manifests;
- missing, installed, and unsupported applications;
- global and platform layers;
- existing-file conflicts;
- whether adoption would be required.

### `dot install`

Installs missing applications from the universal manifests.

```bash
./dot install
./dot install --include optional
```

Default selection:

```text
core + development
```

Arguments:

- `--include optional`: also install optional applications.
- `--yes`: accept the shown install plan without an interactive prompt.

Behavior:

1. Read logical application names from the selected manifests.
2. Ask the active platform installer for each application's status.
3. Show the plan.
4. Ask for confirmation unless `--yes` was given.
5. Install only missing applications.
6. Report failures without hiding successful work.

It does not upgrade installed applications and does not deploy configuration.

### `dot deploy`

Links the shared and current-platform configuration into the home directory.

```bash
./dot deploy
./dot deploy --adopt
./dot deploy --yes
```

Arguments:

- `--adopt`: back up conflicting files, then deploy tracked versions.
- `--yes`: accept a safe, conflict-free plan without prompting. It does not imply `--adopt`.

Behavior:

1. Plan `global/` first and the detected platform second.
2. Check every target before changing anything.
3. Without `--adopt`, stop if a normal file or unrelated link conflicts.
4. With `--adopt`, show every conflict and backup destination.
5. Ask for confirmation.
6. Copy conflicts into a timestamped backup while keeping home-relative paths.
7. Use Stow to create the links.
8. Verify the created links.

Do not call GNU Stow's native `--adopt` option.

### `dot bootstrap`

Runs the complete first-time setup.

```bash
./dot bootstrap
./dot bootstrap --include optional
./dot bootstrap --yes
```

Arguments:

- `--include optional`: include optional applications.
- `--yes`: accept the full shown plan without another prompt. Existing-file conflicts still stop deployment; it does not imply `--adopt`.

Behavior:

1. Run readiness checks.
2. Build one combined install and deploy plan.
3. Show the entire plan.
4. Ask once for confirmation.
5. Install missing applications.
6. Deploy configuration only if installation completed well enough to do so safely.
7. Run final checks and print any manual follow-up.

Bootstrap never adopts existing files automatically. The user must run `dot deploy --adopt` separately after reviewing conflicts.

### `dot undeploy`

Removes links created by the selected global and platform layers.

```bash
./dot undeploy
./dot undeploy --yes
```

Arguments:

- `--yes`: accept the shown unlink plan without prompting.

Behavior:

- show every layer and link that will be removed;
- ask for confirmation;
- use Stow to remove owned links;
- leave applications, normal files, directories, backups, and repository files alone;
- warn instead of deleting a link that no longer points into this repository.

### `dot backups list`

Lists adoption backups.

```bash
./dot backups list
```

Output includes timestamp, size, and file count. It changes nothing.

### `dot backups restore`

Restores one adoption backup.

```bash
./dot backups restore <timestamp>
./dot backups restore <timestamp> --yes
```

Arguments:

- `<timestamp>`: an identifier printed by `backups list`.
- `--yes`: accept the restore plan without prompting.

Behavior:

- show the files to restore;
- allow replacement of links owned by this repository;
- refuse unrelated conflicts rather than overwrite them;
- ask for confirmation;
- restore original home-relative paths;
- keep the backup after a successful restore.

### `dot backups remove`

Deletes one saved backup.

```bash
./dot backups remove <timestamp>
./dot backups remove <timestamp> --yes
```

It shows the backup's size and file count, then asks for confirmation. This cannot be undone.

### `dot backups prune`

Deletes backups older than a chosen age.

```bash
./dot backups prune --older-than 30d
./dot backups prune --older-than 30d --yes
```

Arguments:

- `--older-than <days>d`: required age, such as `30d` or `90d`.
- `--yes`: accept the shown deletion list without prompting.

It never removes anything unless at least one backup matches and the user confirms.

### Help

```bash
./dot help
./dot help <command>
./dot --help
```

Help shows short examples and all accepted arguments. Invalid arguments print the relevant command help.

## Manifests

```text
manifests/core
manifests/development
manifests/optional
```

Format:

```text
# Comments begin with #.
# Blank lines are ignored.

stow
zsh
rg
```

Rules:

- one logical application name per line;
- no versions or platform commands;
- duplicate names are an error;
- names must be known by every platform installer, even if that platform marks one unsupported.

## Platform installer contract

```text
installers/macos.sh
installers/wsl.sh
installers/omarchy.sh
```

Each installer provides two operations for a logical application:

1. report `installed`, `missing`, or `unsupported`;
2. install a missing supported application.

Omarchy prefers `omarchy-*` setup commands. macOS prefers Homebrew. WSL uses its native package tools and may mark desktop applications as externally managed or unsupported.

## Code structure

```text
dot                     command parsing and dispatch only
lib/cli.sh              help, prompts, and common output
lib/platform.sh         platform detection
lib/manifest.sh         plain-text manifest loading and checks
lib/install.sh          shared install planning and flow
lib/deploy.sh           Stow planning, conflict checks, and undeploy
lib/backups.sh          backup list, restore, remove, and prune
lib/doctor.sh           checks and final reports
installers/macos.sh     Homebrew mappings
installers/wsl.sh       WSL mappings
installers/omarchy.sh   Omarchy and Arch mappings
tests/                  shell and fake-home tests
```

Coding rules:

- Bash 3.2-compatible syntax;
- small functions with one clear job;
- quote paths and arguments;
- no `eval`;
- no associative arrays or modern-only Bash helpers;
- keep filesystem work in shared modules;
- keep platform commands in installers;
- do not hide command failures;
- pass ShellCheck;
- test all file-changing behavior against a temporary home directory.

## Testing strategy

### Development loop

Use test-driven development for each public behavior:

1. Add a small test that describes the expected command result.
2. Run it and confirm it fails for the expected reason.
3. Add the smallest implementation that makes it pass.
4. Run the full fast test suite.
5. Clean up the code without changing behavior.

Do not unit-test private shell functions unless a complex pure function appears and cannot be covered clearly through the CLI.

### Fast checks

Run these without network access, package installation, or changes to the real home directory:

- `bash -n` for `dot`, `lib/`, and `installers/`;
- ShellCheck where available;
- `zsh -n` for Zsh configuration;
- manifest validation;
- Starship and RTK parsing;
- canonical-link checks;
- checks for unwanted hard-coded `/Users/...` and `/home/...` paths.

### Command and filesystem tests

Invoke the real `./dot` command with a temporary `HOME` and real Stow. Cover:

- clean and repeated deployment;
- normal-file and unrelated-link conflicts;
- safe replacement of old repository-owned links;
- adoption and backup creation;
- restore, remove, and prune behavior;
- undeployment;
- failure without partial changes.

Assert exit codes, files, links, backup contents, and only the important output lines. Do not compare complete output snapshots.

### Installer tests

Automated tests must not call real Homebrew, Pacman, or Omarchy installers. Put recording fakes first in `PATH`, invoke the public command, and verify the chosen platform command and arguments.

Use real package installation only during WSL/macOS smoke tests or in the disposable Omarchy VM.

### Test layout

```text
tests/run                         small Bash test runner
tests/helpers.sh                  temporary-home and assertion helpers
tests/manifest_test.sh            manifest behavior
tests/install_test.sh             public install and plan flows
tests/deploy_test.sh              deploy and adoption lifecycle
tests/backups_test.sh             restore, remove, and prune flows
tests/installer_contract_test.sh  platform command selection
tests/fixtures/                   test repositories and home trees
tests/fakes/bin/                  recording package-manager commands
```

Do not add a test framework initially. Adopt one only if the small runner becomes harder to maintain than the tests themselves.
