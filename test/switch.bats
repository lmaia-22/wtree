setup() {
  load test_helper
}

@test "switch <branch> prints only the resolved path to stdout" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null

  run --separate-stderr "$WTREE_BIN" switch feature/x
  [ "$status" -eq 0 ] || return 1
  [ "$output" = "$PROJECT_ROOT/feature/x" ] || return 1
  [ -z "$stderr" ]
}

@test "switch <nonexistent-branch> fails via die() on stderr, stdout stays empty" {
  wtree_setup_project

  run --separate-stderr "$WTREE_BIN" switch does-not-exist
  [ "$status" -ne 0 ] || return 1
  [ -z "$output" ] || return 1
  [[ "$stderr" == *"no worktree for branch"* ]]
}

@test "switch with no argument and no fzf on PATH fails with a clear message" {
  wtree_setup_project
  wtree_drop_fzf_from_path

  run --separate-stderr "$WTREE_BIN" switch
  [ "$status" -ne 0 ] || return 1
  [ -z "$output" ] || return 1
  [[ "$stderr" == *"fzf not found"* ]]
}
