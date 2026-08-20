#!/usr/bin/env bash

# Deployment is deliberately planned before Stow is allowed to modify HOME.
# Keep the data as newline-separated paths; dotfile paths cannot contain newlines
# in the supported repository layout.

deploy_display_path() {
  case "$1" in
    "$HOME") printf '~' ;;
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

deploy_root_path() {
  DEPLOY_ROOT_REAL="$(CDPATH= cd -P -- "$DOT_ROOT" 2>/dev/null && pwd -P)" || return 1
}

deploy_resolve_path() {
  deploy_pending="${1#/}"
  deploy_resolved='/'
  deploy_symlink_hops=0
  while [ -n "$deploy_pending" ]; do
    deploy_component="${deploy_pending%%/*}"
    if [ "$deploy_pending" = "$deploy_component" ]; then
      deploy_pending=''
    else
      deploy_pending="${deploy_pending#*/}"
    fi
    case "$deploy_component" in
      ''|.) continue ;;
      ..)
        [ "$deploy_resolved" != / ] && deploy_resolved="$(dirname "$deploy_resolved")"
        continue
        ;;
    esac
    if [ "$deploy_resolved" = / ]; then
      deploy_next="/$deploy_component"
    else
      deploy_next="$deploy_resolved/$deploy_component"
    fi
    if [ -L "$deploy_next" ]; then
      deploy_symlink_hops=$((deploy_symlink_hops + 1))
      [ "$deploy_symlink_hops" -le 40 ] || return 1
      deploy_symlink_target="$(readlink "$deploy_next" 2>/dev/null)" || return 1
      case "$deploy_symlink_target" in
        /*) deploy_resolved='/'; deploy_pending="${deploy_symlink_target#/}"${deploy_pending:+/$deploy_pending} ;;
        *) deploy_resolved="$(dirname "$deploy_next")"; deploy_pending="$deploy_symlink_target${deploy_pending:+/$deploy_pending}" ;;
      esac
    else
      deploy_resolved="$deploy_next"
    fi
  done
  printf '%s' "$deploy_resolved"
}

deploy_link_resolved_path() {
  deploy_link="$1"
  deploy_raw="$(readlink "$deploy_link" 2>/dev/null)" || return 1
  deploy_link_dir="$(CDPATH= cd -P -- "$(dirname "$deploy_link")" 2>/dev/null && pwd -P)" || return 1
  case "$deploy_raw" in
    /*) deploy_candidate="$deploy_raw" ;;
    *) deploy_candidate="$deploy_link_dir/$deploy_raw" ;;
  esac
  deploy_resolve_path "$deploy_candidate"
}

deploy_link_is_repo_owned() {
  deploy_link="$1"
  [ -L "$deploy_link" ] || return 1
  [ -n "${DEPLOY_ROOT_REAL:-}" ] || deploy_root_path || return 1
  deploy_resolved="$(deploy_link_resolved_path "$deploy_link")" || return 1
  case "$deploy_resolved" in
    "$DOT_ROOT"/*|"$DOT_ROOT") return 0 ;;
  esac
  if [ -n "$DEPLOY_ROOT_REAL" ]; then
    case "$deploy_resolved" in
      "$DEPLOY_ROOT_REAL"/*|"$DEPLOY_ROOT_REAL") return 0 ;;
    esac
  fi
  return 1
}

deploy_link_matches_source() {
  deploy_link="$1"
  deploy_source="$2"
  [ -L "$deploy_link" ] || return 1
  deploy_expected="$(deploy_resolve_path "$deploy_source")" || return 1
  case "$deploy_expected" in
    "$DOT_ROOT"/*|"$DOT_ROOT") ;;
    "$DEPLOY_ROOT_REAL"/*|"$DEPLOY_ROOT_REAL") ;;
    *) return 1 ;;
  esac
  [ "$(deploy_link_resolved_path "$deploy_link")" = "$deploy_expected" ]
}

deploy_append_unique() {
  deploy_list_name="$1"
  deploy_value="$2"
  case "$deploy_list_name" in
    DEPLOY_CONFLICTS) deploy_existing="$DEPLOY_CONFLICTS" ;;
    DEPLOY_LEGACY_LINKS) deploy_existing="$DEPLOY_LEGACY_LINKS" ;;
    DEPLOY_SNAPSHOT_PATHS) deploy_existing="$DEPLOY_SNAPSHOT_PATHS" ;;
    DEPLOY_SNAPSHOT_DIRS) deploy_existing="$DEPLOY_SNAPSHOT_DIRS" ;;
    *) dot_error "invalid deployment list: $deploy_list_name"; return 1 ;;
  esac
  while IFS= read -r deploy_item || [ -n "$deploy_item" ]; do
    [ "$deploy_item" = "$deploy_value" ] && return 0
  done <<EOF
$deploy_existing
EOF
  case "$deploy_list_name" in
    DEPLOY_CONFLICTS)
      deploy_filtered=''
      deploy_item=''
      while IFS= read -r deploy_item || [ -n "$deploy_item" ]; do
        [ -z "$deploy_item" ] && continue
        case "$deploy_value" in
          "$deploy_item"/*) return 0 ;;
        esac
        case "$deploy_item" in
          "$deploy_value"/*) continue ;;
        esac
        deploy_filtered="${deploy_filtered}${deploy_item}
"
      done <<EOF
$deploy_existing
EOF
      DEPLOY_CONFLICTS="${deploy_filtered}${deploy_value}
"
      ;;
    DEPLOY_LEGACY_LINKS)
      DEPLOY_LEGACY_LINKS="${deploy_existing}${deploy_value}
"
      ;;
    DEPLOY_SNAPSHOT_PATHS|DEPLOY_SNAPSHOT_DIRS)
      deploy_filtered=''
      deploy_item=''
      while IFS= read -r deploy_item || [ -n "$deploy_item" ]; do
        [ -z "$deploy_item" ] && continue
        case "$deploy_value" in
          "$deploy_item"/*) return 0 ;;
        esac
        case "$deploy_item" in
          "$deploy_value"/*) continue ;;
        esac
        deploy_filtered="${deploy_filtered}${deploy_item}
"
      done <<EOF
$deploy_existing
EOF
      case "$deploy_list_name" in
        DEPLOY_SNAPSHOT_PATHS) DEPLOY_SNAPSHOT_PATHS="${deploy_filtered}${deploy_value}
" ;;
        DEPLOY_SNAPSHOT_DIRS) DEPLOY_SNAPSHOT_DIRS="${deploy_filtered}${deploy_value}
" ;;
      esac
      ;;
  esac
}

deploy_add_entry() {
  deploy_entry_target="$1"
  deploy_entry_source="$2"
  deploy_entry_layer="$3"
  deploy_existing_target=''
  while IFS= read -r deploy_existing_target || [ -n "$deploy_existing_target" ]; do
    [ -z "$deploy_existing_target" ] && continue
    if [ "$deploy_existing_target" = "$deploy_entry_target" ]; then
      dot_error "configuration layers both own $(deploy_display_path "$deploy_entry_target")"
      DEPLOY_PLAN_ERROR=1
      return 0
    fi
  done <<EOF
$DEPLOY_TARGETS
EOF
  DEPLOY_TARGETS="${DEPLOY_TARGETS}${deploy_entry_target}
"
  DEPLOY_SOURCES="${DEPLOY_SOURCES}${deploy_entry_source}
"
  DEPLOY_ENTRY_LAYERS="${DEPLOY_ENTRY_LAYERS}${deploy_entry_layer}
"
  DEPLOY_ENTRY_RECORDS="${DEPLOY_ENTRY_RECORDS}${deploy_entry_target}|${deploy_entry_source}
"
}

deploy_walk_is_ignored() {
  deploy_ignore_root="$1"
  deploy_ignore_relative="$2"
  [ -r "$deploy_ignore_root/.stow-local-ignore" ] || return 1
  deploy_ignore_pattern=''
  while IFS= read -r deploy_ignore_pattern || [ -n "$deploy_ignore_pattern" ]; do
    [ -n "$deploy_ignore_pattern" ] || continue
    case "$deploy_ignore_pattern" in
      \#*) continue ;;
    esac
    DEPLOY_IGNORE_PATTERN="$deploy_ignore_pattern" awk '$0 ~ ENVIRON["DEPLOY_IGNORE_PATTERN"] { found=1 } END { exit !found }' <<EOF
$deploy_ignore_relative
EOF
    [ "$?" = 0 ] && return 0
  done < "$deploy_ignore_root/.stow-local-ignore"
  return 1
}

deploy_walk_layer() {
  local deploy_walk_root deploy_walk_relative deploy_walk_layer_name deploy_walk_package_root
  local deploy_walk_child deploy_walk_name deploy_walk_next deploy_walk_target
  deploy_walk_root="$1"
  deploy_walk_relative="$2"
  deploy_walk_layer_name="$3"
  deploy_walk_package_root="${4:-$deploy_walk_root}"
  deploy_walk_child=''
  for deploy_walk_child in \
    "$deploy_walk_root"/.[!.]* \
    "$deploy_walk_root"/..?* \
    "$deploy_walk_root"/*; do
    [ -e "$deploy_walk_child" ] || [ -L "$deploy_walk_child" ] || continue
    deploy_walk_name="${deploy_walk_child##*/}"
    case "$deploy_walk_name" in
      .|..|.stow-local-ignore) continue ;;
    esac
    if [ -n "$deploy_walk_relative" ]; then
      deploy_walk_next="$deploy_walk_relative/$deploy_walk_name"
    else
      deploy_walk_next="$deploy_walk_name"
    fi
    deploy_walk_is_ignored "$deploy_walk_package_root" "$deploy_walk_next" && continue
    if [ -d "$deploy_walk_child" ] && [ ! -L "$deploy_walk_child" ]; then
      deploy_walk_layer "$deploy_walk_child" "$deploy_walk_next" "$deploy_walk_layer_name" "$deploy_walk_package_root" || return 1
    else
      deploy_walk_target="$HOME/$deploy_walk_next"
      deploy_add_entry "$deploy_walk_target" "$deploy_walk_child" "$deploy_walk_layer_name"
    fi
  done
}

deploy_target_has_legacy_parent() {
  deploy_parent_target="$1"
  deploy_parent_path="$(dirname "$deploy_parent_target")"
  while [ "$deploy_parent_path" != "$HOME" ] && [ "$deploy_parent_path" != / ]; do
    if [ -L "$deploy_parent_path" ]; then
      deploy_link_is_repo_owned "$deploy_parent_path" && return 0
      return 1
    fi
    deploy_parent_path="$(dirname "$deploy_parent_path")"
  done
  return 1
}

deploy_check_target_collisions() {
  deploy_collision_first=''
  deploy_collision_second=''
  while IFS= read -r deploy_collision_first || [ -n "$deploy_collision_first" ]; do
    [ -z "$deploy_collision_first" ] && continue
    while IFS= read -r deploy_collision_second || [ -n "$deploy_collision_second" ]; do
      [ -z "$deploy_collision_second" ] && continue
      [ "$deploy_collision_first" = "$deploy_collision_second" ] && continue
      case "$deploy_collision_second" in
        "$deploy_collision_first"/*)
          dot_error "configuration layers overlap at $(deploy_display_path "$deploy_collision_first")"
          DEPLOY_PLAN_ERROR=1
          ;;
      esac
    done <<EOF
$DEPLOY_TARGETS
EOF
  done <<EOF
$DEPLOY_TARGETS
EOF
}

deploy_check_parent_paths() {
  deploy_check_target="$1"
  deploy_check_parent="$(dirname "$deploy_check_target")"
  while [ "$deploy_check_parent" != "$HOME" ] && [ "$deploy_check_parent" != / ]; do
    if [ -L "$deploy_check_parent" ]; then
      if deploy_link_is_repo_owned "$deploy_check_parent"; then
        deploy_append_unique DEPLOY_LEGACY_LINKS "$deploy_check_parent"
      else
        deploy_append_unique DEPLOY_CONFLICTS "$deploy_check_parent"
      fi
      return 0
    elif [ -e "$deploy_check_parent" ] && [ ! -d "$deploy_check_parent" ]; then
      deploy_append_unique DEPLOY_CONFLICTS "$deploy_check_parent"
      return 0
    fi
    deploy_check_parent="$(dirname "$deploy_check_parent")"
  done
}

deploy_path_fingerprint() {
  deploy_fingerprint_path="$1"
  if [ -L "$deploy_fingerprint_path" ]; then
    printf 'L:%s:%s:%s' "$(readlink "$deploy_fingerprint_path")" "$(deploy_link_resolved_path "$deploy_fingerprint_path")" "$(stat -c %d:%i "$deploy_fingerprint_path" 2>/dev/null || stat -f %d:%i "$deploy_fingerprint_path" 2>/dev/null)"
  elif [ -e "$deploy_fingerprint_path" ]; then
    printf 'F:%s:%s' "$(stat -c %d:%i "$deploy_fingerprint_path" 2>/dev/null || stat -f %d:%i "$deploy_fingerprint_path" 2>/dev/null)" "$(cksum "$deploy_fingerprint_path" 2>/dev/null | awk '{print $1 ":" $2}')"
  else
    printf 'N'
  fi
}

deploy_capture_plan_fingerprints() {
  DEPLOY_FINGERPRINTS=''
  deploy_fingerprint_path_name=''
  while IFS= read -r deploy_fingerprint_path_name || [ -n "$deploy_fingerprint_path_name" ]; do
    [ -n "$deploy_fingerprint_path_name" ] || continue
    DEPLOY_FINGERPRINTS="${DEPLOY_FINGERPRINTS}${deploy_fingerprint_path_name}|$(deploy_path_fingerprint "$deploy_fingerprint_path_name")
"
  done <<EOF
$DEPLOY_CONFLICTS
$DEPLOY_LEGACY_LINKS
EOF
}

deploy_verify_plan_fingerprints() {
  deploy_fingerprint_path_name=''
  deploy_fingerprint_expected=''
  while IFS='|' read -r deploy_fingerprint_path_name deploy_fingerprint_expected || [ -n "$deploy_fingerprint_path_name" ]; do
    [ -n "$deploy_fingerprint_path_name" ] || continue
    [ "$(deploy_path_fingerprint "$deploy_fingerprint_path_name")" = "$deploy_fingerprint_expected" ] || return 1
  done <<EOF
$DEPLOY_FINGERPRINTS
EOF
}

deploy_classify_targets() {
  DEPLOY_CONFLICTS=''
  DEPLOY_LEGACY_LINKS=''
  DEPLOY_TARGET=''
  DEPLOY_SOURCE=''
  while IFS='|' read -r DEPLOY_TARGET DEPLOY_SOURCE || [ -n "$DEPLOY_TARGET" ]; do
    [ -z "$DEPLOY_TARGET" ] && continue
    if ! deploy_target_has_legacy_parent "$DEPLOY_TARGET"; then
      if [ -L "$DEPLOY_TARGET" ]; then
        if deploy_link_matches_source "$DEPLOY_TARGET" "$DEPLOY_SOURCE"; then
          :
        elif deploy_link_is_repo_owned "$DEPLOY_TARGET"; then
          deploy_append_unique DEPLOY_LEGACY_LINKS "$DEPLOY_TARGET"
        else
          deploy_append_unique DEPLOY_CONFLICTS "$DEPLOY_TARGET"
        fi
      elif [ -e "$DEPLOY_TARGET" ]; then
        deploy_append_unique DEPLOY_CONFLICTS "$DEPLOY_TARGET"
      fi
    fi
    deploy_check_parent_paths "$DEPLOY_TARGET"
  done <<EOF
$DEPLOY_ENTRY_RECORDS
EOF
}

deploy_prepare() {
  platform_detect || return 1
  deploy_root_path || { dot_error 'repository path could not be resolved'; return 1; }
  [ -n "${HOME:-}" ] || { dot_error 'HOME is required for deployment'; return 1; }

  DEPLOY_LAYER_NAMES='global'
  DEPLOY_LAYER_NAMES="$DEPLOY_LAYER_NAMES
platforms/$PLATFORM"
  DEPLOY_ACTIVE_LAYERS=''
  DEPLOY_PLAN_ERROR=0
  deploy_layer=''
  while IFS= read -r deploy_layer || [ -n "$deploy_layer" ]; do
    [ -z "$deploy_layer" ] && continue
    if [ -d "$DOT_ROOT/$deploy_layer" ]; then
      DEPLOY_ACTIVE_LAYERS="${DEPLOY_ACTIVE_LAYERS}${deploy_layer}
"
    elif [ -e "$DOT_ROOT/$deploy_layer" ]; then
      dot_error "configuration layer is not a directory: $deploy_layer"
      DEPLOY_PLAN_ERROR=1
    else
      dot_skip "configuration layer not present: $deploy_layer"
    fi
  done <<EOF
$DEPLOY_LAYER_NAMES
EOF
  [ "$DEPLOY_PLAN_ERROR" = 0 ] || return 1
  if [ "${DEPLOY_READ_ONLY:-0}" = 1 ]; then
    return 0
  fi
  if [ -n "$DEPLOY_ACTIVE_LAYERS" ] && ! command -v "${STOW_COMMAND:-stow}" >/dev/null 2>&1; then
    if [ "${DEPLOY_ALLOW_MISSING_STOW:-0}" = 1 ]; then
      dot_plan 'required command will be installed: stow'
    else
      dot_error 'GNU Stow is required for deployment'
      return 1
    fi
  fi
  return 0
}

deploy_build_plan() {
  DEPLOY_TARGETS=''
  DEPLOY_SOURCES=''
  DEPLOY_ENTRY_LAYERS=''
  DEPLOY_ENTRY_RECORDS=''
  DEPLOY_PLAN_ERROR=0
  deploy_layer=''
  while IFS= read -r deploy_layer || [ -n "$deploy_layer" ]; do
    [ -z "$deploy_layer" ] && continue
    deploy_walk_layer "$DOT_ROOT/$deploy_layer" '' "$deploy_layer" || return 1
  done <<EOF
$DEPLOY_ACTIVE_LAYERS
EOF
  deploy_check_target_collisions
  deploy_classify_targets
  deploy_capture_plan_fingerprints
  [ "$DEPLOY_PLAN_ERROR" = 0 ]
}

deploy_print_plan() {
  printf 'Platform: %s\n' "$(platform_label "$PLATFORM")"
  printf 'Configuration layers:\n'
  deploy_layer=''
  while IFS= read -r deploy_layer || [ -n "$deploy_layer" ]; do
    [ -n "$deploy_layer" ] && printf '  - %s\n' "$deploy_layer"
  done <<EOF
$DEPLOY_LAYER_NAMES
EOF

  deploy_count=0
  deploy_target=''
  while IFS= read -r deploy_target || [ -n "$deploy_target" ]; do
    [ -z "$deploy_target" ] && continue
    dot_plan "will link: $(deploy_display_path "$deploy_target")"
    deploy_count=$((deploy_count + 1))
  done <<EOF
$DEPLOY_TARGETS
EOF
  [ "$deploy_count" -gt 0 ] || dot_ok 'no configuration links are planned'

  deploy_legacy=''
  while IFS= read -r deploy_legacy || [ -n "$deploy_legacy" ]; do
    [ -z "$deploy_legacy" ] && continue
    dot_plan "will replace repository link: $(deploy_display_path "$deploy_legacy")"
  done <<EOF
$DEPLOY_LEGACY_LINKS
EOF

  deploy_conflict=''
  while IFS= read -r deploy_conflict || [ -n "$deploy_conflict" ]; do
    [ -z "$deploy_conflict" ] && continue
    if [ -L "$deploy_conflict" ]; then
      dot_warn "existing unrelated link: $(deploy_display_path "$deploy_conflict")"
    else
      dot_warn "existing file: $(deploy_display_path "$deploy_conflict")"
    fi
  done <<EOF
$DEPLOY_CONFLICTS
EOF
  if [ -n "$DEPLOY_CONFLICTS" ]; then
    dot_plan 'adoption is required for the conflicts above'
    if [ "${DEPLOY_ADOPT_MODE:-0}" = 1 ]; then
      deploy_preview_path="${DEPLOY_BACKUP_PREVIEW:-backup location will be selected after confirmation}"
      deploy_conflict=''
      while IFS= read -r deploy_conflict || [ -n "$deploy_conflict" ]; do
        if [ -n "$deploy_conflict" ]; then
          deploy_conflict_relative="${deploy_conflict#"$HOME"/}"
          dot_plan "will back up $(deploy_display_path "$deploy_conflict") to $deploy_preview_path/$deploy_conflict_relative"
        fi
      done <<EOF
$DEPLOY_CONFLICTS
EOF
    fi
  else
    dot_ok 'deployment has no unrelated conflicts'
  fi
}

deploy_stow() {
  deploy_stow_action="$1"
  deploy_stow_layer="$2"
  deploy_stow_bin="${STOW_COMMAND:-stow}"
  command -v "$deploy_stow_bin" >/dev/null 2>&1 || {
    dot_error 'GNU Stow is required for deployment'
    return 1
  }
  deploy_stow_dir="$DOT_ROOT"
  deploy_stow_package="$deploy_stow_layer"
  case "$deploy_stow_layer" in
    platforms/*)
      deploy_stow_dir="$DOT_ROOT/platforms"
      deploy_stow_package="${deploy_stow_layer#platforms/}"
      ;;
  esac
  case "$deploy_stow_action" in
    deploy)
      "$deploy_stow_bin" --no-folding -d "$deploy_stow_dir" -t "$HOME" "$deploy_stow_package"
      ;;
    inspect)
      "$deploy_stow_bin" -n -D -v --no-folding -d "$deploy_stow_dir" -t "$HOME" "$deploy_stow_package"
      ;;
    undeploy)
      "$deploy_stow_bin" -D --no-folding -d "$deploy_stow_dir" -t "$HOME" "$deploy_stow_package"
      ;;
    *)
      dot_error "invalid Stow action: $deploy_stow_action"
      return 2
      ;;
  esac
}

deploy_verify() {
  deploy_verify_target=''
  deploy_verify_source=''
  while IFS='|' read -r deploy_verify_target deploy_verify_source || [ -n "$deploy_verify_target" ]; do
    [ -z "$deploy_verify_target" ] && continue
    if ! deploy_link_matches_source "$deploy_verify_target" "$deploy_verify_source"; then
      dot_error "deployment link was not created: $(deploy_display_path "$deploy_verify_target")"
      return 1
    fi
  done <<EOF
$DEPLOY_ENTRY_RECORDS
EOF
  return 0
}

deploy_backup_copy() {
  deploy_backup_root="$1"
  deploy_backup_path="$2"
  deploy_backup_relative="${deploy_backup_path#"$HOME"/}"
  deploy_backup_destination="$deploy_backup_root/$deploy_backup_relative"
  mkdir -p "$(dirname "$deploy_backup_destination")" || return 1
  cp -a "$deploy_backup_path" "$deploy_backup_destination" || return 1
  printf '%s\n' "$deploy_backup_relative" >> "$deploy_backup_root/.dot-backup-roots"
}

deploy_append_directory_unique() {
  deploy_dir_existing=''
  while IFS= read -r deploy_dir_existing || [ -n "$deploy_dir_existing" ]; do
    [ "$deploy_dir_existing" = "$1" ] && return 1
  done <<EOF
$DEPLOY_SNAPSHOT_DIRS
EOF
  DEPLOY_SNAPSHOT_DIRS="${DEPLOY_SNAPSHOT_DIRS}${1}
"
  return 0
}

deploy_directory_mode() {
  stat -c %a "$1" 2>/dev/null && return 0
  stat -f %Lp "$1" 2>/dev/null
}

deploy_capture_existing_dirs() {
  DEPLOY_SNAPSHOT_DIRS=''
  deploy_dir_target=''
  while IFS= read -r deploy_dir_target || [ -n "$deploy_dir_target" ]; do
    [ -z "$deploy_dir_target" ] && continue
    deploy_dir_path="$(dirname "$deploy_dir_target")"
    while [ "$deploy_dir_path" != "$HOME" ] && [ "$deploy_dir_path" != / ]; do
      if [ -d "$deploy_dir_path" ] && [ ! -L "$deploy_dir_path" ] && deploy_append_directory_unique "$deploy_dir_path"; then
        printf '%s|%s\n' "$deploy_dir_path" "$(deploy_directory_mode "$deploy_dir_path")" >> "$DEPLOY_TRANSACTION_DIR/dirs"
      fi
      deploy_dir_path="$(dirname "$deploy_dir_path")"
    done
  done <<EOF
$DEPLOY_TARGETS
EOF
}

deploy_restore_existing_dirs() {
  deploy_restore_dir=''
  while IFS= read -r deploy_restore_dir || [ -n "$deploy_restore_dir" ]; do
    [ -z "$deploy_restore_dir" ] || mkdir -p "$deploy_restore_dir" || return 1
  done <<EOF
$DEPLOY_SNAPSHOT_DIRS
EOF
  if [ -r "${DEPLOY_TRANSACTION_DIR:-}/dirs" ]; then
    while IFS='|' read -r deploy_restore_dir deploy_restore_mode || [ -n "$deploy_restore_dir" ]; do
      [ -n "$deploy_restore_dir" ] && [ -n "$deploy_restore_mode" ] || continue
      chmod "$deploy_restore_mode" "$deploy_restore_dir" || return 1
    done < "$DEPLOY_TRANSACTION_DIR/dirs"
  fi
}

deploy_make_transaction_snapshot() {
  DEPLOY_TRANSACTION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dot-deploy.XXXXXX")" || return 1
  DEPLOY_SNAPSHOT_PATHS=''
  deploy_snapshot_path=''
  while IFS= read -r deploy_snapshot_path || [ -n "$deploy_snapshot_path" ]; do
    [ -z "$deploy_snapshot_path" ] && continue
    deploy_append_unique DEPLOY_SNAPSHOT_PATHS "$deploy_snapshot_path"
  done <<EOF
$DEPLOY_TARGETS
$DEPLOY_LEGACY_LINKS
$DEPLOY_CONFLICTS
EOF
  deploy_capture_existing_dirs || return 1
  deploy_snapshot_path=''
  while IFS= read -r deploy_snapshot_path || [ -n "$deploy_snapshot_path" ]; do
    [ -z "$deploy_snapshot_path" ] && continue
    if [ -L "$deploy_snapshot_path" ]; then
      printf 'L|%s|%s\n' "$deploy_snapshot_path" "$(readlink "$deploy_snapshot_path")" >> "$DEPLOY_TRANSACTION_DIR/links"
    elif [ -e "$deploy_snapshot_path" ]; then
      deploy_snapshot_relative="${deploy_snapshot_path#"$HOME"/}"
      mkdir -p "$DEPLOY_TRANSACTION_DIR/files/$(dirname "$deploy_snapshot_relative")" || return 1
      cp -a "$deploy_snapshot_path" "$DEPLOY_TRANSACTION_DIR/files/$deploy_snapshot_relative" || return 1
      printf 'F|%s\n' "$deploy_snapshot_relative" >> "$DEPLOY_TRANSACTION_DIR/files.list"
    fi
  done <<EOF
$DEPLOY_SNAPSHOT_PATHS
EOF
  return 0
}

deploy_undeploy_layers_reverse() {
  local deploy_layer_list deploy_first_layer deploy_remaining_layers deploy_layer
  deploy_layer_list="$1"
  deploy_first_layer=''
  deploy_remaining_layers=''
  while IFS= read -r deploy_layer || [ -n "$deploy_layer" ]; do
    [ -z "$deploy_layer" ] && continue
    if [ -z "$deploy_first_layer" ]; then
      deploy_first_layer="$deploy_layer"
    else
      deploy_remaining_layers="${deploy_remaining_layers}${deploy_layer}
"
    fi
  done <<EOF
$deploy_layer_list
EOF
  if [ -n "$deploy_remaining_layers" ]; then
    deploy_undeploy_layers_reverse "$deploy_remaining_layers" || return 1
  fi
  [ -z "$deploy_first_layer" ] || deploy_stow undeploy "$deploy_first_layer" >/dev/null 2>&1
}

deploy_restore_transaction_snapshot() {
  # Stow removes its own partial work; this restores links and adopted paths
  # that existed before the transaction began.
  deploy_rollback_error=0
  if [ -n "${DEPLOY_FAILED_LAYER:-}" ]; then
    deploy_stow undeploy "$DEPLOY_FAILED_LAYER" >/dev/null 2>&1 || deploy_rollback_error=1
  fi
  deploy_undeploy_layers_reverse "${DEPLOY_COMPLETED_LAYERS:-}" || deploy_rollback_error=1

  deploy_snapshot_path=''
  while IFS= read -r deploy_snapshot_path || [ -n "$deploy_snapshot_path" ]; do
    [ -z "$deploy_snapshot_path" ] && continue
    rm -rf "$deploy_snapshot_path" || deploy_rollback_error=1
  done <<EOF
$DEPLOY_SNAPSHOT_PATHS
EOF
  if [ -r "$DEPLOY_TRANSACTION_DIR/links" ]; then
    while IFS='|' read -r deploy_snapshot_type deploy_snapshot_path deploy_snapshot_raw || [ -n "$deploy_snapshot_path" ]; do
      [ "$deploy_snapshot_type" = L ] || continue
      if ! mkdir -p "$(dirname "$deploy_snapshot_path")" || ! ln -s "$deploy_snapshot_raw" "$deploy_snapshot_path"; then
        deploy_rollback_error=1
      fi
    done < "$DEPLOY_TRANSACTION_DIR/links"
  fi
  if [ -r "$DEPLOY_TRANSACTION_DIR/files.list" ]; then
    while IFS='|' read -r deploy_snapshot_type deploy_snapshot_relative || [ -n "$deploy_snapshot_relative" ]; do
      [ "$deploy_snapshot_type" = F ] || continue
      if ! mkdir -p "$(dirname "$HOME/$deploy_snapshot_relative")" || \
        ! cp -a "$DEPLOY_TRANSACTION_DIR/files/$deploy_snapshot_relative" "$HOME/$deploy_snapshot_relative"; then
        deploy_rollback_error=1
      fi
    done < "$DEPLOY_TRANSACTION_DIR/files.list"
  fi
  deploy_restore_existing_dirs || deploy_rollback_error=1
  if [ "$deploy_rollback_error" = 1 ]; then
    dot_error "rollback did not complete; transaction snapshot remains at $DEPLOY_TRANSACTION_DIR"
    return 1
  fi
  return 0
}

deploy_execute() {
  deploy_adopt="${1:-0}"
  deploy_confirmed="${2:-0}"
  deploy_prepared="${3:-0}"
  DEPLOY_ADOPT_MODE="$deploy_adopt"
  DEPLOY_BACKUP_PREVIEW=''
  DEPLOY_BACKUP_PATH=''
  if [ "$deploy_prepared" != 1 ]; then
    deploy_prepare || return 1
    deploy_build_plan || return 1
    if [ "$deploy_adopt" = 1 ] && [ -n "$DEPLOY_CONFLICTS" ]; then
      DEPLOY_BACKUP_PREVIEW="$(backup_preview_directory 2>/dev/null || true)"
    fi
    deploy_print_plan
  fi
  if ! deploy_verify_plan_fingerprints; then
    dot_error 'deployment plan changed before execution; no files changed'
    return 1
  fi
  if [ -n "$DEPLOY_CONFLICTS" ] && [ "$deploy_adopt" != 1 ]; then
    dot_error 'deploy stopped; no files changed'
    return 1
  fi
  if [ -z "$DEPLOY_TARGETS" ]; then
    dot_ok 'no configuration links to deploy'
    return 0
  fi
  if [ "$deploy_confirmed" != 1 ] && ! dot_confirm; then
    dot_warn 'deployment cancelled'
    return 1
  fi
  if [ "$deploy_adopt" = 1 ] && [ -n "$DEPLOY_CONFLICTS" ] && [ -z "$DEPLOY_BACKUP_PREVIEW" ]; then
    DEPLOY_BACKUP_PREVIEW="$(backup_preview_directory 2>/dev/null || true)"
  fi
  if [ -n "$DEPLOY_CONFLICTS" ] && [ "$deploy_adopt" = 1 ]; then
    backup_create_directory || {
      dot_error 'could not create an adoption backup'
      return 1
    }
    DEPLOY_BACKUP_ID="${DEPLOY_BACKUP_PATH##*/}"
    deploy_conflict=''
    while IFS= read -r deploy_conflict || [ -n "$deploy_conflict" ]; do
      [ -z "$deploy_conflict" ] && continue
      deploy_backup_copy "$DEPLOY_BACKUP_PATH" "$deploy_conflict" || {
        dot_error 'could not complete adoption backup; no files changed'
        rm -rf "$DEPLOY_BACKUP_PATH"
        return 1
      }
    done <<EOF
$DEPLOY_CONFLICTS
EOF
    dot_plan "backup: $(deploy_display_path "$DEPLOY_BACKUP_PATH")"
  else
    DEPLOY_BACKUP_ID=''
  fi

  deploy_make_transaction_snapshot || {
    dot_error 'could not prepare deployment transaction; no files changed'
    [ -n "${DEPLOY_BACKUP_PATH:-}" ] && dot_warn "adoption backup retained at $(deploy_display_path "$DEPLOY_BACKUP_PATH")"
    return 1
  }
  if ! deploy_verify_plan_fingerprints; then
    dot_error 'deployment plan changed before replacement; rolling back'
    rm -rf "$DEPLOY_TRANSACTION_DIR"
    return 1
  fi

  # Remove only links that already point into this repository. Normal files
  # are removed only after their adoption copy has completed.
  deploy_old_link=''
  while IFS= read -r deploy_old_link || [ -n "$deploy_old_link" ]; do
    [ -z "$deploy_old_link" ] && continue
    rm -rf "$deploy_old_link" || {
      dot_error 'could not replace a legacy link; rolling back'
      if ! deploy_restore_transaction_snapshot; then
        return 1
      fi
      rm -rf "$DEPLOY_TRANSACTION_DIR"
      return 1
    }
  done <<EOF
$DEPLOY_LEGACY_LINKS
EOF
  if [ -n "$DEPLOY_CONFLICTS" ]; then
    deploy_conflict=''
    while IFS= read -r deploy_conflict || [ -n "$deploy_conflict" ]; do
      [ -z "$deploy_conflict" ] && continue
      rm -rf "$deploy_conflict" || {
        dot_error 'could not clear an adopted conflict; rolling back'
        if ! deploy_restore_transaction_snapshot; then
          return 1
        fi
        rm -rf "$DEPLOY_TRANSACTION_DIR"
        return 1
      }
    done <<EOF
$DEPLOY_CONFLICTS
EOF
  fi

  DEPLOY_FAILED_LAYER=''
  DEPLOY_COMPLETED_LAYERS=''
  deploy_layer=''
  while IFS= read -r deploy_layer || [ -n "$deploy_layer" ]; do
    [ -z "$deploy_layer" ] && continue
    DEPLOY_FAILED_LAYER="$deploy_layer"
    if ! deploy_stow deploy "$deploy_layer"; then
      dot_error 'deploy failed; rolling back all changes'
      if ! deploy_restore_transaction_snapshot; then
        return 1
      fi
      rm -rf "$DEPLOY_TRANSACTION_DIR"
      return 1
    fi
    DEPLOY_COMPLETED_LAYERS="${DEPLOY_COMPLETED_LAYERS}${deploy_layer}
"
    DEPLOY_FAILED_LAYER=''
  done <<EOF
$DEPLOY_ACTIVE_LAYERS
EOF
  if ! deploy_verify; then
    dot_error 'deploy verification failed; rolling back all changes'
    if ! deploy_restore_transaction_snapshot; then
      return 1
    fi
    rm -rf "$DEPLOY_TRANSACTION_DIR"
    return 1
  fi
  rm -rf "$DEPLOY_TRANSACTION_DIR"
  dot_ok 'deployment complete'
  return 0
}

deploy_command() {
  deploy_adopt=0
  DOT_YES=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --adopt) deploy_adopt=1; shift ;;
      --yes) DOT_YES=1; shift ;;
      --help|-h) dot_command_usage deploy; return 0 ;;
      *) dot_bad_args "invalid argument: $1" deploy; return $? ;;
    esac
  done
  deploy_execute "$deploy_adopt"
}

deploy_plan_command() {
  DEPLOY_READ_ONLY=1
  deploy_prepare || return 1
  deploy_build_plan || return 1
  deploy_print_plan
}

deploy_undeploy_command() {
  DOT_YES="${1:-0}"
  deploy_prepare || return 1
  deploy_build_plan || return 1
  printf 'Platform: %s\n' "$(platform_label "$PLATFORM")"
  deploy_layer=''
  deploy_has_work=0
  while IFS= read -r deploy_layer || [ -n "$deploy_layer" ]; do
    [ -z "$deploy_layer" ] && continue
    dot_plan "inspect layer: $deploy_layer"
    deploy_stow_output="$(deploy_stow inspect "$deploy_layer" 2>&1)" || {
      printf '%s\n' "$deploy_stow_output" >&2
      dot_error "could not inspect layer: $deploy_layer"
      return 1
    }
    if [ -n "$deploy_stow_output" ]; then
      while IFS= read -r deploy_line || [ -n "$deploy_line" ]; do
        case "$deploy_line" in
          UNLINK:*) dot_plan "will remove link: ~/${deploy_line#UNLINK: }"; deploy_has_work=1 ;;
          WARNING:*) dot_warn "$deploy_line" ;;
        esac
      done <<EOF
$deploy_stow_output
EOF
    fi
  done <<EOF
$DEPLOY_ACTIVE_LAYERS
EOF
  if [ "$deploy_has_work" = 0 ]; then
    dot_ok 'nothing to undeploy'
    return 0
  fi
  UNDEPLOY_PLAN_LAYERS="$DEPLOY_ACTIVE_LAYERS"
  UNDEPLOY_PLAN_TARGETS="$DEPLOY_TARGETS"
  UNDEPLOY_PLAN_RECORDS="$DEPLOY_ENTRY_RECORDS"
  UNDEPLOY_PLAN_CONFLICTS="$DEPLOY_CONFLICTS"
  if ! dot_confirm; then
    dot_warn 'undeploy cancelled'
    return 1
  fi
  # Rebuild the unlink plan after confirmation so retargeted links or changed
  # layers cannot be removed using stale inspection output.
  deploy_prepare || return 1
  deploy_build_plan || return 1
  if [ "$DEPLOY_ACTIVE_LAYERS" != "$UNDEPLOY_PLAN_LAYERS" ] || \
    [ "$DEPLOY_TARGETS" != "$UNDEPLOY_PLAN_TARGETS" ] || \
    [ "$DEPLOY_ENTRY_RECORDS" != "$UNDEPLOY_PLAN_RECORDS" ] || \
    [ "$DEPLOY_CONFLICTS" != "$UNDEPLOY_PLAN_CONFLICTS" ]; then
    dot_error 'undeploy plan changed after confirmation; no files changed'
    return 1
  fi
  DEPLOY_COMPLETED_LAYERS=''
  DEPLOY_FAILED_LAYER=''
  deploy_make_transaction_snapshot || {
    dot_error 'could not snapshot the current deployment; no files changed'
    return 1
  }
  deploy_layer=''
  while IFS= read -r deploy_layer || [ -n "$deploy_layer" ]; do
    [ -z "$deploy_layer" ] && continue
    DEPLOY_FAILED_LAYER="$deploy_layer"
    if ! deploy_stow undeploy "$deploy_layer"; then
      dot_error 'undeploy failed; rolling back'
      if ! deploy_restore_transaction_snapshot; then
        return 1
      fi
      rm -rf "$DEPLOY_TRANSACTION_DIR"
      return 1
    fi
    DEPLOY_COMPLETED_LAYERS="${DEPLOY_COMPLETED_LAYERS}${deploy_layer}
"
    DEPLOY_FAILED_LAYER=''
  done <<EOF
$DEPLOY_ACTIVE_LAYERS
EOF
  rm -rf "$DEPLOY_TRANSACTION_DIR"
  dot_ok 'undeployment complete'
}
