#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["paho-mqtt==2.1.0"]
# ///
"""Prepare Nautilus live state before restic; ordinary home files need no hook.

Use only through resticprofile: its lock covers preparation/upload/cleanup.
No config edits, image exports, schedules or repository pruning.
Prometheus can be briefly stopped only with explicit one-run opt-in.
All required captures must succeed before the new export set is published.
"""
import base64
from contextlib import closing
import importlib.util
import io
import json
import os
import re
import shutil
import sqlite3
import stat
import threading
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.parse
import urllib.request
import uuid
import zipfile
from pathlib import Path

HOME = Path("/home/rdmm404")
STATE = Path("/var/lib/resticprofile/nautilus")
EXPORTS = STATE / "exports"
POSTGRES_CONTAINER = "svc-postgres-db"
MARIADB_CONTAINER = "svc-grimmory-mariadb"
REDIS_CONTAINER = "svc-aiometadata-redis"
ZIGBEE_CONTAINER = "svc-zigbee2mqtt"
MQTT_CONTAINER = "svc-mqtt"
PROMETHEUS_CONTAINER = "svc-prometheus"
MQTT_BASE_TOPIC = "zigbee2mqtt"  # Current broker allows anonymous clients.
REDIS_FILE = HOME / "services/streaming/redis/dump.rdb"
MQTT_FILE = HOME / "services/home-automation/data/mqtt/data/mosquitto.db"
PROMETHEUS_DATA = HOME / "services/monitoring/data/prometheus"
SQLITE_DATABASES = [
    (HOME / "services/home-automation/data/ha/config/home-assistant_v2.db", "home-assistant.db"),
    (HOME / "services/monitoring/data/grafana/grafana.db", "grafana.db"),
    (HOME / "services/gatus/data/gatus.db", "gatus.db"),
    (HOME / "services/upsnap/data/data.db", "upsnap-data.db"),
    (HOME / "services/upsnap/data/auxiliary.db", "upsnap-auxiliary.db"),
]
TIMEOUT = 180  # Bounded application snapshot waits, not a blanket upload timeout.


def command(arguments, *, timeout=TIMEOUT, **kwargs):
    """Capture outputs privately. Never print SQL dumps, runtime env or ZIP data."""
    try:
        return subprocess.run(arguments, check=True, timeout=timeout,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs).stdout
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as from_error:
        # Raw stderr/command output may contain credentials; do not echo it.
        operation = " ".join(arguments[:3]) if arguments[0] == "docker" else arguments[0]
        raise RuntimeError(f"Required command failed: {operation}") from from_error


def inspect_container(name):
    details = json.loads(command(["docker", "inspect", name]))
    if len(details) != 1 or not details[0]["State"]["Running"]:
        raise RuntimeError(f"Required container is not running: {name}")
    return details[0]


def container_address(details):
    addresses = [v["IPAddress"] for v in details["NetworkSettings"]["Networks"].values()
                 if v.get("IPAddress")]
    if len(addresses) != 1:
        raise RuntimeError("Expected one unambiguous container bridge address")
    return addresses[0]


def private_directory(path):
    if path.is_symlink():
        raise RuntimeError(f"Refusing symlink: {path}")
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)


def source_metadata(path):
    info = path.stat()
    return {"source": str(path), "uid": info.st_uid, "gid": info.st_gid,
            "mode": stat.S_IMODE(info.st_mode)}


def fingerprint(path):
    info = path.stat()
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def copy_stable_file(source, destination):
    """Copy completed immutable/atomically replaced files; reject detected races."""
    if source.is_symlink() or not source.is_file():
        raise RuntimeError(f"Expected regular source: {source}")
    before = fingerprint(source)
    with source.open("rb") as incoming, destination.open("xb") as outgoing:
        shutil.copyfileobj(incoming, outgoing)
    destination.chmod(0o600)
    if fingerprint(source) != before:
        raise RuntimeError(f"Source changed during capture: {source}")
    return source_metadata(source)


def preflight():
    """Read-only prerequisites BEFORE any application snapshot request."""
    if os.geteuid() != 0:
        raise RuntimeError("Broad backup needs reviewed privileged execution for root-owned state")
    try:
        import paho.mqtt.client  # Resolved by uv from inline script metadata.
    except ImportError as error:
        raise RuntimeError("Run preparation through the uv-backed resticprofile hook") from error
    containers = [POSTGRES_CONTAINER, MARIADB_CONTAINER, REDIS_CONTAINER,
                  ZIGBEE_CONTAINER, MQTT_CONTAINER, PROMETHEUS_CONTAINER]
    details = {name: inspect_container(name) for name in containers}
    prom_args = details[PROMETHEUS_CONTAINER]["Config"].get("Cmd") or []
    stop_once = os.environ.get("NAUTILUS_PROMETHEUS_STOP_ONCE", "")
    if stop_once not in ("", "1"):
        raise RuntimeError("NAUTILUS_PROMETHEUS_STOP_ONCE must be unset or 1")
    if not stop_once and "--web.enable-admin-api" not in prom_args and "--web.enable-admin-api=true" not in prom_args:
        raise RuntimeError("Prometheus snapshot API is disabled. Enable it with reviewed restrictions, or explicitly opt into this run's brief stop")
    for source, _ in SQLITE_DATABASES:
        if source.is_symlink() or not source.is_file():
            raise RuntimeError(f"Missing/unsafe SQLite source: {source}")
        with source.open("rb") as stream:
            if stream.read(16) != b"SQLite format 3\x00":
                raise RuntimeError(f"Not a SQLite database: {source}")
    if not MQTT_FILE.is_file() or not PROMETHEUS_DATA.is_dir():
        raise RuntimeError("Required MQTT/Prometheus persistence path is missing")
    return {name: info["Id"] for name, info in details.items()}


def backup_postgresql(container, destination):
    """Reuse the restore-tested native exporter without its old path/main()."""
    private_directory(destination)
    path = Path(__file__).with_name("backup-postgres.py")
    spec = importlib.util.spec_from_file_location("postgres_export", path)
    exporter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(exporter)
    exporter.CONTAINER = container
    exporter.create_export_set(destination)


def mariadb_command(container, executable, *arguments):
    # Use the verified local connection; do not force the rejected env password.
    # This does not change database authentication or client configuration files.
    return ["docker", "exec", container, "sh", "-ec",
            'unset MYSQL_PWD; exec "$@"',
            "sh", executable, "--user=root", *arguments]


def backup_mariadb(container, destination):
    """Discover all application DBs, dump transactionally and preserve grants."""
    private_directory(destination)
    query = "SELECT HEX(SCHEMA_NAME) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME NOT IN ('mysql','information_schema','performance_schema','sys') ORDER BY SCHEMA_NAME"
    def inventory():
        rows = command(mariadb_command(container, "mariadb", "--batch", "--skip-column-names", "--execute", query))
        names = [bytes.fromhex(row).decode() for row in rows.decode().splitlines()]
        if not names:
            raise RuntimeError("Empty MariaDB application DB inventory")
        return names
    names = inventory()
    non_transactional = command(mariadb_command(container, "mariadb", "--batch", "--skip-column-names", "--execute",
        "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA NOT IN ('mysql','information_schema','performance_schema','sys') AND TABLE_TYPE='BASE TABLE' AND ENGINE <> 'InnoDB'"))
    if non_transactional.strip() != b"0":
        raise RuntimeError("MariaDB contains non-transactional application tables; review capture method")
    for name in names:
        path = destination / (name.encode().hex() + ".sql")
        # --databases preserves CREATE/USE statements and database definitions.
        with path.open("xb") as output:
            try:
                subprocess.run(mariadb_command(container, "mariadb-dump", "--single-transaction",
                    "--routines", "--events", "--triggers", "--hex-blob", "--databases", "--", name),
                    stdout=output, stderr=subprocess.PIPE, check=True, timeout=1800)
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                raise RuntimeError("MariaDB dump failed") from error
        if path.stat().st_size == 0:
            raise RuntimeError("Empty MariaDB dump")
    # MariaDB's logical system-user export, rather than hot mysql system tables.
    users = command(mariadb_command(container, "mariadb-dump", "--system=users"), timeout=1800)
    if not users.strip():
        raise RuntimeError("Empty MariaDB users/grants dump")
    (destination / "users.sql").write_bytes(users)
    if inventory() != names:
        raise RuntimeError("MariaDB inventory changed during capture")
    (destination / "databases.json").write_text(json.dumps(names, indent=2) + "\n")


def backup_sqlite(source, destination):
    """One reusable online SQLite backup; output is a standalone checked DB."""
    private_directory(destination.parent)
    if destination.exists():
        raise RuntimeError("Refusing existing SQLite output")
    deadline = time.monotonic() + TIMEOUT
    def progress(status, remaining, total):
        if time.monotonic() > deadline:
            raise RuntimeError("SQLite backup timed out")
    uri = source.resolve().as_uri() + "?mode=ro"
    with closing(sqlite3.connect(uri, uri=True, timeout=5)) as incoming:
        with closing(sqlite3.connect(destination)) as outgoing:
            incoming.backup(outgoing, pages=256, progress=progress, sleep=0.1)
            outgoing.execute("PRAGMA journal_mode=DELETE")
            if outgoing.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                raise RuntimeError("SQLite backup failed integrity check")
    destination.chmod(0o600)
    return source_metadata(source)


def redis_info(container):
    lines = command(["docker", "exec", container, "redis-cli", "--raw", "INFO", "persistence"]).decode().splitlines()
    data = dict(line.split(":", 1) for line in lines if ":" in line and not line.startswith("#"))
    if "rdb_bgsave_in_progress" not in data:
        raise RuntimeError("Redis persistence info unavailable (check authentication)")
    return data


def wait_for(predicate, description):
    deadline = time.monotonic() + TIMEOUT
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(0.25)
    raise RuntimeError(f"Timed out: {description}")


def backup_redis(container, destination):
    private_directory(destination)
    wait_for(lambda: redis_info(container)["rdb_bgsave_in_progress"] == "0", "existing Redis save")
    previous = fingerprint(REDIS_FILE) if REDIS_FILE.exists() else None
    reply = command(["docker", "exec", container, "redis-cli", "--raw", "BGSAVE"])
    if reply.strip() != b"Background saving started":
        raise RuntimeError("Redis refused native snapshot request")
    def completed():
        info = redis_info(container)
        if info["rdb_bgsave_in_progress"] != "0":
            return False
        if info.get("rdb_last_bgsave_status") != "ok":
            raise RuntimeError("Redis background save failed")
        return REDIS_FILE.exists() and fingerprint(REDIS_FILE) != previous
    wait_for(completed, "completed Redis native snapshot")
    output = destination / "dump.rdb"
    metadata = copy_stable_file(REDIS_FILE, output)
    # Validate with matching Redis tooling; use a private temporary container file.
    shell = 'umask 077; tmp=$(mktemp); trap \'rm -f "$tmp"\' EXIT; cat > "$tmp"; redis-check-rdb "$tmp"'
    with output.open("rb") as incoming:
        command(["docker", "exec", "-i", container, "sh", "-ec", shell], stdin=incoming)
    return metadata


def request_zigbee_backup(host):
    """Use the maintained MQTT client, subscribe first, correlate the response."""
    import paho.mqtt.client as mqtt
    ready, finished = threading.Event(), threading.Event()
    transaction = uuid.uuid4().hex
    result = {}
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,
                         client_id="backup-" + transaction[:16])

    def on_connect(connection, userdata, flags, reason, properties):
        if reason.is_failure:
            result["error"] = "MQTT broker rejected backup client"
            ready.set()
        else:
            connection.subscribe(MQTT_BASE_TOPIC + "/bridge/response/backup")

    def on_subscribe(connection, userdata, mid, reasons, properties):
        if any(reason.is_failure for reason in reasons):
            result["error"] = "MQTT backup subscription rejected"
        ready.set()

    def on_message(connection, userdata, message):
        if message.retain:
            return
        try:
            response = json.loads(message.payload)
            if response.get("transaction") != transaction:
                return
            if response.get("status") != "ok":
                result["error"] = "Zigbee2MQTT rejected its backup request"
            else:
                result["zip"] = base64.b64decode(response["data"]["zip"], validate=True)
        except (ValueError, KeyError, TypeError):
            result["error"] = "Malformed Zigbee backup response"
        finished.set()

    client.on_connect, client.on_subscribe, client.on_message = on_connect, on_subscribe, on_message
    try:
        client.connect(host, 1883, keepalive=60)
        client.loop_start()
        if not ready.wait(30):
            raise RuntimeError("Timed out subscribing to Zigbee backup response")
        if "error" in result:
            raise RuntimeError(result["error"])
        info = client.publish(MQTT_BASE_TOPIC + "/bridge/request/backup",
                              json.dumps({"transaction": transaction}))
        info.wait_for_publish(timeout=30)
        if not finished.wait(TIMEOUT):
            raise RuntimeError("Timed out waiting for correlated Zigbee backup")
        if "error" in result:
            raise RuntimeError(result["error"])
        return result["zip"]
    finally:
        client.disconnect()
        client.loop_stop()


def backup_zigbee(container, destination):
    inspect_container(container)
    private_directory(destination)
    data = request_zigbee_backup(container_address(inspect_container(MQTT_CONTAINER)))
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("Corrupt Zigbee backup archive")
        names = archive.namelist()
        if any(Path(name).is_absolute() or ".." in Path(name).parts for name in names):
            raise RuntimeError("Unsafe Zigbee archive path")
        basenames = {Path(name).name for name in names}
        if not {"configuration.yaml", "database.db", "coordinator_backup.json"} <= basenames:
            raise RuntimeError("Zigbee archive missing required network/pairing state")
    (destination / "backup.zip").write_bytes(data)


def backup_mqtt(container, destination):
    private_directory(destination)
    previous = fingerprint(MQTT_FILE)
    command(["docker", "kill", "--signal=USR1", container])
    # Mosquitto writes a temporary .new file then atomically renames it.
    # Wait for a new inode/mtime, not just signal delivery or a log message.
    wait_for(lambda: fingerprint(MQTT_FILE) != previous, "completed MQTT persistence save")
    output = destination / "mosquitto.db"
    metadata = copy_stable_file(MQTT_FILE, output)
    with output.open("rb") as stream:
        if stream.read(15) != b"\x00\xb5\x00mosquitto db":
            raise RuntimeError("Invalid MQTT persistence header")
    return metadata


def backup_prometheus_stopped(container, destination):
    """One-run fallback: stop original container, archive TSDB, ALWAYS restart."""
    identity = inspect_container(container)["Id"]
    private_directory(destination)
    print("Briefly stopping Prometheus for TSDB capture; no other services stop", flush=True)
    try:
        # Use immutable ID: never stop/restart a concurrently recreated container.
        command(["docker", "stop", "--time", "30", identity], timeout=60)
        details = json.loads(command(["docker", "inspect", identity]))[0]
        if details["State"]["Running"] or details["State"].get("OOMKilled") or details["State"].get("ExitCode") != 0:
            raise RuntimeError("Prometheus did not stop cleanly; archive refused")
        for path in PROMETHEUS_DATA.rglob("*"):
            if path.is_symlink() or not (path.is_dir() or path.is_file()):
                raise RuntimeError("Unsupported Prometheus TSDB entry")
        if not any(PROMETHEUS_DATA.rglob("meta.json")) and not (PROMETHEUS_DATA / "wal").is_dir():
            raise RuntimeError("Prometheus data directory has no blocks or WAL")
        def keep_tsdb(member):
            relative = Path(member.name).relative_to("prometheus")
            if relative.parts and relative.parts[0] in ("snapshots", "lock", "queries.active"):
                return None
            return member
        with tarfile.open(destination / "tsdb.tar", "w") as archive:
            archive.add(PROMETHEUS_DATA, arcname="prometheus", filter=keep_tsdb)
        (destination / "source.json").write_text(json.dumps(source_metadata(PROMETHEUS_DATA), indent=2) + "\n")
    finally:
        # Even a timeout, copy failure or Ctrl-C must attempt restart. This also
        # safely handles stop-command failure if the original is still running.
        try:
            command(["docker", "start", identity], timeout=60)
            restarted = json.loads(command(["docker", "inspect", identity]))[0]
            if not restarted["State"]["Running"]:
                raise RuntimeError("Container is not running after restart")
        except Exception as error:
            raise RuntimeError(f"PROMETHEUS RESTART FAILED; check/start original container {identity}") from error
        print("Prometheus container restarted; upload has not started yet", flush=True)


def backup_prometheus(container, destination):
    """Default: native snapshot. Explicit one-run opt-in: brief clean stop."""
    if os.environ.get("NAUTILUS_PROMETHEUS_STOP_ONCE") == "1":
        backup_prometheus_stopped(container, destination)
        return
    details = inspect_container(container)
    url = f"http://{container_address(details)}:9090/api/v1/admin/tsdb/snapshot?skip_head=false"
    request = urllib.request.Request(url, data=b"", method="POST")
    # Bypass external proxy env: never send local admin requests to a proxy.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=TIMEOUT) as response:
        result = json.load(response)
    if result.get("status") != "success":
        raise RuntimeError("Prometheus snapshot failed")
    name = result["data"]["name"]
    if not re.fullmatch(r"[0-9]{8}T[0-9]{6}Z-[0-9a-f]+", name):
        raise RuntimeError("Unsafe Prometheus snapshot name")
    source = PROMETHEUS_DATA / "snapshots" / name
    if source.is_symlink() or not source.is_dir():
        raise RuntimeError("Prometheus snapshot directory missing/unsafe")
    try:
        # Reject links/special files; archive preserves restore ownership/modes.
        for path in source.rglob("*"):
            if path.is_symlink() or not (path.is_dir() or path.is_file()):
                raise RuntimeError("Unsupported Prometheus snapshot entry")
        if not any(source.rglob("meta.json")):
            raise RuntimeError("Prometheus snapshot has no TSDB blocks")
        private_directory(destination)
        with tarfile.open(destination / "tsdb.tar", "w") as archive:
            archive.add(source, arcname="prometheus", recursive=True)
        (destination / "source.json").write_text(json.dumps(source_metadata(PROMETHEUS_DATA), indent=2) + "\n")
    finally:
        # Only the newly requested snapshot, never existing TSDB/history/snapshots.
        if not source.is_symlink():
            shutil.rmtree(source)


def prepare_exports(destination):
    metadata = {"sqlite": {}}
    backup_postgresql(POSTGRES_CONTAINER, destination / "postgresql")
    print("Prepared PostgreSQL dumps")
    backup_mariadb(MARIADB_CONTAINER, destination / "mariadb")
    print("Prepared MariaDB dumps and users")
    for source, filename in SQLITE_DATABASES:
        metadata["sqlite"][filename] = backup_sqlite(source, destination / "sqlite" / filename)
    print("Prepared consistent SQLite databases")
    metadata["redis"] = backup_redis(REDIS_CONTAINER, destination / "redis")
    backup_zigbee(ZIGBEE_CONTAINER, destination / "zigbee")
    metadata["mqtt"] = backup_mqtt(MQTT_CONTAINER, destination / "mqtt")
    backup_prometheus(PROMETHEUS_CONTAINER, destination / "prometheus")
    (destination / "restore-metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print("Prepared Redis, Zigbee, MQTT and Prometheus snapshots")


def publish(temporary):
    previous = STATE / "exports.previous"
    if EXPORTS.is_symlink() or previous.exists() or previous.is_symlink():
        raise RuntimeError("Unsafe export target or unfinished previous publication")
    had_previous = EXPORTS.exists()
    if had_previous:
        EXPORTS.rename(previous)
    try:
        temporary.rename(EXPORTS)
    except BaseException:
        if had_previous:
            previous.rename(EXPORTS)
        raise
    if had_previous:
        shutil.rmtree(previous)


def cleanup_exports():
    if STATE.is_symlink() or EXPORTS.is_symlink() or (STATE / "exports.previous").exists():
        raise RuntimeError("Unsafe/unfinished export state; cleanup refused")
    if EXPORTS.exists():
        shutil.rmtree(EXPORTS)


def main():
    os.umask(0o077)
    if os.environ.get("PROFILE_NAME") != "nautilus" or os.environ.get("PROFILE_COMMAND") != "backup":
        raise RuntimeError("Invoke only through resticprofile -n nautilus backup")
    if STATE.parent.is_symlink() or STATE.is_symlink():
        raise RuntimeError("Unsafe backup state directory")
    if sys.argv[1:] == ["--cleanup"]:
        cleanup_exports()
        return
    if sys.argv[1:]:
        raise RuntimeError("Only --cleanup is supported; use resticprofile")
    # 1. Read-only prerequisite checks before requesting any live snapshots.
    container_ids = preflight()
    private_directory(STATE)
    temporary = Path(tempfile.mkdtemp(prefix=".exports-", dir=STATE))
    try:
        # 2. Produce and validate every required capture in private temporary space.
        prepare_exports(temporary)
        for name, identity in container_ids.items():
            if inspect_container(name)["Id"] != identity:
                raise RuntimeError("A service container changed during preparation; retry")
        # 3. Publish only the complete set. Resticprofile uploads, then cleans up.
        publish(temporary)
        print("Published complete Nautilus export set")
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # No raw subprocess output or application responses (may contain secrets).
        print(f"Backup preparation failed: {type(error).__name__}: {error}", file=sys.stderr)
        sys.exit(1)
