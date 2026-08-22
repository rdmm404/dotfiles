focusd_start() {
  omarchy plugin enable bibek.focusd || return

  focusd start || {
    local exit_status=$?
    omarchy plugin disable bibek.focusd
    return "$exit_status"
  }
}

focusd_stop() {
  focusd stop
  local exit_status=$?
  omarchy plugin disable bibek.focusd || return
  return "$exit_status"
}
