"""Offline tests only: no real Docker, services, Google Drive or privileged work."""
from contextlib import closing
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tarfile
import tempfile
import types
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("preparation", Path(__file__).with_name("prepare_backup.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.old_umask = os.umask(0o077)

    def tearDown(self):
        os.umask(self.old_umask)

    def test_sqlite_includes_uncheckpointed_wal_without_modifying_source(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "live.db"
            connection = sqlite3.connect(source)
            try:
                connection.execute("PRAGMA journal_mode=WAL")
                connection.execute("PRAGMA wal_autocheckpoint=0")
                connection.execute("CREATE TABLE entries (value TEXT)")
                connection.execute("INSERT INTO entries VALUES ('committed in WAL')")
                connection.commit()
                self.assertTrue(Path(str(source) + "-wal").is_file())
                before = source.read_bytes()
                output = Path(folder) / "export/snapshot.db"
                metadata = m.backup_sqlite(source, output)
                with closing(sqlite3.connect(output)) as restored:
                    self.assertEqual(restored.execute("SELECT value FROM entries").fetchall(), [("committed in WAL",)])
                    self.assertEqual(restored.execute("PRAGMA integrity_check").fetchone(), ("ok",))
                self.assertEqual(source.read_bytes(), before)
                self.assertEqual(output.stat().st_mode & 0o777, 0o600)
                self.assertFalse(Path(str(output) + "-wal").exists())
                self.assertEqual(metadata["source"], str(source))
            finally:
                connection.close()

    def test_sqlite_missing_source_does_not_create_a_database(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "missing.db"
            with self.assertRaises(sqlite3.OperationalError):
                m.backup_sqlite(source, Path(folder) / "output.db")
            self.assertFalse(source.exists())

    def test_failed_preparation_keeps_previous_and_removes_partial_set(self):
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder) / "state"
            exports = state / "exports"
            exports.mkdir(parents=True)
            (exports / "sentinel").write_text("previous complete set")
            def fail(destination):
                (destination / "private-partial-dump").write_text("partial")
                raise RuntimeError("required capture failed")
            with patch.object(m, "STATE", state), patch.object(m, "EXPORTS", exports), patch.object(m, "preflight", return_value={}), patch.object(m, "prepare_exports", side_effect=fail), patch.object(m.sys, "argv", ["prepare_backup.py"]), patch.dict(os.environ, {"PROFILE_NAME": "nautilus", "PROFILE_COMMAND": "backup"}):
                with self.assertRaisesRegex(RuntimeError, "required capture failed"):
                    m.main()
            self.assertEqual((exports / "sentinel").read_text(), "previous complete set")
            self.assertEqual(list(state.iterdir()), [exports])

    def test_publish_replaces_complete_set_privately(self):
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder)
            exports = state / "exports"
            exports.mkdir()
            (exports / "old").write_text("old")
            temporary = state / ".temporary"
            temporary.mkdir(mode=0o700)
            (temporary / "new").write_text("new")
            with patch.object(m, "STATE", state), patch.object(m, "EXPORTS", exports):
                m.publish(temporary)
            self.assertEqual((exports / "new").read_text(), "new")
            self.assertFalse((exports / "old").exists())
            self.assertFalse((state / "exports.previous").exists())

    def test_cleanup_rejects_symlink_and_keeps_target(self):
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder) / "state"
            state.mkdir()
            outside = Path(folder) / "outside"
            outside.mkdir()
            exports = state / "exports"
            exports.symlink_to(outside)
            with patch.object(m, "STATE", state), patch.object(m, "EXPORTS", exports):
                with self.assertRaises(RuntimeError):
                    m.cleanup_exports()
            self.assertTrue(outside.is_dir())

    def test_cleanup_refuses_unfinished_publication(self):
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder)
            exports = state / "exports"
            exports.mkdir()
            (state / "exports.previous").mkdir()
            with patch.object(m, "STATE", state), patch.object(m, "EXPORTS", exports):
                with self.assertRaises(RuntimeError):
                    m.cleanup_exports()
            self.assertTrue(exports.exists())

    def test_preflight_rejects_disabled_prometheus_api_before_captures(self):
        modules = {name: types.ModuleType(name) for name in ("paho", "paho.mqtt", "paho.mqtt.client")}
        details = {"Id": "test", "Config": {"Cmd": ["--web.enable-lifecycle"]}}
        with patch.dict(m.sys.modules, modules), patch.object(m.os, "geteuid", return_value=0), patch.object(m, "inspect_container", return_value=details):
            with self.assertRaisesRegex(RuntimeError, "snapshot API is disabled"):
                m.preflight()

    def test_container_change_prevents_publication(self):
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder) / "state"
            exports = state / "exports"
            exports.mkdir(parents=True)
            (exports / "old").write_text("old")
            with patch.object(m, "STATE", state), patch.object(m, "EXPORTS", exports), patch.object(m, "preflight", return_value={"service": "original"}), patch.object(m, "prepare_exports"), patch.object(m, "inspect_container", return_value={"Id": "replacement"}), patch.object(m.sys, "argv", ["prepare_backup.py"]), patch.dict(os.environ, {"PROFILE_NAME": "nautilus", "PROFILE_COMMAND": "backup"}):
                with self.assertRaisesRegex(RuntimeError, "container changed"):
                    m.main()
            self.assertTrue((exports / "old").exists())
            self.assertEqual(list(state.iterdir()), [exports])

    def test_direct_invocation_is_rejected(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "resticprofile"):
                m.main()

    def test_command_failure_does_not_echo_sensitive_stderr(self):
        error = m.subprocess.CalledProcessError(1, ["docker"], stderr=b"secret-value")
        with patch.object(m.subprocess, "run", side_effect=error):
            with self.assertRaises(RuntimeError) as caught:
                m.command(["docker"])
        self.assertNotIn("secret-value", str(caught.exception))

    def test_mariadb_password_is_not_on_argv_and_options_precede_separator(self):
        command = m.mariadb_command("container", "mariadb-dump", "--databases", "--", "example")
        self.assertEqual(command[5], 'unset MYSQL_PWD; exec "$@"')
        self.assertFalse(any("MYSQL_ROOT_PASSWORD" in part for part in command))
        self.assertLess(command.index("--user=root"), command.index("--"))
        self.assertEqual(command[-1], "example")

    def test_stable_file_rejects_a_detected_race(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "source"
            source.write_text("file")
            with patch.object(m, "fingerprint", side_effect=[("before",), ("after",)]):
                with self.assertRaisesRegex(RuntimeError, "changed during capture"):
                    m.copy_stable_file(source, Path(folder) / "output")

    def test_zigbee_archive_requires_pairing_state(self):
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, "w") as output:
            output.writestr("configuration.yaml", "test")
        with tempfile.TemporaryDirectory() as folder:
            with patch.object(m, "inspect_container", return_value={}), patch.object(m, "container_address", return_value="127.0.0.1"), patch.object(m, "request_zigbee_backup", return_value=archive.getvalue()):
                with self.assertRaisesRegex(RuntimeError, "missing required"):
                    m.backup_zigbee("container", Path(folder) / "zigbee")

    @unittest.skipUnless(shutil.which("restic"), "restic binary needed for local fixture test")
    def test_real_restic_exclusions_keep_files_and_prepared_metrics(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            home = root / "home"
            exports = root / "exports"
            cases = {
                "services/adguard/data/work/data/stats.db": False,
                "services/adguard/data/work/data/leases.json": True,
                "services/adguard/data/work/data/querylog.json": False,
                "services/home-automation/data/ha/config/backups/completed.tar": True,
                "services/home-automation/data/ha/config/home-assistant_v2.db": False,
                "services/monitoring/data/grafana/grafana.db-wal": False,
                "services/monitoring/grafana/dashboards/dashboard.json": True,
                "services/monitoring/data/prometheus/hot-block": False,
                "apps/voltr-finance/.env": True,
                "apps/data-viento/retired": False,
                "services/syncthing/data/folders/obsidian-vault/note.md": True,
                "services/home-automation/data/esphome/secrets.yaml": True,
                "some-project/node_modules/dependency": False,
            }
            for relative in cases:
                path = home / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"test-only fixture")
            metrics = exports / "prometheus/tsdb.tar"
            metrics.parent.mkdir(parents=True)
            metrics.write_bytes(b"test-only snapshot fixture")
            exclusions = Path(__file__).parent.parent / "exclude.txt"
            if not exclusions.exists():
                exclusions = Path(__file__).with_name("exclude.txt")
            rebased = root / "exclusions.txt"
            rebased.write_text(exclusions.read_text().replace("/home/rdmm404", str(home)))
            env = {**os.environ, "RESTIC_PASSWORD": "offline-test-only", "RESTIC_REPOSITORY": str(root / "repo")}
            def run(*args):
                return subprocess.check_output(["restic", *args], env=env, stderr=subprocess.PIPE, text=True)
            run("init")
            run("backup", "--exclude-file", str(rebased), str(home), str(exports))
            nodes = [json.loads(line) for line in run("ls", "--json", "latest").splitlines()]
            paths = {node["path"] for node in nodes if node.get("struct_type") == "node"}
            for relative, included in cases.items():
                self.assertEqual(str(home / relative) in paths, included, relative)
            self.assertIn(str(metrics), paths)
            run("check", "--read-data")

    def stopped_prometheus_case(self, fail_archive=False, fail_stop=False):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = root / "data"
            (data / "block").mkdir(parents=True)
            (data / "block/meta.json").write_text('{}')
            (data / "snapshots/old").mkdir(parents=True)
            (data / "snapshots/old/unwanted").write_text('old')
            (data / "lock").write_text('')
            calls = []
            def fake_command(arguments, **kwargs):
                calls.append(arguments)
                if arguments[1] == "stop":
                    if fail_stop:
                        raise RuntimeError("stop failed")
                    return b"original"
                if arguments[1] == "start":
                    return b"original"
                running = any(call[1] == "start" for call in calls)
                return json.dumps([{"State": {"Running": running, "OOMKilled": False, "ExitCode": 0}}]).encode()
            output = root / "exports"
            with patch.object(m, "PROMETHEUS_DATA", data), patch.object(m, "inspect_container", return_value={"Id": "original"}), patch.object(m, "command", side_effect=fake_command):
                if fail_archive:
                    with patch.object(m.tarfile, "open", side_effect=OSError("disk full")):
                        with self.assertRaises(OSError):
                            m.backup_prometheus_stopped("prometheus", output)
                elif fail_stop:
                    with self.assertRaisesRegex(RuntimeError, "stop failed"):
                        m.backup_prometheus_stopped("prometheus", output)
                else:
                    m.backup_prometheus_stopped("prometheus", output)
                    with tarfile.open(output / "tsdb.tar") as archive:
                        names = archive.getnames()
                        self.assertIn("prometheus/block/meta.json", names)
                        self.assertNotIn("prometheus/snapshots", names)
                        self.assertNotIn("prometheus/lock", names)
            self.assertIn(["docker", "start", "original"], calls)
            self.assertTrue((data / "snapshots/old/unwanted").exists())

    def test_prometheus_stop_capture_restart(self):
        self.stopped_prometheus_case()

    def test_prometheus_restarts_on_archive_failure(self):
        self.stopped_prometheus_case(fail_archive=True)

    def test_prometheus_attempts_restart_even_if_stop_fails(self):
        self.stopped_prometheus_case(fail_stop=True)

    def test_prometheus_requests_head_snapshot_and_archives_then_removes_only_new_snapshot(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            snapshot_name = "20261012T120000Z-abc123"
            source = root / "prometheus/snapshots" / snapshot_name
            source.mkdir(parents=True)
            (source / "block").mkdir()
            (source / "block/meta.json").write_text('{"test": true}')
            existing = source.parent / "older-snapshot"
            existing.mkdir()
            class Opener:
                def open(self, request, timeout):
                    self_request = request
                    assert "skip_head=false" in self_request.full_url
                    assert self_request.get_method() == "POST"
                    return io.BytesIO(json.dumps({"status": "success", "data": {"name": snapshot_name}}).encode())
            with patch.object(m, "PROMETHEUS_DATA", root / "prometheus"), patch.object(m, "inspect_container", return_value={}), patch.object(m, "container_address", return_value="127.0.0.1"), patch.object(m.urllib.request, "build_opener", return_value=Opener()):
                m.backup_prometheus("prometheus", root / "export")
            with tarfile.open(root / "export/tsdb.tar") as archive:
                self.assertIn("prometheus/block/meta.json", archive.getnames())
            self.assertFalse(source.exists())
            self.assertTrue(existing.exists())


if __name__ == "__main__":
    unittest.main()
