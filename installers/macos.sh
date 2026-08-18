#!/usr/bin/env bash

macos_brew_package() {
  case "$1" in
    nerd-font) printf '%s' font-fira-code-nerd-font ;;
    rg) printf '%s' ripgrep ;;
    vscode) printf '%s' visual-studio-code ;;
    ghostty) printf '%s' ghostty ;;
    *) printf '%s' "$1" ;;
  esac
}

macos_cask_installed() {
  command -v brew >/dev/null 2>&1 && brew list --cask "$1" >/dev/null 2>&1
}

macos_plugin_repository() {
  case "$1" in
    zsh-autosuggestions) printf 'zsh-users/zsh-autosuggestions' ;;
    zsh-autopair) printf 'hlissner/zsh-autopair' ;;
    zsh-history-substring-search) printf 'zsh-users/zsh-history-substring-search' ;;
    *) return 1 ;;
  esac
}

macos_plugin_file() {
  case "$1" in
    zsh-autosuggestions) printf 'zsh-autosuggestions.zsh' ;;
    zsh-autopair) printf 'autopair.zsh' ;;
    zsh-history-substring-search) printf 'zsh-history-substring-search.zsh' ;;
    *) return 1 ;;
  esac
}

macos_plugin_installed() {
  plugin="$1"
  plugin_dir="${XDG_DATA_HOME:-${HOME:-}/.local/share}/zap/plugins/$plugin"
  plugin_file="$(macos_plugin_file "$plugin")" || return 1
  [ -f "$plugin_dir/$plugin_file" ]
}

macos_install_plugin() {
  plugin="$1"
  plugin_repository="$(macos_plugin_repository "$plugin")" || return 1
  dot_install_zap || return 1
  zsh -c 'source "$HOME/.local/share/zap/zap.zsh" && plug "$1"' dot-zap "$plugin_repository"
}

installer_status() {
  app="$1"
  INSTALLER_STATUS=unsupported
  app_known "$app" || return 2

  case "$app" in
    ghostty|vscode|nerd-font)
      if macos_cask_installed "$(macos_brew_package "$app")"; then
        INSTALLER_STATUS=installed
      elif [ "$app" != nerd-font ] && command -v "$(app_command "$app")" >/dev/null 2>&1; then
        INSTALLER_STATUS=installed
      else
        INSTALLER_STATUS=missing
      fi
      ;;
    zsh)
      if command -v zsh >/dev/null 2>&1 && [ -f "${HOME:-}/.local/share/zap/zap.zsh" ]; then
        INSTALLER_STATUS=installed
      else
        INSTALLER_STATUS=missing
      fi
      ;;
    stow|git|gh|starship|zoxide|fzf|fd|rg|bat|eza|rtk|git-open)
      command -v "$(app_command "$app")" >/dev/null 2>&1 && INSTALLER_STATUS=installed || INSTALLER_STATUS=missing
      ;;
    zsh-autosuggestions|zsh-autopair|zsh-history-substring-search)
      macos_plugin_installed "$app" && INSTALLER_STATUS=installed || INSTALLER_STATUS=missing
      ;;
  esac
  return 0
}

macos_brew_install() {
  if ! command -v brew >/dev/null 2>&1; then
    dot_error 'Homebrew is required to install macOS applications'
    return 1
  fi
  if [ "$1" = cask ]; then
    brew install --cask "$2"
  else
    brew install "$2"
  fi
}

installer_install() {
  app="$1"
  app_known "$app" || return 2
  case "$app" in
    zsh)
      command -v zsh >/dev/null 2>&1 || macos_brew_install formula zsh || return 1
      dot_install_zap
      ;;
    nerd-font|ghostty|vscode)
      macos_brew_install cask "$(macos_brew_package "$app")"
      ;;
    zsh-autosuggestions|zsh-autopair|zsh-history-substring-search)
      macos_install_plugin "$app"
      ;;
    *)
      macos_brew_install formula "$(macos_brew_package "$app")"
      ;;
  esac
}
