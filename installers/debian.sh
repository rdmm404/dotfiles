#!/usr/bin/env bash

# Debian 13 and Ubuntu share the selected APT package mappings, Zap plugins,
# and pinned Linux binaries. Keep one implementation; platform manifests choose
# applications independently of deployment files (notably Nautilus backups).
. "$DOT_ROOT/installers/ubuntu.sh"
