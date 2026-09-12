#!/usr/bin/env bash

install_command() {
  local include="${1:-0}" dry_run="${2:-0}" verbose="${3:-0}"
  local app installed=0 unchanged=0 unsupported=0 failed=0
  platform_detect || return 1
  platform_load_installer "$PLATFORM" || return 1
  manifest_load "$include" || return 1
  [ "$verbose" = 1 ] && printf 'Platform: %s\n' "$(platform_label "$PLATFORM")"

  for app in "${APPS[@]}" "${OPTIONAL_APPS[@]}"; do
    app_status "$app"
    case "$APP_STATUS" in
      installed)
        unchanged=$((unchanged + 1))
        [ "$verbose" = 1 ] && dot_ok "already installed: $app"
        ;;
      unsupported)
        unsupported=$((unsupported + 1))
        [ "$verbose" = 1 ] && dot_skip "unsupported on $(platform_label "$PLATFORM"): $app"
        ;;
      missing)
        if [ "$dry_run" = 1 ]; then
          dot_change "will install: $app"
          installed=$((installed + 1))
        else
          dot_change "installing: $app"
          if installer_install "$app"; then
            app_status "$app"
            if [ "$APP_STATUS" = installed ]; then
              installed=$((installed + 1))
              continue
            fi
            dot_error "installer completed but application is still missing: $app"
          else
            dot_error "failed to install: $app"
          fi
          failed=$((failed + 1))
        fi
        ;;
    esac
  done
  if [ "$dry_run" = 1 ]; then
    dot_ok "dry run: $installed to install; unchanged: $unchanged; unsupported: $unsupported"
  else
    dot_ok "installed: $installed; unchanged: $unchanged; unsupported: $unsupported; failed: $failed"
  fi
  [ "$failed" = 0 ]
}

bootstrap_command() {
  local include="${1:-0}" dry_run="${2:-0}" verbose="${3:-0}" replace="${4:-0}"
  local args=(deploy)
  install_command "$include" "$dry_run" "$verbose" || return 1
  command -v python3 >/dev/null 2>&1 || {
    dot_error 'python3 is required for bootstrap deployment; install it separately'
    return 1
  }
  [ "$dry_run" = 1 ] && args[${#args[@]}]=--dry-run
  [ "$verbose" = 1 ] && args[${#args[@]}]=--verbose
  [ "$replace" = 1 ] && args[${#args[@]}]=--replace
  files_command "${args[@]}"
}
