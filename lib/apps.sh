#!/usr/bin/env bash

# The catalog is the single source of truth for logical application IDs.
app_known() {
  app_catalog_file="$DOT_ROOT/manifests/catalog"
  [ -r "$app_catalog_file" ] || return 1
  app_catalog_entry=''
  while IFS= read -r app_catalog_entry || [ -n "$app_catalog_entry" ]; do
    app_catalog_entry=${app_catalog_entry#"${app_catalog_entry%%[![:space:]]*}"}
    app_catalog_entry=${app_catalog_entry%"${app_catalog_entry##*[![:space:]]}"}
    [ -z "$app_catalog_entry" ] && continue
    case "$app_catalog_entry" in \#*) continue ;; esac
    [ "$app_catalog_entry" = "$1" ] && return 0
  done < "$app_catalog_file"
  return 1
}

app_command() {
  case "$1" in
    vscode) printf 'code' ;;
    nerd-font) printf '' ;;
    *) printf '%s' "$1" ;;
  esac
}
