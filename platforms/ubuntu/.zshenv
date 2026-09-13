# Also applies to non-interactive SSH commands (for example: ssh bebop herdr).
# Keep this silent and lightweight: no plugins, prompts, agents, or subprocesses.
typeset -U path
path=("$HOME/.local/bin" $path)
export PATH
