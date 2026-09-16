# Configuration composition

Implemented for TOML. This document began as a proposal for VS Code settings;
Herdr is the first application using the mechanism. VS Code is unchanged.

## Precedence

For each destination, global is the base and the active platform is more specific:

| Sources | Deployment |
| --- | --- |
| Global file only | Link to global |
| Platform file only | Link to platform |
| Both ordinary files | Link to platform; no merge |
| Global file + platform merge file | Generate merged output and link to it |
| Platform full file + platform merge file | Full file wins; warn and ignore merge file |

Directories combine their children, but file/directory collisions fail. The
full-file/merge ambiguity is a warning in both deploy and doctor, not a failure.
Ignored merge files are not parsed and do not require a base or supported format.

## Marking a merge

```text
global/.config/herdr/config.toml
platforms/omarchy/.config/herdr/config.merge.toml
```

Both contribute to `~/.config/herdr/config.toml`. The merge marker is removed
from the deployed filename; the overlay itself is not linked into HOME.
Ubuntu needs no overlay and links the global config directly.

Merge markers use `NAME.merge.FORMAT` and are reserved for platform layers.
Active merges require a global base and regular file inputs. Unsupported formats,
missing bases, and invalid input fail before deployment changes anything.
TOML is the only supported format initially.

## Merge semantics

- If both values are tables/objects, merge their keys recursively.
- Otherwise, take the platform value, including when its type differs.
- Arrays replace entirely, including arrays of tables.
- No deletion operators or special array operations.
- Validate syntax, not the application's schema: a syntactically valid but
  nonsensical platform setting is the user's responsibility.

Generated formatting/comments are not preserved. Comments remain in the source
files; the generated config has a header identifying it as generated.

## Generated output and daily use

Outputs live at:

```text
${XDG_STATE_HOME:-~/.local/state}/dot/generated/<repo-id>/<platform>/<destination>
```

The repo ID is derived from the canonical clone path. Platforms and different
clones never share outputs. Sibling `<platform>.json` metadata records output
checksums. State is not tracked in Git. Ordinary files still link directly to
repository sources; only composed files use generated storage.

```bash
less ~/.config/herdr/config.toml  # view the result through its normal symlink
# edit global config.toml and/or platform config.merge.toml
./dot deploy --dry-run --verbose # preview; includes changed merge source/output paths
./dot deploy
herdr server reload-config
```

Deploy renders active merges before touching deployed files, replaces changed
outputs atomically, and does not rewrite unchanged files/links. Generated files
have mode `0600`. Doctor renders and compares without updating output.

Editing the deployed path edits generated output, not its sources. Such edits
are detected through checksums and require explicit `--replace`, even on a TTY.
Dot snapshots the edited bytes before regenerating; backing up only the symlink
would not preserve them. Retained output is protected even when its HOME link
has been removed. Existing unrelated HOME conflicts retain the normal backup
and replacement behavior.

Removing an overlay restores the global link on the next deploy. Undeploy removes
managed links but retains output/checksums, including edits. It can find recorded
generated destinations after both source files are removed, and needs neither
UV nor valid TOML syntax to unlink them. There is no automatic state pruning.
`dot add` skips managed generated links and does not create/extract overlays.

## Implementation and dependencies

- `lib/files.py`: layer selection, Stow exclusions, links, backup integration.
- `lib/composition.py`: marker recognition, helper invocation, generated storage
  and checksums; standard library only.
- `lib/merge_config.py`: UV script with inline, pinned TOML dependencies and
  format adapters. Add future adapters here and enable their suffixes in
  `composition.py`; the deployment lifecycle is format-independent.

UV is selected by the core manifests: Homebrew on macOS, the package manager on
Omarchy, and a pinned/checksummed upstream executable on Ubuntu. The TOML helper
requires Python 3.9+; UV manages its isolated environment. Normal filesystem
commands continue to use Python 3.7+ and its standard library.

First use may download dependencies or a compatible interpreter. Consequently,
composition during doctor or dry-run can populate UV's cache, but never writes
repository, deployed configuration, or deployment state. Offline use requires
preparing that environment beforehand. UV/library failures stop composition with
an actionable error; they never fall back to silently replacing the whole file.

Deployment remains nontransactional: completed writes/links are kept if a later
operation fails. Backups and checksums protect replacement, not rollback.
