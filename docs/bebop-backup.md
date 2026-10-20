# Bebop: home and system backups

## Rollout status — 18 October 2026

Configuration deployed on Bebop. All 25 offline backup tests passed there,
including real local-restic exclusion fixtures. All 24 actual live SQLite
exports passed integrity and SHA-256 verification in private user staging.
The dotfiles test suite passed locally. No live services were stopped.

Full root-run snapshot **8168c0b9**, 18 October 20:36–20:37 Toronto, succeeded:
46,173 files, 4.679 GiB logical, 252.522 MiB newly stored. Scoped retention kept
its one matching snapshot and did not forget historical snapshots. All 24 DB
exports were restored from restic with verification and passed manifest SHA-256
and SQLite integrity checks. Twelve selected configuration/secret/deployment
files matched live bytes; hot DB/sidecar and cache/staging exclusions passed.

Gatus's separate Bebop endpoint is configured. An invalid token was rejected
(401), and a manual heartbeat for this verified snapshot succeeded (200).
Nautilus's existing endpoint retained its history. The native success hook was then proven by **305cf922**, 18 October
20:50:11–20:50:40 Toronto: 4.680 GiB logical, 5.970 MiB newly stored; retention
kept both matching full snapshots. Gatus recorded success at 20:50:40 Toronto,
separate from the earlier manual test.

**Enabled and active:** persistent root timer
`resticprofile-backup@profile-bebop.timer`, daily 05:00 America/Toronto;
`Persistent=yes` and next run 19 October 05:00 EDT / 09:00 UTC independently
verified. Its first unattended execution has not yet occurred. Configuration
deployment alone does not install a schedule or initialize a repository.

## Coverage

Sources: `/home/rdmm404`, `/etc`, `/usr/local`, `/var/spool/cron/crontabs`,
`/var/lib/systemd/linger` and `/var/lib/resticprofile/bebop/exports`.

Home includes hidden/ignored files, private credentials, SSH, dotfiles, local
agents deployment, both AI checkouts, development work and Codex/Pi/Herdr state.
`exclude.txt` removes specific rebuildable dependencies/caches and transient
process/backup staging. It does not exclude `.local`, `.git` or ignored files
wholesale. Restic archives symlinks without following them; the home source
also contains their retained dotfiles/generated-configuration targets.

`sqlite.json` requires Voltio activities and all five current Codex databases.
It discovers additional Codex/Voltio databases and retained CloudCLI/Hapi/Gemini
stores. Reviewed current inventory: 24 databases. A changed required path fails
closed; review the policy after tool/schema upgrades. This is not automatic
detection of every future database technology anywhere on the machine.

The Debian helper is a repository-relative link to Nautilus's `prepare_backup.py`.
Its SQLite-only mode uses the **same** online SQLite backup, integrity check,
private staging, atomic publication and cleanup functions. No Nautilus service
is contacted, and uv/MQTT dependencies are not needed for this mode. The normal
Nautilus code path remains covered by regression tests; it has not been deployed
to Nautilus as part of this rollout.

Every capture records original source, owner/group/mode and SHA-256 in
`exports/restore-metadata.json`. Export paths mirror the home-relative originals
under `exports/sqlite/`. Generated `sqlite-exclude.txt` excludes exactly those hot
DBs and WAL/SHM/journal sidecars; the exports replace them. Required capture or
inventory failures abort upload, rather than backing up yesterday's exports.

Native package/manual-package, system-unit, filesystem, Docker image/container
and backup-tool version inventories are captured under `exports/inventory/`.
Inventories aid reconstruction; they are not a complete application installer.

Not a disk image: Docker image layers/storage, `/root`, live Tailscale state and
other `/var/lib` trees are not captured. Rebuild Voltio images from retained
source, reinstall system packages/tools and re-enrol Tailscale. Do not claim a
proven quick fresh-host rebuild until an isolated end-to-end rehearsal passes.
Separate database captures and ordinary files are not globally atomic.

## Credentials and repository

Existing repository: `rclone:nautilus-drive:backups/nautilus`. **Never init.**
Retain mode-600 `~/.config/resticprofile/{restic-password,rclone.conf}` inside the
mode-700 directory. Recover the password independently from the existing
Bitwarden item and recover Drive authorization separately. Do not print resolved
profiles once private webhook includes exist.

The profile lock covers prepare/upload/retention/cleanup. Native restic lock
retry is 30 minutes for overlap with Nautilus repository operations. Retention
keeps a 30-day window scoped to host `bebop`, both tags
`agents,home-and-host-config` and this profile's source paths. Historical Bebop
and other-host snapshots are not forgotten. Prune is repository-wide, but only
unreferenced data can be removed.

## Finish installation (interactive sudo on Bebop)

After reviewing the deployed policy, run this deliberately. It creates a private
root state directory, captures live SQLite exports, writes a new encrypted full
snapshot and applies the scoped retention/pruning:

```bash
sudo install -d -o root -g root -m 700 /var/lib/resticprofile/bebop
sudo /usr/local/bin/resticprofile -c /home/rdmm404/.config/resticprofile/profiles.yaml -n bebop backup
```

Then independently inspect the selected snapshot and restore exported databases
and representative configuration/secret files into private isolated staging.
Verify file bytes, manifest hashes and SQLite integrity. Do not restore over
running services; the exported DBs must be mapped back using the manifest.
A source-export check alone is not a remote-restic restore test.

Only after that proof, install the native persistent root timer:

```bash
sudo /usr/local/bin/resticprofile -c /home/rdmm404/.config/resticprofile/profiles.yaml -n bebop schedule
systemctl list-timers --all 'resticprofile*'
```

Intended schedule: daily **05:00 America/Toronto**. Expected unit names:
`resticprofile-backup@profile-bebop.{timer,service}`. Never run a Nautilus profile
on Bebop. No lingering change is required for this system/root job.

`Backup / Bebop agents` is configured in Nautilus Gatus with a 36-hour
heartbeat, existing Telegram delivery, recovery notices and 12-hour reminders.
Bebop's ignored mode-600 `~/.config/resticprofile/gatus.yaml` supplies a native
backup-success POST to
`https://status.nautilus.voltr.org/api/v1/endpoints/backup_bebop-agents/external?success=true`.
The separate matching token is `GATUS_BEBOP_BACKUP_TOKEN` in Nautilus's ignored
`~/services/gatus/.env`. Only Gatus was recreated, retaining its existing image
and SQLite history. Bebop HTTPS access works without firewall changes.

Invalid-token rejection and a manual heartbeat for the verified first snapshot
passed. The actual `305cf922` backup then delivered a second successful heartbeat
at 20:50:40 Toronto, proving the native hook; the root timer is enabled/active.
Keep the bearer token out of Git and resolved profile output. No deliberate Telegram failure test/human receipt confirmation,
immediate failed-attempt alert or independent repository-age checker exists.

## Recovery outline

1. Install compatible Debian, create `rdmm404` with reviewed UID/GID, install
   restic/rclone and independently recover repository access.
2. Select host/tags/time deliberately, not unqualified `latest`. Restore to
   separate private staging with restic verification.
3. Reinstall packages/tools using the inventories and retained configuration;
   restore home with appropriate ownership and selectively adapt `/etc`.
   Never overwrite new disk UUIDs, network interfaces or identities wholesale.
4. With writers stopped, map SQLite exports to their original paths using the
   manifest and verify hashes/integrity. Review stale WAL/SHM sidecars.
5. Rebuild retained Voltio images/deployment, restore private environment and
   finance config, enable the Codex user unit and reviewed lingering settings.
   Re-enrol Tailscale. Do not reactivate historical retired services.
6. Validate application behavior, then restore working backup scheduling and
   notifications. A fresh-host application restore remains untested.
