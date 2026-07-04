#!/bin/sh
# HISTFILE="$XDG_DATA_HOME"/zsh/history
HISTSIZE=1000000
SAVEHIST=1000000
export EDITOR="nano"
export TERMINAL="kitty"
export PATH="$HOME/.local/bin":$PATH
export PATH="$HOME/.docker/bin":$PATH
export PATH="$HOME/bin":$PATH
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1
#export PATH="$PATH:./node_modules/.bin"
eval "$(starship init zsh)"
eval "$(zoxide init zsh --cmd cd)"
# Set up fzf key bindings and fuzzy completion
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Forgit - git fzf
[ -f $HOMEBREW_PREFIX/share/forgit/forgit.plugin.zsh ] && source $HOMEBREW_PREFIX/share/forgit/forgit.plugin.zsh

export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

export AWS_PROFILE=admin
# bun completions
# [ -s "/home/rdmm123/.bun/_bun" ] && source "/home/rdmm123/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/$(whoami)/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/$(whoami)/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/$(whoami)/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/rdmm123/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

export XDG_CONFIG_HOME="$HOME/.config/"

export PATH="/usr/local/opt/mysql-client/bin:$PATH"

# opencode
export PATH=/Users/rdmm123/.opencode/bin:$PATH

# Added by Antigravity
export PATH="/Users/rdmm123/.antigravity/antigravity/bin:$PATH"

case "$(uname -s)" in

Darwin)
  export PNPM_HOME="/Users/$(whoami)/Library/pnpm"
	# echo 'Mac OS X'
  export DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib
  # fnm
  eval "$(fnm env --use-on-cd --shell zsh)"
	;;

Linux)
  export PNPM_HOME="$HOME/.pnpm"
  export PATH="$PATH:/snap/bin"
  export HOST_IP=$(ip route | awk '/default/ { print $3 }')
  if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
    # forwarding GUIs to windows for WSL
    # https://medium.com/@matthewkleinsmith/headful-playwright-with-wsl-4bf697a44ecf
    # https://aalonso.dev/blog/2021/how-to-use-gui-apps-in-wsl2-forwarding-x-server-cdj
    export DISPLAY="$HOST_IP:1.0"
    export LIBGL_ALWAYS_INDIRECT=true
    export LIBGL_ALWAYS_SOFTWARE=true
  fi
  # fnm
  FNM_PATH="/home/rdmm123/.local/share/fnm"
  if [ -d "$FNM_PATH" ]; then
    export PATH="/home/rdmm123/.local/share/fnm:$PATH"
    eval "`fnm env`"
  fi
	;;

CYGWIN* | MINGW32* | MSYS* | MINGW*)
	# echo 'MS Windows'
	;;
*)
	# echo 'Other OS'
	;;
esac

case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
