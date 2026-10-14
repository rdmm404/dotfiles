# Manually restore access to root-written files; nothing runs at shell startup.
# Recursive: use a narrow service directory, not your whole home/services tree.
function acl_fix() {
  if (( $# == 0 )); then
    print -u2 'Usage: acl_fix <directory> [directory...]'
    return 1
  fi

  local acl_user directory failed=0
  acl_user=$(id -un) || return 1

  for directory in "$@"; do
    if [[ ! -d "$directory" ]]; then
      print -u2 "Error: '$directory' is not a directory"
      failed=1
      continue
    fi

    print "Setting ACLs on $directory for user $acl_user..."
    if sudo setfacl -R -m "u:${acl_user}:rwX,m::rwX" -- "$directory" &&
       sudo setfacl -R -d -m "u:${acl_user}:rwX,m::rwX" -- "$directory"; then
      print "Done: $directory"
    else
      failed=1
    fi
  done

  return "$failed"
}
