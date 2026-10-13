"""Offline tests: no Docker daemon, databases or repository access."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys
from unittest.mock import patch

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("exporter", Path(__file__).with_name("backup-postgres.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class Exports(unittest.TestCase):
    def run_case(self, names, fail=False, changed=False):
        calls = []
        discovery = 0
        def fake(args, **kwargs):
            nonlocal discovery
            calls.append(args)
            if "psql" in args:
                discovery += 1
                result = names + (["new_db"] if changed and discovery > 1 else [])
                return subprocess.CompletedProcess(args, 0, json.dumps(result))
            if "pg_dump" in args and fail:
                raise subprocess.CalledProcessError(1, args)
            if "stdout" in kwargs and hasattr(kwargs["stdout"], "write"):
                kwargs["stdout"].write(b"PGDMP-test" if "pg_dump" in args else b"-- globals\n")
            return subprocess.CompletedProcess(args, 0)
        return calls, fake

    def test_discovery_publication_and_permissions(self):
        names = ["default", "postgres", "voltr_finance", "weird/name='db"]
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / "state"
            calls, fake = self.run_case(names)
            with patch.object(m, "STATE", state), patch.object(m.subprocess, "run", side_effect=fake):
                m.main()
                m.main()  # replaces the old complete set safely
            target = state / "exports/postgres"
            manifest = json.loads((target / "manifest.json").read_text())
            self.assertEqual([x["database"] for x in manifest["databases"]], names)
            self.assertTrue(all((target / x["file"]).is_file() for x in manifest["databases"]))
            self.assertEqual(target.stat().st_mode & 0o777, 0o700)
            self.assertEqual((target / "globals.sql").stat().st_mode & 0o777, 0o600)
            self.assertFalse((state / "exports/postgres.previous").exists())

    def test_failed_dump_keeps_previous_and_returns_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / "state"
            target = state / "exports/postgres"
            target.mkdir(parents=True)
            (target / "sentinel").write_text("previous")
            calls, fake = self.run_case(["voltr_finance"], fail=True)
            with patch.object(m, "STATE", state), patch.object(m.subprocess, "run", side_effect=fake):
                with self.assertRaises(subprocess.CalledProcessError):
                    m.main()
            self.assertEqual((target / "sentinel").read_text(), "previous")
            self.assertEqual(list((state / "exports").iterdir()), [target])

    def test_changed_inventory_aborts(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / "state"
            calls, fake = self.run_case(["voltr_finance"], changed=True)
            with patch.object(m, "STATE", state), patch.object(m.subprocess, "run", side_effect=fake):
                with self.assertRaisesRegex(RuntimeError, "inventory changed"):
                    m.main()
            self.assertFalse((state / "exports/postgres").exists())


if __name__ == "__main__":
    unittest.main()
