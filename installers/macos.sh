#!/usr/bin/env bash

macos_package() {
  case "$1" in
    nerd-font) printf 'font-fira-code-nerd-font' ;;
    rg) printf 'ripgrep' ;;
    vscode) printf 'visual-studio-code' ;;
    *) printf '%s' "$1" ;;
  esac
}

installer_available() {
  case "$1" in
    zsh|zsh-autosuggestions|zsh-autopair|zsh-history-substring-search)
      zap_available "$1"
      ;;
    ghostty|vscode|nerd-font)
      if [ "$1" != nerd-font ] && command -v "$(app_command "$1")" >/dev/null 2>&1; then return 0; fi
      command -v brew >/dev/null 2>&1 && brew list --cask "$(macos_package "$1")" >/dev/null 2>&1
      ;;
    *) command -v "$(app_command "$1")" >/dev/null 2>&1 ;;
  esac
}

macos_install_package() {
  command -v brew >/dev/null 2>&1 || { dot_error 'Homebrew is required to install macOS applications'; return 1; }
  case "$1" in
    nerd-font|ghostty|vscode) brew install --cask "$(macos_package "$1")" ;;
    *) brew install "$(macos_package "$1")" ;;
  esac
}

installer_install() {
  case "$1" in
    zsh)
      command -v zsh >/dev/null 2>&1 || macos_install_package zsh || return 1
      zap_install zsh
      ;;
    zsh-autosuggestions|zsh-autopair|zsh-history-substring-search) zap_install "$1" ;;
    *) macos_install_package "$1" ;;
  esac
}
