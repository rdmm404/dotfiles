#!/usr/bin/env bash

# Common output and interaction helpers. Keep this file Bash 3.2 compatible.

dot_plan() { printf '[plan] %s\n' "$*"; }
dot_ok() { printf '[ok]   %s\n' "$*"; }
dot_skip() { printf '[skip] %s\n' "$*"; }
dot_warn() { printf '[warn] %s\n' "$*"; }
dot_error() { printf '[error] %s\n' "$*" >&2; }

dot_confirm() {
  if [ "${DOT_YES:-0}" = 1 ]; then
    return 0
  fi

  printf 'Continue? [y/N] ' >&2
  read -r answer || return 1
  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

dot_usage() {
  cat <<'EOF'
Usage: dot <command> [options]

Commands:
  doctor                         Check repository and system readiness
  plan [--include optional]     Show the installation plan
  install [options]              Install missing applications
  bootstrap [options]            Install and deploy configuration
  deploy [options]               Link configuration into HOME
  undeploy [--yes]               Remove repository-owned links
  backups <list|restore|remove|prune> Manage adoption backups
  help [command]                 Show help

Options for install and bootstrap:
  --include optional             Include the optional manifest
  --yes                          Do not ask for confirmation

Run 'dot help <command>' for command-specific help.
EOF
}

dot_command_usage() {
  case "${1:-}" in
    doctor)
      cat <<'EOF'
Usage: dot doctor
Check platform, manifests, required commands, syntax, and configuration checks.
This command never changes the system.
EOF
      ;;
    plan)
      cat <<'EOF'
Usage: dot plan [--include optional]
Show installed, missing, and unsupported applications without changing anything.
Example: dot plan --include optional
EOF
      ;;
    install)
      cat <<'EOF'
Usage: dot install [--include optional] [--yes]
Install only missing applications; existing applications are never upgraded.
Example: dot install --yes
EOF
      ;;
    bootstrap)
      cat <<'EOF'
Usage: dot bootstrap [--include optional] [--yes]
Install missing applications and deploy configuration after one confirmation.
Existing conflicts stop bootstrap; use dot deploy --adopt separately.
Example: dot bootstrap --yes
EOF
      ;;
    deploy)
      cat <<'EOF'
Usage: dot deploy [--adopt] [--yes]
Link global and current-platform configuration into HOME.
--adopt backs up conflicts before replacing them; it never uses Stow --adopt.
EOF
      ;;
    undeploy)
      cat <<'EOF'
Usage: dot undeploy [--yes]
Remove only links owned by the global and current-platform layers.
EOF
      ;;
    backups)
      cat <<'EOF'
Usage: dot backups <list|restore|remove|prune> [options]
  list
  restore <timestamp> [--yes]
  remove <timestamp> [--yes]
  prune --older-than <days>d [--yes]
EOF
      ;;
    'backups list'|'backups restore'|'backups remove'|'backups prune')
      dot_command_usage backups
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
