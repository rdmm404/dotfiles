# Silent PATH setup for noninteractive SSH; no plugins, agents or subprocesses.
typeset -U path
path=("$HOME/.local/bin" $path)
# Preserve the existing default Node installation for remote Codex/Pi commands.
if [ -d "$HOME/.local/share/fnm/aliases/default/bin" ]; then
  path=("$HOME/.local/share/fnm/aliases/default/bin" $path)
fi
export PATH
