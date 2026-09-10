#!/usr/bin/env bash

# Common output and interaction helpers. Keep this file Bash 3.2 compatible.

dot_ok() { printf '[ok]   %s\n' "$*"; }
dot_skip() { printf '[skip] %s\n' "$*"; }
dot_warn() { printf '[warn] %s\n' "$*"; }
dot_error() { printf '[error] %s\n' "$*" >&2; }

dot_change() { printf '[change] %s\n' "$*"; }

# Filesystem operations live in lib/files.py. Keep this small bridge in Bash so
# platform detection and the Python process agree about the active platform.
files_command() {
  platform_detect || return 1
  if ! command -v python3 >/dev/null 2>&1; then
    dot_error 'python3 is required for filesystem commands'
    return 1
  fi
  [ -f "$DOT_ROOT/lib/files.py" ] || {
    dot_error "filesystem helper is missing: $DOT_ROOT/lib/files.py"
    return 1
  }
  DOT_PLATFORM="$PLATFORM" python3 "$DOT_ROOT/lib/files.py" "$@"
}

dot_usage() {
  cat <<'EOF'
Usage: dot <command> [options]

Commands:
  doctor                         Check deployed configuration and required apps
  install [options]              Install missing applications
  bootstrap [options]            Install applications and deploy configuration
  deploy [options]               Deploy configuration into HOME
  undeploy [options]             Remove repository-owned links
  add PATH... (--global|--platform)  Import files or directories into a layer
  backups <command>              List or manage replacement backups
  help [command]                 Show help

Options for install and bootstrap:
  --include optional             Include the optional manifest
  --dry-run                      Preview changes without writing
  --verbose                      List unchanged/installed items

Run 'dot help <command>' for command-specific help.
EOF
}

dot_command_usage() {
  case "${1:-}" in
    doctor)
      cat <<'EOF'
Usage: dot doctor [--verbose]
Check the current deployment and required applications without changing anything.
Optional applications that are missing do not block the check.
EOF
      ;;
    install)
      cat <<'EOF'
Usage: dot install [--include optional] [--dry-run] [--verbose]
Install missing applications. Invocation is consent; --dry-run previews only.
EOF
      ;;
    bootstrap)
      cat <<'EOF'
Usage: dot bootstrap [--include optional] [--dry-run] [--verbose] [--replace]
Install missing applications, then deploy configuration.
--replace allows deployment to replace conflicting paths.
EOF
      ;;
    deploy)
      files_command deploy --help
      ;;
    undeploy)
      files_command undeploy --help
      ;;
    add)
      files_command add --help
      ;;
    backups)
      files_command backups --help
      ;;
    'backups list'|'backups restore'|'backups remove'|'backups prune')
      files_command backups "${1#backups }" --help
      ;;
    *)
      dot_usage
      return 2
      ;;
  esac
}

dot_bad_args() {
  dot_error "$1"
  dot_command_usage "$2" >&2
  return 2
}
