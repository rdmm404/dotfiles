#!/usr/bin/env bash

# Parse each selected manifest once. Arrays and local variables work in Bash 3.2.
manifest_read() {
  local file="$1" line seen='|'
  MANIFEST_ENTRIES=()
  [ -r "$file" ] || { dot_error "manifest is missing or unreadable: $file"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    case "$line" in ''|\#*) continue ;; esac
    case "$line" in
      *[!A-Za-z0-9._+-]*) dot_error "invalid application name '$line' in $file"; return 1 ;;
    esac
    case "$seen" in
      *"|$line|"*) dot_error "duplicate application '$line' in $file"; return 1 ;;
    esac
    seen="$seen$line|"
    MANIFEST_ENTRIES[${#MANIFEST_ENTRIES[@]}]="$line"
  done < "$file"
}

manifest_load() {
  local group entry file catalog='|' seen='|'
  local groups=(core development)
  [ "${1:-0}" = 1 ] && groups[2]=optional
  APPS=()
  OPTIONAL_APPS=()
  manifest_read "$DOT_ROOT/manifests/catalog" || return 1
  for entry in "${MANIFEST_ENTRIES[@]}"; do catalog="$catalog$entry|"; done
  for group in "${groups[@]}"; do
    file="$DOT_ROOT/manifests/$group"
    # Each platform may replace a selection group, not the canonical catalog.
    if [ -n "${PLATFORM:-}" ] && [ -e "$DOT_ROOT/manifests/$PLATFORM/$group" ]; then
      file="$DOT_ROOT/manifests/$PLATFORM/$group"
    fi
    manifest_read "$file" || return 1
    for entry in "${MANIFEST_ENTRIES[@]}"; do
      case "$catalog" in
        *"|$entry|"*) ;;
        *) dot_error "unknown application '$entry' in $file"; return 1 ;;
      esac
      case "$seen" in
        *"|$entry|"*) dot_error "duplicate application '$entry' across manifests"; return 1 ;;
      esac
      seen="$seen$entry|"
      if [ "$group" = optional ]; then
        OPTIONAL_APPS[${#OPTIONAL_APPS[@]}]="$entry"
      else
        APPS[${#APPS[@]}]="$entry"
      fi
    done
  done
}
