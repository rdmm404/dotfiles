DOT_ZSH_FOUNDATION=zap

if [ -r "$HOME/.local/share/zap/zap.zsh" ]; then
  source "$HOME/.local/share/zap/zap.zsh"
  if command -v plug >/dev/null 2>&1; then
    plug 'zsh-users/zsh-autosuggestions'
    plug 'hlissner/zsh-autopair'
    plug 'zap-zsh/supercharge'
    plug 'zap-zsh/fzf'
    plug 'zap-zsh/exa'
    plug 'zsh-users/zsh-history-substring-search'
    plug 'paulirish/git-open'
  fi
fi
