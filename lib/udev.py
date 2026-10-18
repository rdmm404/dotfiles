#!/usr/bin/env python3
"""Install explicit Linux udev rules as copies, never HOME-layer links."""

import argparse
from datetime import datetime
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys


# Elevate only this installation step, not the repository's Python interpreter.
# Recheck conflicts after authentication in case the destination changed.
INSTALL_SCRIPT = r'''
set -eu
target_dir=$1
replace=$2
stamp=$3
shift 3
mkdir -p "$target_dir"
for source in "$@"; do
    target="$target_dir/${source##*/}"
    if [ -L "$target" ] || { [ -e "$target" ] && [ ! -f "$target" ]; }; then
        printf 'Refusing non-regular destination: %s\n' "$target" >&2
        exit 1
    fi
    if [ -f "$target" ] && ! cmp -s "$source" "$target"; then
        if [ "$replace" != 1 ]; then
            printf 'Destination changed; rerun with --replace: %s\n' "$target" >&2
            exit 1
        fi
        backup="$target.bak.$stamp"
        test ! -e "$backup"
        cp -p "$target" "$backup"
        printf '[ok]   backup: %s\n' "$backup"
    fi
    install -o root -g root -m 0644 "$source" "$target"
done
udevadm control --reload-rules
udevadm trigger --action=add --subsystem-match=hidraw
udevadm settle
'''


def run_privileged(command):
    if os.geteuid() == 0:
        prefix = []
    elif sys.stdin.isatty():
        prefix = ["sudo"]
    else:
        prefix = ["pkexec"]
    if prefix and not shutil.which(prefix[0]):
        raise RuntimeError("{} is required to install system rules".format(prefix[0]))
    subprocess.run(prefix + command, check=True)


def install_rules(source_dir, target_dir, dry_run=False, verbose=False,
                  replace=False, runner=run_privileged):
    sources = sorted(source_dir.glob("*.rules"))
    if not sources:
        raise RuntimeError("no udev rules found in {}".format(source_dir))
    changes = []
    conflicts = []
    for source in sources:
        if source.is_symlink() or not source.is_file():
            raise RuntimeError("rule source must be a regular file: {}".format(source))
        target = target_dir / source.name
        if target.is_symlink() or (target.exists() and not target.is_file()):
            raise RuntimeError("refusing non-regular destination: {}".format(target))
        same = target.exists() and source.read_bytes() == target.read_bytes()
        if same:
            info = target.stat()
            if (info.st_uid, info.st_gid, stat.S_IMODE(info.st_mode)) == (0, 0, 0o644):
                if verbose:
                    print("[ok]   unchanged: {}".format(target))
                continue
        if target.exists() and not same and not replace:
            conflicts.append(target)
        changes.append(source)
    if conflicts:
        raise RuntimeError("differing rules require --replace: {}".format(
            ", ".join(str(path) for path in conflicts)))
    for source in changes:
        print("[change] {}install: {}".format(
            "will " if dry_run else "", target_dir / source.name), flush=True)
    if dry_run or not changes:
        return
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    runner(["/bin/sh", "-c", INSTALL_SCRIPT, "dot-udev", str(target_dir),
            "1" if replace else "0", stamp] + [str(path) for path in changes])
    print("[ok]   udev rules installed and reloaded")


def main():
    parser = argparse.ArgumentParser(
        prog="dot udev", description="Install Linux keyboard udev rules as root-owned copies.")
    parser.add_argument("--dry-run", action="store_true", help="preview without writing or authenticating")
    parser.add_argument("--verbose", action="store_true", help="list unchanged rules")
    parser.add_argument("--replace", action="store_true", help="back up and replace differing rules")
    args = parser.parse_args()
    if os.environ.get("DOT_PLATFORM") == "macos":
        print("[skip] udev rules are Linux-only")
        return 0
    try:
        install_rules(Path(os.environ["DOT_ROOT"]) / "system/linux/udev",
                      Path("/etc/udev/rules.d"), args.dry_run, args.verbose, args.replace)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print("[error] {}".format(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
