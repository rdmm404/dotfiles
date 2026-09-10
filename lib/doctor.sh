#!/usr/bin/env bash

# Doctor is intentionally a runtime check. Repository linting, shell syntax
# checks, and checks for inactive platforms belong in development tooling, not
# in the command a user runs to assess the current deployment.
doctor_check_apps_in_manifest() {
  doctor_apps_manifest="$1"
  doctor_apps_required="${2:-1}"
  manifest_read "$doctor_apps_manifest" || return 1
  doctor_apps_entry=''
  while IFS= read -r doctor_apps_entry || [ -n "$doctor_apps_entry" ]; do
    [ -z "$doctor_apps_entry" ] && continue
    if ! installer_status "$doctor_apps_entry"; then
      dot_error "unknown application for $PLATFORM: $doctor_apps_entry"
      [ "$doctor_apps_required" = 1 ] && DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
    elif [ "$INSTALLER_STATUS" = installed ]; then
      [ "${DOCTOR_VERBOSE:-0}" = 1 ] && dot_ok "available: $doctor_apps_entry"
    elif [ "$INSTALLER_STATUS" = unsupported ]; then
      dot_skip "unsupported on $PLATFORM: $doctor_apps_entry"
    elif [ "$doctor_apps_required" = 1 ]; then
      dot_error "missing required application: $doctor_apps_entry"
      DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
    else
      dot_warn "missing optional application: $doctor_apps_entry"
    fi
  done <<EOF
$MANIFEST_ENTRIES
EOF
}

doctor_check_deployment() {
  if [ "${DOCTOR_VERBOSE:-0}" = 1 ]; then
    files_command check --verbose
  else
    files_command check
  fi
  if [ "$?" != 0 ]; then
    dot_error 'runtime deployment check found blocking problems'
    DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
  fi
}

doctor_command() {
  DOCTOR_PROBLEMS=0
  DOCTOR_VERBOSE="${1:-0}"
  [ "$#" = 0 ] || [ "$#" = 1 ] || {
    dot_error "invalid doctor argument: $2"
    return 2
  }

  platform_detect || return 1
  platform_load_installer "$PLATFORM" || return 1
  printf 'Platform: %s\n' "$(platform_label "$PLATFORM")"

  # Validate the manifests before asking installers about their entries. This
  # retains the manifest API and gives a useful error for a malformed catalog,
  # while only the required manifests can make the runtime app check fail.
  if ! manifest_validate_all; then
    return 1
  fi

  doctor_check_deployment
  doctor_check_apps_in_manifest "$DOT_ROOT/manifests/core" 1 ||
    DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
  doctor_check_apps_in_manifest "$DOT_ROOT/manifests/development" 1 ||
    DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
  doctor_check_apps_in_manifest "$DOT_ROOT/manifests/optional" 0 ||
    DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))

  if [ "$DOCTOR_PROBLEMS" = 0 ]; then
    dot_ok 'doctor found no blocking problems'
    return 0
  fi
  dot_error "doctor found $DOCTOR_PROBLEMS blocking problem(s)"
  return 1
}
