#!/usr/bin/env bash
set -eu
TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
python3 "$TEST_DIR/herdr_launch_checks.py"
if command -v node >/dev/null; then
  node --test "$TEST_DIR/herdr_title_checks.mjs"
else
  echo 'SKIP title plugin tests (Node.js required)'
fi
