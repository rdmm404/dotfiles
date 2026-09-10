#!/usr/bin/env python3
"""Dot's filesystem operations. No persistent deployment state or transactions.

Inspect once, touch only changed paths, let Stow link the active layers. Failed
operations leave successful work in place; backups protect explicit replacement.
"""
import argparse
from dataclasses import dataclass
from datetime import datetime
import filecmp
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import time


class Error(Exception):
    pass


def inside(path, parent):
    return path == parent or parent in path.parents


def exists(path):
    return path.exists() or path.is_symlink()


def directory(path):
    return path.is_dir() and not path.is_symlink()


def identical(first, second):
    return (not first.is_symlink() and not second.is_symlink()
            and first.is_file() and second.is_file()
            and stat.S_IMODE(first.stat().st_mode) == stat.S_IMODE(second.stat().st_mode)
            and filecmp.cmp(first, second, shallow=False))


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if directory(source):
        shutil.copytree(source, target, symlinks=True)
    else:
        shutil.copy2(source, target, follow_symlinks=False)


def remove(path):
    if directory(path):
        shutil.rmtree(path)
    else:
        path.unlink()


def regular_parents(path, root):
    """Don't write through a symlinked parent, especially during import/restore."""
    for parent in path.parents:
        if parent == root:
            return
        if parent.is_symlink() or (parent.exists() and not parent.is_dir()):
            raise Error(f"Not a regular directory: {parent}")
    raise Error(f"Path is outside {root}: {path}")


class Ignore:
    # Stow's defaults. A local/global ignore file replaces (not extends) them.
    DEFAULT = (r"RCS .+,v CVS \.\#.+ \.cvsignore \.svn _darcs \.hg \.git "
               r"\.gitignore \.gitmodules .+~ \#.*\# ^/README.* ^/LICENSE.* ^/COPYING")

    def __init__(self, layer, home):
        text = self.DEFAULT.replace(" ", "\n")
        for path in (layer / ".stow-local-ignore", home / ".stow-global-ignore"):
            if path.exists():
                text = path.read_text()
                break
        self.patterns = []
        for line in text.splitlines():
            line = re.sub(r"\s+#.+", "", line.strip())
            if not line or line.startswith("#"):
                continue
            line = line.replace(r"\#", "#")
            full_path = "/" in line
            expression = r"(^|/)(?:" + line + r")(/|$)" if full_path else r"^(?:" + line + r")$"
            self.patterns.append((full_path, re.compile(expression)))

    def __call__(self, relative):
        if relative == Path(".stow-local-ignore"):
            return True
        # Checking each prefix also applies directory ignores to explicit add paths.
        for part in [*reversed(relative.parents), relative]:
            if part == Path("."):
                continue
            for full_path, pattern in self.patterns:
                if pattern.search("/" + part.as_posix() if full_path else part.name):
                    return True
        return False


@dataclass
class Entry:
    source: Path
    is_dir: bool


@dataclass
class Change:
    target: Path
    entry: Entry
    action: str


class Files:
    def __init__(self):
        for name in ("HOME", "DOT_ROOT", "DOT_PLATFORM"):
            if not os.environ.get(name):
                raise Error(f"{name} is required")
        self.home = Path(os.environ["HOME"]).resolve()
        self.root = Path(os.environ["DOT_ROOT"]).resolve()
        self.platform = os.environ["DOT_PLATFORM"]
        if self.platform not in ("macos", "wsl", "omarchy"):
            raise Error(f"Unsupported platform: {self.platform}")
        self.layers = [self.root / "global", self.root / "platforms" / self.platform]
        self.backup_root = self.home / ".local/state/dot/backups"

    def display(self, path):
        return "~" + str(path)[len(str(self.home)):] if inside(path, self.home) else str(path)

    def owned(self, path):
        if not path.is_symlink():
            return False
        try:
            destination = Path(os.path.abspath(path.parent / os.readlink(path)))
            # The link must address the repo, not another HOME link which
            # eventually reaches it. Resolve ancestors to reject repo/escape/file
            # when escape points outside. A tracked adapter itself is still ours.
            return (destination == self.root
                    or inside(destination.parent.resolve(), self.root))
        except (OSError, RuntimeError):
            return False

    def inventory(self):
        entries = {}
        for layer in self.layers:
            if not layer.exists():
                continue
            if not directory(layer):
                raise Error(f"Configuration layer is not a regular directory: {layer}")
            ignored = Ignore(layer, self.home)

            def walk(folder):
                for source in sorted(folder.iterdir()):
                    relative = source.relative_to(layer)
                    if ignored(relative):
                        continue
                    if relative == Path(".stowrc"):
                        raise Error("dot does not deploy .stowrc; Stow options would change deployment semantics.")
                    entry = Entry(source, directory(source))
                    target = self.home / relative
                    if inside(target, self.root) or (not entry.is_dir and inside(self.root, target)):
                        raise Error(f"Configuration would overwrite the repository: {target}")
                    if relative in entries and not (entry.is_dir and entries[relative].is_dir):
                        raise Error(f"Configuration layers overlap at ~/{relative}")
                    entries.setdefault(relative, entry)
                    if entry.is_dir:
                        walk(source)
                    elif not source.is_symlink() and not source.is_file():
                        raise Error(f"Not a regular file or symlink: {source}")
            walk(layer)
        # Parents occur before children even when supplied by different layers.
        return dict(sorted(entries.items(), key=lambda item: (len(item[0].parts), str(item[0]))))

    def changes(self, entries):
        changes, replaced_dirs, unchanged = [], set(), 0
        for relative, entry in entries.items():
            target = self.home / relative
            below_replacement = any(parent in replaced_dirs for parent in target.parents)
            if below_replacement or not exists(target):
                action = "mkdir" if entry.is_dir else "link"
            elif entry.is_dir and directory(target):
                continue
            elif not entry.is_dir and self.owned(target) and target.resolve() == entry.source.resolve():
                unchanged += 1
                continue
            elif self.owned(target):
                action = "relink"
            elif not entry.is_dir and identical(target, entry.source):
                action = "identical"
            else:
                action = "replace"
            changes.append(Change(target, entry, action))
            if entry.is_dir and action in ("replace", "relink"):
                replaced_dirs.add(target)
        return changes, unchanged

    def show_changes(self, changes, dry_run, verbose):
        visible = [change for change in changes if change.action != "mkdir"]
        if not visible and changes:
            visible = changes
        for change in visible if verbose or len(visible) <= 10 else []:
            verb = {"replace": "Back up and replace", "relink": "Relink",
                    "identical": "Link identical file", "link": "Link", "mkdir": "Create directory"}[change.action]
            if dry_run:
                verb = "Would " + verb[0].lower() + verb[1:]
            else:
                verb = {"replace": "Backed up and replaced", "relink": "Relinked",
                        "identical": "Linked identical file", "link": "Linked", "mkdir": "Created directory"}[change.action]
            print(f"{verb} {self.display(change.target)}")

    def deploy(self, args):
        entries = self.inventory()
        changes, unchanged = self.changes(entries)
        if not changes:
            if args.verbose:
                for relative, entry in entries.items():
                    if not entry.is_dir:
                        print(f"Unchanged ~/{relative}")
            print("Already up to date.")
            return
        conflicts = [change.target for change in changes if change.action == "replace"]
        if conflicts and not args.replace:
            for path in conflicts:
                print(f"Conflict: {self.display(path)}", file=sys.stderr)
            approved = (not args.dry_run and sys.stdin.isatty()
                        and input(f"Back up and replace {len(conflicts)} conflicting path(s)? [y/N] ").lower() in ("y", "yes"))
            if not approved:
                raise Error("Nothing changed. Use --replace to back up and replace conflicts, or dot add to import them.")
        # Stow reads these implicit options even with explicit -d/-t. In
        # particular --adopt or --dotfiles would invalidate our path decisions.
        for rc in {self.home / ".stowrc", self.root / ".stowrc"}:
            if rc.exists():
                raise Error(f"dot does not support Stow option files: {rc}; use .stow-local-ignore for ignore rules.")
        if args.dry_run:
            self.show_changes(changes, True, args.verbose)
            print(f"Dry run: {len(changes)} change(s), {unchanged} unchanged.")
            return
        stow = shutil.which(os.environ.get("STOW_COMMAND", "stow"))
        if not stow:
            raise Error("GNU Stow is required for deployment; run dot install.")
        if conflicts:
            self.save_backup(conflicts)
        for change in changes:
            if change.action in ("replace", "relink", "identical"):
                remove(change.target)
        completed = []
        for layer in self.layers:
            if not layer.exists():
                continue
            result = subprocess.run([stow, "--no-folding", "-d", str(layer.parent),
                                     "-t", str(self.home), layer.name], cwd=self.root, capture_output=True, text=True)
            if result.returncode:
                if result.stderr:
                    print(result.stderr.rstrip(), file=sys.stderr)
                if completed:
                    print(f"Completed layers: {', '.join(completed)}")
                raise Error(f"Stow failed for {layer.relative_to(self.root)}. Successful work was kept; fix the error and rerun dot deploy.")
            completed.append(str(layer.relative_to(self.root)))
            if args.verbose and result.stderr:
                print(result.stderr.rstrip())
        self.show_changes(changes, False, args.verbose)
        count = sum(not change.entry.is_dir for change in changes)
        print(f"{count} link(s) updated, {unchanged} unchanged ({self.platform}).")

    def add(self, args):
        layer = self.root / ("global" if args.global_layer else "platforms/" + self.platform)
        ignored = Ignore(layer, self.home)
        # A shared import must also remain compatible with inactive platforms.
        other_layers = ([p for p in (self.root / "platforms").glob("*") if p.is_dir()]
                        if args.global_layer else [self.root / "global"])
        pending, dirs, managed, skipped = {}, {}, set(), set()

        def collect(path, selection):
            relative = path.relative_to(self.home)
            destination = layer / relative
            if ignored(relative):
                skipped.add(path)
                return
            regular_parents(path, self.home)
            regular_parents(destination, self.root)
            if self.owned(path):
                managed.add(path)
                return
            is_dir = directory(path)
            if path.is_symlink():
                raw = Path(os.readlink(path))
                lexical = Path(os.path.abspath(path.parent / raw))
                if path == selection or (not raw.is_absolute() and not inside(lexical, selection)):
                    raise Error(f"Unmanaged symlink: {self.display(path)}; import its file explicitly.")
            elif not is_dir and not path.is_file():
                raise Error(f"Not a regular file or directory: {self.display(path)}")
            for other in other_layers:
                candidate = other / relative
                if exists(candidate) and not (is_dir and directory(candidate)):
                    raise Error(f"Already owned by another layer: {candidate.relative_to(self.root)}")
                regular_parents(candidate, other)
            if is_dir:
                if exists(destination) and not directory(destination):
                    raise Error(f"Repository conflict: {destination.relative_to(self.root)}")
                dirs[path] = destination
                for child in sorted(path.iterdir()):
                    collect(child, selection)
            else:
                if exists(destination) and not identical(path, destination):
                    raise Error(f"Repository conflict: {destination.relative_to(self.root)}; compare the files before importing.")
                pending[path] = destination

        selections = sorted({Path(os.path.abspath(os.path.expanduser(value))) for value in args.paths}, key=lambda p: len(p.parts))
        selected = []
        for path in selections:
            if not inside(path, self.home) or inside(path, self.root) or inside(self.root, path):
                raise Error(f"Choose a path inside HOME, outside the repository: {path}")
            if any(inside(path, previous) for previous in selected):
                continue
            selected.append(path)
            collect(path, path)
        for path, dest in pending.items():
            if not path.is_symlink():
                continue
            raw = Path(os.readlink(path))
            if not raw.is_absolute():
                reference = Path(os.path.abspath(path.parent / raw))
                if reference not in pending and reference not in dirs and not exists(dest.parent / raw):
                    raise Error(f"Relative symlink target is not imported into this layer: {self.display(path)}")
        new_dirs = {source: dest for source, dest in dirs.items() if not dest.exists()}
        if args.dry_run:
            for path in pending:
                print(f"Would add {self.display(path)} -> {pending[path].relative_to(self.root)}")
            for path, dest in new_dirs.items():
                if args.verbose or not pending:
                    print(f"Would create {dest.relative_to(self.root)}/")
        else:
            for source, dest in new_dirs.items():
                dest.mkdir(mode=0o700, parents=True, exist_ok=True)
            for path, dest in pending.items():
                if not exists(dest):
                    copy(path, dest)
                path.unlink()
                path.symlink_to(os.path.relpath(dest, path.parent))
                if args.verbose or len(pending) <= 10:
                    print(f"Added {self.display(path)} -> {dest.relative_to(self.root)}")
            # Applying read-only directory modes before copying children would
            # prevent an otherwise valid import of writable nested directories.
            for source, dest in reversed(list(new_dirs.items())):
                shutil.copystat(source, dest)
        for path in sorted(skipped):
            print(f"Skipped (Stow ignore): {self.display(path)}")
        if pending or new_dirs:
            print(f"{'Dry run: would add' if args.dry_run else 'Added'} {len(pending)} file(s) to {layer.relative_to(self.root)}; {len(managed)} already managed.")
        else:
            print("Already managed; nothing to add." if managed else "Nothing to add.")

    def undeploy(self, args):
        removed = []
        for relative in self.inventory():
            path = self.home / relative
            if any(inside(path, parent) for parent in removed):
                continue
            # A foreign symlinked directory is not ours to traverse or modify.
            if any(parent.is_symlink() for parent in path.parents if parent != self.home and inside(parent, self.home)):
                continue
            if self.owned(path):
                removed.append(path)
                if not args.dry_run:
                    path.unlink()
                print(f"{'Would unlink' if args.dry_run else 'Unlinked'} {self.display(path)}")
            elif args.verbose and exists(path):
                print(f"Kept {self.display(path)}")
        print(f"{'Would remove' if args.dry_run else 'Removed'} {len(removed)} link(s)." if removed else "Nothing to undeploy.")

    def check(self, args):
        changes, unchanged = self.changes(self.inventory())
        for change in changes:
            if change.action != "mkdir" or args.verbose:
                print(f"{'Conflict' if change.action == 'replace' else 'Not deployed'}: {self.display(change.target)}")
        if changes:
            raise Error("Run dot deploy to reconcile configuration.")
        print(f"Configuration is deployed ({unchanged} links).")

    def backup_directory(self, identifier):
        regular_parents(self.backup_root / "placeholder", self.home)
        if identifier == "latest":
            candidates = self.backup_directories()
            if not candidates:
                raise Error("No backups.")
            return candidates[-1]
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", identifier):
            raise Error(f"Invalid backup ID: {identifier}")
        path = self.backup_root / identifier
        if not directory(path):
            raise Error(f"Backup not found: {identifier}")
        return path

    def backup_directories(self):
        regular_parents(self.backup_root / "placeholder", self.home)
        return sorted((p for p in self.backup_root.glob("*") if directory(p)),
                      key=lambda p: (p.stat().st_mtime_ns, p.name))

    def save_backup(self, paths):
        regular_parents(self.backup_root / "placeholder", self.home)
        if any(inside(self.backup_root, path) for path in paths):
            raise Error("Cannot back up a directory containing the backup storage itself.")
        self.backup_root.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        backup = self.backup_root / stamp
        backup.mkdir(mode=0o700)
        saved = []
        # Record only completed copies. On failure both the originals and all
        # completed backup copies remain available, without a rollback engine.
        print(f"Backup: {self.display(backup)}")
        for path in paths:
            relative = path.relative_to(self.home)
            copy(path, backup / "files" / relative)
            saved.append(str(relative))
            (backup / "manifest.json").write_text(json.dumps(saved, indent=2) + "\n")
        return backup

    def backup_contents(self, backup):
        manifest = backup / "manifest.json"
        legacy = backup / ".dot-backup-roots"
        if manifest.is_symlink() or legacy.is_symlink():
            raise Error("Backup metadata must not be a symlink.")
        if manifest.exists():
            names, payload = json.loads(manifest.read_text()), backup / "files"
        elif legacy.exists():
            names, payload = legacy.read_text().splitlines(), backup
        else:
            raise Error(f"Backup metadata is missing: {backup.name}")
        if not isinstance(names, list) or not all(isinstance(name, str) for name in names):
            raise Error("Invalid backup metadata.")
        paths = []
        for name in names:
            relative = Path(name)
            if not name or relative.is_absolute() or any(part in ("", ".", "..") for part in name.split("/")):
                raise Error(f"Invalid backup path: {name}")
            if any(inside(relative, p) or inside(p, relative) for p in paths):
                raise Error(f"Overlapping backup paths: {name}")
            source = payload / relative
            regular_parents(source, backup)
            if not exists(source):
                raise Error(f"Missing backup file: {source}")
            paths.append(relative)
        return payload, paths

    def restore_allowed(self, target):
        if not exists(target) or self.owned(target):
            return True
        if directory(target):
            return all(self.restore_allowed(child) for child in target.iterdir())
        return False

    def backups(self, args):
        if args.operation == "list":
            backups = self.backup_directories()
            for backup in backups:
                payload, paths = self.backup_contents(backup)
                size = sum(p.lstat().st_size for p in backup.rglob("*") if not directory(p))
                print(f"{backup.name}  {len(paths)} path(s)  {size / 1024:.1f} KiB")
            if not backups:
                print("No backups.")
            return
        if args.operation == "prune":
            if not re.fullmatch(r"[0-9]+d", args.older_than):
                raise Error("Age must look like 30d.")
            cutoff = time.time() - int(args.older_than[:-1]) * 86400
            backups = [p for p in self.backup_directories() if p.stat().st_mtime < cutoff]
        else:
            backups = [self.backup_directory(args.identifier)]
        if args.operation in ("remove", "prune"):
            for backup in backups:
                if not args.dry_run:
                    shutil.rmtree(backup)
                print(f"{'Would remove' if args.dry_run else 'Removed'} backup {backup.name}")
            if not backups:
                print("No backups match the requested age.")
            return
        backup = backups[0]
        payload, paths = self.backup_contents(backup)
        conflicts = []
        for relative in paths:
            target = self.home / relative
            regular_parents(target, self.home)
            if inside(target, self.root) or inside(self.root, target) or inside(target, self.backup_root) or inside(self.backup_root, target):
                raise Error(f"Restore would overwrite repository or backup storage: {target}")
            if not self.restore_allowed(target):
                conflicts.append(target)
        if conflicts and not args.replace:
            raise Error("Restore conflicts: " + ", ".join(self.display(p) for p in conflicts) + "; use --replace to back up and replace them.")
        if not args.dry_run and conflicts:
            self.save_backup(conflicts)
        for relative in paths:
            target = self.home / relative
            if not args.dry_run:
                if exists(target):
                    remove(target)
                copy(payload / relative, target)
            print(f"{'Would restore' if args.dry_run else 'Restored'} {self.display(target)}")


def parser():
    cli = argparse.ArgumentParser(prog="dot", description="Direct dotfiles operations; use --dry-run to preview.")
    commands = cli.add_subparsers(dest="command", required=True)
    for name, description in (("deploy", "Link global and current-platform configuration."),
                              ("undeploy", "Remove owned links; leave files and directories alone."),
                              ("add", "Import files/directories and link them back, without staging a Git commit."),
                              ("check", "Check runtime deployment.")):
        command = commands.add_parser(name, description=description)
        command.add_argument("--verbose", action="store_true", help="show individual paths and unchanged items")
        if name != "check":
            command.add_argument("--dry-run", action="store_true", help="preview without writing")
        if name == "deploy":
            command.add_argument("--replace", action="store_true", help="back up and replace conflicting home paths without prompting")
        if name == "add":
            command.add_argument("paths", metavar="PATH", nargs="+")
            layer = command.add_mutually_exclusive_group(required=True)
            layer.add_argument("--global", dest="global_layer", action="store_true", help="store in global/ for every platform")
            layer.add_argument("--platform", action="store_true", help="store in the detected platform layer")
    backups = commands.add_parser("backups", description="Replacement backups. Explicit removal commands do not prompt.")
    operations = backups.add_subparsers(dest="operation", required=True)
    operations.add_parser("list")
    for name in ("restore", "remove", "prune"):
        operation = operations.add_parser(name)
        operation.add_argument("--dry-run", action="store_true", help="preview without writing")
        if name == "prune":
            operation.add_argument("--older-than", required=True, metavar="30d")
        else:
            operation.add_argument("identifier", metavar="ID", help="backup ID or latest")
        if name == "restore":
            operation.add_argument("--replace", action="store_true", help="back up conflicting current files before restoring")
    return cli


def main():
    args = parser().parse_args()
    try:
        files = Files()
        getattr(files, args.command)(args)
    except (Error, OSError, RuntimeError, ValueError, re.error, EOFError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Interrupted; completed work was kept.", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
