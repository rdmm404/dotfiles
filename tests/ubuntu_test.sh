#!/usr/bin/env bash
set -e
TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TEST_DIR/helpers.sh"

ubuntu_fixture() {
  make_fixture
  trap cleanup_fixture EXIT
  export HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/.local/share" DOT_ROOT="$TEST_ROOT"
  # This suite tests installers with fakes and does not require system Stow.
  REAL_STOW="$TEST_BIN/stow"
  . "$DOT_ROOT/lib/cli.sh"
  . "$DOT_ROOT/lib/apps.sh"
  . "$DOT_ROOT/installers/ubuntu.sh"
}

ubuntu_platform_test() {
  ubuntu_fixture
  . "$DOT_ROOT/lib/platform.sh"
  DOT_PLATFORM=ubuntu platform_detect
  [ "$PLATFORM" = ubuntu ]
  [ "$(platform_label ubuntu)" = Ubuntu ]
  # Test os-release parsing independently of this test runner's distribution.
  if [ ! -f /etc/omarchy-release ]; then
    printf 'ID=ubuntu\nID_LIKE=debian\n' > "$TEST_TMP/os-release"
    uname() { printf 'Linux\n'; }
    DOT_PLATFORM='' OMARCHY='' DOT_OS_RELEASE="$TEST_TMP/os-release" platform_detect
    [ "$PLATFORM" = ubuntu ]
    printf 'ID=debian\n' > "$TEST_TMP/os-release"
    if DOT_PLATFORM='' OMARCHY='' DOT_OS_RELEASE="$TEST_TMP/os-release" platform_detect; then
      fail 'Debian incorrectly detected as Ubuntu'
    fi
  fi
}

ubuntu_selection_test() {
  ubuntu_fixture
  mkdir -p "$DOT_ROOT/manifests/ubuntu"
  cp "$TEST_REPO/manifests/ubuntu/"* "$DOT_ROOT/manifests/ubuntu/"
  . "$DOT_ROOT/lib/manifest.sh"
  PLATFORM=ubuntu manifest_load 0
  printf '%s\n' "${APPS[@]}" > "$TEST_TMP/apps"
  for app in stow uv zsh fd bat rtk git-open herdr; do assert_contains "$TEST_TMP/apps" "$app"; done
  for app in ghostty vscode nerd-font; do assert_not_contains "$TEST_TMP/apps" "$app"; done
  printf 'herdr\n' > "$DOT_ROOT/manifests/optional"
  if PLATFORM=ubuntu manifest_load 1; then fail 'cross-manifest duplicate accepted'; fi
  printf 'unknown-app\n' > "$DOT_ROOT/manifests/ubuntu/core"
  if PLATFORM=ubuntu manifest_load 0; then fail 'unknown platform application accepted'; fi
  # No Ubuntu selections should leak into macOS/Omarchy.
  PLATFORM=omarchy manifest_load 0
  [ "${#APPS[@]}" = 0 ]
}

ubuntu_mapping_test() {
  ubuntu_fixture
  [ "$(ubuntu_command fd)" = fdfind ]
  [ "$(ubuntu_command bat)" = batcat ]
  ubuntu_apt() { printf '%s\n' "$*" >> "$TEST_TMP/packages"; }
  installer_install fd
  installer_install rg
  installer_install bat
  assert_contains "$TEST_TMP/packages" fd-find
  assert_contains "$TEST_TMP/packages" ripgrep
  assert_contains "$TEST_TMP/packages" bat
  for app in ghostty vscode nerd-font; do
    if installer_available "$app"; then fail "$app unexpectedly supported"; else [ "$?" = 2 ]; fi
  done
  # Bare zsh is insufficient: the preinstalled foundation must also exist.
  if installer_available zsh; then fail 'missing Zap was accepted'; fi
}

ubuntu_apt_privilege_test() {
  ubuntu_fixture
  apt-get() { printf 'apt-get %s\n' "$*" >> "$TEST_TMP/apt"; }
  sudo() { printf 'sudo %s\n' "$*" >> "$TEST_TMP/apt"; }
  id() { printf '1000\n'; }
  ubuntu_apt fd-find
  assert_contains "$TEST_TMP/apt" 'sudo apt-get install -y -- fd-find'
  id() { printf '0\n'; }
  ubuntu_apt zsh
  assert_contains "$TEST_TMP/apt" 'apt-get install -y -- zsh'
  apt-get() { return 1; }
  if ubuntu_apt stow; then fail 'APT failure swallowed'; fi
}

ubuntu_dry_run_test() {
  ubuntu_fixture
  printf 'herdr\n' > "$DOT_ROOT/manifests/core"
  DOT_PLATFORM=ubuntu run_dot install --dry-run --verbose
  assert_contains "$TEST_OUTPUT" 'will install: herdr'
  [ ! -e "$TEST_HOME/.local/bin/herdr" ]
  [ ! -s "$TEST_TMP/commands" ]
  mkdir -p "$TEST_HOME/.local/bin"
  printf '#!/bin/sh\nexit 0\n' > "$TEST_HOME/.local/bin/herdr"
  chmod +x "$TEST_HOME/.local/bin/herdr"
  DOT_PLATFORM=ubuntu run_dot install --verbose
  assert_contains "$TEST_OUTPUT" 'already installed: herdr'
  [ ! -s "$TEST_TMP/commands" ]
}

ubuntu_plugin_install_test() {
  ubuntu_fixture
  git() {
    printf '%s\n' "$*" >> "$TEST_TMP/clones"
    local destination="${@: -1}"
    mkdir -p "$destination"
    case "$*" in
      *zap-zsh/zap*) touch "$destination/zap.zsh" ;;
      *git-open*) touch "$destination/git-open"; chmod +x "$destination/git-open" ;;
      *supercharge*) touch "$destination/supercharge.plugin.zsh" ;;
      *zap-zsh/exa*) touch "$destination/eza.plugin.zsh" ;;
      *zsh-autopair*) touch "$destination/autopair.zsh" ;;
      *zsh-history-substring-search*) touch "$destination/zsh-history-substring-search.zsh" ;;
      *zsh-autosuggestions*) touch "$destination/zsh-autosuggestions.zsh" ;;
      *zsh-syntax-highlighting*) touch "$destination/zsh-syntax-highlighting.zsh" ;;
    esac
  }
  zsh() { :; }
  installer_install zsh
  installer_available zsh
  rm "$(zap_path)/plugins/supercharge/supercharge.plugin.zsh"
  if installer_available zsh; then fail 'missing Supercharge was accepted'; fi
  installer_install zsh
  eza() { :; }
  if installer_available eza; then fail 'missing eza plugin was accepted'; fi
  installer_install eza
  installer_available eza
  for app in zsh-autopair zsh-autosuggestions zsh-history-substring-search git-open; do
    installer_install "$app"
    installer_available "$app"
  done
  assert_contains "$TEST_TMP/clones" 'zsh-users/zsh-syntax-highlighting.git'
  assert_contains "$TEST_TMP/clones" 'paulirish/git-open.git'
  assert_contains "$TEST_TMP/clones" 'zap-zsh/supercharge.git'
  assert_contains "$TEST_TMP/clones" 'zap-zsh/exa.git'
  local clone_count
  clone_count=$(wc -l < "$TEST_TMP/clones")
  installer_install zsh
  installer_install eza
  [ "$(wc -l < "$TEST_TMP/clones")" = "$clone_count" ]
}

ubuntu_binary_test() {
  ubuntu_fixture
  uname() { printf 'x86_64\n'; }
  curl() {
    printf '%s\n' "$*" >> "$TEST_TMP/downloads"
    printf '#!/bin/sh\nexit 0\n' > "${@: -1}"
  }
  sha256sum() { while IFS= read -r line; do printf '%s\n' "$line" >> "$TEST_TMP/digests"; done; }
  ubuntu_install_binary herdr
  [ -x "$HOME/.local/bin/herdr" ]
  assert_contains "$TEST_TMP/downloads" 'herdrdev/herdr/releases/download/v0.9.0/herdr-linux-x86_64'
  assert_contains "$TEST_TMP/digests" '4fa1a01158dd8043da92d31b270780b0dcc10603038d9b61cac4d81ab63fb71f'
  tar() {
    [ "$1" = -xOzf ] && [ "$3" = rtk ] || return 1
    printf '#!/bin/sh\nexit 0\n'
  }
  ubuntu_install_binary rtk
  [ -x "$HOME/.local/bin/rtk" ]
  assert_contains "$TEST_TMP/downloads" 'rtk-ai/rtk/releases/download/v0.49.0/rtk-x86_64-unknown-linux-musl.tar.gz'
  tar() {
    [ "$1" = -xOzf ] && [ "$3" = "uv-$(uname -m)-unknown-linux-gnu/uv" ] || return 1
    printf '#!/bin/sh\nexit 0\n'
  }
  installer_install uv
  installer_available uv
  [ -x "$HOME/.local/bin/uv" ]
  assert_contains "$TEST_TMP/downloads" 'astral-sh/uv/releases/download/0.12.13/uv-x86_64-unknown-linux-gnu.tar.gz'
  assert_contains "$TEST_TMP/digests" '745765a3b6e360ad76743599ae5c42e9278c7edf8bbff9fc76d05bf2623a04dd'
  uname() { printf 'aarch64\n'; }
  ubuntu_install_binary uv
  assert_contains "$TEST_TMP/downloads" 'uv-aarch64-unknown-linux-gnu.tar.gz'
  assert_contains "$TEST_TMP/digests" '2eaa5d94f5db7b3a1a092156b9420459e42ab0217d917fe74a876309cef9b5e9'
  uname() { printf 'x86_64\n'; }
  printf 'preserve me\n' > "$HOME/.local/bin/herdr"
  sha256sum() { return 1; }
  if ubuntu_install_binary herdr; then fail 'checksum mismatch accepted'; fi
  assert_contains "$HOME/.local/bin/herdr" 'preserve me'
  curl() { return 1; }
  if ubuntu_install_binary herdr; then fail 'download failure accepted'; fi
  uname() { printf 'riscv64\n'; }
  if ubuntu_install_binary herdr; then fail 'unknown architecture accepted'; fi
}

for test in ubuntu_platform_test ubuntu_selection_test ubuntu_mapping_test \
  ubuntu_apt_privilege_test ubuntu_dry_run_test ubuntu_plugin_install_test ubuntu_binary_test; do
  ( "$test" )
done
printf 'Ubuntu tests passed\n'
