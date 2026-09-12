#!/usr/bin/env bash

# Runtime checks only. Missing optional apps are useful detail, not problems.
doctor_command() {
  local verbose="${1:-0}" app missing=0 deployment=0
  local args=(check)
  platform_detect || return 1
  platform_load_installer "$PLATFORM" || return 1
  manifest_load 1 || return 1
  if [ "$verbose" = 1 ]; then
    printf 'Platform: %s\n' "$(platform_label "$PLATFORM")"
    args[1]=--verbose
  fi
  if ! files_command "${args[@]}"; then
    deployment=1
    dot_error 'deployment needs attention; run dot deploy --dry-run'
  fi
  for app in "${APPS[@]}"; do
    app_status "$app"
    case "$APP_STATUS" in
      installed) [ "$verbose" = 1 ] && dot_ok "available: $app" ;;
      unsupported) [ "$verbose" = 1 ] && dot_skip "unsupported on $PLATFORM: $app" ;;
      missing)
        dot_error "missing required application: $app"
        missing=$((missing + 1))
        ;;
    esac
  done
  for app in "${OPTIONAL_APPS[@]}"; do
    app_status "$app"
    case "$APP_STATUS" in
      installed) dot_ok "available (optional): $app" ;;
      unsupported) dot_skip "unsupported on $PLATFORM: $app" ;;
      missing) dot_warn "missing optional application: $app" ;;
    esac
  done
  [ "$missing" = 0 ] || dot_error "$missing required application(s) missing; run dot install"
  [ "$missing" = 0 ] && [ "$deployment" = 0 ] || return 1
  dot_ok 'doctor found no blocking problems'
}
