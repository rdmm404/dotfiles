#!/usr/bin/env bash

TEST_REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  return 1
}

assert_linked() {
  [ -L "$1" ] || fail "expected link: $1"
}

assert_contains() {
  rg -F -- "$2" "$1" >/dev/null 2>&1 || fail "expected '$2' in $1"
}

configuration_deploy_test() {
  configuration_platform="$1"
  configuration_tmp=$(mktemp -d "${TMPDIR:-/tmp}/dot-config.XXXXXX") || return 1
  mkdir -p "$configuration_tmp/home"
  if ! HOME="$configuration_tmp/home" DOT_ROOT="$TEST_REPO" DOT_PLATFORM="$configuration_platform" \
    STOW_COMMAND="$(command -v stow)" "$TEST_REPO/dot" deploy --yes \
    >"$configuration_tmp/output" 2>"$configuration_tmp/error"; then
    cat "$configuration_tmp/output"
    cat "$configuration_tmp/error" >&2
    rm -rf "$configuration_tmp"
    return 1
  fi

  assert_linked "$configuration_tmp/home/.zshrc" || { rm -rf "$configuration_tmp"; return 1; }
  assert_linked "$configuration_tmp/home/.config/zsh/platform.zsh" || { rm -rf "$configuration_tmp"; return 1; }
  assert_linked "$configuration_tmp/home/.config/vscode/styles.css" || { rm -rf "$configuration_tmp"; return 1; }
  assert_linked "$configuration_tmp/home/.agents/skills/ask-matt/SKILL.md" || { rm -rf "$configuration_tmp"; fail 'agent skill missing'; return 1; }
  [ ! -e "$configuration_tmp/home/skills-lock.json" ] || { rm -rf "$configuration_tmp"; fail 'skills lock file was linked'; return 1; }
  [ -f "$configuration_tmp/home/.config/rtk/config.toml" ] || { rm -rf "$configuration_tmp"; fail 'RTK config missing'; return 1; }
  [ -f "$configuration_tmp/home/.config/starship.toml" ] || { rm -rf "$configuration_tmp"; fail 'Starship config missing'; return 1; }
  [ -f "$configuration_tmp/home/.config/vscode/settings.json" ] || { rm -rf "$configuration_tmp"; fail 'Linux VS Code settings missing'; return 1; }

  case "$configuration_platform" in
    macos)
      assert_contains "$TEST_REPO/platforms/macos/.config/ghostty/config" 'config-file = ~/.config/ghostty/shared.conf' || { rm -rf "$configuration_tmp"; return 1; }
      [ -f "$configuration_tmp/home/.config/ghostty/shared.conf" ] || { rm -rf "$configuration_tmp"; fail 'macOS Ghostty shared config missing'; return 1; }
      assert_linked "$configuration_tmp/home/Library/Application Support/Code/User/settings.json" || { rm -rf "$configuration_tmp"; return 1; }
      assert_contains "$TEST_REPO/platforms/macos/Library/Application Support/Code/User/settings.json" '"workbench.colorTheme": "Dracula Theme"' || { rm -rf "$configuration_tmp"; return 1; }
      assert_contains "$TEST_REPO/platforms/macos/Library/Application Support/Code/User/settings.json" '"workbench.colorCustomizations"' || { rm -rf "$configuration_tmp"; return 1; }
      assert_linked "$configuration_tmp/home/Library/Application Support/rtk/config.toml" || { rm -rf "$configuration_tmp"; return 1; }
      [ -f "$configuration_tmp/home/Library/Application Support/MTMR/items.json" ] || { rm -rf "$configuration_tmp"; fail 'MTMR config missing'; return 1; }
      assert_linked "$configuration_tmp/home/.config/ghostty/config" || { rm -rf "$configuration_tmp"; return 1; }
      ;;
    wsl)
      assert_linked "$configuration_tmp/home/.config/Code/User/settings.json" || { rm -rf "$configuration_tmp"; return 1; }
      [ ! -e "$configuration_tmp/home/Library" ] || { rm -rf "$configuration_tmp"; fail 'WSL received macOS config'; return 1; }
      ;;
    omarchy)
      assert_linked "$configuration_tmp/home/.config/Code/User/settings.json" || { rm -rf "$configuration_tmp"; return 1; }
      assert_linked "$configuration_tmp/home/.config/ghostty/config" || { rm -rf "$configuration_tmp"; return 1; }
      assert_contains "$TEST_REPO/platforms/omarchy/.config/ghostty/config" 'config-file = ?"~/.local/state/omarchy/current/theme/ghostty.conf"' || { rm -rf "$configuration_tmp"; return 1; }
      ;;
  esac

  rm -rf "$configuration_tmp"
}

shared_configuration_test() {
  [ -f "$TEST_REPO/global/.config/rtk/config.toml" ] && [ ! -L "$TEST_REPO/global/.config/rtk/config.toml" ] || fail 'RTK config is not canonical' || return 1
  if rg -n '(/Users/[A-Za-z]|/home/[A-Za-z]|Poetry|ollama\.exe|/snap/bin)' \
    "$TEST_REPO/global" >/dev/null 2>&1; then
    fail 'shared configuration contains platform-specific paths'
    return 1
  fi
  if rg -n 'FiraCode|Dracula' "$TEST_REPO/platforms/omarchy" >/dev/null 2>&1; then
    fail 'Omarchy configuration takes ownership of theme or font'
    return 1
  fi
  assert_contains "$TEST_REPO/global/.config/vscode/settings.json" 'file://${userHome}/.config/vscode/styles.css' || return 1
  for old_path in zsh starship rtk vscode ghostty mtmr; do
    [ ! -e "$TEST_REPO/$old_path" ] || { fail "old package remains: $old_path"; return 1; }
  done
}

shared_configuration_test || exit 1
configuration_deploy_test macos || exit 1
configuration_deploy_test wsl || exit 1
configuration_deploy_test omarchy || exit 1
printf 'configuration tests passed\n'
