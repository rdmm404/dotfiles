DOT_ZSH_FOUNDATION=zap

ZAP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zap"
if [ -r "$ZAP_DIR/zap.zsh" ]; then
  source "$ZAP_DIR/zap.zsh"
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
