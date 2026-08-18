#!/usr/bin/env bash

installer_status() {
  app="$1"
  INSTALLER_STATUS=unsupported
  app_known "$app" || return 2
  case "$app" in
    zsh)
      if command -v zsh >/dev/null 2>&1 && { [ -f "${HOME:-}/.local/share/omarchy-zsh/omarchy-zsh.zsh" ] || [ -f /usr/share/omarchy-zsh/omarchy-zsh.zsh ] || [ -f /usr/share/omarchy-zsh/shell/omarchy-zsh.zsh ] || [ -f /usr/share/omarchy-zsh/shell/all ]; }; then
        INSTALLER_STATUS=installed
      else
        INSTALLER_STATUS=missing
      fi
      ;;
    zsh-autopair)
      # No Arch or AUR package currently provides hlissner/zsh-autopair.
      INSTALLER_STATUS=unsupported
      ;;
    nerd-font)
      if command -v fc-list >/dev/null 2>&1 && fc-list 2>/dev/null | awk 'BEGIN { IGNORECASE=1 } /nerd[[:space:]]*font/ { found=1 } END { exit !found }'; then
        INSTALLER_STATUS=installed
      else
        INSTALLER_STATUS=missing
      fi
      ;;
    zsh-autosuggestions|zsh-history-substring-search)
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
    zsh) printf 'omarchy-zsh' ;;
    fd) printf 'fd' ;;
    rg) printf 'ripgrep' ;;
    nerd-font) printf 'ttf-fira-code-nerd' ;;
    vscode) printf 'visual-studio-code-bin' ;;
    *) printf '%s' "$1" ;;
  esac
}

omarchy_install_with_command() {
  app="$1"
  package="$2"
  if command -v omarchy >/dev/null 2>&1; then
    case "$app" in
      ghostty) omarchy install terminal ghostty ;;
      vscode) omarchy install editor vscode ;;
      rtk|git-open) omarchy pkg aur add "$package" ;;
      *) omarchy pkg add "$package" ;;
    esac
    return $?
  fi

  if command -v pacman >/dev/null 2>&1; then
    case "$app" in
      rtk|git-open)
        dot_error "Omarchy's AUR package helper is required to install $app"
        return 1
        ;;
    esac
    if [ "${DOT_NO_SUDO:-0}" = 1 ] || ! command -v sudo >/dev/null 2>&1; then
      pacman -S --needed --noconfirm "$package"
    else
      sudo pacman -S --needed --noconfirm "$package"
    fi
  else
    dot_error 'neither the omarchy package helper nor pacman is available'
    return 1
  fi
}

installer_install() {
  app="$1"
  app_known "$app" || return 2
  omarchy_install_with_command "$app" "$(omarchy_package "$app")"
}
