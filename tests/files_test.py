"""Public CLI tests. Every filesystem mutation is confined to a temporary HOME."""
import json
import os
import pty
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
STOW = shutil.which("stow")


class FilesTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(STOW, "Install GNU Stow to run filesystem tests")
        self.tmp = tempfile.TemporaryDirectory(prefix="dot-files-test-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.root = self.home / "dotfiles"
        self.home.mkdir()
        self.root.mkdir()
        shutil.copy2(REPO / "dot", self.root)
        shutil.copytree(REPO / "lib", self.root / "lib")
        for layer in ("global", "platforms/wsl", "platforms/macos", "platforms/omarchy"):
            (self.root / layer).mkdir(parents=True)
        self.env = dict(os.environ, HOME=str(self.home), DOT_ROOT=str(self.root),
                        DOT_PLATFORM="wsl", STOW_COMMAND=STOW or "stow")

    def write(self, path, text="config\n"):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def cli(self, *args, ok=True):
        result = subprocess.run(["bash", str(self.root / "dot"), *map(str, args)],
                                env=self.env, cwd=self.home, input="", text=True,
                                capture_output=True, timeout=15)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def backup(self):
        backups = sorted((self.home / ".local/state/dot/backups").iterdir())
        self.assertTrue(backups)
        return backups[-1]

    def assert_link(self, path, source):
        self.assertTrue(path.is_symlink(), str(path))
        self.assertEqual(path.resolve(), source.resolve())

    def test_deploy_no_prompt_and_true_noop(self):
        source = self.write(self.root / "global/.config/app/settings")
        target = self.home / ".config/app/settings"
        self.cli("deploy")
        self.assert_link(target, source)
        identity = target.lstat().st_ino
        output = self.cli("deploy").stdout
        self.assertIn("Already up to date", output)
        self.assertLessEqual(len(output.splitlines()), 2)
        self.assertEqual(target.lstat().st_ino, identity)
        self.assertFalse((self.home / ".local/state/dot").exists())

    def test_dry_run_is_read_only(self):
        self.write(self.root / "global/.config/app/file")
        output = self.cli("deploy", "--dry-run").stdout
        self.assertIn("Would link", output)
        self.assertFalse((self.home / ".config").exists())

    def test_conflict_refused_then_replaced_with_backup(self):
        source = self.write(self.root / "global/.config/app", "tracked")
        target = self.write(self.home / ".config/app", "personal")
        result = self.cli("deploy", ok=False)
        self.assertIn("--replace", result.stderr)
        self.assertEqual(target.read_text(), "personal")
        self.cli("deploy", "--replace", "--dry-run")
        self.assertEqual(target.read_text(), "personal")
        self.assertFalse((self.home / ".local/state").exists())
        self.cli("deploy", "--replace")
        self.assert_link(target, source)
        self.assertEqual((self.backup() / "files/.config/app").read_text(), "personal")

    def test_identical_files_link_without_backup_but_modes_matter(self):
        source = self.write(self.root / "global/.tool")
        target = self.write(self.home / ".tool")
        self.cli("deploy")
        self.assert_link(target, source)
        self.assertFalse((self.home / ".local/state").exists())
        target.unlink()
        self.write(target).chmod(0o700)
        self.cli("deploy", ok=False)
        self.assertEqual(target.stat().st_mode & 0o777, 0o700)

    def test_parent_conflicts_and_legacy_folded_links(self):
        source = self.write(self.root / "global/.config/app/file")
        foreign = self.write(self.base / "foreign/file", "foreign")
        (self.home / ".config").symlink_to(foreign.parent)
        self.cli("deploy", ok=False)
        self.cli("deploy", "--replace")
        self.assert_link(self.home / ".config/app/file", source)
        self.assertEqual(foreign.read_text(), "foreign")
        self.cli("backups", "restore", "latest")
        self.assertTrue((self.home / ".config").is_symlink())
        self.assertEqual((self.home / ".config").resolve(), foreign.parent)
        (self.home / ".config").unlink()
        (self.home / ".config").symlink_to(self.root / "global/.config")
        self.cli("deploy")
        self.assertEqual(source.read_text(), "config\n")
        self.assert_link(self.home / ".config/app/file", source)

    def test_layer_collisions_refused(self):
        self.write(self.root / "global/.config/app")
        self.write(self.root / "platforms/wsl/.config/app/child")
        self.cli("deploy", ok=False)
        self.assertFalse((self.home / ".config").exists())

    def test_adapter_links_and_repository_escape(self):
        canonical = self.write(self.root / "global/.canonical")
        (self.root / "platforms/wsl/.adapter").symlink_to("../../global/.canonical")
        self.cli("deploy")
        self.assert_link(self.home / ".adapter", canonical)
        (self.home / ".canonical").unlink()
        (self.root / "escape").symlink_to(self.base / "foreign")
        (self.home / ".canonical").symlink_to(self.root / "escape/missing")
        self.cli("deploy", ok=False)
        self.assertEqual(os.readlink(self.home / ".canonical"), str(self.root / "escape/missing"))

    def test_stow_ignore_rules(self):
        self.write(self.root / "global/.stow-local-ignore", "^skills-lock\\.json$\n^/cache\n")
        self.write(self.root / "global/skills-lock.json")
        self.write(self.root / "global/cache/file")
        source = self.write(self.root / "global/.agents/skills/demo/README.md")
        self.write(self.root / "platforms/wsl/README.md")
        self.cli("deploy")
        self.assert_link(self.home / ".agents/skills/demo/README.md", source)
        self.assertFalse((self.home / "skills-lock.json").exists())
        self.assertFalse((self.home / "cache").exists())
        self.assertFalse((self.home / "README.md").exists())
        self.assertIn("Already up to date", self.cli("deploy").stdout)

    def test_failed_layer_keeps_successful_work(self):
        self.write(self.root / "global/.one")
        self.write(self.root / "platforms/wsl/.two")
        fake = self.write(self.base / "stow", '#!/bin/sh\ncase "$*" in *" wsl") exit 1;; esac\nexec "$REAL_STOW" "$@"\n')
        fake.chmod(0o755)
        self.env.update(STOW_COMMAND=str(fake), REAL_STOW=STOW)
        self.cli("deploy", ok=False)
        self.assertTrue((self.home / ".one").is_symlink())
        self.env["STOW_COMMAND"] = STOW
        self.cli("deploy")
        self.assertTrue((self.home / ".two").is_symlink())

    def test_add_file_requires_layer_and_preserves_mode(self):
        target = self.write(self.home / ".config/tool/settings file", "personal")
        target.chmod(0o600)
        result = self.cli("add", target, ok=False)
        self.assertEqual(result.returncode, 2)
        self.cli("add", target, "--platform", "--dry-run")
        self.assertFalse((self.root / "platforms/wsl/.config").exists())
        self.cli("add", target, "--platform")
        source = self.root / "platforms/wsl/.config/tool/settings file"
        self.assert_link(target, source)
        self.assertEqual(source.read_text(), "personal")
        self.assertEqual(source.stat().st_mode & 0o777, 0o600)
        self.assertIn("Already managed", self.cli("add", target, "--platform").stdout)

    def test_add_directory_merges_new_files_and_skips_managed(self):
        tree = self.home / ".config/tool"
        self.write(tree / "nested/.hidden", "hidden")
        self.write(tree / "config", "main")
        (tree / "empty").mkdir()
        (tree / "alias").symlink_to("config")
        self.cli("add", tree, "--global")
        self.assertTrue(tree.is_dir())
        self.assertFalse(tree.is_symlink())
        self.assert_link(tree / "nested/.hidden", self.root / "global/.config/tool/nested/.hidden")
        self.assertEqual((tree / "alias").read_text(), "main")
        self.assertTrue((self.root / "global/.config/tool/empty").is_dir())
        self.write(tree / "new file", "later")
        self.cli("add", tree, "--global")
        self.assert_link(tree / "new file", self.root / "global/.config/tool/new file")
        self.assertIn("Already up to date", self.cli("deploy").stdout)

    def test_add_does_not_deploy_unrelated_files(self):
        self.write(self.root / "global/.unrelated", "repo")
        other = self.write(self.home / ".unrelated", "keep")
        target = self.write(self.home / ".new")
        self.cli("add", target, "--global")
        self.assertEqual(other.read_text(), "keep")
        self.assertFalse(other.is_symlink())

    def test_add_refuses_repository_overwrite_and_cross_layer_ownership(self):
        target = self.write(self.home / ".config/app", "personal")
        source = self.write(self.root / "global/.config/app", "tracked")
        self.cli("add", target, "--global", ok=False)
        self.assertEqual(source.read_text(), "tracked")
        self.assertEqual(target.read_text(), "personal")
        self.cli("add", target, "--platform", ok=False)
        self.assertFalse((self.root / "platforms/wsl/.config").exists())

    def test_add_rejects_outside_home_repo_and_foreign_symlink(self):
        outside = self.write(self.base / "outside")
        self.cli("add", outside, "--global", ok=False)
        self.cli("add", self.home, "--global", ok=False)
        self.cli("add", self.root, "--global", ok=False)
        (self.home / ".foreign").symlink_to(outside)
        self.cli("add", self.home / ".foreign", "--global", ok=False)
        self.assertEqual(outside.read_text(), "config\n")

    def test_add_multiple_paths_and_ignored_files(self):
        self.write(self.root / "global/.stow-local-ignore", "^ignored$\n")
        first = self.write(self.home / ".one")
        second = self.write(self.home / ".two")
        ignored = self.write(self.home / "ignored")
        self.cli("add", first, second, ignored, "--global")
        self.assertTrue(first.is_symlink())
        self.assertTrue(second.is_symlink())
        self.assertFalse(ignored.is_symlink())
        self.assertFalse((self.root / "global/ignored").exists())

    def test_undeploy_leaves_unrelated_files_and_directories(self):
        self.write(self.root / "global/.config/app")
        self.write(self.root / "global/.other")
        self.cli("deploy")
        (self.home / ".other").unlink()
        foreign = self.write(self.base / "foreign")
        (self.home / ".other").symlink_to(foreign)
        self.cli("undeploy", "--dry-run")
        self.assertTrue((self.home / ".config/app").is_symlink())
        self.cli("undeploy")
        self.assertFalse((self.home / ".config/app").exists())
        self.assertTrue((self.home / ".config").is_dir())
        self.assertTrue((self.home / ".other").is_symlink())

    def test_backups_lifecycle(self):
        self.write(self.root / "global/.app", "repo")
        target = self.write(self.home / ".app", "home")
        self.cli("deploy", "--replace")
        backup = self.backup()
        self.assertIn(backup.name, self.cli("backups", "list").stdout)
        self.cli("backups", "restore", "latest", "--dry-run")
        self.assertTrue(target.is_symlink())
        self.cli("backups", "restore", "latest")
        self.assertEqual(target.read_text(), "home")
        self.assertFalse(target.is_symlink())
        self.cli("backups", "restore", "latest", ok=False)
        self.cli("backups", "remove", backup.name, "--dry-run")
        self.assertTrue(backup.exists())
        os.utime(backup, (0, 0))
        self.cli("backups", "prune", "--older-than", "30d", "--dry-run")
        self.assertTrue(backup.exists())
        self.cli("backups", "prune", "--older-than", "30d")
        self.assertFalse(backup.exists())

    def test_legacy_backup_and_unsafe_metadata(self):
        backup = self.home / ".local/state/dot/backups/old"
        self.write(backup / ".dot-backup-roots", ".app\n")
        self.write(backup / ".app", "old")
        self.cli("backups", "restore", "old")
        self.assertEqual((self.home / ".app").read_text(), "old")
        self.write(backup / ".dot-backup-roots", "../outside\n")
        self.cli("backups", "restore", "old", ok=False)
        self.write(backup / ".dot-backup-roots", "tree\ntree/file\n")
        self.cli("backups", "restore", "old", ok=False)
        self.cli("backups", "remove", "../outside", ok=False)

    def test_stow_option_files_cannot_adopt_or_rename_sources(self):
        source = self.write(self.root / "global/.app", "repo")
        target = self.write(self.home / ".app", "home")
        self.write(self.home / ".stowrc", "--adopt\n--dotfiles\n")
        self.cli("deploy", "--replace", ok=False)
        self.assertEqual(source.read_text(), "repo")
        self.assertEqual(target.read_text(), "home")
        self.assertFalse((self.home / ".local/state").exists())

    def test_stow_option_file_cannot_be_deployed_between_layers(self):
        self.write(self.root / "global/.stowrc", "--adopt\n")
        self.write(self.root / "platforms/wsl/.app", "repo")
        target = self.write(self.home / ".app", "home")
        self.cli("deploy", "--replace", ok=False)
        self.assertEqual(target.read_text(), "home")
        self.assertFalse((self.home / ".stowrc").exists())

    def test_interactive_conflicts_ask_once(self):
        source = self.write(self.root / "global/.app", "repo")
        target = self.write(self.home / ".app", "home")
        master, slave = pty.openpty()
        try:
            with subprocess.Popen(["bash", str(self.root / "dot"), "deploy"],
                                  env=self.env, cwd=self.home, stdin=slave,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as process:
                os.write(master, b"yes\n")
                stdout, stderr = process.communicate(timeout=15)
                self.assertEqual(process.returncode, 0, stdout + stderr)
                self.assertEqual(stdout.count("[y/N]"), 1)
        finally:
            os.close(master)
            os.close(slave)
        self.assert_link(target, source)
        self.assertEqual((self.backup() / "files/.app").read_text(), "home")

    def test_deploy_refuses_repository_overlap(self):
        source = self.write(self.root / "global/dotfiles/dot", "oops")
        original = (self.root / "dot").read_text()
        self.cli("deploy", "--replace", ok=False)
        self.assertEqual((self.root / "dot").read_text(), original)
        self.assertEqual(source.read_text(), "oops")

    def test_legacy_and_dangling_owned_links_are_relinked(self):
        source = self.write(self.root / "global/.app", "new")
        target = self.home / ".app"
        target.symlink_to(self.root / "removed/file")
        self.cli("deploy")
        self.assert_link(target, source)
        self.assertFalse((self.home / ".local/state").exists())

    def test_add_preflights_all_inputs_before_importing(self):
        first = self.write(self.home / ".first")
        second = self.write(self.home / ".second", "personal")
        tracked = self.write(self.root / "global/.second", "repo")
        self.cli("add", first, second, "--global", ok=False)
        self.assertFalse(first.is_symlink())
        self.assertFalse((self.root / "global/.first").exists())
        self.assertEqual(tracked.read_text(), "repo")

    def test_add_identical_existing_file_and_inactive_platform_conflict(self):
        first = self.write(self.home / ".first")
        source = self.write(self.root / "global/.first")
        self.cli("add", first, "--global")
        self.assert_link(first, source)
        second = self.write(self.home / ".second")
        self.write(self.root / "platforms/macos/.second")
        self.cli("add", second, "--global", ok=False)
        self.assertFalse(second.is_symlink())

    def test_add_relative_symlink_must_keep_its_referent(self):
        tree = self.home / ".tool"
        self.write(tree / "config")
        (tree / "alias").symlink_to("config")
        self.write(self.root / "global/.stow-local-ignore", "^config$\n")
        self.cli("add", tree, "--global", ok=False)
        self.assertFalse((self.root / "global/.tool").exists())
        self.assertEqual((tree / "alias").read_text(), "config\n")
        # A HOME alias to a managed file isn't itself stored in the repo yet.
        (self.root / "global/.stow-local-ignore").unlink()
        self.cli("add", tree / "config", "--platform")
        self.cli("add", tree, "--global", ok=False)
        self.cli("add", tree, "--platform")
        self.assertTrue((self.root / "platforms/wsl/.tool/alias").is_symlink())
        self.assertEqual((tree / "alias").read_text(), "config\n")

    def test_add_applies_directory_modes_after_copying_children(self):
        tree = self.home / ".tool"
        self.write(tree / "nested/config")
        tree.chmod(0o555)
        self.cli("add", tree, "--global")
        self.assertEqual((self.root / "global/.tool").stat().st_mode & 0o777, 0o555)
        self.assert_link(tree / "nested/config", self.root / "global/.tool/nested/config")

    def test_undeploy_does_not_traverse_foreign_parent_links(self):
        source = self.write(self.root / "global/.config/app")
        foreign = self.base / "foreign"
        foreign.mkdir()
        (foreign / "app").symlink_to(source)
        (self.home / ".config").symlink_to(foreign)
        self.cli("undeploy")
        self.assertTrue((foreign / "app").is_symlink())
        self.assertTrue((self.home / ".config").is_symlink())

    def test_restore_replace_backs_up_current_content(self):
        self.write(self.root / "global/.app", "repo")
        target = self.write(self.home / ".app", "original")
        self.cli("deploy", "--replace")
        backup = self.backup()
        target.unlink()
        self.write(target, "later")
        self.cli("backups", "restore", backup.name, "--replace", "--dry-run")
        self.assertEqual(target.read_text(), "later")
        self.cli("backups", "restore", backup.name, "--replace")
        self.assertEqual(target.read_text(), "original")
        self.assertEqual((self.backup() / "files/.app").read_text(), "later")
        self.assertTrue(backup.exists())

    def test_latest_backup_uses_age_not_name(self):
        self.write(self.root / "global/.app", "repo")
        self.write(self.home / ".app", "original")
        self.cli("deploy", "--replace")
        recent = self.backup()
        legacy = recent.parent / "zz-legacy"
        self.write(legacy / ".dot-backup-roots", ".app\n")
        self.write(legacy / ".app", "old")
        os.utime(legacy, (0, 0))
        self.cli("backups", "restore", "latest")
        self.assertEqual((self.home / ".app").read_text(), "original")
        self.cli("backups", "remove", "latest")
        self.assertFalse(recent.exists())
        self.assertTrue(legacy.exists())

    def test_backup_metadata_and_payload_symlinks_cannot_escape(self):
        backup = self.home / ".local/state/dot/backups/test"
        self.write(backup / "manifest.json", json.dumps(["tree/file"]))
        foreign = self.write(self.base / "foreign/file", "foreign")
        (backup / "files").mkdir()
        (backup / "files/tree").symlink_to(foreign.parent)
        self.cli("backups", "restore", "test", ok=False)
        self.assertFalse((self.home / "tree").exists())
        (backup / "manifest.json").unlink()
        (backup / "manifest.json").symlink_to(foreign)
        self.cli("backups", "restore", "test", ok=False)
        (backup.parent / "external").symlink_to(foreign.parent)
        self.cli("backups", "remove", "external", ok=False)
        self.assertEqual(foreign.read_text(), "foreign")

    def test_backup_duplicate_metadata_is_rejected(self):
        backup = self.home / ".local/state/dot/backups/test"
        self.write(backup / "manifest.json", json.dumps([".app", ".app"]))
        self.write(backup / "files/.app")
        self.cli("backups", "restore", "test", ok=False)
        self.assertFalse((self.home / ".app").exists())

    def test_check_reports_missing_and_conflicting_targets(self):
        self.write(self.root / "global/.app")
        self.cli("deploy", "--dry-run")
        result = subprocess.run(["python3", str(self.root / "lib/files.py"), "check"],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.cli("deploy")
        result = subprocess.run(["python3", str(self.root / "lib/files.py"), "check"],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
