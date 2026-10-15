#!/usr/bin/env bash
set -e
TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DOT_SHELL_PLATFORM=debian bash "$TEST_DIR/ubuntu_shell_test.sh"
