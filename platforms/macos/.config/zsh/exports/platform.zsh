export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1
export PNPM_HOME="$HOME/Library/pnpm"
export DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib
export PATH="$PNPM_HOME:$PATH"
export PATH="/usr/local/opt/mysql-client/bin:$PATH"
export PATH="$HOME/.opencode/bin:$PATH"
export PATH="$HOME/.antigravity/antigravity/bin:$PATH"

if [ -f "$HOME/Downloads/google-cloud-sdk/path.zsh.inc" ]; then
  source "$HOME/Downloads/google-cloud-sdk/path.zsh.inc"
fi
if [ -f "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc" ]; then
  source "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc"
fi

if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi
