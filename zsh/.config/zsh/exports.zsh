#!/bin/sh
# HISTFILE="$XDG_DATA_HOME"/zsh/history
HISTSIZE=1000000
SAVEHIST=1000000
export EDITOR="nano"
export TERMINAL="kitty"
export PATH="$HOME/.local/bin":$PATH
export PATH="$HOME/.docker/bin":$PATH
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1
#export PATH="$PATH:./node_modules/.bin"
eval "$(starship init zsh)"
eval "$(zoxide init zsh --cmd cd)"
# Set up fzf key bindings and fuzzy completion
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# nvm
export NVM_DIR="$HOME/.nvm"
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
# [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Forgit - git fzf
[ -f $HOMEBREW_PREFIX/share/forgit/forgit.plugin.zsh ] && source $HOMEBREW_PREFIX/share/forgit/forgit.plugin.zsh

# . "$HOME/.cargo/env"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

export AWS_PROFILE=admin
# bun completions
# [ -s "/home/rdmm123/.bun/_bun" ] && source "/home/rdmm123/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

case "$(uname -s)" in

Darwin)
	# echo 'Mac OS X'
  export DYLD_LIBRARY_PATH=/opt/homebrew/lib/
  export DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib
	;;

Linux)
  export PATH="$PATH:/snap/bin"
  if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
    # forwarding GUIs to windows for WSL
    # https://medium.com/@matthewkleinsmith/headful-playwright-with-wsl-4bf697a44ecf
    # https://aalonso.dev/blog/2021/how-to-use-gui-apps-in-wsl2-forwarding-x-server-cdj
    export DISPLAY=$(ip route | awk '/default/ { print $3 }'):1.0
    export LIBGL_ALWAYS_INDIRECT=true
    export LIBGL_ALWAYS_SOFTWARE=true
  fi

	;;

CYGWIN* | MINGW32* | MSYS* | MINGW*)
	# echo 'MS Windows'
	;;
*)
	# echo 'Other OS'
	;;
esac
