#!/usr/bin/env bash

dot_install_zap() {
  [ -f "${HOME:-}/.local/share/zap/zap.zsh" ] && return 0
  command -v curl >/dev/null 2>&1 || { dot_error 'curl is required to install Zap'; return 1; }
  command -v zsh >/dev/null 2>&1 || { dot_error 'zsh is required to install Zap'; return 1; }

  zap_file="${TMPDIR:-/tmp}/dot-zap-installer.$$"
  zap_url='https://raw.githubusercontent.com/zap-zsh/zap/d8e74d3d97ded884d14079f98f0a328580e4f8dc/install.zsh'
  zap_sha256='f73fe83a252da7c0a67d18ebe42e6c54d34f1d8b4438a891c0f6453417814579'
  if ! curl -fsSL "$zap_url" > "$zap_file"; then
    rm -f "$zap_file"
    dot_error 'failed to download the Zap installer'
    return 1
  fi

  zap_hash=''
  if command -v shasum >/dev/null 2>&1; then
    zap_hash="$(shasum -a 256 "$zap_file" | awk '{print $1}')"
  elif command -v sha256sum >/dev/null 2>&1; then
    zap_hash="$(sha256sum "$zap_file" | awk '{print $1}')"
  else
    rm -f "$zap_file"
    dot_error 'shasum or sha256sum is required to verify the Zap installer'
    return 1
  fi
  if [ "$zap_hash" != "$zap_sha256" ]; then
    rm -f "$zap_file"
    dot_error 'Zap installer checksum did not match the pinned release'
    return 1
  fi

  zap_script="$(<"$zap_file")"
  rm -f "$zap_file"
  zsh -c "$zap_script" zap-install --branch release-v1
}

install_prepare() {
  platform_detect || return 1
  platform_load_installer "$PLATFORM" || return 1
  manifest_validate_all || return 1
  manifest_load_selected "${1:-0}" || return 1
  return 0
}

install_print_context() {
  printf 'Platform: %s\n' "$(platform_label "$PLATFORM")"
  printf 'Manifests: core, development'
  [ "${1:-0}" = 1 ] && printf ', optional'
  printf '\n'
}

# Inspect the selected entries once. Installation is deliberately a direct
# operation: this is a status report, not a separate approval/plan phase.
install_scan() {
  INSTALL_MISSING_ENTRIES=''
  INSTALL_MISSING_COUNT=0
  INSTALL_UNCHANGED_COUNT=0
  INSTALL_UNSUPPORTED_COUNT=0
  INSTALL_UNSUPPORTED_NAMES=''
  INSTALL_SCAN_ERROR=0
  install_entry=''
  while IFS= read -r install_entry || [ -n "$install_entry" ]; do
    [ -z "$install_entry" ] && continue
    if installer_status "$install_entry"; then
      case "$INSTALLER_STATUS" in
        installed)
          INSTALL_UNCHANGED_COUNT=$((INSTALL_UNCHANGED_COUNT + 1))
          [ "${INSTALL_VERBOSE:-0}" = 1 ] && dot_ok "already installed: $install_entry"
          ;;
        missing)
          dot_change "will install: $install_entry"
          INSTALL_MISSING_ENTRIES="${INSTALL_MISSING_ENTRIES}${install_entry}
"
          INSTALL_MISSING_COUNT=$((INSTALL_MISSING_COUNT + 1))
          ;;
        unsupported)
          INSTALL_UNSUPPORTED_COUNT=$((INSTALL_UNSUPPORTED_COUNT + 1))
          INSTALL_UNSUPPORTED_NAMES="${INSTALL_UNSUPPORTED_NAMES}${install_entry}, "
          ;;
        *)
          dot_error "installer returned an invalid status for $install_entry"
          INSTALL_SCAN_ERROR=1
          ;;
      esac
    else
      dot_error "unknown application for $PLATFORM: $install_entry"
      INSTALL_SCAN_ERROR=1
    fi
  done <<EOF
$SELECTED_ENTRIES
EOF

  if [ "$INSTALL_UNCHANGED_COUNT" -gt 0 ]; then
    dot_ok "unchanged: $INSTALL_UNCHANGED_COUNT application(s)"
  fi
  if [ "$INSTALL_UNSUPPORTED_COUNT" -gt 0 ]; then
    INSTALL_UNSUPPORTED_NAMES="${INSTALL_UNSUPPORTED_NAMES%, }"
    dot_skip "unsupported on $PLATFORM: $INSTALL_UNSUPPORTED_NAMES ($INSTALL_UNSUPPORTED_COUNT application(s))"
  fi
  [ "$INSTALL_SCAN_ERROR" = 0 ]
}

install_execute() {
  install_entry=''
  install_failed=0
  while IFS= read -r install_entry || [ -n "$install_entry" ]; do
    [ -z "$install_entry" ] && continue
    if ! installer_status "$install_entry"; then
      dot_error "could not re-check application before installing: $install_entry"
      install_failed=1
    elif [ "$INSTALLER_STATUS" = missing ]; then
      if installer_install "$install_entry"; then
        if installer_status "$install_entry" && [ "$INSTALLER_STATUS" = installed ]; then
          dot_ok "installed: $install_entry"
        else
          dot_error "installer completed but application is still missing: $install_entry"
          install_failed=1
        fi
      else
        dot_error "failed to install: $install_entry"
        install_failed=1
      fi
    fi
  done <<EOF
$INSTALL_MISSING_ENTRIES
EOF
  [ "$install_failed" = 0 ]
}

install_command() {
  install_include="${1:-0}"
  install_dry_run="${2:-0}"
  INSTALL_VERBOSE="${3:-0}"
  install_prepare "$install_include" || return 1
  install_print_context "$install_include"
  install_scan || return 1
  if [ "$INSTALL_MISSING_COUNT" = 0 ]; then
    dot_ok 'nothing to install'
    return 0
  fi
  if [ "$install_dry_run" = 1 ]; then
    dot_ok 'dry run: no applications changed'
    return 0
  fi
  install_execute
}

bootstrap_command() {
  bootstrap_include="${1:-0}"
  bootstrap_dry_run="${2:-0}"
  bootstrap_verbose="${3:-0}"
  bootstrap_replace="${4:-0}"

  # Bootstrap intentionally composes the two public operations. It does not
  # run doctor, retain a second snapshot/plan, or promise an all-or-nothing
  # transaction across package installation and deployment.
  install_command "$bootstrap_include" "$bootstrap_dry_run" "$bootstrap_verbose" || return 1

  bootstrap_files_args=(deploy)
  [ "$bootstrap_dry_run" = 1 ] && bootstrap_files_args[${#bootstrap_files_args[@]}]=--dry-run
  [ "$bootstrap_verbose" = 1 ] && bootstrap_files_args[${#bootstrap_files_args[@]}]=--verbose
  [ "$bootstrap_replace" = 1 ] && bootstrap_files_args[${#bootstrap_files_args[@]}]=--replace
  files_command "${bootstrap_files_args[@]}"
}
