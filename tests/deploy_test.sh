#!/usr/bin/env bash

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$TEST_DIR/helpers.sh"

make_config_fixture() {
  make_fixture || return 1
  mkdir -p "$TEST_ROOT/global/.config" "$TEST_ROOT/platforms/wsl/.config"
  printf 'shared\n' > "$TEST_ROOT/global/.config/shared"
  printf 'platform\n' > "$TEST_ROOT/platforms/wsl/.config/platform"
}

clean_deploy_test() {
  make_config_fixture || return 1
  TEST_REAL_STOW=1 run_dot deploy --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  [ -L "$TEST_HOME/.config/shared" ] || { cleanup_fixture; fail 'shared file was not linked'; return 1; }
  [ -L "$TEST_HOME/.config/platform" ] || { cleanup_fixture; fail 'platform file was not linked'; return 1; }
  assert_contains "$TEST_HOME/.config/shared" 'shared' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

repeat_deploy_test() {
  make_config_fixture || return 1
  TEST_REAL_STOW=1 run_dot deploy --yes || { cleanup_fixture; return 1; }
  first_link_identity="$(stat -c %i "$TEST_HOME/.config/shared" 2>/dev/null || stat -f %i "$TEST_HOME/.config/shared")"
  TEST_REAL_STOW=1 run_dot deploy --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  second_link_identity="$(stat -c %i "$TEST_HOME/.config/shared" 2>/dev/null || stat -f %i "$TEST_HOME/.config/shared")"
  [ "$first_link_identity" = "$second_link_identity" ] || { cleanup_fixture; fail 'repeat deploy recreated an existing link'; return 1; }
  assert_contains "$TEST_OUTPUT" 'deployment has no unrelated conflicts' || { cleanup_fixture; return 1; }
  [ ! -d "$TEST_HOME/.local/state/dot/backups" ] || { cleanup_fixture; fail 'repeat deploy made a backup'; return 1; }
  cleanup_fixture
}

conflict_refusal_test() {
  make_config_fixture || return 1
  mkdir -p "$TEST_HOME/.config"
  printf 'keep me\n' > "$TEST_HOME/.config/shared"
  if TEST_REAL_STOW=1 run_dot deploy --yes; then
    cleanup_fixture
    fail 'conflicting deploy unexpectedly succeeded'
    return 1
  fi
  assert_contains "$TEST_ERROR" 'deploy stopped; no files changed' || { cleanup_fixture; return 1; }
  assert_contains "$TEST_HOME/.config/shared" 'keep me' || { cleanup_fixture; return 1; }
  [ ! -L "$TEST_HOME/.config/platform" ] || { cleanup_fixture; fail 'partial deploy created platform link'; return 1; }
  cleanup_fixture
}

adoption_and_restore_test() {
  make_config_fixture || return 1
  mkdir -p "$TEST_HOME/.config"
  printf 'old value\n' > "$TEST_HOME/.config/shared"
  TEST_REAL_STOW=1 run_dot deploy --adopt --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  [ -L "$TEST_HOME/.config/shared" ] || { cleanup_fixture; fail 'adopt did not deploy link'; return 1; }
  backup_dir=''
  for backup_dir in "$TEST_HOME/.local/state/dot/backups"/*; do [ -d "$backup_dir" ] && break; done
  [ -d "$backup_dir" ] || { cleanup_fixture; fail 'adoption backup was not created'; return 1; }
  assert_contains "$backup_dir/.config/shared" 'old value' || { cleanup_fixture; return 1; }
  backup_id="${backup_dir##*/}"
  TEST_REAL_STOW=1 run_dot backups restore "$backup_id" --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  [ ! -L "$TEST_HOME/.config/shared" ] || { cleanup_fixture; fail 'restore left repository link'; return 1; }
  assert_contains "$TEST_HOME/.config/shared" 'old value' || { cleanup_fixture; return 1; }
  TEST_REAL_STOW=1 run_dot backups remove "$backup_id" --yes || { cleanup_fixture; return 1; }
  [ ! -e "$backup_dir" ] || { cleanup_fixture; fail 'backup was not removed'; return 1; }
  cleanup_fixture
}

legacy_link_replacement_test() {
  make_config_fixture || return 1
  mkdir -p "$TEST_ROOT/old" "$TEST_HOME"
  printf 'old\n' > "$TEST_ROOT/old/shared"
  ln -s "$TEST_ROOT/old/shared" "$TEST_HOME/legacy"
  # The configured target is deliberately an old link into this repository.
  ln -s "$TEST_ROOT/old/shared" "$TEST_HOME/.config-shared" 2>/dev/null || true
  printf 'new\n' > "$TEST_ROOT/global/.config-shared"
  TEST_REAL_STOW=1 run_dot deploy --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  [ -L "$TEST_HOME/.config-shared" ] || { cleanup_fixture; fail 'legacy repository link was not replaced'; return 1; }
  [ ! -d "$TEST_HOME/.local/state/dot/backups" ] || { cleanup_fixture; fail 'legacy link required adoption'; return 1; }
  cleanup_fixture
}

folded_legacy_link_test() {
  make_config_fixture || return 1
  ln -s "$TEST_ROOT/global/.config" "$TEST_HOME/.config"
  TEST_REAL_STOW=1 run_dot deploy --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  [ -d "$TEST_HOME/.config" ] && [ ! -L "$TEST_HOME/.config" ] || { cleanup_fixture; fail 'folded legacy link was not replaced safely'; return 1; }
  [ -L "$TEST_HOME/.config/shared" ] || { cleanup_fixture; fail 'shared link missing after folded replacement'; return 1; }
  [ ! -d "$TEST_HOME/.local/state/dot/backups" ] || { cleanup_fixture; fail 'folded legacy link required adoption'; return 1; }
  cleanup_fixture
}

broken_legacy_link_test() {
  make_config_fixture || return 1
  ln -s "$TEST_ROOT/removed/shared" "$TEST_HOME/.config-shared"
  TEST_REAL_STOW=1 run_dot deploy --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  [ -L "$TEST_HOME/.config-shared" ] || { cleanup_fixture; fail 'broken repository link was not replaced'; return 1; }
  [ ! -d "$TEST_HOME/.local/state/dot/backups" ] || { cleanup_fixture; fail 'broken repository link required adoption'; return 1; }
  cleanup_fixture
}

source_adapter_link_test() {
  make_config_fixture || return 1
  mv "$TEST_ROOT/global/.config/shared" "$TEST_ROOT/global/.config/shared-real"
  ln -s shared-real "$TEST_ROOT/global/.config/shared"
  TEST_REAL_STOW=1 run_dot deploy --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  [ -L "$TEST_HOME/.config/shared" ] || { cleanup_fixture; fail 'source adapter link was not deployed'; return 1; }
  cleanup_fixture
}

repository_escape_link_test() {
  make_config_fixture || return 1
  mkdir -p "$TEST_TMP/foreign" "$TEST_HOME/.config"
  ln -s "$TEST_TMP/foreign" "$TEST_ROOT/escape"
  ln -s "$TEST_ROOT/escape/shared" "$TEST_HOME/.config/shared"
  if TEST_REAL_STOW=1 run_dot deploy --yes; then
    cleanup_fixture
    fail 'repository escape link was treated as owned'
    return 1
  fi
  [ -L "$TEST_HOME/.config/shared" ] || { cleanup_fixture; fail 'escape link was changed'; return 1; }
  cleanup_fixture
}

dangling_repository_escape_link_test() {
  make_config_fixture || return 1
  mkdir -p "$TEST_TMP/foreign" "$TEST_HOME/.config"
  ln -s "$TEST_TMP/foreign/missing" "$TEST_ROOT/escape"
  ln -s "$TEST_ROOT/escape/shared" "$TEST_HOME/.config/shared"
  if TEST_REAL_STOW=1 run_dot deploy --yes; then
    cleanup_fixture
    fail 'dangling repository escape link was treated as owned'
    return 1
  fi
  [ -L "$TEST_HOME/.config/shared" ] || { cleanup_fixture; fail 'dangling escape link was changed'; return 1; }
  cleanup_fixture
}

empty_directory_preservation_test() {
  make_config_fixture || return 1
  mkdir -p "$TEST_HOME/.config"
  TEST_REAL_STOW=1 run_dot deploy --yes || { cleanup_fixture; return 1; }
  TEST_REAL_STOW=1 run_dot undeploy --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  [ -d "$TEST_HOME/.config" ] && [ ! -L "$TEST_HOME/.config" ] || { cleanup_fixture; fail 'pre-existing directory was removed'; return 1; }
  cleanup_fixture
}

backup_metadata_validation_test() {
  make_config_fixture || return 1
  mkdir -p "$TEST_HOME/.local/state/dot/backups/unsafe"
  printf '../outside\n' > "$TEST_HOME/.local/state/dot/backups/unsafe/.dot-backup-roots"
  printf 'unsafe\n' > "$TEST_HOME/.local/state/dot/backups/unsafe/payload"
  if TEST_REAL_STOW=1 run_dot backups restore unsafe --yes; then
    cleanup_fixture
    fail 'unsafe backup metadata was accepted'
    return 1
  fi
  [ ! -e "$TEST_TMP/outside" ] || { cleanup_fixture; fail 'unsafe restore escaped HOME'; return 1; }
  cleanup_fixture
}

backup_overlap_validation_test() {
  make_config_fixture || return 1
  mkdir -p "$TEST_HOME/.local/state/dot/backups/overlap/tree/link"
  printf 'tree\ntree/link/file\n' > "$TEST_HOME/.local/state/dot/backups/overlap/.dot-backup-roots"
  printf 'payload\n' > "$TEST_HOME/.local/state/dot/backups/overlap/tree/link/file"
  if TEST_REAL_STOW=1 run_dot backups restore overlap --yes; then
    cleanup_fixture
    fail 'overlapping backup metadata was accepted'
    return 1
  fi
  cleanup_fixture
}

backup_duplicate_validation_test() {
  make_config_fixture || return 1
  mkdir -p "$TEST_HOME/.local/state/dot/backups/duplicate/tree"
  printf 'tree\ntree\n' > "$TEST_HOME/.local/state/dot/backups/duplicate/.dot-backup-roots"
  printf 'payload\n' > "$TEST_HOME/.local/state/dot/backups/duplicate/tree/file"
  if TEST_REAL_STOW=1 run_dot backups restore duplicate --yes; then
    cleanup_fixture
    fail 'duplicate backup metadata was accepted'
    return 1
  fi
  cleanup_fixture
}

backup_symlink_id_validation_test() {
  make_config_fixture || return 1
  mkdir -p "$TEST_HOME/.local/state/dot/backups" "$TEST_TMP/external-backup"
  ln -s "$TEST_TMP/external-backup" "$TEST_HOME/.local/state/dot/backups/unsafe"
  if TEST_REAL_STOW=1 run_dot backups restore unsafe --yes; then
    cleanup_fixture
    fail 'external backup symlink was accepted'
    return 1
  fi
  cleanup_fixture
}

ancestor_backup_restore_test() {
  make_config_fixture || return 1
  mkdir -p "$TEST_TMP/foreign"
  printf 'foreign\n' > "$TEST_TMP/foreign/shared"
  ln -s "$TEST_TMP/foreign" "$TEST_HOME/.config"
  TEST_REAL_STOW=1 run_dot deploy --adopt --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  backup_dir=''
  for backup_dir in "$TEST_HOME/.local/state/dot/backups"/*; do [ -d "$backup_dir" ] && break; done
  [ -d "$backup_dir" ] || { cat "$TEST_OUTPUT"; cat "$TEST_ERROR" >&2; cleanup_fixture; fail 'ancestor backup missing'; return 1; }
  backup_id="${backup_dir##*/}"
  TEST_REAL_STOW=1 run_dot backups restore "$backup_id" --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  [ -L "$TEST_HOME/.config" ] || { cleanup_fixture; fail 'ancestor symlink was not restored'; return 1; }
  [ "$(readlink "$TEST_HOME/.config")" = "$TEST_TMP/foreign" ] || { cleanup_fixture; fail 'wrong ancestor symlink restored'; return 1; }
  cleanup_fixture
}

undeploy_safety_test() {
  make_config_fixture || return 1
  TEST_REAL_STOW=1 run_dot deploy --yes || { cleanup_fixture; return 1; }
  printf unrelated > "$TEST_HOME/unrelated"
  ln -s "$TEST_HOME/unrelated" "$TEST_HOME/foreign-link"
  TEST_REAL_STOW=1 run_dot undeploy --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  [ ! -e "$TEST_HOME/.config/shared" ] || { cleanup_fixture; fail 'owned shared link remained'; return 1; }
  [ -L "$TEST_HOME/foreign-link" ] || { cleanup_fixture; fail 'unrelated link was removed'; return 1; }
  cleanup_fixture
}

backup_prune_test() {
  make_config_fixture || return 1
  mkdir -p "$TEST_HOME/.config"
  printf 'old value\n' > "$TEST_HOME/.config/shared"
  TEST_REAL_STOW=1 run_dot deploy --adopt --yes || { cleanup_fixture; return 1; }
  backup_dir=''
  for backup_dir in "$TEST_HOME/.local/state/dot/backups"/*; do [ -d "$backup_dir" ] && break; done
  [ -d "$backup_dir" ] || { cleanup_fixture; fail 'prune fixture backup missing'; return 1; }
  touch -t 200001010000 "$backup_dir"
  TEST_REAL_STOW=1 run_dot backups prune --older-than 2d --yes || { cat "$TEST_ERROR" >&2; cleanup_fixture; return 1; }
  [ ! -e "$backup_dir" ] || { cleanup_fixture; fail 'old backup was not pruned'; return 1; }
  TEST_REAL_STOW=1 run_dot backups list || { cleanup_fixture; return 1; }
  assert_contains "$TEST_OUTPUT" 'no backups' || { cleanup_fixture; return 1; }
  cleanup_fixture
}

partial_failure_test() {
  make_config_fixture || return 1
  cat > "$TEST_BIN/stow" <<'EOF'
#!/bin/bash
case "$*" in
  *' wsl') exit 1 ;;
  *) exec "$REAL_STOW" "$@" ;;
esac
EOF
  chmod +x "$TEST_BIN/stow"
  if TEST_REAL_STOW=1 TEST_KEEP_STOW=1 run_dot deploy --yes; then
    cleanup_fixture
    fail 'failed second layer unexpectedly succeeded'
    return 1
  fi
  [ ! -e "$TEST_HOME/.config/shared" ] || { cleanup_fixture; fail 'partial deployment remained after failure'; return 1; }
  [ ! -e "$TEST_HOME/.config/platform" ] || { cleanup_fixture; fail 'failed platform deployment left a link'; return 1; }
  cleanup_fixture
}

undeploy_rollback_test() {
  make_config_fixture || return 1
  TEST_REAL_STOW=1 run_dot deploy --yes || { cleanup_fixture; return 1; }
  cat > "$TEST_BIN/stow" <<'EOF'
#!/bin/bash
if [ "$1" = -D ] && [ "${STOW_FAIL_ONCE:-0}" = 1 ] && case "$*" in *' wsl') true ;; *) false ;; esac && [ ! -e "$FAIL_MARKER" ]; then
  : > "$FAIL_MARKER"
  exit 1
fi
exec "$REAL_STOW" "$@"
EOF
  chmod +x "$TEST_BIN/stow"
  if STOW_FAIL_ONCE=1 FAIL_MARKER="$TEST_TMP/fail-marker" TEST_REAL_STOW=1 TEST_KEEP_STOW=1 run_dot undeploy --yes; then
    cleanup_fixture
    fail 'failed undeploy unexpectedly succeeded'
    return 1
  fi
  [ -L "$TEST_HOME/.config/shared" ] || { cleanup_fixture; fail 'undeploy rollback lost shared link'; return 1; }
  [ -L "$TEST_HOME/.config/platform" ] || { cleanup_fixture; fail 'undeploy rollback lost platform link'; return 1; }
  cleanup_fixture
}

clean_deploy_test && repeat_deploy_test && conflict_refusal_test && adoption_and_restore_test && legacy_link_replacement_test && folded_legacy_link_test && broken_legacy_link_test && source_adapter_link_test && repository_escape_link_test && dangling_repository_escape_link_test && empty_directory_preservation_test && backup_metadata_validation_test && backup_overlap_validation_test && backup_duplicate_validation_test && backup_symlink_id_validation_test && ancestor_backup_restore_test && undeploy_safety_test && backup_prune_test && partial_failure_test && undeploy_rollback_test
