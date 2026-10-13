#!/bin/sh
# Only called after a successful PostgreSQL restic backup. No service data removed.
set -eu
exports="$HOME/.local/state/backup/exports"
test ! -L "$exports"
test ! -L "$exports/postgres"
rm -rf -- "$exports/postgres"
