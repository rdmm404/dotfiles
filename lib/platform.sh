#!/usr/bin/env bash

platform_detect() {
  if [ -n "${DOT_PLATFORM:-}" ]; then
    case "$DOT_PLATFORM" in
      macos|wsl|omarchy) PLATFORM="$DOT_PLATFORM"; return 0 ;;
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
      elif [ -n "${WSL_DISTRO_NAME:-}" ] || \
        { [ -r /proc/version ] && grep -qi microsoft /proc/version; }; then
        PLATFORM=wsl
      else
        dot_error 'could not detect a supported platform (expected macOS, WSL, or Omarchy)'
        return 1
      fi
      ;;
    *)
      dot_error 'could not detect a supported platform (expected macOS, WSL, or Omarchy)'
      return 1
      ;;
  esac
  return 0
}

platform_label() {
  case "$1" in
    macos) printf 'macOS' ;;
    wsl) printf 'WSL' ;;
    omarchy) printf 'Omarchy' ;;
    *) printf '%s' "$1" ;;
  esac
}

platform_load_installer() {
  case "$1" in
    macos) . "$DOT_ROOT/installers/macos.sh" ;;
    wsl) . "$DOT_ROOT/installers/wsl.sh" ;;
    omarchy) . "$DOT_ROOT/installers/omarchy.sh" ;;
    *) dot_error "no installer for platform: $1"; return 1 ;;
  esac
}
