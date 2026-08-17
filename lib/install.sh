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
  if ! platform_detect; then
    return 1
  fi
  platform_load_installer "$PLATFORM" || return 1
  manifest_validate_all || return 1
  manifest_load_selected "${1:-0}" || return 1
  return 0
}

install_print_header() {
  printf 'Platform: %s\n' "$(platform_label "$PLATFORM")"
  printf 'Manifests:\n'
  printf '  - core\n  - development\n'
  if [ "${1:-0}" = 1 ]; then
    printf '  - optional\n'
  fi
}

install_plan() {
  INSTALL_MISSING_ENTRIES=''
  INSTALL_MISSING_COUNT=0
  INSTALL_PLAN_ERROR=0
  install_entry=''
  while IFS= read -r install_entry || [ -n "$install_entry" ]; do
    [ -z "$install_entry" ] && continue
    if installer_status "$install_entry"; then
      case "$INSTALLER_STATUS" in
        installed)
          dot_ok "already installed: $install_entry"
          ;;
        missing)
          dot_plan "will install: $install_entry"
          INSTALL_MISSING_ENTRIES="${INSTALL_MISSING_ENTRIES}${install_entry}
"
          INSTALL_MISSING_COUNT=$((INSTALL_MISSING_COUNT + 1))
          ;;
        unsupported)
          dot_skip "unsupported on $PLATFORM: $install_entry"
          ;;
        *)
          dot_error "installer returned an invalid status for $install_entry"
          INSTALL_PLAN_ERROR=1
          ;;
      esac
    else
      dot_error "unknown application for $PLATFORM: $install_entry"
      INSTALL_PLAN_ERROR=1
    fi
  done <<EOF
$SELECTED_ENTRIES
EOF
  [ "$INSTALL_PLAN_ERROR" = 0 ]
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
  include_optional="${1:-0}"
  DOT_YES="${2:-0}"
  install_prepare "$include_optional" || return 1
  install_print_header "$include_optional"
  install_plan || return 1
  if [ "$INSTALL_MISSING_COUNT" = 0 ]; then
    dot_ok 'nothing to install'
    return 0
  fi
  if ! dot_confirm; then
    dot_warn 'installation cancelled'
    return 1
  fi
  install_execute
}

bootstrap_command() {
  include_optional="${1:-0}"
  DOT_YES="${2:-0}"
  DOCTOR_ALLOW_MISSING=1
  doctor_command --for-bootstrap || return 1
  install_prepare "$include_optional" || return 1
  install_print_header "$include_optional"
  install_plan || return 1
  dot_plan 'configuration deployment is deferred until Phase 2'
  if [ "$INSTALL_MISSING_COUNT" = 0 ]; then
    dot_ok 'nothing to install; no deployment performed'
    return 0
  fi
  if ! dot_confirm; then
    dot_warn 'bootstrap cancelled'
    return 1
  fi
  install_execute || return 1
  dot_ok 'bootstrap installation complete; run dot deploy after Phase 2 is implemented'
}
