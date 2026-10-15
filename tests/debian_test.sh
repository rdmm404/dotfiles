#!/usr/bin/env bash
set -e
TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TEST_DIR/helpers.sh"

make_fixture
trap cleanup_fixture EXIT
export HOME="$TEST_HOME" DOT_ROOT="$TEST_ROOT"
. "$DOT_ROOT/lib/cli.sh"
. "$DOT_ROOT/lib/platform.sh"
DOT_PLATFORM=debian platform_detect
[ "$PLATFORM" = debian ]
[ "$(platform_label debian)" = Debian ]
if [ ! -f /etc/omarchy-release ]; then
  uname() { printf 'Linux\n'; }
  printf 'ID=debian\n' > "$TEST_TMP/os-release"
  DOT_PLATFORM='' OMARCHY='' DOT_OS_RELEASE="$TEST_TMP/os-release" platform_detect
  [ "$PLATFORM" = debian ]
  printf 'ID=ubuntu\nID_LIKE=debian\n' > "$TEST_TMP/os-release"
  DOT_PLATFORM='' OMARCHY='' DOT_OS_RELEASE="$TEST_TMP/os-release" platform_detect
  [ "$PLATFORM" = ubuntu ]
  printf 'ID=unknown\nID_LIKE=debian\n' > "$TEST_TMP/os-release"
  if DOT_PLATFORM='' OMARCHY='' DOT_OS_RELEASE="$TEST_TMP/os-release" platform_detect; then
    fail 'unsupported derivative selected Debian'
  fi
fi
PLATFORM=debian
mkdir -p "$DOT_ROOT/manifests/ubuntu" "$DOT_ROOT/manifests/debian"
cp "$TEST_REPO/manifests/ubuntu/"* "$DOT_ROOT/manifests/ubuntu/"
cp -P "$TEST_REPO/manifests/debian/"* "$DOT_ROOT/manifests/debian/"
. "$DOT_ROOT/lib/manifest.sh"
manifest_load 0
printf '%s\n' "${APPS[@]}" > "$TEST_TMP/apps"
for app in zsh stow uv fd bat rtk herdr git-open; do assert_contains "$TEST_TMP/apps" "$app"; done
for app in ghostty vscode nerd-font; do assert_not_contains "$TEST_TMP/apps" "$app"; done
. "$DOT_ROOT/lib/apps.sh"
platform_load_installer debian
[ "$(ubuntu_command fd)" = fdfind ]
[ "$(ubuntu_command bat)" = batcat ]
ubuntu_apt() { printf '%s\n' "$*" >> "$TEST_TMP/packages"; }
installer_install fd
installer_install bat
assert_contains "$TEST_TMP/packages" fd-find
assert_contains "$TEST_TMP/packages" bat
printf 'Debian detection, selection and installer tests passed\n'
