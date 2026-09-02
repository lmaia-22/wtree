setup() {
  load test_helper
}

@test "switch <branch> prints only the resolved path to stdout" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null

  run --separate-stderr "$WTREE_BIN" switch feature/x
  [ "$status" -eq 0 ]
  [ "$output" = "$PROJECT_ROOT/feature/x" ]
  [ -z "$stderr" ]
}

@test "switch <nonexistent-branch> fails via die() on stderr, stdout stays empty" {
  wtree_setup_project

  run --separate-stderr "$WTREE_BIN" switch does-not-exist
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"no worktree for branch"* ]]
}

@test "switch with no argument and no fzf on PATH fails with a clear message" {
  wtree_setup_project
  PATH=/usr/bin:/bin

  run --separate-stderr "$WTREE_BIN" switch
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"fzf not found"* ]]
}
