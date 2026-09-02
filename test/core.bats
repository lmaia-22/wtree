setup() {
  load test_helper
}

@test "clone creates .bare and a worktree for the default branch" {
  wtree_setup_project main
  [ -d "$PROJECT_ROOT/.bare" ]
  [ -d "$PROJECT_ROOT/main" ]
  [ -f "$PROJECT_ROOT/.git" ]
}

@test "clone falls back to main when the remote has no HEAD symref (empty repo)" {
  cd "$BATS_TEST_TMPDIR"
  mkdir origin.git
  git -C origin.git init -q --bare --initial-branch=main
  # No commits at all — ls-remote --symref returns nothing.

  run "$WTREE_BIN" clone "$BATS_TEST_TMPDIR/origin.git" proj
  [ "$status" -eq 0 ]
  [ -d "proj/main" ]
}

@test "clone refuses if the target directory already exists" {
  cd "$BATS_TEST_TMPDIR"
  mkdir origin.git
  git -C origin.git init -q --bare --initial-branch=main
  mkdir proj

  run "$WTREE_BIN" clone "$BATS_TEST_TMPDIR/origin.git" proj
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "add creates a new branch and worktree when neither exists" {
  wtree_setup_project

  run "$WTREE_BIN" add feature/x
  [ "$status" -eq 0 ]
  [ -d "$PROJECT_ROOT/feature/x" ]
  git -C "$PROJECT_ROOT/.bare" show-ref --verify --quiet refs/heads/feature/x
}

@test "add checks out an existing local branch without -b" {
  wtree_setup_project
  git -C .bare branch feature/existing

  run "$WTREE_BIN" add feature/existing
  [ "$status" -eq 0 ]
  [ -d "$PROJECT_ROOT/feature/existing" ]
}

@test "add tracks origin/<branch> when a remote-only branch exists" {
  wtree_setup_project
  git -C main branch feature/remote-only
  git -C main push -q origin feature/remote-only
  git -C main branch -D feature/remote-only
  git -C .bare fetch origin --quiet

  run "$WTREE_BIN" add feature/remote-only
  [ "$status" -eq 0 ]
  run git -C "$PROJECT_ROOT/feature/remote-only" rev-parse --abbrev-ref --symbolic-full-name @{u}
  [ "$output" = "origin/feature/remote-only" ]
}

@test "add refuses a duplicate worktree for the same branch" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null

  run "$WTREE_BIN" add feature/x
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "rm removes a worktree and prunes" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null

  run "$WTREE_BIN" rm feature/x
  [ "$status" -eq 0 ]
  [ ! -d "$PROJECT_ROOT/feature/x" ]
  run git worktree list --porcelain
  [[ "$output" != *"feature/x"* ]]
}

@test "rm prunes stale worktree admin entries" {
  wtree_setup_project
  "$WTREE_BIN" add feature/a >/dev/null
  "$WTREE_BIN" add feature/b >/dev/null
  rm -rf "$PROJECT_ROOT/feature/b"   # simulate stale entry, bypassing wtree rm

  run "$WTREE_BIN" rm feature/a
  [ "$status" -eq 0 ]
  run git worktree list --porcelain
  [[ "$output" != *"feature/b"* ]]
}

@test "add works from a subdirectory of the project, not just the root" {
  wtree_setup_project
  cd main

  run "$WTREE_BIN" add feature/x
  [ "$status" -eq 0 ]
  [ -d "$PROJECT_ROOT/feature/x" ]
}

@test "list works from a subdirectory and shows all worktrees" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  cd feature/x

  run "$WTREE_BIN" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"main"* ]]
  [[ "$output" == *"feature/x"* ]]
}
