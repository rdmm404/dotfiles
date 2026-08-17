#!/usr/bin/env bash

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TEST_DIR/helpers.sh"

omarchy_command_test() {
  make_fixture || return 1
  printf '%s\n' 'ghostty' > "$TEST_ROOT/manifests/core"
  DOT_PLATFORM=omarchy run_dot install --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_TMP/commands" 'omarchy-install --yes ghostty' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

macos_mapping_test() {
  make_fixture || return 1
  printf '%s\n' 'zsh-autopair' > "$TEST_ROOT/manifests/core"
  DOT_PLATFORM=macos run_dot install --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_TMP/commands" 'brew install zsh-autopair' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

macos_ripgrep_mapping_test() {
  make_fixture || return 1
  printf '%s\n' 'rg' > "$TEST_ROOT/manifests/core"
  DOT_PLATFORM=macos run_dot install --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_TMP/commands" 'brew install ripgrep' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

wsl_zap_plugin_status_test() {
  make_fixture || return 1
  mkdir -p "$TEST_HOME/.local/share/zap/plugins/zsh-autopair"
  : > "$TEST_HOME/.local/share/zap/plugins/zsh-autopair/autopair.zsh"
  printf '%s\n' 'zsh-autopair' > "$TEST_ROOT/manifests/core"
  run_dot plan || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'already installed: zsh-autopair' || { cleanup_fixture; return 1; }
  assert_not_contains "$TEST_OUTPUT" 'will install: zsh-autopair' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

wsl_zap_plugin_install_test() {
  make_fixture || return 1
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
  printf '%s\n' 'zsh-autopair' > "$TEST_ROOT/manifests/core"
  run_dot install --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_TMP/commands" 'hlissner/zsh-autopair' || { cleanup_fixture; return 1; }
  assert_not_contains "$TEST_TMP/commands" 'apt-get install -y zsh-autopair' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

wsl_batcat_test() {
  make_fixture || return 1
  cat > "$TEST_BIN/batcat" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$TEST_BIN/batcat"
  printf '%s\n' 'bat' > "$TEST_ROOT/manifests/core"
  run_dot plan || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'already installed: bat' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

zap_argument_test() {
  make_fixture || return 1
  cat > "$TEST_BIN/zsh" <<'EOF'
#!/bin/bash
printf 'zsh %s\n' "$*" >> "${FAKE_LOG:?}"
/bin/mkdir -p "$HOME/.local/share/zap"
: > "$HOME/.local/share/zap/zap.zsh"
exit 0
EOF
  cat > "$TEST_BIN/curl" <<'EOF'
#!/bin/bash
printf '# fake zap installer\n'
EOF
  chmod +x "$TEST_BIN/zsh" "$TEST_BIN/curl"
  printf '%s\n' 'zsh' > "$TEST_ROOT/manifests/core"
  run_dot install --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_TMP/commands" 'zap-install --branch release-v1' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

omarchy_failure_test() {
  make_fixture || return 1
  cat > "$TEST_BIN/omarchy-install" <<'EOF'
#!/bin/bash
printf 'omarchy-install %s\n' "$*" >> "${FAKE_LOG:?}"
exit 1
EOF
  chmod +x "$TEST_BIN/omarchy-install"
  printf '%s\n' 'ghostty' > "$TEST_ROOT/manifests/core"
  if DOT_PLATFORM=omarchy run_dot install --yes; then
    cleanup_fixture
    fail 'failed Omarchy setup command unexpectedly succeeded'
    return 1
  fi
  assert_not_contains "$TEST_TMP/commands" 'pacman -S' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

pacman_fallback_test() {
  make_fixture || return 1
  rm -f "$TEST_BIN/omarchy-install"
  printf '%s\n' 'ghostty' > "$TEST_ROOT/manifests/core"
  DOT_PLATFORM=omarchy run_dot install --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  assert_contains "$TEST_TMP/commands" 'pacman -S --needed --noconfirm ghostty' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

omarchy_command_test && macos_mapping_test && macos_ripgrep_mapping_test && wsl_zap_plugin_status_test && wsl_zap_plugin_install_test && wsl_batcat_test && zap_argument_test && omarchy_failure_test && pacman_fallback_test
