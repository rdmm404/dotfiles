#!/usr/bin/env bash
set -euo pipefail
TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
python3 "$TEST_DIR/calculator_checks.py"
