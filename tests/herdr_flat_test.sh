#!/usr/bin/env bash
set -eu
TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
python3 "$TEST_DIR/herdr_flat_checks.py"
