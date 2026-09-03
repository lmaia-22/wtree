setup() {
  load test_helper
}

@test "a worktree with a missing directory is categorized BROKEN" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  rm -rf feature/x

  run "$WTREE_BIN" clean <<<"n"
  [[ "$output" == *"BROKEN"* ]] || return 1
  [[ "$output" == *"feature/x"* ]] || return 1
  [[ "$output" != *"MERGED"* ]]
}

@test "a worktree whose remote branch is gone (after prune) is categorized MERGED" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  git -C feature/x push -q -u origin feature/x
  git push -q origin --delete feature/x

  run "$WTREE_BIN" clean <<<"n"
  [[ "$output" == *"MERGED"* ]] || return 1
  [[ "$output" == *"feature/x"* ]] || return 1
  [[ "$output" != *"BROKEN"* ]]
}

@test "a merged branch with uncommitted changes is SKIPPED, not auto-deleted" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  git -C feature/x push -q -u origin feature/x
  git push -q origin --delete feature/x
  echo "uncommitted" >feature/x/scratch.txt

  run "$WTREE_BIN" clean <<<"n"
  [[ "$output" == *"SKIPPED"* ]] || return 1
  [[ "$output" == *"feature/x"* ]] || return 1
  [[ "$output" != *"MERGED"* ]]
}

@test "a branch that was never pushed is left alone entirely" {
  wtree_setup_project
  "$WTREE_BIN" add feature/never-pushed >/dev/null

  run "$WTREE_BIN" clean
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"nothing to clean"* ]]
}

@test "declining the confirmation prompt leaves everything untouched" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  rm -rf feature/x

  run "$WTREE_BIN" clean <<<"n"
  [[ "$output" == *"aborted"* ]] || return 1
  run git worktree list --porcelain
  [[ "$output" == *"feature/x"* ]]
}

@test "confirming removes BROKEN registration but keeps the local branch" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  rm -rf feature/x

  run "$WTREE_BIN" clean <<<"y"
  [ "$status" -eq 0 ] || return 1
  run git worktree list --porcelain
  [[ "$output" != *"feature/x"* ]] || return 1
  run git -C .bare branch --list feature/x
  [[ -n "$output" ]]
}

@test "confirming removes both worktree and branch for a MERGED entry" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  git -C feature/x push -q -u origin feature/x
  git push -q origin --delete feature/x

  run "$WTREE_BIN" clean <<<"y"
  [ "$status" -eq 0 ] || return 1
  [ ! -d "$PROJECT_ROOT/feature/x" ] || return 1
  run git -C .bare branch --list feature/x
  [ -z "$output" ]
}

@test "clean on a project with nothing to clean exits 0 without prompting" {
  wtree_setup_project

  run "$WTREE_BIN" clean
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"nothing to clean"* ]]
}
