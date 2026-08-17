#!/usr/bin/env bash

doctor_check_zsh_tree() {
  doctor_zsh_path="$1"
  doctor_zsh_child=''
  [ -d "$doctor_zsh_path" ] || return 0
  for doctor_zsh_child in "$doctor_zsh_path"/.[!.]* "$doctor_zsh_path"/*; do
    [ -e "$doctor_zsh_child" ] || continue
    [ -L "$doctor_zsh_child" ] && continue
    if [ -d "$doctor_zsh_child" ]; then
      doctor_check_zsh_tree "$doctor_zsh_child"
    elif case "$doctor_zsh_child" in *.zsh|*/.zshrc) true ;; *) false ;; esac; then
      if ! zsh -n "$doctor_zsh_child" >/dev/null 2>&1; then
        dot_error "Zsh syntax error: ${doctor_zsh_child#$DOT_ROOT/}"
        DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
      fi
    fi
  done
}

doctor_check_syntax() {
  doctor_file=''
  for doctor_file in "$DOT_ROOT/dot" "$DOT_ROOT"/lib/*.sh "$DOT_ROOT"/installers/*.sh "$DOT_ROOT"/tests/*.sh "$DOT_ROOT/tests/run" "$DOT_ROOT"/tests/fakes/bin/*; do
    [ -f "$doctor_file" ] || continue
    if bash -n "$doctor_file"; then
      :
    else
      dot_error "Bash syntax error: ${doctor_file#$DOT_ROOT/}"
      DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
    fi
  done

  if command -v zsh >/dev/null 2>&1; then
    for doctor_zsh_root in "$DOT_ROOT/zsh" "$DOT_ROOT/global" "$DOT_ROOT/platforms"; do
      doctor_check_zsh_tree "$doctor_zsh_root"
    done
  else
    dot_warn 'Zsh syntax checks skipped: zsh is not installed'
  fi
}

doctor_check_fast_checks() {
  if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -e SC1090,SC1091 "$DOT_ROOT/dot" "$DOT_ROOT"/lib/*.sh "$DOT_ROOT"/installers/*.sh "$DOT_ROOT"/tests/*.sh "$DOT_ROOT/tests/run" "$DOT_ROOT"/tests/fakes/bin/*; then
      dot_ok 'ShellCheck passed'
    else
      dot_error 'ShellCheck found problems'
      DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
    fi
  else
    dot_skip 'ShellCheck unavailable'
  fi

  if command -v starship >/dev/null 2>&1 && [ -r "$DOT_ROOT/starship/.config/starship.toml" ]; then
    if STARSHIP_CONFIG="$DOT_ROOT/starship/.config/starship.toml" starship print-config >/dev/null 2>&1; then
      dot_ok 'Starship configuration parses'
    else
      dot_error 'Starship configuration failed to parse'
      DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
    fi
  else
    dot_skip 'Starship configuration check deferred until Phase 3'
  fi

  if command -v rtk >/dev/null 2>&1 && [ -r "$DOT_ROOT/rtk/.config/rtk/config.toml" ]; then
    if RTK_CONFIG="$DOT_ROOT/rtk/.config/rtk/config.toml" rtk config >/dev/null 2>&1; then
      dot_ok 'RTK configuration parses'
    else
      dot_error 'RTK configuration failed to parse'
      DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
    fi
  else
    dot_skip 'RTK configuration check deferred until Phase 3'
  fi

  if command -v fd >/dev/null 2>&1; then
    doctor_link=''
    doctor_broken_links=0
    while IFS= read -r doctor_link || [ -n "$doctor_link" ]; do
      [ -z "$doctor_link" ] && continue
      if [ ! -e "$doctor_link" ]; then
        dot_error "broken repository link: ${doctor_link#$DOT_ROOT/}"
        doctor_broken_links=$((doctor_broken_links + 1))
      fi
    done <<EOF
$(fd --type l --hidden --exclude .git . "$DOT_ROOT" 2>/dev/null)
EOF
    if [ "$doctor_broken_links" = 0 ]; then
      dot_ok 'repository links are intact'
    else
      DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + doctor_broken_links))
    fi
  else
    dot_skip 'link checks skipped: fd is not installed'
  fi

  if command -v rg >/dev/null 2>&1; then
    if rg -n '(/Users/[A-Za-z]|/home/[A-Za-z])' "$DOT_ROOT/dot" "$DOT_ROOT"/lib "$DOT_ROOT"/installers "$DOT_ROOT"/manifests "$DOT_ROOT"/tests >/dev/null 2>&1; then
      dot_error 'new Phase 1 files contain a hard-coded user home path'
      DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
    else
      dot_ok 'no hard-coded user home paths in Phase 1 files'
    fi
  fi
  dot_skip 'canonical-link checks deferred until configuration restructuring'
}

doctor_check_apps() {
  doctor_manifest=''
  doctor_entry=''
  for doctor_manifest in "$DOT_ROOT/manifests/core" "$DOT_ROOT/manifests/development" "$DOT_ROOT/manifests/optional"; do
    manifest_read "$doctor_manifest" || { DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1)); continue; }
    while IFS= read -r doctor_entry || [ -n "$doctor_entry" ]; do
      [ -z "$doctor_entry" ] && continue
      if ! installer_status "$doctor_entry"; then
        dot_error "unknown application for $PLATFORM: $doctor_entry"
        DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
      elif [ "$INSTALLER_STATUS" = installed ]; then
        dot_ok "available: $doctor_entry"
      elif [ "$INSTALLER_STATUS" = unsupported ]; then
        dot_skip "unsupported on $PLATFORM: $doctor_entry"
      else
        dot_warn "missing application: $doctor_entry"
        if [ "${DOCTOR_ALLOW_MISSING:-0}" != 1 ]; then
          DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
        fi
      fi
    done <<EOF
$MANIFEST_ENTRIES
EOF
  done
}

doctor_command() {
  DOCTOR_PROBLEMS=0
  DOCTOR_ALLOW_MISSING=0
  if [ "${1:-}" = --for-bootstrap ]; then
    shift
    DOCTOR_ALLOW_MISSING=1
  fi
  [ "$#" = 0 ] || { dot_error "invalid doctor argument: $1"; return 2; }
  platform_detect || return 1
  platform_load_installer "$PLATFORM" || return 1
  printf 'Platform: %s\n' "$(platform_label "$PLATFORM")"

  doctor_required=''
  for doctor_required in dot lib installers manifests tests; do
    if [ -e "$DOT_ROOT/$doctor_required" ]; then
      dot_ok "repository entry exists: $doctor_required"
    else
      dot_error "repository entry is missing: $doctor_required"
      DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
    fi
  done

  doctor_manifests_valid=1
  if ! manifest_validate_all; then
    DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
    doctor_manifests_valid=0
  fi

  for doctor_required in bash stow; do
    if command -v "$doctor_required" >/dev/null 2>&1; then
      dot_ok "required command: $doctor_required"
    else
      if [ "$doctor_required" = stow ] && [ "${DOCTOR_ALLOW_MISSING:-0}" = 1 ]; then
        dot_plan 'required command will be installed: stow'
      else
        dot_error "required command is missing: $doctor_required"
        DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
      fi
    fi
  done
  if [ "$PLATFORM" = macos ] && ! command -v brew >/dev/null 2>&1; then
    dot_error 'Homebrew is required on macOS but is not installed'
    DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
  fi

  doctor_check_syntax
  doctor_check_fast_checks
  if [ "$doctor_manifests_valid" = 1 ]; then
    doctor_check_apps
  fi

  if [ "$DOCTOR_PROBLEMS" = 0 ]; then
    dot_ok 'doctor found no blocking problems'
    return 0
  fi
  dot_error "doctor found $DOCTOR_PROBLEMS blocking problem(s)"
  dot_warn 'next commands: dot plan; dot install --yes; fix any repository error above'
  return 1
}
