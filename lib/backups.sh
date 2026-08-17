#!/usr/bin/env bash

backup_root() {
  printf '%s/.local/state/dot/backups' "$HOME"
}

backup_validate_root() {
  backup_home_real="$(CDPATH= cd -P -- "$HOME" 2>/dev/null && pwd -P)" || return 1
  backup_root_path="$(backup_root)"
  backup_probe="$backup_root_path"
  while [ "$backup_probe" != "$HOME" ] && [ "$backup_probe" != / ]; do
    [ ! -L "$backup_probe" ] || {
      dot_error 'backup directory contains a symlinked ancestor'
      return 1
    }
    backup_probe="$(dirname "$backup_probe")"
  done
  if [ -d "$backup_root_path" ]; then
    backup_root_real="$(CDPATH= cd -P -- "$backup_root_path" 2>/dev/null && pwd -P)" || return 1
    case "$backup_root_real" in
      "$backup_home_real"/*) ;;
      *) dot_error 'backup directory is outside HOME'; return 1 ;;
    esac
  fi
}

backup_preview_directory() {
  backup_validate_root || return 1
  backup_parent="$(backup_root)"
  backup_stamp="$(date +%Y%m%d-%H%M%S)" || return 1
  backup_candidate="$backup_parent/$backup_stamp"
  backup_suffix=0
  while [ -e "$backup_candidate" ]; do
    backup_suffix=$((backup_suffix + 1))
    backup_candidate="$backup_parent/$backup_stamp.$backup_suffix"
  done
  printf '%s' "$backup_candidate"
}

backup_create_directory() {
  backup_validate_root || return 1
  backup_parent="$(backup_root)"
  mkdir -p "$backup_parent" || return 1
  if [ -n "${DEPLOY_BACKUP_PREVIEW:-}" ]; then
    backup_candidate="$DEPLOY_BACKUP_PREVIEW"
  else
    backup_candidate="$(backup_preview_directory)" || return 1
  fi
  mkdir "$backup_candidate" 2>/dev/null || return 1
  DEPLOY_BACKUP_PATH="$backup_candidate"
}

backup_validate_id() {
  case "$1" in
    ''|.|..|*[!A-Za-z0-9._-]*)
      dot_error "invalid backup timestamp: $1"
      return 1
      ;;
  esac
}

backup_directory_for_id() {
  backup_validate_root || return 1
  backup_validate_id "$1" || return 1
  BACKUP_SELECTED="$(backup_root)/$1"
  [ -d "$BACKUP_SELECTED" ] && [ ! -L "$BACKUP_SELECTED" ] || {
    dot_error "backup does not exist as a regular directory: $1"
    return 1
  }
  backup_parent_real="$(CDPATH= cd -P -- "$(backup_root)" 2>/dev/null && pwd -P)" || return 1
  backup_selected_real="$(CDPATH= cd -P -- "$BACKUP_SELECTED" 2>/dev/null && pwd -P)" || return 1
  case "$backup_selected_real" in
    "$backup_parent_real"/*) ;;
    *)
      dot_error "backup is not contained by the backup directory: $1"
      return 1
      ;;
  esac
}

backup_validate_candidate_directory() {
  backup_candidate="$1"
  [ -d "$backup_candidate" ] && [ ! -L "$backup_candidate" ] || return 1
  backup_candidate_real="$(CDPATH= cd -P -- "$backup_candidate" 2>/dev/null && pwd -P)" || return 1
  backup_root_real="$(CDPATH= cd -P -- "$(backup_root)" 2>/dev/null && pwd -P)" || return 1
  case "$backup_candidate_real" in
    "$backup_root_real"/*) return 0 ;;
  esac
  return 1
}

backup_validate_source_path() {
  backup_source_path="$BACKUP_SELECTED/$1"
  backup_source_parent="$(dirname "$backup_source_path")"
  while [ "$backup_source_parent" != "$BACKUP_SELECTED" ] && [ "$backup_source_parent" != / ]; do
    if [ -L "$backup_source_parent" ]; then
      dot_error "backup metadata crosses a symlink: $1"
      return 1
    fi
    backup_source_parent="$(dirname "$backup_source_parent")"
  done
}

backup_validate_root_set() {
  backup_root_a=''
  backup_root_b=''
  backup_root_seen=''
  while IFS= read -r backup_root_a || [ -n "$backup_root_a" ]; do
    [ -n "$backup_root_a" ] || continue
    backup_root_seen_item=''
    while IFS= read -r backup_root_seen_item || [ -n "$backup_root_seen_item" ]; do
      [ "$backup_root_a" = "$backup_root_seen_item" ] || continue
      dot_error "duplicate path in backup metadata: $backup_root_a"
      return 1
    done <<EOF
$backup_root_seen
EOF
    backup_root_seen="${backup_root_seen}${backup_root_a}
"
  done <<EOF
$BACKUP_ROOTS
EOF
  while IFS= read -r backup_root_a || [ -n "$backup_root_a" ]; do
    [ -n "$backup_root_a" ] || continue
    while IFS= read -r backup_root_b || [ -n "$backup_root_b" ]; do
      [ -n "$backup_root_b" ] || continue
      [ "$backup_root_a" = "$backup_root_b" ] && continue
      case "$backup_root_b" in
        "$backup_root_a"/*)
          dot_error "overlapping paths in backup metadata: $backup_root_a and $backup_root_b"
          return 1
          ;;
      esac
    done <<EOF
$BACKUP_ROOTS
EOF
  done <<EOF
$BACKUP_ROOTS
EOF
}

backup_walk() {
  local backup_walk_root backup_walk_relative
  local backup_walk_child backup_walk_name backup_walk_next
  backup_walk_root="$1"
  backup_walk_relative="$2"
  backup_walk_child=''
  for backup_walk_child in \
    "$backup_walk_root"/.[!.]* \
    "$backup_walk_root"/..?* \
    "$backup_walk_root"/*; do
    [ -e "$backup_walk_child" ] || [ -L "$backup_walk_child" ] || continue
    backup_walk_name="${backup_walk_child##*/}"
    case "$backup_walk_name" in .|..|.dot-backup-roots) continue ;; esac
    if [ -d "$backup_walk_child" ] && [ ! -L "$backup_walk_child" ]; then
      if [ -n "$backup_walk_relative" ]; then
        backup_walk_next="$backup_walk_relative/$backup_walk_name"
      else
        backup_walk_next="$backup_walk_name"
      fi
      backup_walk "$backup_walk_child" "$backup_walk_next" || return 1
    else
      if [ -n "$backup_walk_relative" ]; then
        BACKUP_FILES="${BACKUP_FILES}${backup_walk_relative}/$backup_walk_name
"
      else
        BACKUP_FILES="${BACKUP_FILES}$backup_walk_name
"
      fi
    fi
  done
}

backup_file_count() {
  BACKUP_FILES=''
  backup_walk "$1" '' || return 1
  backup_count=0
  backup_file=''
  while IFS= read -r backup_file || [ -n "$backup_file" ]; do
    [ -n "$backup_file" ] && backup_count=$((backup_count + 1))
  done <<EOF
$BACKUP_FILES
EOF
  printf '%s' "$backup_count"
}

backup_size() {
  if du -sk "$1" >/dev/null 2>&1; then
    du -sk "$1" | awk '{print $1 " KB"}'
  else
    printf 'unknown'
  fi
}

backups_list_command() {
  backup_validate_root || return 1
  backup_parent="$(backup_root)"
  if [ ! -d "$backup_parent" ]; then
    dot_ok 'no backups'
    return 0
  fi
  backup_found=0
  backup_dir=''
  for backup_dir in "$backup_parent"/*; do
    [ -d "$backup_dir" ] || continue
    backup_validate_candidate_directory "$backup_dir" || {
      dot_error "unsafe backup directory: $backup_dir"
      return 1
    }
    backup_found=1
    backup_id="${backup_dir##*/}"
    backup_count="$(backup_file_count "$backup_dir")" || return 1
    printf '%s: %s, %s file(s)\n' "$backup_id" "$(backup_size "$backup_dir")" "$backup_count"
  done
  [ "$backup_found" = 1 ] || dot_ok 'no backups'
}

backups_restore_directory_is_deploy_owned() {
  restore_directory="$1"
  restore_seen=0
  restore_child=''
  for restore_child in \
    "$restore_directory"/.[!.]* \
    "$restore_directory"/..?* \
    "$restore_directory"/*; do
    [ -e "$restore_child" ] || [ -L "$restore_child" ] || continue
    restore_seen=1
    if [ -d "$restore_child" ] && [ ! -L "$restore_child" ]; then
      backups_restore_directory_is_deploy_owned "$restore_child" || return 1
    elif [ -L "$restore_child" ]; then
      deploy_link_is_repo_owned "$restore_child" || return 1
    else
      return 1
    fi
  done
  [ "$restore_seen" = 1 ]
}

backups_restore_parent_conflict() {
  restore_parent="$(dirname "$1")"
  while [ "$restore_parent" != "$HOME" ] && [ "$restore_parent" != / ]; do
    if [ -L "$restore_parent" ]; then
      return 0
    elif [ -e "$restore_parent" ] && [ ! -d "$restore_parent" ]; then
      return 0
    fi
    restore_parent="$(dirname "$restore_parent")"
  done
  return 1
}

backups_restore_target_allowed() {
  restore_relative="$1"
  restore_target="$HOME/$restore_relative"
  backups_restore_parent_conflict "$restore_target" && return 1
  if [ -e "$restore_target" ] || [ -L "$restore_target" ]; then
    if [ -L "$restore_target" ] && deploy_link_is_repo_owned "$restore_target"; then
      return 0
    elif [ -d "$restore_target" ] && [ ! -L "$restore_target" ] && backups_restore_directory_is_deploy_owned "$restore_target"; then
      return 0
    fi
    return 1
  fi
  return 0
}

backup_validate_relative_path() {
  case "$1" in
    ''|/*|.|./*|*/./*|*/.|../*|*/../*|*/..|*//*|*/)
      dot_error "invalid path in backup metadata: $1"
      return 1
      ;;
  esac
}

backups_restore_rollback() {
  restore_rollback_error=0
  restore_file=''
  while IFS= read -r restore_file || [ -n "$restore_file" ]; do
    [ -z "$restore_file" ] || rm -rf "$HOME/$restore_file" || restore_rollback_error=1
  done <<EOF
$BACKUP_ROOTS
EOF
  if [ -r "$BACKUP_RESTORE_SNAPSHOT/list" ]; then
    while IFS='|' read -r restore_relative restore_target || [ -n "$restore_relative" ]; do
      [ -n "$restore_relative" ] || continue
      if ! mkdir -p "$(dirname "$restore_target")" || \
        ! cp -a "$BACKUP_RESTORE_SNAPSHOT/$restore_relative" "$restore_target"; then
        restore_rollback_error=1
      fi
    done < "$BACKUP_RESTORE_SNAPSHOT/list"
  fi
  if [ "$restore_rollback_error" = 1 ]; then
    dot_error "backup restore rollback failed; inspect HOME before retrying"
    return 1
  fi
  return 0
}

backups_restore_command() {
  backup_id="$1"
  shift
  DOT_YES=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --yes) DOT_YES=1; shift ;;
      --help|-h) dot_command_usage 'backups restore'; return 0 ;;
      *) dot_bad_args "invalid argument: $1" 'backups restore'; return $? ;;
    esac
  done
  backup_directory_for_id "$backup_id" || return 1
  BACKUP_FILES=''
  backup_walk "$BACKUP_SELECTED" '' || return 1
  BACKUP_ROOTS=''
  if [ -e "$BACKUP_SELECTED/.dot-backup-roots" ] || [ -L "$BACKUP_SELECTED/.dot-backup-roots" ]; then
    [ -f "$BACKUP_SELECTED/.dot-backup-roots" ] && [ ! -L "$BACKUP_SELECTED/.dot-backup-roots" ] || {
      dot_error 'backup metadata is not a regular file'
      return 1
    }
  fi
  if [ -f "$BACKUP_SELECTED/.dot-backup-roots" ] && [ ! -L "$BACKUP_SELECTED/.dot-backup-roots" ]; then
    backup_metadata_root=''
    while IFS= read -r backup_metadata_root || [ -n "$backup_metadata_root" ]; do
      [ -n "$backup_metadata_root" ] || continue
      backup_validate_relative_path "$backup_metadata_root" || return 1
      backup_validate_source_path "$backup_metadata_root" || return 1
      [ -e "$BACKUP_SELECTED/$backup_metadata_root" ] || [ -L "$BACKUP_SELECTED/$backup_metadata_root" ] || {
        dot_error "backup metadata refers to a missing path: $backup_metadata_root"
        return 1
      }
      BACKUP_ROOTS="${BACKUP_ROOTS}${backup_metadata_root}
"
    done < "$BACKUP_SELECTED/.dot-backup-roots"
  else
    BACKUP_ROOTS="$BACKUP_FILES"
  fi
  [ -n "$BACKUP_ROOTS" ] || { dot_ok 'backup is empty'; return 0; }
  if [ ! -f "$BACKUP_SELECTED/.dot-backup-roots" ] || [ -L "$BACKUP_SELECTED/.dot-backup-roots" ]; then
    backup_fallback_root=''
    while IFS= read -r backup_fallback_root || [ -n "$backup_fallback_root" ]; do
      [ -n "$backup_fallback_root" ] || continue
      backup_validate_relative_path "$backup_fallback_root" || return 1
      backup_validate_source_path "$backup_fallback_root" || return 1
    done <<EOF
$BACKUP_ROOTS
EOF
  fi
  backup_validate_root_set || return 1

  backup_conflicts=''
  backup_file=''
  while IFS= read -r backup_file || [ -n "$backup_file" ]; do
    [ -z "$backup_file" ] && continue
    backup_target="$HOME/$backup_file"
    if ! backups_restore_target_allowed "$backup_file"; then
      backup_conflicts="${backup_conflicts}${backup_target}
"
    fi
  done <<EOF
$BACKUP_ROOTS
EOF
  if [ -n "$backup_conflicts" ]; then
    backup_conflict=''
    while IFS= read -r backup_conflict || [ -n "$backup_conflict" ]; do
      [ -n "$backup_conflict" ] && dot_warn "restore conflict: $(deploy_display_path "$backup_conflict")"
    done <<EOF
$backup_conflicts
EOF
    dot_error 'restore stopped; unrelated files would be overwritten'
    return 1
  fi

  dot_plan "will restore backup: $backup_id"
  backup_file=''
  while IFS= read -r backup_file || [ -n "$backup_file" ]; do
    [ -n "$backup_file" ] && dot_plan "will restore: $(deploy_display_path "$HOME/$backup_file")"
  done <<EOF
$BACKUP_ROOTS
EOF
  if ! dot_confirm; then
    dot_warn 'restore cancelled'
    return 1
  fi
  BACKUP_RESTORE_SNAPSHOT="$(mktemp -d "${TMPDIR:-/tmp}/dot-restore.XXXXXX")" || return 1
  backup_file=''
  while IFS= read -r backup_file || [ -n "$backup_file" ]; do
    [ -z "$backup_file" ] && continue
    backups_restore_target_allowed "$backup_file" || {
      rm -rf "$BACKUP_RESTORE_SNAPSHOT"
      dot_error "restore target changed or became unsafe: $backup_file"
      return 1
    }
    backup_target="$HOME/$backup_file"
    if [ -e "$backup_target" ] || [ -L "$backup_target" ]; then
      mkdir -p "$BACKUP_RESTORE_SNAPSHOT/$(dirname "$backup_file")" || { rm -rf "$BACKUP_RESTORE_SNAPSHOT"; return 1; }
      cp -a "$backup_target" "$BACKUP_RESTORE_SNAPSHOT/$backup_file" || { rm -rf "$BACKUP_RESTORE_SNAPSHOT"; return 1; }
      printf '%s|%s\n' "$backup_file" "$backup_target" >> "$BACKUP_RESTORE_SNAPSHOT/list"
    fi
  done <<EOF
$BACKUP_ROOTS
EOF
  backup_file=''
  while IFS= read -r backup_file || [ -n "$backup_file" ]; do
    [ -z "$backup_file" ] && continue
    backup_validate_source_path "$backup_file" || {
      dot_error "backup source became unsafe: $backup_file"
      backups_restore_rollback
      return 1
    }
    backups_restore_target_allowed "$backup_file" || {
      dot_error "restore target changed or became unsafe: $backup_file"
      backups_restore_rollback
      return 1
    }
    backup_target="$HOME/$backup_file"
    mkdir -p "$(dirname "$backup_target")" || { backups_restore_rollback; return 1; }
    backups_restore_target_allowed "$backup_file" || {
      dot_error "restore target changed or became unsafe: $backup_file"
      backups_restore_rollback
      return 1
    }
    if [ -L "$backup_target" ] || [ -d "$backup_target" ]; then
      rm -rf "$backup_target" || { backups_restore_rollback; return 1; }
    fi
    cp -a "$BACKUP_SELECTED/$backup_file" "$backup_target" || { backups_restore_rollback; return 1; }
  done <<EOF
$BACKUP_ROOTS
EOF
  rm -rf "$BACKUP_RESTORE_SNAPSHOT"
  dot_ok "restored backup: $backup_id"
}

backups_remove_command() {
  backup_id="$1"
  shift
  DOT_YES=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --yes) DOT_YES=1; shift ;;
      --help|-h) dot_command_usage 'backups remove'; return 0 ;;
      *) dot_bad_args "invalid argument: $1" 'backups remove'; return $? ;;
    esac
  done
  backup_directory_for_id "$backup_id" || return 1
  backup_count="$(backup_file_count "$BACKUP_SELECTED")" || return 1
  dot_plan "will permanently remove backup: $backup_id ($(backup_size "$BACKUP_SELECTED"), $backup_count file(s))"
  if ! dot_confirm; then
    dot_warn 'backup removal cancelled'
    return 1
  fi
  backup_validate_candidate_directory "$BACKUP_SELECTED" || {
    dot_error 'backup changed or became unsafe; nothing removed'
    return 1
  }
  rm -rf "$BACKUP_SELECTED" || return 1
  dot_ok "removed backup: $backup_id"
}

backup_mtime() {
  stat -c %Y "$1" 2>/dev/null && return 0
  stat -f %m "$1" 2>/dev/null
}

backups_prune_command() {
  backup_validate_root || return 1
  older=''
  DOT_YES=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --older-than)
        [ "$#" -ge 2 ] || { dot_bad_args 'missing value for --older-than' 'backups prune'; return $?; }
        older="$2"
        shift 2
        ;;
      --yes) DOT_YES=1; shift ;;
      --help|-h) dot_command_usage 'backups prune'; return 0 ;;
      *) dot_bad_args "invalid argument: $1" 'backups prune'; return $? ;;
    esac
  done
  case "$older" in
    *d) ;;
    *) dot_bad_args 'age must look like 30d' 'backups prune'; return $? ;;
  esac
  prune_days="${older%d}"
  case "$prune_days" in
    ''|*[!0-9]*) dot_bad_args 'age must look like 30d' 'backups prune'; return $? ;;
  esac
  prune_now="$(date +%s)" || return 1
  prune_cutoff=$((prune_days * 86400))
  prune_matches=''
  backup_parent="$(backup_root)"
  for backup_dir in "$backup_parent"/*; do
    [ -d "$backup_dir" ] || continue
    backup_validate_candidate_directory "$backup_dir" || {
      dot_error "unsafe backup directory: $backup_dir"
      return 1
    }
    prune_mtime="$(backup_mtime "$backup_dir")" || continue
    [ $((prune_now - prune_mtime)) -ge "$prune_cutoff" ] || continue
    prune_matches="${prune_matches}${backup_dir}
"
  done
  if [ -z "$prune_matches" ]; then
    dot_ok 'no backups match the requested age'
    return 0
  fi
  prune_match=''
  while IFS= read -r prune_match || [ -n "$prune_match" ]; do
    [ -n "$prune_match" ] && dot_plan "will permanently remove backup: ${prune_match##*/}"
  done <<EOF
$prune_matches
EOF
  if ! dot_confirm; then
    dot_warn 'backup pruning cancelled'
    return 1
  fi
  while IFS= read -r prune_match || [ -n "$prune_match" ]; do
    [ -n "$prune_match" ] || continue
    backup_validate_candidate_directory "$prune_match" || {
      dot_error "backup changed or became unsafe: $prune_match"
      return 1
    }
    rm -rf "$prune_match" || return 1
  done <<EOF
$prune_matches
EOF
  dot_ok 'old backups pruned'
}
