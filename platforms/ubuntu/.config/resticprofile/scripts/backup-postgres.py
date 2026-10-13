#!/usr/bin/env python3
"""Prepare PostgreSQL dump files for restic to back up.

This script does NOT upload anything or stop PostgreSQL. Resticprofile runs it
before the upload, then runs the separate cleanup helper after upload succeeds.
If an export fails, this script raises an error and the backup must stop.

Flow: discover databases -> export into a temporary folder -> validate ->
      write a manifest -> replace the previous completed export folder.
"""

import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

CONTAINER = "svc-postgres-db"
STATE = Path.home() / ".local/state/backup"

# PostgreSQL has template databases used when creating new databases.
# Back up everything else, including databases added in the future.
DATABASE_LIST_SQL = """
SELECT coalesce(json_agg(datname ORDER BY datname), '[]'::json)
FROM pg_database
WHERE NOT datistemplate;
"""


def postgres_command(*arguments):
    """Run a PostgreSQL tool inside the existing container.

    The small shell command reads POSTGRES_USER inside the container and passes
    our arguments unchanged. Python does not read or print the DB credentials.
    """
    return [
        "docker", "exec", CONTAINER,
        "sh", "-ec", 'exec "$@" --username="$POSTGRES_USER"',
        "sh", *arguments,
    ]


def discover_databases():
    """Ask PostgreSQL for a sorted list of non-template database names."""
    result = subprocess.run(
        postgres_command(
            "psql",
            "--dbname=postgres",
            "--no-psqlrc",           # Ignore personal psql startup settings.
            "--no-password",         # Fail rather than wait for a password.
            "--tuples-only",
            "--no-align",
            "--set=ON_ERROR_STOP=1",  # SQL errors must fail the export.
            "--command", DATABASE_LIST_SQL,
        ),
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    database_names = json.loads(result.stdout)
    valid_list = (
        isinstance(database_names, list)
        and bool(database_names)
        and all(isinstance(name, str) for name in database_names)
    )
    if not valid_list:
        raise RuntimeError("Invalid or empty database inventory")
    return database_names


def write_command_output(output_path, *arguments):
    """Save tool output; reject failed commands and empty output files."""
    # 'xb' creates a new binary file and refuses to overwrite an existing file.
    with output_path.open("xb") as output_file:
        subprocess.run(
            postgres_command(*arguments),
            stdout=output_file,
            check=True,
        )
    if output_path.stat().st_size == 0:
        raise RuntimeError(f"Empty export: {output_path.name}")


def file_metadata(file_path):
    """Record a file's name, size and checksum for later restore verification."""
    checksum = hashlib.sha256()
    with file_path.open("rb") as source_file:
        while True:
            chunk = source_file.read(1024 * 1024)
            if not chunk:
                break
            checksum.update(chunk)
    return {
        "file": file_path.name,
        "bytes": file_path.stat().st_size,
        "sha256": checksum.hexdigest(),
    }


def dump_database(database_name, temporary_directory):
    """Create one custom-format dump and check its archive contents listing."""
    # Encode the name so slashes/quotes cannot turn it into an unsafe filename.
    # The manifest keeps the original name for the person restoring the dump.
    filename = database_name.encode("utf-8").hex() + ".dump"
    dump_path = temporary_directory / filename

    # pg_dump accepts a connection string. Quote the name so a database called
    # e.g. 'name=example' is treated as a name, not extra connection settings.
    escaped_name = database_name.replace("\\", "\\\\").replace("'", "\\'")
    connection_string = f"dbname='{escaped_name}'"
    write_command_output(
        dump_path,
        "pg_dump",
        "--format=custom",
        "--no-password",
        "--dbname=" + connection_string,
    )

    # Use pg_restore from the same container to check the archive's TOC.
    # This is a basic check, NOT a substitute for actually testing a restore.
    with dump_path.open("rb") as dump_file:
        subprocess.run(
            ["docker", "exec", "-i", CONTAINER, "pg_restore", "--list"],
            stdin=dump_file,
            stdout=subprocess.DEVNULL,
            check=True,
        )
    return {"database": database_name, **file_metadata(dump_path)}


def create_export_set(temporary_directory):
    """Export globals and every discovered database, then write the manifest."""
    database_names = discover_databases()
    globals_path = temporary_directory / "globals.sql"
    write_command_output(globals_path, "pg_dumpall", "--globals-only", "--no-password")

    manifest = {
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "container": CONTAINER,
        "globals": file_metadata(globals_path),
        "databases": [],
    }
    for database_name in database_names:
        database_export = dump_database(database_name, temporary_directory)
        manifest["databases"].append(database_export)

    # A DB created/dropped while this ran means this is not a complete set.
    if discover_databases() != database_names:
        raise RuntimeError("Database inventory changed during export; retry")

    manifest["completed_utc"] = datetime.now(timezone.utc).isoformat()
    manifest_path = temporary_directory / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    return len(database_names)


def prepare_private_directory(directory):
    """Keep financial exports readable only by this Unix user."""
    if directory.is_symlink():
        raise RuntimeError(f"Refusing symlink directory: {directory}")
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)


def publish_exports(temporary_directory, completed_directory, previous_directory):
    """Replace the completed folder only after all exports have succeeded."""
    had_previous_exports = completed_directory.exists()
    if had_previous_exports:
        completed_directory.rename(previous_directory)

    try:
        temporary_directory.rename(completed_directory)
    except BaseException:
        # If publication fails, put the old complete set back where it was.
        if had_previous_exports:
            previous_directory.rename(completed_directory)
        raise

    if had_previous_exports:
        shutil.rmtree(previous_directory)


def main():
    # New files are mode 600; new directories are mode 700 (private).
    os.umask(0o077)
    prepare_private_directory(STATE)

    # This lock protects exports if someone launches this script directly.
    # Resticprofile's separate lock covers the whole export/upload/cleanup job.
    with (STATE / "postgres-export.lock").open("a") as export_lock:
        fcntl.flock(export_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

        export_root = STATE / "exports"
        prepare_private_directory(export_root)
        completed_directory = export_root / "postgres"
        previous_directory = export_root / "postgres.previous"
        if completed_directory.is_symlink() or previous_directory.exists() or previous_directory.is_symlink():
            raise RuntimeError("Unsafe target or unfinished publication; inspect manually")

        temporary_directory = Path(tempfile.mkdtemp(prefix=".postgres-", dir=export_root))
        try:
            # 1. Create and validate a complete set in the temporary folder.
            database_count = create_export_set(temporary_directory)
            # 2. Make that completed set available to restic.
            publish_exports(temporary_directory, completed_directory, previous_directory)
            print(f"Published complete PostgreSQL export set: {database_count} databases")
        finally:
            # 3. Remove partial exports on failure. On success, the temporary
            #    folder was renamed and no longer exists under its old name.
            if temporary_directory.exists():
                shutil.rmtree(temporary_directory)


if __name__ == "__main__":
    main()
