#!/usr/bin/env bash

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TEST_DIR/helpers.sh"

manifest_test() {
  make_fixture || return 1
  printf '%s\n' '# comment' '' 'stow' '  # another comment' > "$TEST_ROOT/manifests/core"
  printf '%s\n' 'git' > "$TEST_ROOT/manifests/development"
  run_dot install --dry-run --verbose || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'already installed: stow' || { cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'already installed: git' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

duplicate_test() {
  make_fixture || return 1
  printf '%s\n' 'stow' 'stow' > "$TEST_ROOT/manifests/core"
  if run_dot install --dry-run; then
    cleanup_fixture
    fail 'duplicate manifest entry unexpectedly succeeded'
    return 1
  fi
  assert_contains "$TEST_ERROR" "duplicate application 'stow'" || { cleanup_fixture; return 1; }
  cleanup_fixture
}

unknown_test() {
  make_fixture || return 1
  printf '%s\n' 'not-a-real-application' > "$TEST_ROOT/manifests/core"
  if run_dot install --dry-run; then
    cleanup_fixture
    fail 'unknown manifest entry unexpectedly succeeded'
    return 1
  fi
  assert_contains "$TEST_ERROR" 'unknown application' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

invalid_name_test() {
  make_fixture || return 1
  printf '%s\n' 'not a valid name' > "$TEST_ROOT/manifests/core"
  if run_dot install --dry-run; then
    cleanup_fixture
    fail 'invalid manifest entry unexpectedly succeeded'
    return 1
  fi
  assert_contains "$TEST_ERROR" 'invalid application name' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

manifest_test && duplicate_test && unknown_test && invalid_name_test
