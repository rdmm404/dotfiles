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

make_wsl_zap_fake() {
  cat > "$TEST_BIN/zsh" <<'EOF'
#!/bin/bash
printf 'zsh %s\n' "$*" >> "${FAKE_LOG:?}"
if [ "$3" = zap-install ]; then
  /bin/mkdir -p "$HOME/.local/share/zap/plugins"
  : > "$HOME/.local/share/zap/zap.zsh"
elif [ "$4" = hlissner/zsh-autopair ]; then
  /bin/mkdir -p "$HOME/.local/share/zap/plugins/zsh-autopair"
  : > "$HOME/.local/share/zap/plugins/zsh-autopair/autopair.zsh"
fi
exit 0
EOF
  cat > "$TEST_BIN/curl" <<'EOF'
#!/bin/bash
printf '# fake zap installer\n'
EOF
  chmod +x "$TEST_BIN/zsh" "$TEST_BIN/curl"
}

install_choice_test() {
  make_fixture || return 1
  make_wsl_zap_fake
  printf '%s\n' 'zsh-autopair' > "$TEST_ROOT/manifests/core"
  run_dot install --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_TMP/commands" 'hlissner/zsh-autopair' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

repeat_install_test() {
  make_fixture || return 1
  make_wsl_zap_fake
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
  assert_contains "$TEST_OUTPUT" 'deployment complete' || { cleanup_fixture; return 1; }
  assert_not_contains "$TEST_TMP/commands" 'apt-get install' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

bootstrap_missing_stow_test() {
  make_fixture || return 1
  mkdir -p "$TEST_ROOT/global/.config" "$TEST_ROOT/platforms/wsl/.config"
  printf 'shared\n' > "$TEST_ROOT/global/.config/shared"
  printf '%s\n' 'stow' > "$TEST_ROOT/manifests/core"
  printf '%s\n' '# empty' > "$TEST_ROOT/manifests/development"
  cat > "$TEST_BIN/apt-get" <<'EOF'
#!/bin/bash
pkg=''
for arg in "$@"; do pkg="$arg"; done
printf 'apt-get %s\n' "$*" >> "${FAKE_LOG:?}"
printf '%s\n' "$pkg" >> "${FAKE_INSTALLED:?}"
if [ "$pkg" = stow ]; then
  cp "$REAL_STOW" "$FAKE_BIN/missing-stow"
  chmod +x "$FAKE_BIN/missing-stow"
fi
EOF
  chmod +x "$TEST_BIN/apt-get"
  TEST_STOW_COMMAND=missing-stow TEST_REAL_STOW=1 run_dot bootstrap --yes || { cat "$TEST_OUTPUT"; cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  [ -L "$TEST_HOME/.config/shared" ] || { cleanup_fixture; fail 'bootstrap did not deploy after installing Stow'; return 1; }
  assert_contains "$TEST_OUTPUT" 'required command will be installed: stow' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

bootstrap_conflict_plan_test() {
  make_fixture || return 1
  mkdir -p "$TEST_ROOT/global/.config" "$TEST_HOME/.config"
  printf 'shared\n' > "$TEST_ROOT/global/.config/shared"
  printf 'keep\n' > "$TEST_HOME/.config/shared"
  printf '%s\n' 'stow' > "$TEST_ROOT/manifests/core"
  printf '%s\n' '# empty' > "$TEST_ROOT/manifests/development"
  if TEST_STOW_COMMAND=missing-stow run_dot bootstrap --yes; then
    cleanup_fixture
    fail 'bootstrap conflict unexpectedly succeeded'
    return 1
  fi
  assert_contains "$TEST_OUTPUT" 'will install: stow' || { cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'existing file: ~/.config/shared' || { cleanup_fixture; return 1; }
  [ ! -e "$TEST_TMP/commands" ] || { cleanup_fixture; fail 'bootstrap installed before resolving conflict'; return 1; }
  cleanup_fixture
}

platform_test && planning_is_read_only_test && install_choice_test && repeat_install_test && optional_plan_test && invalid_argument_test && cancel_test && doctor_test && bootstrap_readiness_test && bootstrap_missing_stow_test && bootstrap_conflict_plan_test
