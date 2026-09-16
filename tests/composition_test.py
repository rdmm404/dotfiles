# /// script
# requires-python = ">=3.9"
# dependencies = ["tomlkit==0.13.3"]
# ///
"""Composition CLI tests. Deployments, state, and helper caches use temp dirs."""
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

import tomlkit

sys.dont_write_bytecode = True
from files_test import DotFixture, REPO


class CompositionTests(DotFixture):
    @classmethod
    def setUpClass(cls):
        cls.cache = tempfile.TemporaryDirectory(prefix="dot-uv-test-")
        cls.addClassCleanup(cls.cache.cleanup)

    def setUp(self):
        super().setUp()
        self.env["UV_CACHE_DIR"] = self.cache.name
        self.relative = Path(".config/app/config.toml")
        self.target = self.home / self.relative
        self.base_file = self.root / "global" / self.relative
        self.overlay = self.root / "platforms/omarchy/.config/app/config.merge.toml"
        self.write(self.base_file, '[ui]\ncolor = "blue"\nkeep = true\nkeys = ["a", "b"]\n')
        self.write(self.overlay, '[ui]\ncolor = "red"\nkeys = ["c"]\n')
        # Doctor tests only deployment, not this machine's installed apps.
        shutil.copytree(REPO / "installers", self.root / "installers")
        for name in ("catalog", "core", "development", "optional"):
            self.write(self.root / "manifests" / name, "# no applications\n")

    def parsed(self, path=None):
        return tomlkit.parse((path or self.target).read_text()).unwrap()

    def no_uv(self):
        bin_dir = self.base / "bin"
        bin_dir.mkdir()
        (bin_dir / "bash").symlink_to("/bin/bash")
        (bin_dir / "python3").symlink_to(sys.executable)
        self.env["PATH"] = str(bin_dir)

    def test_merge_is_recursive_and_arrays_replace(self):
        self.cli("deploy", "--verbose")
        self.assertEqual(self.parsed(), {"ui": {"color": "red", "keep": True, "keys": ["c"]}})
        self.assertTrue(self.target.is_symlink())
        self.assertIn("/dot/generated/", str(self.target.resolve()))
        self.assertFalse((self.home / ".config/app/config.merge.toml").exists())
        self.assertIn('color = "blue"', self.base_file.read_text())
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.cli("doctor")

    def test_table_scalar_type_changes_and_arrays_of_tables(self):
        self.write(self.base_file, 'scalar = 1\narray = [1, 2]\n[table]\na = true\n[[items]]\nx = 1\n')
        self.write(self.overlay, 'table = "replace"\n[scalar]\nx = 2\n[array]\ny = 3\n[[items]]\nx = 9\n')
        self.cli("deploy")
        self.assertEqual(self.parsed(), {"scalar": {"x": 2}, "array": {"y": 3},
                                         "table": "replace", "items": [{"x": 9}]})

    def test_dates_unicode_and_quoted_dotted_keys(self):
        self.write(self.base_file, '"a.b" = { keep = true, value = "old" }\ndate = 2020-01-02\n')
        self.write(self.overlay, '"a.b" = { value = "こんにちは" }\n')
        self.cli("deploy")
        self.assertEqual(self.parsed()["a.b"], {"keep": True, "value": "こんにちは"})
        self.assertEqual(str(self.parsed()["date"]), "2020-01-02")

    def test_full_file_wins_warns_in_deploy_and_doctor(self):
        full = self.write(self.overlay.with_name("config.toml"), 'full = true\n')
        self.write(self.overlay, "invalid TOML {{{")
        self.no_uv()
        result = self.cli("deploy")
        self.assertIn("ignored", result.stderr)
        self.assertIn("only one", result.stderr)
        self.assert_link(self.target, full)
        self.assertIn("ignored", self.cli("doctor").stderr)
        self.assertFalse((self.home / ".local/state").exists())
        self.base_file.unlink()
        self.cli("deploy")  # Ignored overlays don't even require a base.

    def test_unsupported_ignored_overlay_is_not_validated(self):
        self.overlay.unlink()
        full = self.write(self.overlay.with_name("config.json"), '{"full": true}')
        self.write(self.overlay.with_name("config.merge.json"), "invalid")
        self.no_uv()
        self.assertIn("ignored", self.cli("deploy").stderr)
        self.assert_link(self.home / ".config/app/config.json", full)

    def test_invalid_inputs_fail_before_any_changes(self):
        self.write(self.root / "global/.unrelated")
        self.write(self.overlay, "broken = [")
        result = self.cli("deploy", "--replace", ok=False)
        self.assertIn("Configuration merge failed", result.stderr)
        self.assertFalse((self.home / ".unrelated").exists())
        self.assertFalse((self.home / ".local/state").exists())
        self.write(self.overlay, "valid = true")
        self.write(self.base_file, "broken = [")
        self.cli("deploy", ok=False)
        self.assertFalse((self.home / ".config").exists())

    def test_bad_second_merge_does_not_partially_update_first(self):
        self.cli("deploy")
        original = self.target.read_bytes()
        self.write(self.overlay, "updated = true\n")
        self.write(self.root / "global/.config/z-last/config.toml", "valid = true\n")
        self.write(self.root / "platforms/omarchy/.config/z-last/config.merge.toml", "invalid = [")
        self.cli("deploy", "--replace", ok=False)
        self.assertEqual(self.target.read_bytes(), original)
        self.assertFalse((self.home / ".config/z-last").exists())

    def test_missing_base_and_unsupported_format(self):
        self.base_file.unlink()
        self.assertIn("no global base", self.cli("deploy", ok=False).stderr)
        self.overlay.unlink()
        self.write(self.base_file.with_suffix(".json"), "{}")
        self.write(self.overlay.with_name("config.merge.json"), "{}")
        self.assertIn("Unsupported merge format", self.cli("deploy", ok=False).stderr)
        self.assertFalse((self.home / ".config").exists())

    def test_merge_markers_in_global_are_rejected(self):
        self.overlay.unlink()
        self.write(self.base_file.with_name("other.merge.toml"), "x = 1")
        self.assertIn("platform layers", self.cli("deploy", ok=False).stderr)

    def test_merge_file_directory_collisions(self):
        self.base_file.unlink()
        self.write(self.base_file / "child")
        self.assertIn("regular file inputs", self.cli("deploy", ok=False).stderr)
        shutil.rmtree(self.base_file)
        self.write(self.base_file, "x = 1")
        self.write(self.overlay.with_name("config.toml") / "child")
        self.assertIn("File/directory", self.cli("deploy", ok=False).stderr)

    def test_missing_uv_only_blocks_active_composition(self):
        self.no_uv()
        self.assertIn("UV is required", self.cli("deploy", ok=False).stderr)
        self.assertFalse((self.home / ".config").exists())
        self.overlay.unlink()
        self.cli("deploy")
        self.assert_link(self.target, self.base_file)

    def test_uv_installed_in_local_bin_is_found(self):
        uv = shutil.which("uv")
        self.no_uv()
        local = self.home / ".local/bin/uv"
        local.parent.mkdir(parents=True)
        local.symlink_to(uv)
        self.cli("deploy")
        self.assertTrue(self.target.is_symlink())

    def test_dry_run_leaves_deployment_state_untouched(self):
        output = self.cli("deploy", "--dry-run", "--verbose").stdout
        self.assertIn("Merge global/", output)
        self.assertIn("dot/generated/", output)
        self.assertFalse((self.home / ".config").exists())
        self.assertFalse((self.home / ".local/state").exists())
        self.assertFalse((self.root / "lib/__pycache__").exists())
        self.cli("deploy")
        generated = self.target.resolve()
        previous = generated.read_bytes()
        self.write(self.overlay, 'different = true\n')
        self.cli("deploy", "--dry-run")
        self.assertEqual(generated.read_bytes(), previous)
        self.cli("doctor", ok=False)
        self.assertEqual(generated.read_bytes(), previous)

    def test_noop_and_regeneration_preserve_link_identity(self):
        self.cli("deploy")
        generated = self.target.resolve()
        link_identity = self.target.lstat().st_ino
        output_identity = generated.stat().st_ino
        metadata = generated.parents[3] / "omarchy.json"
        metadata_time = metadata.stat().st_mtime_ns
        self.assertIn("Already up to date", self.cli("deploy").stdout)
        self.assertEqual(generated.stat().st_ino, output_identity)
        self.assertEqual(metadata.stat().st_mtime_ns, metadata_time)
        self.write(self.overlay, '[ui]\ncolor = "green"\n')
        self.assertIn("Regenerated", self.cli("deploy").stdout)
        self.assertEqual(self.target.lstat().st_ino, link_identity)
        self.assertEqual(self.parsed()["ui"]["color"], "green")
        self.write(self.base_file, '[ui]\nnew = "base edit"\n')
        self.cli("deploy")
        self.assertEqual(self.parsed()["ui"]["new"], "base edit")
        self.cli("doctor")

    def test_edited_output_requires_replace_and_backup_is_a_snapshot(self):
        self.cli("deploy")
        self.target.write_text('personal = true\n')
        result = self.cli("deploy", ok=False)
        self.assertIn("Generated configuration was edited", result.stderr)
        self.cli("doctor", ok=False)
        self.cli("deploy", "--replace", "--dry-run")
        self.assertEqual(self.target.read_text(), 'personal = true\n')
        self.cli("deploy", "--replace")
        saved = self.backup() / "files" / self.relative
        self.assertFalse(saved.is_symlink())
        self.assertEqual(saved.read_text(), 'personal = true\n')
        self.assertIn("ui", self.parsed())
        self.cli("backups", "restore", "latest")
        self.assertFalse(self.target.is_symlink())
        self.assertEqual(self.target.read_text(), 'personal = true\n')

    def test_retained_edits_protected_when_home_link_is_missing(self):
        self.cli("deploy")
        generated = self.target.resolve()
        self.cli("undeploy")
        generated.write_text('retained = true\n')
        self.cli("deploy", ok=False)
        self.cli("deploy", "--replace")
        self.assertEqual((self.backup() / "files" / self.relative).read_text(), 'retained = true\n')
        self.assertIn("ui", self.parsed())

    def test_retained_edits_and_unrelated_home_conflict_are_both_backed_up(self):
        self.cli("deploy")
        generated = self.target.resolve()
        generated.write_text('retained = true\n')
        self.target.unlink()
        self.target.write_text('home = true\n')
        self.cli("deploy", "--replace")
        backups = self.home / ".local/state/dot/backups"
        texts = {(folder / "files" / self.relative).read_text() for folder in backups.iterdir()}
        self.assertEqual(texts, {'retained = true\n', 'home = true\n'})

    def test_overlay_removal_and_full_replacement(self):
        self.cli("deploy")
        generated = self.target.resolve()
        self.overlay.unlink()
        self.cli("deploy")
        self.assert_link(self.target, self.base_file)
        self.assertTrue(generated.exists())
        self.write(self.overlay, "x = 1")
        self.cli("deploy")
        full = self.write(self.overlay.with_name("config.toml"), "full = true")
        self.cli("deploy")
        self.assert_link(self.target, full)

    def test_overlay_removal_protects_modified_output(self):
        self.cli("deploy")
        self.target.write_text("edited = true\n")
        self.overlay.unlink()
        self.cli("deploy", ok=False)
        self.cli("deploy", "--replace")
        self.assert_link(self.target, self.base_file)
        self.assertEqual((self.backup() / "files" / self.relative).read_text(), "edited = true\n")

    def test_undeploy_retains_edits_and_does_not_need_uv_or_valid_toml(self):
        self.cli("deploy")
        generated = self.target.resolve()
        generated.write_text("edited = true\n")
        self.write(self.overlay, "invalid = [")
        self.no_uv()
        self.cli("undeploy", "--dry-run")
        self.assertTrue(self.target.is_symlink())
        self.cli("undeploy")
        self.assertFalse(self.target.is_symlink())
        self.assertEqual(generated.read_text(), "edited = true\n")

    def test_undeploy_finds_outputs_even_after_sources_removed(self):
        self.cli("deploy")
        generated = self.target.resolve()
        self.base_file.unlink()
        self.overlay.unlink()
        self.cli("undeploy")
        self.assertFalse(self.target.is_symlink())
        self.assertTrue(generated.exists())

    def test_xdg_state_and_platform_isolation(self):
        state = self.base / "external-state"
        self.env["XDG_STATE_HOME"] = str(state)
        self.cli("deploy")
        omarchy_output = self.target.resolve()
        self.assertIn(str(state), str(omarchy_output))
        self.env["DOT_PLATFORM"] = "macos"
        self.write(self.root / "platforms/macos/.config/app/config.merge.toml", 'macos = true\n')
        self.cli("deploy")
        macos_output = self.target.resolve()
        self.assertNotEqual(macos_output, omarchy_output)
        self.assertTrue(self.parsed()["macos"])
        self.assertNotIn("macos", self.parsed(omarchy_output))

    def test_different_clones_do_not_share_outputs(self):
        self.cli("deploy")
        first = self.target.resolve()
        second_root = self.home / "other-clone"
        shutil.copytree(self.root, second_root, symlinks=True)
        self.env["DOT_ROOT"] = str(second_root)
        self.cli("deploy", ok=False)  # Other clone's link isn't owned by this clone.
        self.cli("deploy", "--replace")
        self.assertNotEqual(self.target.resolve(), first)
        self.assertTrue(first.exists())

    def test_metadata_loss_does_not_adopt_existing_output(self):
        self.cli("deploy")
        output = self.target.resolve()
        metadata = output.parents[3] / "omarchy.json"
        self.assertTrue(metadata.exists())
        metadata.unlink()
        self.cli("deploy", ok=False)
        self.cli("deploy", "--replace")
        self.cli("doctor")

    def test_missing_output_is_regenerated(self):
        self.cli("deploy")
        generated = self.target.resolve()
        generated.unlink()
        self.cli("deploy")
        self.assertIn("ui", self.parsed())
        self.cli("doctor")

    def test_state_symlinks_are_never_followed(self):
        self.cli("deploy")
        generated = self.target.resolve()
        foreign = self.write(self.base / "foreign", "preserve")
        generated.unlink()
        generated.symlink_to(foreign)
        self.cli("deploy", "--replace", ok=False)
        self.assertEqual(foreign.read_text(), "preserve")

    def test_state_directory_symlink_and_repository_storage_rejected(self):
        state = self.home / ".local/state"
        state.mkdir(parents=True)
        foreign = self.base / "foreign-dir"
        foreign.mkdir()
        (state / "dot").symlink_to(foreign)
        self.cli("deploy", "--replace", ok=False)
        self.assertEqual(list(foreign.iterdir()), [])
        self.env["XDG_STATE_HOME"] = str(self.root / "state")
        self.assertIn("outside the repository", self.cli("deploy", ok=False).stderr)
        self.assertFalse((self.root / "state").exists())
        self.env["XDG_STATE_HOME"] = "relative/state"
        self.assertIn("absolute path", self.cli("deploy", ok=False).stderr)

    def test_metadata_symlink_and_unsafe_records_rejected(self):
        self.cli("deploy")
        output = self.target.resolve()
        metadata = output.parents[3] / "omarchy.json"
        original = metadata.read_text()
        self.write(metadata, json.dumps({"../escape": "a" * 64}))
        self.cli("deploy", ok=False)
        foreign = self.write(self.base / "metadata", original)
        metadata.unlink()
        metadata.symlink_to(foreign)
        self.cli("deploy", "--replace", ok=False)
        self.assertEqual(foreign.read_text(), original)

    def test_generated_metadata_cannot_unlink_repository_files(self):
        self.cli("deploy")
        output = self.target.resolve()
        metadata = output.parents[3] / "omarchy.json"
        source = self.write(self.root / "global/.source", "keep")
        alias = self.root / "global/.alias"
        alias.symlink_to(source)
        name = alias.relative_to(self.home).as_posix()
        self.write(metadata, json.dumps({name: "a" * 64}))
        self.cli("undeploy", ok=False)
        self.assertTrue(alias.is_symlink())
        self.assertEqual(source.read_text(), "keep")

    def test_ignored_marker_leaves_base_unmerged(self):
        self.write(self.root / "platforms/omarchy/.stow-local-ignore", r".*\.merge\.toml" + "\n")
        self.cli("deploy")
        self.assert_link(self.target, self.base_file)
        self.assertFalse((self.home / ".local/state").exists())

    def test_add_skips_generated_links_instead_of_importing_output(self):
        self.cli("deploy")
        self.assertIn("Already managed", self.cli("add", self.target, "--platform").stdout)
        self.assertFalse(self.overlay.with_name("config.toml").exists())


if __name__ == "__main__":
    unittest.main()
