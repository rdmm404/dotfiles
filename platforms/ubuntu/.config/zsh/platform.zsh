# Standalone shell foundation; no Omarchy, desktop session, or login-shell changes.
DOT_ZSH_FOUNDATION=zap
# SSH sessions inherit their agent (including forwarding); do not launch another
# agent, overwrite SSH_AUTH_SOCK, or prompt to unlock keys during shell startup.
DOT_ZSH_SSH_AGENT=external

bindkey -e
ZAP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zap"
DOT_ZSH_SYNTAX_FILE="$ZAP_DIR/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
if [ -r "$ZAP_DIR/zap.zsh" ]; then
  source "$ZAP_DIR/zap.zsh"
else
  print -u2 'Zap was not found; run dot install before using this Zsh configuration'
fi

# Source installed plugins only: shell startup must not download missing code.
for ubuntu_plugin in \
  zsh-autosuggestions/zsh-autosuggestions.zsh \
  zsh-autopair/autopair.zsh \
  supercharge/supercharge.plugin.zsh \
  exa/eza.plugin.zsh \
  zsh-history-substring-search/zsh-history-substring-search.zsh; do
  if [ -r "$ZAP_DIR/plugins/$ubuntu_plugin" ]; then
    source "$ZAP_DIR/plugins/$ubuntu_plugin"
    ZAP_INSTALLED_PLUGINS+=("${ubuntu_plugin%%/*}")
  fi
done
unset ubuntu_plugin

# git-open is an executable, not a shell startup plugin.
if [ -x "$ZAP_DIR/plugins/git-open/git-open" ]; then
  path=("$ZAP_DIR/plugins/git-open" $path)
  ZAP_INSTALLED_PLUGINS+=(git-open)
fi
if [ -r "$DOT_ZSH_SYNTAX_FILE" ]; then
  ZAP_INSTALLED_PLUGINS+=(zsh-syntax-highlighting)
fi

command -v fzf >/dev/null 2>&1 && eval "$(fzf --zsh)"
