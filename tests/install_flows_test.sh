#!/usr/bin/env bash
# Public-command regressions for the simplified install/doctor flows.
TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TEST_DIR/helpers.sh"

unchanged_install_is_quiet() {
  make_fixture || return 1
  printf '%s\n' stow git > "$TEST_ROOT/manifests/core"
  run_dot install || { cleanup_fixture; return 1; }
  [ "$(wc -l < "$TEST_OUTPUT")" -eq 1 ] || { cleanup_fixture; fail 'unchanged install was noisy'; return 1; }
  cleanup_fixture
}

failed_install_is_reported() {
  make_fixture || return 1
  printf '%s\n' rtk git > "$TEST_ROOT/manifests/core"
  cat > "$TEST_BIN/omarchy" <<'EOF'
#!/bin/bash
printf 'omarchy %s\n' "$*" >> "$FAKE_LOG"
case "$*" in *rtk*) exit 1;; esac
exit 0
EOF
  chmod +x "$TEST_BIN/omarchy"
  if TEST_PATH="$TEST_BIN" run_dot install; then
    cleanup_fixture
    fail 'failed installation accepted'
    return 1
  fi
  assert_contains "$TEST_ERROR" 'failed to install: rtk'
  assert_contains "$TEST_OUTPUT" 'failed: 1'
  cleanup_fixture
}

bootstrap_stops_after_install_failure() {
  make_fixture || return 1
  printf '%s\n' rtk > "$TEST_ROOT/manifests/core"
  cat > "$TEST_BIN/omarchy" <<'EOF'
#!/bin/bash
printf 'omarchy %s\n' "$*" >> "$FAKE_LOG"
exit 1
EOF
  chmod +x "$TEST_BIN/omarchy"
  TEST_PATH="$TEST_BIN" run_dot bootstrap && { cleanup_fixture; fail 'failed bootstrap accepted'; return 1; }
  ! rg -F 'stow' "$TEST_TMP/commands" >/dev/null 2>&1 || {
    cleanup_fixture
    fail 'bootstrap deployed after install failure'
    return 1
  }
  cleanup_fixture
}

optional_apps_are_nonblocking_in_doctor() {
  make_fixture || return 1
  printf '%s\n' optional-app >> "$TEST_ROOT/manifests/catalog"
  printf '%s\n' optional-app > "$TEST_ROOT/manifests/optional"
  printf 'import sys\nsys.exit(0)\n' > "$TEST_ROOT/lib/files.py"
  run_dot doctor || { cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'missing optional application: optional-app' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

unchanged_install_is_quiet && failed_install_is_reported && bootstrap_stops_after_install_failure && optional_apps_are_nonblocking_in_doctor
