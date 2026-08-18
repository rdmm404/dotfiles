DOT_ZSH_FOUNDATION=omarchy
DOT_ZSH_OMARCHY_LOADED=0

for omarchy_zsh_file in \
  /usr/share/omarchy-zsh/omarchy-zsh.zsh \
  /usr/share/omarchy-zsh/shell/omarchy-zsh.zsh \
  "$HOME/.local/share/omarchy-zsh/omarchy-zsh.zsh"; do
  if [ -r "$omarchy_zsh_file" ]; then
    source "$omarchy_zsh_file"
    DOT_ZSH_OMARCHY_LOADED=1
    break
  fi
done

if [ "$DOT_ZSH_OMARCHY_LOADED" = 0 ]; then
  print -u2 'omarchy-zsh foundation was not found; install omarchy-zsh before starting Zsh'
fi

omarchy_source_plugin() {
  case "$1" in
    zsh-autosuggestions)
      omarchy_plugin_files=(
        /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
        /usr/share/zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
      )
      ;;
    zsh-autopair)
      omarchy_plugin_files=(
        /usr/share/zsh/plugins/zsh-autopair/autopair.zsh
        /usr/share/zsh/zsh-autopair/autopair.zsh
      )
      ;;
    zsh-history-substring-search)
      omarchy_plugin_files=(
        /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
        /usr/share/zsh/zsh-history-substring-search/zsh-history-substring-search.zsh
      )
      ;;
    *) return 1 ;;
  esac
  for omarchy_plugin_file in $omarchy_plugin_files; do
    if [ -r "$omarchy_plugin_file" ]; then
      source "$omarchy_plugin_file"
      return 0
    fi
  done
  return 1
}

omarchy_source_plugin zsh-autosuggestions
omarchy_source_plugin zsh-autopair
omarchy_source_plugin zsh-history-substring-search
unfunction omarchy_source_plugin
