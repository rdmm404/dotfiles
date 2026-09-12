#!/usr/bin/env bash

app_command() {
  case "$1" in
    stow) printf '%s' "${STOW_COMMAND:-stow}" ;;
    vscode) printf 'code' ;;
    *) printf '%s' "$1" ;;
  esac
}

# Platform probes return 0 for available, 1 for missing, 2 for unsupported.
app_status() {
  APP_STATUS=missing
  if installer_available "$1"; then
    APP_STATUS=installed
  elif [ "$?" = 2 ]; then
    APP_STATUS=unsupported
  fi
}

# Shared by macOS and Omarchy where applicable. Clone files only: no downloaded setup script,
# shell startup, plugin execution, or changes to .zshrc during installation.
zap_path() {
  printf '%s/zap' "${XDG_DATA_HOME:-$HOME/.local/share}"
}

zap_plugin_file() {
  case "$1" in
    zsh-autopair) printf 'autopair.zsh' ;;
    *) printf '%s.zsh' "$1" ;;
  esac
}

zap_available() {
  case "$1" in
    zsh) command -v zsh >/dev/null 2>&1 && [ -f "$(zap_path)/zap.zsh" ] ;;
    *) [ -f "$(zap_path)/plugins/$1/$(zap_plugin_file "$1")" ] ;;
  esac
}

zap_install() {
  local app="$1" repository directory branch=()
  if [ "$app" = zsh ]; then
    [ -f "$(zap_path)/zap.zsh" ] && return 0
    repository=zap-zsh/zap
    directory="$(zap_path)"
    branch=(--branch release-v1)
  else
    zap_install zsh || return 1
    case "$app" in
      zsh-autopair) repository=hlissner/zsh-autopair ;;
      *) repository="zsh-users/$app" ;;
    esac
    directory="$(zap_path)/plugins/$app"
  fi
  command -v git >/dev/null 2>&1 || { dot_error 'git is required to install Zap and its plugins'; return 1; }
  mkdir -p "${directory%/*}" || return 1
  git clone --quiet --depth 1 "${branch[@]}" "https://github.com/$repository.git" "$directory"
}
