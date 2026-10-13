#!/bin/sh
# Called by resticprofile before backup. No live-volume copying or service stops.
set -eu
exec python3 "$(dirname "$0")/backup-postgres.py"
