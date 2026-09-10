#!/usr/bin/env bash

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TEST_DIR/helpers.sh"

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

make_files_fake() {
  cat > "$TEST_ROOT/lib/files.py" <<'EOF'
#!/usr/bin/env python3
import os
import sys
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("files " + " ".join(sys.argv[1:]) + "\n")
EOF
}

platform_test() {
  make_fixture || return 1
  printf '%s\n' 'stow' > "$TEST_ROOT/manifests/core"
  printf '%s\n' 'git' > "$TEST_ROOT/manifests/development"
  run_dot install --dry-run || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'Platform: WSL' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

dry_run_is_read_only_test() {
  make_fixture || return 1
  printf '%s\n' 'bat' > "$TEST_ROOT/manifests/core"
  run_dot install --dry-run || { cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'will install: bat' || { cleanup_fixture; return 1; }
  [ ! -e "$TEST_TMP/commands" ] || { cleanup_fixture; fail 'dry-run invoked package manager'; return 1; }
  assert_contains "$TEST_OUTPUT" 'dry run: no applications changed' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

install_is_consent_test() {
  make_fixture || return 1
  make_wsl_zap_fake
  printf '%s\n' 'zsh-autopair' > "$TEST_ROOT/manifests/core"
  run_dot install || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_TMP/commands" 'hlissner/zsh-autopair' || { cleanup_fixture; return 1; }
  assert_not_contains "$TEST_OUTPUT" 'Continue?' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

verbose_status_test() {
  make_fixture || return 1
  printf '%s\n' 'stow' > "$TEST_ROOT/manifests/core"
  run_dot install --dry-run --verbose || { cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'already installed: stow' || { cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'unchanged:' || { cleanup_fixture; return 1; }
  assert_not_contains "$TEST_OUTPUT" '[plan]' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

optional_manifest_test() {
  make_fixture || return 1
  printf '%s\n' 'bat' > "$TEST_ROOT/manifests/optional"
  run_dot install --include optional --dry-run || { cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'Manifests: core, development, optional' || { cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'will install: bat' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

invalid_argument_test() {
  make_fixture || return 1
  if run_dot install --yes; then
    cleanup_fixture
    fail '--yes unexpectedly remained a valid install option'
    return 1
  fi
  assert_contains "$TEST_ERROR" 'invalid argument' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

plan_command_removed_test() {
  make_fixture || return 1
  if run_dot plan; then
    cleanup_fixture
    fail 'removed plan command unexpectedly succeeded'
    return 1
  fi
  assert_contains "$TEST_ERROR" 'unknown command: plan' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

bootstrap_is_composed_test() {
  make_fixture || return 1
  make_files_fake
  mkdir -p "$TEST_ROOT/global/.config" "$TEST_ROOT/platforms/wsl/.config"
  printf 'shared\n' > "$TEST_ROOT/global/.config/shared"
  printf '%s\n' 'stow' > "$TEST_ROOT/manifests/core"
  printf '%s\n' 'git' > "$TEST_ROOT/manifests/development"
  run_dot bootstrap --dry-run --verbose --replace || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_TMP/commands" 'files deploy --dry-run --verbose --replace' || { cleanup_fixture; return 1; }
  assert_not_contains "$TEST_TMP/commands" 'files check' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

bootstrap_optional_test() {
  make_fixture || return 1
  make_files_fake
  printf '%s\n' 'bat' > "$TEST_ROOT/manifests/optional"
  run_dot bootstrap --include optional --dry-run || { cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'will install: bat' || { cleanup_fixture; return 1; }
  assert_contains "$TEST_TMP/commands" 'files deploy --dry-run' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

doctor_runtime_only_test() {
  make_fixture || return 1
  make_files_fake
  printf '%s\n' 'stow' > "$TEST_ROOT/manifests/core"
  printf '%s\n' 'git' > "$TEST_ROOT/manifests/development"
  printf '%s\n' 'bat' > "$TEST_ROOT/manifests/optional"
  run_dot doctor --verbose || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_TMP/commands" 'files check --verbose' || { cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'missing optional application: bat' || { cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'doctor found no blocking problems' || { cleanup_fixture; return 1; }
  assert_not_contains "$TEST_OUTPUT" 'ShellCheck' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

platform_test && dry_run_is_read_only_test && install_is_consent_test && verbose_status_test && optional_manifest_test && invalid_argument_test && plan_command_removed_test && bootstrap_is_composed_test && bootstrap_optional_test && doctor_runtime_only_test
