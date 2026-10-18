#!/usr/bin/env python3
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("udev", REPO / "lib/udev.py")
udev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(udev)


class UdevTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sources = self.root / "sources"
        self.targets = self.root / "targets"
        self.sources.mkdir()
        self.targets.mkdir()
        self.source = self.sources / "70-test.rules"
        self.target = self.targets / self.source.name
        self.source.write_text('KERNEL=="hidraw*", TAG+="uaccess"\n')
        self.runner = Mock()

    def install(self, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()):
            udev.install_rules(self.sources, self.targets, runner=self.runner, **kwargs)

    def test_missing_rule_is_installed_as_copy(self):
        self.install()
        args = self.runner.call_args[0][0]
        self.assertEqual(args[:2], ["/bin/sh", "-c"])
        self.assertIn('install -o root -g root -m 0644', args[2])
        self.assertEqual(args[-1], str(self.source))

    def test_dry_run_never_elevates_or_writes(self):
        self.install(dry_run=True)
        self.runner.assert_not_called()
        self.assertFalse(self.target.exists())

    def test_unchanged_root_owned_rule_needs_no_privileges(self):
        shutil.copyfile(self.source, self.target)
        self.target.chmod(0o644)
        original_stat = Path.stat

        def root_stat(path, *args, **kwargs):
            result = original_stat(path, *args, **kwargs)
            if path == self.target:
                values = list(result)
                values[4] = values[5] = 0
                return os.stat_result(values)
            return result

        with patch.object(Path, "stat", root_stat):
            self.install(verbose=True)
        self.runner.assert_not_called()

    def test_wrong_mode_is_repaired_without_replace(self):
        shutil.copyfile(self.source, self.target)
        self.target.chmod(0o600)
        self.install()
        self.runner.assert_called_once()

    def test_conflicts_block_entire_plan(self):
        self.target.write_text("old rule\n")
        (self.sources / "60-new.rules").write_text("new rule\n")
        with self.assertRaisesRegex(RuntimeError, "require --replace"):
            self.install()
        self.runner.assert_not_called()
        self.assertFalse((self.targets / "60-new.rules").exists())

    def test_symlink_destinations_are_refused_even_with_replace(self):
        self.target.symlink_to(self.source)
        with self.assertRaisesRegex(RuntimeError, "non-regular destination"):
            self.install(replace=True)
        self.runner.assert_not_called()

    def test_symlink_sources_are_refused(self):
        self.source.unlink()
        self.target.write_text("rule\n")
        self.source.symlink_to(self.target)
        with self.assertRaisesRegex(RuntimeError, "regular file"):
            self.install()

    def test_privileged_script_backups_installs_and_reloads(self):
        self.target.write_text("old rule\n")
        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        # Preserve the installation operation but avoid actual root ownership.
        install = fake_bin / "install"
        install.write_text('#!/bin/sh\nshift 4\nexec /usr/bin/install "$@"\n')
        install.chmod(0o755)
        udevadm = fake_bin / "udevadm"
        udevadm.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$UDEV_LOG"\n')
        udevadm.chmod(0o755)
        log = self.root / "udev.log"
        env = dict(os.environ, PATH=str(fake_bin) + ":" + os.environ["PATH"], UDEV_LOG=str(log))

        def sandbox_runner(args):
            subprocess.run(args, env=env, check=True, capture_output=True)

        self.runner = sandbox_runner
        self.install(replace=True)
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())
        self.assertFalse(self.target.is_symlink())
        self.assertEqual(stat.S_IMODE(self.target.stat().st_mode), 0o644)
        backups = list(self.targets.glob("*.bak.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "old rule\n")
        self.assertEqual(log.read_text().splitlines(), [
            "control --reload-rules", "trigger --action=add --subsystem-match=hidraw", "settle"])

    def test_privileged_step_rechecks_conflict(self):
        def changed_destination(args):
            self.target.write_text("changed during authentication\n")
            subprocess.run(args, check=True, capture_output=True)

        self.runner = changed_destination
        with self.assertRaises(subprocess.CalledProcessError):
            self.install()
        self.assertEqual(self.target.read_text(), "changed during authentication\n")

    def test_cli_macos_skip_and_invalid_arguments(self):
        env = dict(os.environ, DOT_ROOT=str(REPO), DOT_PLATFORM="macos")
        skipped = subprocess.run([str(REPO / "dot"), "udev"], env=env,
                                 capture_output=True, text=True)
        self.assertEqual(skipped.returncode, 0)
        self.assertIn("Linux-only", skipped.stdout)
        invalid = subprocess.run([str(REPO / "dot"), "udev", "--bogus"], env=env,
                                 capture_output=True, text=True)
        self.assertEqual(invalid.returncode, 2)

    def test_authentication_is_scoped_to_installation(self):
        with patch.object(udev.os, "geteuid", return_value=1000), \
                patch.object(udev.shutil, "which", return_value="/usr/bin/auth"), \
                patch.object(udev.subprocess, "run") as run:
            with patch.object(udev.sys.stdin, "isatty", return_value=True):
                udev.run_privileged(["install", "file"])
            self.assertEqual(run.call_args[0][0], ["sudo", "install", "file"])
            with patch.object(udev.sys.stdin, "isatty", return_value=False):
                udev.run_privileged(["install", "file"])
            self.assertEqual(run.call_args[0][0], ["pkexec", "install", "file"])


if __name__ == "__main__":
    unittest.main()
