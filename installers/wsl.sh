#!/usr/bin/env bash

wsl_package() {
  case "$1" in
    fd) printf 'fd-find' ;;
    rg) printf 'ripgrep' ;;
    nerd-font|ghostty) printf '' ;;
    vscode) printf '' ;;
    *) printf '%s' "$1" ;;
  esac
}

wsl_command_for() {
  case "$1" in
    fd) printf 'fdfind' ;;
    bat) printf 'batcat' ;;
    *) app_command "$1" ;;
  esac
}

wsl_plugin_repository() {
  case "$1" in
    zsh-autosuggestions) printf 'zsh-users/zsh-autosuggestions' ;;
    zsh-autopair) printf 'hlissner/zsh-autopair' ;;
    zsh-history-substring-search) printf 'zsh-users/zsh-history-substring-search' ;;
    *) return 1 ;;
  esac
}

wsl_plugin_file() {
  case "$1" in
    zsh-autosuggestions) printf 'zsh-autosuggestions.zsh' ;;
    zsh-autopair) printf 'autopair.zsh' ;;
    zsh-history-substring-search) printf 'zsh-history-substring-search.zsh' ;;
    *) return 1 ;;
  esac
}

wsl_plugin_installed() {
  plugin="$1"
  plugin_dir="${XDG_DATA_HOME:-${HOME:-}/.local/share}/zap/plugins/$plugin"
  plugin_file="$(wsl_plugin_file "$plugin")" || return 1
  [ -f "$plugin_dir/$plugin_file" ]
}

wsl_install_plugin() {
  plugin="$1"
  plugin_repository="$(wsl_plugin_repository "$plugin")" || return 1
  dot_install_zap || return 1
  zsh -c 'source "$HOME/.local/share/zap/zap.zsh" && plug "$1"' dot-zap "$plugin_repository"
}

wsl_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    printf 'apt-get'
  elif command -v yum >/dev/null 2>&1; then
    printf 'yum'
  else
    return 1
  fi
}

installer_status() {
  app="$1"
  INSTALLER_STATUS=unsupported
  app_known "$app" || return 2
  case "$app" in
    ghostty|nerd-font)
      INSTALLER_STATUS=unsupported
      ;;
    vscode)
      command -v code >/dev/null 2>&1 && INSTALLER_STATUS=installed || INSTALLER_STATUS=unsupported
      ;;
    zsh)
      if command -v zsh >/dev/null 2>&1 && [ -f "${HOME:-}/.local/share/zap/zap.zsh" ]; then
        INSTALLER_STATUS=installed
      else
        INSTALLER_STATUS=missing
      fi
      ;;
    fd)
      if command -v fdfind >/dev/null 2>&1 || command -v fd >/dev/null 2>&1; then
        INSTALLER_STATUS=installed
      else
        INSTALLER_STATUS=missing
      fi
      ;;
    zsh-autosuggestions|zsh-autopair|zsh-history-substring-search)
      if wsl_plugin_installed "$app"; then
        INSTALLER_STATUS=installed
      else
        INSTALLER_STATUS=missing
      fi
      ;;
    *)
      command -v "$(wsl_command_for "$app")" >/dev/null 2>&1 && INSTALLER_STATUS=installed || INSTALLER_STATUS=missing
      ;;
  esac
  return 0
}

wsl_run_package_manager() {
  manager="$1"
  shift
  if [ "${DOT_NO_SUDO:-0}" = 1 ] || ! command -v sudo >/dev/null 2>&1; then
    "$manager" "$@"
  else
    sudo "$manager" "$@"
  fi
}

installer_install() {
  app="$1"
  app_known "$app" || return 2
  case "$app" in
    ghostty|nerd-font|vscode)
      dot_error "unsupported on WSL: $app"
      return 1
      ;;
    zsh)
      if ! command -v zsh >/dev/null 2>&1; then
        manager="$(wsl_package_manager)" || { dot_error 'no supported WSL package manager found'; return 1; }
        wsl_run_package_manager "$manager" install -y zsh || return 1
      fi
      dot_install_zap
      ;;
    fd)
      manager="$(wsl_package_manager)" || { dot_error 'no supported WSL package manager found'; return 1; }
      wsl_run_package_manager "$manager" install -y "$(wsl_package fd)"
      ;;
    zsh-autosuggestions|zsh-autopair|zsh-history-substring-search)
      wsl_install_plugin "$app"
      ;;
    *)
      manager="$(wsl_package_manager)" || { dot_error 'no supported WSL package manager found'; return 1; }
      wsl_run_package_manager "$manager" install -y "$(wsl_package "$app")"
      ;;
  esac
}
