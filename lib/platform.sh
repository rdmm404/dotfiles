#!/usr/bin/env bash

platform_detect() {
  if [ -n "${DOT_PLATFORM:-}" ]; then
    case "$DOT_PLATFORM" in
      macos|omarchy|ubuntu) PLATFORM="$DOT_PLATFORM"; return 0 ;;
      *) dot_error "unsupported platform override: $DOT_PLATFORM"; return 1 ;;
    esac
  fi

  case "$(uname -s 2>/dev/null || printf unknown)" in
    Darwin)
      PLATFORM=macos
      ;;
    Linux)
      if [ -n "${OMARCHY:-}" ] || [ -f /etc/omarchy-release ] || \
        { [ -r /etc/os-release ] && grep -qi omarchy /etc/os-release; }; then
        PLATFORM=omarchy
      elif [ -r "${DOT_OS_RELEASE:-/etc/os-release}" ] &&
        ( . "${DOT_OS_RELEASE:-/etc/os-release}"; [ "${ID:-}" = ubuntu ] ); then
        PLATFORM=ubuntu
      else
        dot_error 'could not detect a supported platform (expected macOS, Omarchy, or Ubuntu)'
        return 1
      fi
      ;;
    *)
      dot_error 'could not detect a supported platform (expected macOS, Omarchy, or Ubuntu)'
      return 1
      ;;
  esac
  return 0
}

platform_label() {
  case "$1" in
    macos) printf 'macOS' ;;
    omarchy) printf 'Omarchy' ;;
    ubuntu) printf 'Ubuntu' ;;
    *) printf '%s' "$1" ;;
  esac
}

platform_load_installer() {
  case "$1" in
    macos) . "$DOT_ROOT/installers/macos.sh" ;;
    omarchy) . "$DOT_ROOT/installers/omarchy.sh" ;;
    ubuntu) . "$DOT_ROOT/installers/ubuntu.sh" ;;
    *) dot_error "no installer for platform: $1"; return 1 ;;
  esac
}
