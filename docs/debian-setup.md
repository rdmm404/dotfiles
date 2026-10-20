# Debian: SSH-first agent host

Debian 13 uses the shared Zsh, Starship, Herdr and CLI foundation. Platform
selection requires `ID=debian`; Ubuntu and unrelated derivatives remain distinct.

The Debian manifests and shell files reference the existing Ubuntu selections
and shell foundation with repository-relative symlinks. The installer reuses
its APT/Zap/pinned-Linux-binary implementation. Changes to those shared files
apply to both distributions; test both profiles. Debian's `.zshenv` additionally
exposes an existing fnm default Node bin directory for noninteractive SSH.

No desktop configuration, login-shell change, Node installation, agent units,
or Nautilus backup profiles are deployed. Debian deploys Bebop's home/system
backup profile, but never credentials or scheduling. Review its absolute paths
before using it on another host. See [Bebop backup](bebop-backup.md).
Agent deployment files, startup units, credentials and state stay local and are
protected by backups, not imported into this repository. Existing fnm/Node and Herdr executables are reused. A Debian Herdr overlay
preserves terminal toast delivery and the existing all-agents panel scope while
inheriting shared bindings and appearance.

## First deployment

1. Keep a working Bash/SSH connection open and back up local configuration.
2. Inspect `./dot install --dry-run --verbose`. On a minimal Debian machine,
   install missing APT packages using an interactive sudo session. This profile
   does not refresh package indexes or upgrade existing tools.
3. Run `./dot install` for missing plugins and supported tools, then
   `bash tests/run`. Shell tests use isolated fixtures and do not modify ACLs.
4. Preview `./dot deploy --dry-run --verbose`. Review existing Herdr, Zsh and
   agent-skill conflicts before using `--replace`.
5. Run `./dot doctor --verbose`, test `zsh -il`, and verify node/npm/Codex/Pi,
   Herdr, fd/bat aliases, completion, history, and the inherited SSH agent.
6. Only after verification, optionally run `chsh -s /usr/bin/zsh` yourself.
   Check a second SSH connection and a noninteractive remote command before
   closing the original connection. No agent restart is needed for this switch.

## Migrating the old server-dotfiles checkout

On Bebop, `.config/systemd` and `.config/resticprofile` were directory links
into the old checkout. Materialize retained Codex unit/enablement and backup
credentials as local files before replacing that checkout. Preserve the user
manager PATH drop-in. Reload user unit definitions and verify Codex stays active;
do not re-enable retired Wattson or WhatsApp units.

The old `.bash_secrets` contained only retired Cloudflare credentials. Remove
it rather than importing it. Replace custom Bash startup links with Debian's
standard skeleton files as a fallback; shared Zsh supplies the useful shell
behavior and `acl_fix`. The new repository contains no private credentials.

Keep the old checkout until shell and startup-link checks pass, then retire it.
Preserve the resulting local files and new deployment in a fresh encrypted
backup. Shell deployment alone does not establish recurring agent backup
scheduling; use the separate [backup procedure](bebop-backup.md).
