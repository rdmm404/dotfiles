export PNPM_HOME="$HOME/.pnpm"
export PATH="$PNPM_HOME:$PATH"
export PATH="/snap/bin:$PATH"

if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
  HOST_IP=$(ip route 2>/dev/null | awk '/default/ { print $3; exit}')
  if [ -n "$HOST_IP" ]; then
    export HOST_IP
    export DISPLAY="$HOST_IP:1.0"
  fi
  export LIBGL_ALWAYS_INDIRECT=true
  export LIBGL_ALWAYS_SOFTWARE=true
fi

if [ -d "$HOME/.local/share/fnm" ]; then
  export PATH="$HOME/.local/share/fnm:$PATH"
fi
if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --shell zsh)"
fi
