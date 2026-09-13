# Preserve the existing fnm installation without pinning a Node version's path.
# .zshrc loads this for interactive SSH sessions as well as local terminals.
export FNM_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/fnm"
if [ -d "$FNM_PATH" ]; then
  path=("$FNM_PATH" $path)
fi
if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi
