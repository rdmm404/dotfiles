#!/usr/bin/env bash

installer_available() {
  case "$1" in
    zsh)
      command -v zsh >/dev/null 2>&1 && {
        [ -f "$HOME/.local/share/omarchy-zsh/omarchy-zsh.zsh" ] ||
        [ -f /usr/share/omarchy-zsh/omarchy-zsh.zsh ] ||
        [ -f /usr/share/omarchy-zsh/shell/omarchy-zsh.zsh ] ||
        [ -f /usr/share/omarchy-zsh/shell/all ]
      }
      ;;
    zsh-autopair) return 2 ;; # No Arch/AUR package; Omarchy owns the shell plugins.
    zsh-autosuggestions|zsh-history-substring-search)
      [ -f "/usr/share/zsh/plugins/$1/$1.zsh" ] || [ -f "/usr/share/zsh/$1/$1.zsh" ] ||
        { command -v pacman >/dev/null 2>&1 && pacman -Q "$1" >/dev/null 2>&1; }
      ;;
    nerd-font)
      command -v fc-list >/dev/null 2>&1 && fc-list 2>/dev/null |
        awk 'tolower($0) ~ /nerd[[:space:]]*font/ { found=1 } END { exit !found }'
      ;;
    *) command -v "$(app_command "$1")" >/dev/null 2>&1 ;;
  esac
}

installer_install() {
  command -v omarchy >/dev/null 2>&1 || { dot_error 'the omarchy command is required to install Omarchy applications'; return 1; }
  # Package helpers only: installing an app must not switch the default editor
  # or terminal, or copy Omarchy's configuration over the user's preferences.
  case "$1" in
    zsh-autopair) dot_error 'unsupported on Omarchy: zsh-autopair'; return 1 ;;
    zsh) omarchy pkg add omarchy-zsh ;;
    rg) omarchy pkg add ripgrep ;;
    nerd-font) omarchy pkg add ttf-fira-code-nerd ;;
    vscode) omarchy pkg aur add visual-studio-code-bin ;;
    rtk|git-open) omarchy pkg aur add "$1" ;;
    *) omarchy pkg add "$1" ;;
  esac
}
