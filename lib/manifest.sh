#!/usr/bin/env bash

# On success, MANIFEST_ENTRIES contains one entry per line and
# MANIFEST_COUNT contains the number of entries.
manifest_read() {
  manifest_file="$1"
  MANIFEST_ENTRIES=''
  MANIFEST_COUNT=0
  manifest_seen='|'

  if [ ! -r "$manifest_file" ]; then
    dot_error "manifest is missing or unreadable: $manifest_file"
    return 1
  fi

  while IFS= read -r manifest_line || [ -n "$manifest_line" ]; do
    # Trim leading and trailing whitespace without relying on newer Bash.
    manifest_line=${manifest_line#"${manifest_line%%[![:space:]]*}"}
    manifest_line=${manifest_line%"${manifest_line##*[![:space:]]}"}
    [ -z "$manifest_line" ] && continue
    case "$manifest_line" in
      \#*) continue ;;
    esac

    case "$manifest_line" in
      *[!A-Za-z0-9._+-]*)
        dot_error "invalid application name '$manifest_line' in $manifest_file"
        return 1
        ;;
    esac
    case "$manifest_seen" in
      *"|$manifest_line|"*)
        dot_error "duplicate application '$manifest_line' in $manifest_file"
        return 1
        ;;
    esac
    manifest_seen="${manifest_seen}${manifest_line}|"
    MANIFEST_ENTRIES="${MANIFEST_ENTRIES}${manifest_line}
"
    MANIFEST_COUNT=$((MANIFEST_COUNT + 1))
  done < "$manifest_file"
  return 0
}

manifest_validate_all() {
  manifest_all_seen='|'
  manifest_all_file=''
  manifest_all_entry=''
  manifest_read "$DOT_ROOT/manifests/catalog" || return 1
  for manifest_all_file in "$DOT_ROOT/manifests/core" "$DOT_ROOT/manifests/development" "$DOT_ROOT/manifests/optional"; do
    manifest_read "$manifest_all_file" || return 1
    while IFS= read -r manifest_all_entry || [ -n "$manifest_all_entry" ]; do
      [ -z "$manifest_all_entry" ] && continue
      if ! app_known "$manifest_all_entry"; then
        dot_error "unknown application '$manifest_all_entry' in $manifest_all_file"
        return 1
      fi
      case "$manifest_all_seen" in
        *"|$manifest_all_entry|"*)
          dot_error "duplicate application '$manifest_all_entry' across manifests"
          return 1
          ;;
      esac
      manifest_all_seen="${manifest_all_seen}${manifest_all_entry}|"
    done <<EOF
$MANIFEST_ENTRIES
EOF
  done
  return 0
}

manifest_select() {
  include_optional="${1:-0}"
  SELECTED_MANIFESTS="$DOT_ROOT/manifests/core
$DOT_ROOT/manifests/development"
  if [ "$include_optional" = 1 ]; then
    SELECTED_MANIFESTS="$SELECTED_MANIFESTS
$DOT_ROOT/manifests/optional"
  fi
}

manifest_load_selected() {
  manifest_select "${1:-0}"
  SELECTED_ENTRIES=''
  selected_seen='|'
  selected_file=''
  while IFS= read -r selected_file || [ -n "$selected_file" ]; do
    [ -z "$selected_file" ] && continue
    manifest_read "$selected_file" || return 1
    selected_entry=''
    while IFS= read -r selected_entry || [ -n "$selected_entry" ]; do
      [ -z "$selected_entry" ] && continue
      case "$selected_seen" in
        *"|$selected_entry|"*)
          dot_error "application '$selected_entry' appears in more than one selected manifest"
          return 1
          ;;
      esac
      selected_seen="${selected_seen}${selected_entry}|"
      SELECTED_ENTRIES="${SELECTED_ENTRIES}${selected_entry}
"
    done <<EOF
$MANIFEST_ENTRIES
EOF
  done <<EOF
$SELECTED_MANIFESTS
EOF
  return 0
}
