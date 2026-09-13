# Ubuntu packages keep these executable names. Scripts should use the actual
# names too; interactive aliases deliberately do not install system-wide shims.
command -v fdfind >/dev/null 2>&1 && alias fd='fdfind'
command -v batcat >/dev/null 2>&1 && alias bat='batcat'
