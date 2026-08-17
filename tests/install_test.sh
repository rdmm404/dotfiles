#!/usr/bin/env bash

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TEST_DIR/helpers.sh"

platform_test() {
  make_fixture || return 1
  printf '%s\n' 'stow' > "$TEST_ROOT/manifests/core"
  printf '%s\n' 'git' > "$TEST_ROOT/manifests/development"
  TEST_AUTO_PLATFORM=1 run_dot plan || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'Platform: WSL' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

planning_is_read_only_test() {
  make_fixture || return 1
  printf '%s\n' 'bat' > "$TEST_ROOT/manifests/core"
  run_dot plan || { cleanup_fixture; return 1; }
  [ ! -e "$TEST_TMP/commands" ] || { cleanup_fixture; fail 'plan invoked package manager'; return 1; }
  cleanup_fixture
}

install_choice_test() {
  make_fixture || return 1
  printf '%s\n' 'bat' > "$TEST_ROOT/manifests/core"
  run_dot install --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_TMP/commands" 'apt-get install -y bat' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

repeat_install_test() {
  make_fixture || return 1
  printf '%s\n' 'zsh-autopair' > "$TEST_ROOT/manifests/core"
  run_dot install --yes || { cleanup_fixture; return 1; }
  run_dot install --yes || { cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'already installed: zsh-autopair' || { cleanup_fixture; return 1; }
  assert_not_contains "$TEST_OUTPUT" 'will install: zsh-autopair' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

optional_plan_test() {
  make_fixture || return 1
  run_dot plan --include optional || { cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" '  - optional' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

invalid_argument_test() {
  make_fixture || return 1
  if run_dot install --not-a-real-option; then
    cleanup_fixture
    fail 'invalid option unexpectedly succeeded'
    return 1
  fi
  assert_contains "$TEST_ERROR" 'invalid argument' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

cancel_test() {
  make_fixture || return 1
  printf '%s\n' 'zsh-autopair' > "$TEST_ROOT/manifests/core"
  if TEST_NO_INPUT=1 run_dot install; then
    cleanup_fixture
    fail 'cancelled install unexpectedly succeeded'
    return 1
  fi
  assert_contains "$TEST_OUTPUT" 'installation cancelled' || { cleanup_fixture; return 1; }
  [ ! -e "$TEST_TMP/commands" ] || { cleanup_fixture; fail 'cancelled install invoked package manager'; return 1; }
  cleanup_fixture
}

doctor_test() {
  make_fixture || return 1
  printf '%s\n' 'stow' > "$TEST_ROOT/manifests/core"
  printf '%s\n' 'git' > "$TEST_ROOT/manifests/development"
  run_dot doctor || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'doctor found no blocking problems' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

bootstrap_readiness_test() {
  make_fixture || return 1
  printf '%s\n' 'stow' > "$TEST_ROOT/manifests/core"
  printf '%s\n' 'git' > "$TEST_ROOT/manifests/development"
  run_dot bootstrap --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'configuration deployment is deferred until Phase 2' || { cleanup_fixture; return 1; }
  assert_not_contains "$TEST_TMP/commands" 'apt-get install' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

platform_test && planning_is_read_only_test && install_choice_test && repeat_install_test && optional_plan_test && invalid_argument_test && cancel_test && doctor_test && bootstrap_readiness_test
