#!/usr/bin/env bash

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TEST_DIR/helpers.sh"

omarchy_command_test() {
  make_fixture || return 1
  printf '%s\n' rtk > "$TEST_ROOT/manifests/core"
  TEST_PATH="$TEST_BIN" DOT_PLATFORM=omarchy run_dot install || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_TMP/commands" 'omarchy pkg aur add rtk' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

macos_cask_mapping_test() {
  make_fixture || return 1
  printf '%s\n' nerd-font > "$TEST_ROOT/manifests/core"
  DOT_PLATFORM=macos run_dot install || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_TMP/commands" 'brew install --cask font-fira-code-nerd' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

unsupported_platform_app_test() {
  make_fixture || return 1
  printf '%s\n' zsh-autopair > "$TEST_ROOT/manifests/core"
  run_dot install --dry-run --verbose || { cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'unsupported on Omarchy: zsh-autopair' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

omarchy_failure_test() {
  make_fixture || return 1
  cat > "$TEST_BIN/omarchy" <<'EOF'
#!/bin/bash
printf 'omarchy %s\n' "$*" >> "${FAKE_LOG:?}"
exit 1
EOF
  chmod +x "$TEST_BIN/omarchy"
  printf '%s\n' rtk > "$TEST_ROOT/manifests/core"
  if TEST_PATH="$TEST_BIN" DOT_PLATFORM=omarchy run_dot install; then
    cleanup_fixture
    fail 'failed Omarchy setup command unexpectedly succeeded'
    return 1
  fi
  cleanup_fixture
}

omarchy_command_test && macos_cask_mapping_test && unsupported_platform_app_test && omarchy_failure_test
