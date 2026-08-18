#!/usr/bin/env bash

TEST_REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_TMP=''
TEST_HOME=''
TEST_ROOT=''
TEST_BIN=''
TEST_OUTPUT=''
TEST_ERROR=''

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  return 1
}

assert_contains() {
  assert_file="$1"
  assert_text="$2"
  if ! rg -F -- "$assert_text" "$assert_file" >/dev/null 2>&1; then
    fail "expected '$assert_text' in $assert_file"
  fi
}

assert_not_contains() {
  assert_file="$1"
  assert_text="$2"
  if rg -F -- "$assert_text" "$assert_file" >/dev/null 2>&1; then
    fail "did not expect '$assert_text' in $assert_file"
  fi
}

make_fixture() {
  TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/dot-test.XXXXXX") || return 1
  TEST_HOME="$TEST_TMP/home"
  TEST_ROOT="$TEST_TMP/repo"
  TEST_BIN="$TEST_TMP/bin"
  mkdir -p "$TEST_HOME" "$TEST_BIN" "$TEST_ROOT"
  : > "$TEST_TMP/installed"
  cp "$TEST_REPO/tests/fakes/bin"/* "$TEST_BIN/"
  cp "$TEST_REPO/dot" "$TEST_ROOT/dot"
  cp -R "$TEST_REPO/lib" "$TEST_ROOT/lib"
  cp -R "$TEST_REPO/installers" "$TEST_ROOT/installers"
  mkdir -p "$TEST_ROOT/manifests" "$TEST_ROOT/tests"
  cp -R "$TEST_REPO/global" "$TEST_ROOT/global"
  cp -R "$TEST_REPO/platforms" "$TEST_ROOT/platforms"
  cp "$TEST_REPO/manifests/catalog" "$TEST_ROOT/manifests/catalog"
  printf '%s\n' '# fixture' > "$TEST_ROOT/manifests/core"
  printf '%s\n' '# fixture' > "$TEST_ROOT/manifests/development"
  printf '%s\n' '# fixture' > "$TEST_ROOT/manifests/optional"
  chmod +x "$TEST_ROOT/dot"
}

run_dot() {
  TEST_OUTPUT="$TEST_TMP/output"
  TEST_ERROR="$TEST_TMP/error"
  if [ "${TEST_AUTO_PLATFORM:-0}" = 1 ]; then
    test_platform=''
  else
    test_platform="${DOT_PLATFORM:-wsl}"
  fi
  test_path="${TEST_PATH:-$TEST_BIN:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin}"
  test_stow_command="${TEST_STOW_COMMAND:-${REAL_STOW:-$(command -v stow)}}"
  if [ "${TEST_REAL_STOW:-0}" = 1 ]; then
    if [ "${TEST_KEEP_STOW:-0}" = 1 ]; then
      test_stow_command="$TEST_BIN/stow"
    else
      rm -f "$TEST_BIN/stow"
    fi
  fi
  if [ "${TEST_NO_INPUT:-0}" = 1 ]; then
    HOME="$TEST_HOME" DOT_ROOT="$TEST_ROOT" DOT_PLATFORM="$test_platform" \
      WSL_DISTRO_NAME="${WSL_DISTRO_NAME:-test-wsl}" DOT_NO_SUDO=1 \
      FAKE_LOG="$TEST_TMP/commands" FAKE_INSTALLED="$TEST_TMP/installed" FAKE_BIN="$TEST_BIN" \
      STOW_COMMAND="$test_stow_command" REAL_STOW="${REAL_STOW:-$(command -v stow)}" PATH="$test_path" /bin/bash "$TEST_ROOT/dot" "$@" </dev/null >"$TEST_OUTPUT" 2>"$TEST_ERROR"
  else
    HOME="$TEST_HOME" DOT_ROOT="$TEST_ROOT" DOT_PLATFORM="$test_platform" \
      WSL_DISTRO_NAME="${WSL_DISTRO_NAME:-test-wsl}" DOT_NO_SUDO=1 \
      FAKE_LOG="$TEST_TMP/commands" FAKE_INSTALLED="$TEST_TMP/installed" FAKE_BIN="$TEST_BIN" \
      STOW_COMMAND="$test_stow_command" REAL_STOW="${REAL_STOW:-$(command -v stow)}" PATH="$test_path" /bin/bash "$TEST_ROOT/dot" "$@" >"$TEST_OUTPUT" 2>"$TEST_ERROR"
  fi
}

cleanup_fixture() {
  [ -n "$TEST_TMP" ] && rm -rf "$TEST_TMP"
}
