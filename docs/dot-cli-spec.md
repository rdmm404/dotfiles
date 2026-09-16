# `dot` CLI specification

This is the current specification for the implemented, simplified `dot`
command. It is a Bash entry point with Python-backed filesystem operations.

## General contract

- Supported platforms are macOS, Omarchy, and Ubuntu (including Xubuntu);
  the active platform is detected automatically. Ubuntu detection uses
  `ID=ubuntu` in `/etc/os-release`, not merely `ID_LIKE=debian`.
  `DOT_PLATFORM` can explicitly select one of the three platforms.
- `global/` is the base layer; `platforms/<platform>/` takes precedence for
  colliding files. Normal platform files replace the whole global file;
  `.merge.toml` platform files explicitly opt into composition.
- `--dry-run` previews without changing repository, deployed files, or deployment
  state. Composition may prepare UV's dependency/interpreter cache.
- There are no routine confirmation prompts. `dot install` and `dot bootstrap`
  are direct operations. A deploy with conflicts and no `--replace` asks one
  question only when standard input is a TTY; answering yes permits backup and
  replacement. Non-interactive use must pass `--replace` to replace conflicts.
- Successful work is retained if a later step fails. Operations are not
  transactions and do not roll back.
- Invalid command usage exits with status 2; operation failures exit with
  status 1.

The removed `plan`, `--adopt`, and `--yes` interfaces are not part of the
current CLI.

## Commands

### `dot doctor`

```bash
./dot doctor [--verbose]
```

Checks the current deployment and the core, development, and optional
application manifests without changing anything. Missing required applications
or deployment problems fail the check; missing optional applications are
warnings, and unsupported applications are skipped. A full platform file alongside
its merge overlay produces a nonblocking warning; only the full file is used.
Active merges are rendered for validation and compared with deployed output, but
not written. Missing bases, unsupported merge formats, invalid TOML, stale output,
and edited generated files fail the deployment check.

### `dot install`

```bash
./dot install [--include optional] [--dry-run] [--verbose]
```

The default manifests are `core` and `development`; `--include optional` adds
the optional manifest. Installation checks each logical application, installs
only missing supported applications, and does not upgrade installed ones.
`--dry-run` performs the scan only. `--verbose` lists unchanged applications.
Installation is direct and does not require Python.

### `dot bootstrap`

```bash
./dot bootstrap [--include optional] [--dry-run] [--verbose] [--replace]
```

Runs `install` first and then `deploy` with the corresponding options. It is
not a combined transaction: successful installations remain if deployment
fails, and deployment has its normal conflict behavior. An installation
failure prevents the deploy step.

### `dot deploy`

```bash
./dot deploy [--dry-run] [--verbose] [--replace]
```

Plans all non-ignored files in the global and active platform layers, resolves
file precedence, and renders active merges in memory before changing deployment.
GNU Stow with no folding links ordinary files, excluding shadowed sources and
merge inputs. Composed files are linked directly to generated local-state output.
File/directory collisions between layers are errors. `--replace` backs up and
replaces conflicting home paths without prompting. Without it, a conflicting
regular file, directory, or unrelated link is refused unless the one TTY
prompt is answered yes. Edited generated output always requires explicit
`--replace`, even interactively. `--dry-run` never changes deployment;
`--verbose` shows individual paths and changed merges' source/output paths.

A regular target file with identical contents **and permission mode** is
safe to deduplicate: it is replaced by the repository-owned link without a
backup. Existing links owned by this repository are reconciled or relinked to
the current source. Unrelated links are conflicts. Backups made for
replacement are stored under `~/.local/state/dot/backups/<ID>/`.

A platform `NAME.merge.toml` merges global `NAME.toml` and deploys at `NAME.toml`.
Tables merge recursively; all other values (including arrays and type changes)
are replaced by the platform value. There are no deletion operators. Only TOML
is supported initially. A full platform file takes precedence over its merge
file, with a warning; the ignored merge is not parsed or otherwise validated.
Active merges require a global base and file inputs. Merge markers are reserved
for platform layers.

Generated output and checksums live under
`${XDG_STATE_HOME:-~/.local/state}/dot/generated/<repo-id>/`, separated by platform.
The normal application path is a symlink to that output. Outputs are atomically
replaced, with mode `0600`. Their checksums detect local edits, including edits
to retained output after undeploy; `--replace` snapshots those edits before
regeneration. Backups of generated links contain the bytes, not a link to a
file that will change. Missing output can be regenerated automatically.

Removing a merge overlay restores the global link on the next deploy. Generated
output is retained; removing both source files does not automatically prune HOME
links, but `undeploy` can still find recorded generated destinations.

Dot does not support `.stowrc` option files in HOME or the repository, nor
deploying `.stowrc` itself. Use `.stow-local-ignore` for ignore rules instead.

### `dot add`

```bash
./dot add PATH... (--global|--platform) [--dry-run] [--verbose]
```

Imports paths inside `HOME` into the explicitly selected layer. Directories
are traversed recursively; imported leaf files become repository links, while
new repository directories are created as needed.

- Repository-owned source links and this repository's generated links are skipped.
- Existing repository files are never overwritten; differing files are an
  error. Import remains conservative: ownership conflicts with another layer are
  also errors, even though manually authored overlapping files can now deploy.
  `add` does not create merge files or extract overlays from generated output.
- The command does not stage Git changes or create commits.
- Stow ignore rules are honored, and ignored paths are reported as skipped.
- Explicit unmanaged symlink arguments are refused. Nested relative symlinks
  are supported when their targets remain available in the selected layer;
  importing a link without its target is refused.

Paths must be inside `HOME` and outside the repository.
Ignore files are interpreted with Python's `re` engine; arbitrary Perl-only
regex constructs are not guaranteed to be compatible.

### `dot undeploy`

```bash
./dot undeploy [--dry-run] [--verbose]
```

Removes only links owned by this repository from the global and active platform
layers. It leaves normal files, directories, unrelated links, applications,
and repository files alone. Recorded generated links are also removed, including
those whose source files have since been removed. Generated output and checksums
are retained, preserving edits. Unlinking does not need UV or parse TOML inputs.
There is no confirmation prompt.

## Backups

Backups are stored below `~/.local/state/dot/backups/`. These commands do not
prompt; use `--dry-run` to inspect a mutating operation first.

```bash
./dot backups list
./dot backups restore ID [--dry-run] [--replace]
./dot backups remove ID [--dry-run]
./dot backups prune --older-than Nd [--dry-run]
```

`ID` is a backup identifier printed by `list`; `latest` selects the newest
backup by directory modification time for `restore` or `remove`. `prune` removes backups older than the given
number of days, such as `30d`.

Restore refuses unrelated current conflicts. `restore --replace` backs up
those conflicts before restoring them; links owned by this repository may be
replaced, as may directory trees containing only owned links and empty
directories. A restored backup is retained until explicitly removed. Both the
current `manifest.json` plus `files/` format and the legacy
`.dot-backup-roots` backup format are readable.

## Configuration and manifests

Configuration and application selection live in:

```text
global/
platforms/macos/
platforms/omarchy/
platforms/ubuntu/
manifests/core
manifests/development
manifests/optional
```

Manifest files contain one logical application name per line; blank lines and
`#` comments are ignored. Core and development are selected by default.
`manifests/<platform>/<group>` replaces the corresponding shared selection
when present; missing platform groups fall back to the shared manifest.
All selections are validated against the shared `manifests/catalog` and cannot
contain duplicates across selected groups. Doctor and install use the same
selection rules.

Ubuntu overrides core and development for an SSH-first setup: no Ghostty,
VS Code, or server-side Nerd Font installation. See [Ubuntu setup](ubuntu-setup.md)
for package mappings, shell behavior, and installation boundaries.

## Dependencies

- Bash 3.2+ for the command wrapper.
- Python 3.7+ with its standard library for the filesystem planner.
- GNU Stow for `deploy` and the deployment portion of `bootstrap`; it is in
  the core manifest, so `dot install` can install it.
- UV for active TOML merges, installed through the core manifests. A separate
  Python 3.9+ helper declares a pinned `tomlkit` dependency inline; UV prepares its
  environment and may download a compatible Python if needed. First use can
  require network access, including during doctor/dry-run. Ordinary file linking
  and undeploy do not require UV. No TOML package is added to the planner's Python
  environment.

`dot install` can run without Python and may install applications listed in the
manifests, but it does not imply that Python will be installed. Filesystem
commands fail clearly when Python is unavailable.
