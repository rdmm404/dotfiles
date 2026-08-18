#!/usr/bin/env zsh

# The platform layer supplies the shell foundation before shared settings load.
DOT_ZSH_FOUNDATION=none
if [ -r "$HOME/.config/zsh/platform.zsh" ]; then
  source "$HOME/.config/zsh/platform.zsh"
fi

HISTFILE="$HOME/.zsh_history"
HISTSIZE=1000000
SAVEHIST=1000000

for f in "$HOME"/.config/zsh/exports/*.zsh(N); do
  source "$f"
done

for f in "$HOME"/.config/zsh/aliases/*.zsh(N); do
  source "$f"
done

for f in "$HOME"/.config/zsh/functions/*.zsh(N); do
  source "$f"
done

# Zap remains the SSH-agent/plugin foundation on macOS and WSL only.
if [ "$DOT_ZSH_FOUNDATION" = zap ] && command -v plug >/dev/null 2>&1; then
  plug "$HOME/.config/zsh/plugins/ssh-agent.zsh"
fi

if [ "$DOT_ZSH_FOUNDATION" = zap ]; then
  command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"
  command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh --cmd cd)"
fi

if command -v bat >/dev/null 2>&1; then
  alias cat="bat -pp --theme \"Visual Studio Dark+\""
  alias catt="bat --theme \"Visual Studio Dark+\""
fi

bindkey '^ ' autosuggest-accept
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey '\eOA' history-substring-search-up
bindkey '\eOB' history-substring-search-down
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down
bindkey ';5D' backward-word
bindkey ';5C' forward-word

WORDCHARS=${WORDCHARS//[\/_.-=]/}

if [ "$DOT_ZSH_FOUNDATION" = zap ] && command -v plug >/dev/null 2>&1; then
  plug 'zsh-users/zsh-syntax-highlighting'
fi
