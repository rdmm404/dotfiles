#!/usr/bin/env bash

installer_status() {
  app="$1"
  INSTALLER_STATUS=unsupported
  app_known "$app" || return 2
  case "$app" in
    zsh)
      if command -v zsh >/dev/null 2>&1 && { command -v omarchy-zsh >/dev/null 2>&1 || [ -f "${HOME:-}/.local/share/omarchy-zsh/omarchy-zsh.zsh" ]; }; then
        INSTALLER_STATUS=installed
      else
        INSTALLER_STATUS=missing
      fi
      ;;
    nerd-font)
      if command -v fc-list >/dev/null 2>&1 && fc-list 2>/dev/null | awk 'BEGIN { IGNORECASE=1 } /nerd[[:space:]]*font/ { found=1 } END { exit !found }'; then
        INSTALLER_STATUS=installed
      else
        INSTALLER_STATUS=missing
      fi
      ;;
    zsh-autosuggestions|zsh-autopair|zsh-history-substring-search)
      if omarchy_plugin_installed "$app"; then
        INSTALLER_STATUS=installed
      else
        INSTALLER_STATUS=missing
      fi
      ;;
    *)
      command -v "$(app_command "$app")" >/dev/null 2>&1 && INSTALLER_STATUS=installed || INSTALLER_STATUS=missing
      ;;
  esac
  return 0
}

omarchy_plugin_installed() {
  plugin="$1"
  case "$plugin" in
    zsh-autosuggestions) plugin_file=zsh-autosuggestions/zsh-autosuggestions.zsh ;;
    zsh-autopair) plugin_file=zsh-autopair/autopair.zsh ;;
    zsh-history-substring-search) plugin_file=zsh-history-substring-search/zsh-history-substring-search.zsh ;;
    *) return 1 ;;
  esac
  [ -f "/usr/share/zsh/plugins/$plugin_file" ] || [ -f "/usr/share/zsh/$plugin_file" ] || \
    { command -v pacman >/dev/null 2>&1 && pacman -Q "$plugin" >/dev/null 2>&1; }
}

omarchy_package() {
  case "$1" in
    fd) printf 'fd' ;;
    rg) printf 'ripgrep' ;;
    nerd-font) printf 'ttf-fira-code-nerd' ;;
    vscode) printf 'visual-studio-code' ;;
    *) printf '%s' "$1" ;;
  esac
}

omarchy_install_with_command() {
  if command -v omarchy-install >/dev/null 2>&1; then
    if [ "${DOT_YES:-0}" = 1 ]; then
      omarchy-install --yes "$1"
    else
      omarchy-install "$1"
    fi
    return $?
  elif command -v pacman >/dev/null 2>&1; then
    if [ "${DOT_NO_SUDO:-0}" = 1 ] || ! command -v sudo >/dev/null 2>&1; then
      pacman -S --needed --noconfirm "$2"
    else
      sudo pacman -S --needed --noconfirm "$2"
    fi
  else
    dot_error 'neither omarchy-install nor pacman is available'
    return 1
  fi
}

installer_install() {
  app="$1"
  app_known "$app" || return 2
  if [ "$app" = zsh ]; then
    omarchy_install_with_command omarchy-zsh omarchy-zsh
  else
    omarchy_install_with_command "$app" "$(omarchy_package "$app")"
  fi
}
