#!/usr/bin/env bash
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SHELL_PLATFORM="${DOT_SHELL_PLATFORM:-ubuntu}"
if ! command -v zsh >/dev/null 2>&1; then
  printf 'SKIP Ubuntu shell runtime tests: zsh is not installed\n'
  exit 0
fi
TMP=$(mktemp -d "${TMPDIR:-/tmp}/dot-ubuntu-shell.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/.config" "$TMP/bin" "$TMP/home/.local/share/fnm"
cp -R "$REPO/global/.config/zsh" "$TMP/home/.config/"
cp -RL "$REPO/platforms/$SHELL_PLATFORM/.config/zsh/." "$TMP/home/.config/zsh/"
cp "$REPO/global/.zshrc" "$REPO/platforms/$SHELL_PLATFORM/.zshenv" "$TMP/home/"
ZAP="$TMP/home/.local/share/zap"
mkdir -p "$ZAP/plugins"
printf 'typeset -a ZAP_INSTALLED_PLUGINS=()\n' > "$ZAP/zap.zsh"
for spec in zsh-autosuggestions/zsh-autosuggestions.zsh zsh-autopair/autopair.zsh \
  zsh-history-substring-search/zsh-history-substring-search.zsh zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
  mkdir -p "$ZAP/plugins/${spec%/*}"
  printf ':\n' > "$ZAP/plugins/$spec"
done
# Model foundation plugins locally to test wiring without downloading code.
mkdir -p "$ZAP/plugins/supercharge" "$ZAP/plugins/exa"
cat > "$ZAP/plugins/supercharge/supercharge.plugin.zsh" <<'EOF'
autoload -Uz compinit
compinit
zmodload zsh/complist
zstyle ':completion:*' menu yes select
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}'
setopt menu_complete
EOF
cat > "$ZAP/plugins/exa/eza.plugin.zsh" <<'EOF'
alias ls='eza --group-directories-first --icons=auto'
alias ll='ls -lh' la='ll -a' tree='ll --tree --level=2'
EOF
# Define the same widget names as the real plugins, without downloading them.
cat > "$ZAP/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" <<'EOF'
autosuggest-accept() { :; }
zle -N autosuggest-accept
EOF
cat > "$ZAP/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh" <<'EOF'
history-substring-search-up() { :; }
history-substring-search-down() { :; }
zle -N history-substring-search-up
zle -N history-substring-search-down
EOF
for tool in git curl ssh-agent ssh-add; do
  printf '#!/bin/sh\necho unexpected-%s >> "$HOME/unexpected"\nexit 1\n' "$tool" > "$TMP/bin/$tool"
done
for tool in fdfind batcat eza; do
  printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/$tool"
done
cat > "$TMP/bin/fzf" <<'EOF'
#!/bin/sh
[ "$*" = --zsh ] || exit 1
printf 'export DOT_TEST_FZF_READY=1\n'
EOF
cat > "$TMP/bin/starship" <<'EOF'
#!/bin/sh
[ "$*" = 'init zsh' ] || exit 1
printf 'export DOT_TEST_STARSHIP_READY=1\n'
EOF
cat > "$TMP/bin/zoxide" <<'EOF'
#!/bin/sh
[ "$*" = 'init zsh --cmd cd' ] || exit 1
printf 'export DOT_TEST_ZOXIDE_READY=1\n'
EOF
cat > "$TMP/home/.local/share/fnm/fnm" <<'EOF'
#!/bin/sh
[ "$*" = 'env --use-on-cd --shell zsh' ] || exit 1
printf 'export DOT_TEST_FNM_READY=1\n'
EOF
chmod +x "$TMP/bin/"* "$TMP/home/.local/share/fnm/fnm"
HOME="$TMP/home" ZDOTDIR="$TMP/home" XDG_DATA_HOME="$TMP/home/.local/share" \
  SSH_AUTH_SOCK=/tmp/dot-forwarded-agent SSH_CONNECTION='test connection' \
  PATH="$TMP/bin:/usr/bin:/bin" zsh -d -i -c '
    [[ "$DOT_TEST_FNM_READY:$DOT_TEST_STARSHIP_READY:$DOT_TEST_ZOXIDE_READY:$DOT_TEST_FZF_READY" == 1:1:1:1 ]] || exit 1
    [[ "$SSH_AUTH_SOCK" == /tmp/dot-forwarded-agent ]] || exit 1
    [[ "$aliases[fd]" == fdfind && "$aliases[bat]" == batcat ]] || exit 1
    [[ "$aliases[cat]" == bat* ]] || exit 1
    [[ -n "$widgets[history-substring-search-up]" ]] || exit 1
    [[ "$aliases[ls]" == *--group-directories-first* && "$aliases[tree]" == *--tree* ]] || exit 1
    [[ -o menu_complete ]] || exit 1
    zstyle -a ":completion:*" menu menu_style
    [[ "$menu_style" == "yes select" ]] || exit 1
    [[ " $ZAP_INSTALLED_PLUGINS " == *" supercharge "* && " $ZAP_INSTALLED_PLUGINS " == *" exa "* ]] || exit 1

    # ACL helper is loaded, but tests never run sudo or change real ACLs.
    (( $+functions[acl_fix] )) || exit 1
    typeset -a acl_calls=()
    acl_test_fail=0
    sudo() {
      acl_calls+=("${(j:|:)@}")
      [[ "$acl_test_fail" == 0 ]]
    }
    if acl_fix > /dev/null 2>&1; then exit 1; fi
    if acl_fix "$HOME/missing" > /dev/null 2>&1; then exit 1; fi
    (( ${#acl_calls} == 0 )) || exit 1
    mkdir -p "$HOME/acl test" "$HOME/second"
    acl_user=$(id -un)
    acl_fix "$HOME/acl test" "$HOME/second" > "$HOME/acl-result" || exit 1
    (( ${#acl_calls} == 4 )) || exit 1
    [[ "$acl_calls[1]" == "setfacl|-R|-m|u:${acl_user}:rwX,m::rwX|--|$HOME/acl test" ]] || exit 1
    [[ "$acl_calls[2]" == "setfacl|-R|-d|-m|u:${acl_user}:rwX,m::rwX|--|$HOME/acl test" ]] || exit 1
    [[ "$acl_calls[3]" == "setfacl|-R|-m|u:${acl_user}:rwX,m::rwX|--|$HOME/second" ]] || exit 1
    [[ "$acl_calls[4]" == "setfacl|-R|-d|-m|u:${acl_user}:rwX,m::rwX|--|$HOME/second" ]] || exit 1
    # Ask the real Linux parser to validate both forms without changing ACLs.
    if command -v setfacl >/dev/null 2>&1; then
      command setfacl --test -m "u:${acl_user}:rwX,m::rwX" -- "$HOME/acl test" > /dev/null || exit 1
      command setfacl --test -d -m "u:${acl_user}:rwX,m::rwX" -- "$HOME/acl test" > /dev/null || exit 1
    fi
    acl_calls=()
    acl_test_fail=1
    if acl_fix "$HOME/acl test" > "$HOME/acl-result"; then exit 1; fi
    (( ${#acl_calls} == 1 )) || exit 1
    [[ "$(< "$HOME/acl-result")" != *"Done:"* ]] || exit 1
  ' > "$TMP/output" 2> "$TMP/error"
[ ! -s "$TMP/error" ] || { cat "$TMP/error" >&2; exit 1; }
[ ! -e "$TMP/home/unexpected" ]
# Debian also exposes existing Node/Codex to noninteractive SSH without fnm init.
if [ "$SHELL_PLATFORM" = debian ]; then
  mkdir -p "$TMP/home/.local/share/fnm/aliases/default/bin"
  for tool in node codex pi; do
    printf '#!/bin/sh\nexit 0\n' > "$TMP/home/.local/share/fnm/aliases/default/bin/$tool"
    chmod +x "$TMP/home/.local/share/fnm/aliases/default/bin/$tool"
  done
fi
# Noninteractive SSH commands need user binaries but must not initialize plugins.
HOME="$TMP/home" ZDOTDIR="$TMP/home" PATH=/usr/bin:/bin zsh -d -c '
  [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || exit 1
  [[ -z "$DOT_TEST_FNM_READY" ]] || exit 1
  if [[ -d "$HOME/.local/share/fnm/aliases/default/bin" ]]; then
    [[ ":$PATH:" == *":$HOME/.local/share/fnm/aliases/default/bin:"* ]] || exit 1
    [[ "$(command -v codex)" == "$HOME/.local/share/fnm/aliases/default/bin/codex" ]] || exit 1
  fi
' > "$TMP/noninteractive"
[ ! -s "$TMP/noninteractive" ]
printf '%s shell tests passed\n' "$SHELL_PLATFORM"
