function pi() {
  command -v fnm >/dev/null 2>&1 || { echo 'fnm is required for pi' >&2; return 1; }
  fnm exec --using=24 -- pi "$@"
}
