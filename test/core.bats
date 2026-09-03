setup() {
  load test_helper
}

@test "clone creates .bare and a worktree for the default branch" {
  wtree_setup_project main
  [ -d "$PROJECT_ROOT/.bare" ] || return 1
  [ -d "$PROJECT_ROOT/main" ] || return 1
  [ -f "$PROJECT_ROOT/.git" ]
}

@test "clone falls back to main when the remote has no HEAD symref (empty repo)" {
  cd "$BATS_TEST_TMPDIR"
  mkdir origin.git
  git -C origin.git init -q --bare --initial-branch=main
  # No commits at all — ls-remote --symref returns nothing.

  run "$WTREE_BIN" clone "$BATS_TEST_TMPDIR/origin.git" proj
  [ "$status" -eq 0 ] || return 1
  [ -d "proj/main" ]
}

@test "clone refuses if the target directory already exists" {
  cd "$BATS_TEST_TMPDIR"
  mkdir origin.git
  git -C origin.git init -q --bare --initial-branch=main
  mkdir proj

  run "$WTREE_BIN" clone "$BATS_TEST_TMPDIR/origin.git" proj
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"already exists"* ]]
}

@test "clone refuses a name argument containing a path separator" {
  cd "$BATS_TEST_TMPDIR"
  mkdir origin.git
  git -C origin.git init -q --bare --initial-branch=main

  run "$WTREE_BIN" clone "$BATS_TEST_TMPDIR/origin.git" nested/dir
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"plain directory name"* ]]
}

@test "add creates a new branch and worktree when neither exists" {
  wtree_setup_project

  run "$WTREE_BIN" add feature/x
  [ "$status" -eq 0 ] || return 1
  [ -d "$PROJECT_ROOT/feature/x" ] || return 1
  git -C "$PROJECT_ROOT/.bare" show-ref --verify --quiet refs/heads/feature/x
}

@test "add checks out an existing local branch without -b" {
  wtree_setup_project
  git -C .bare branch feature/existing

  run "$WTREE_BIN" add feature/existing
  [ "$status" -eq 0 ] || return 1
  [ -d "$PROJECT_ROOT/feature/existing" ]
}

@test "add tracks origin/<branch> when a remote-only branch exists" {
  wtree_setup_project
  git -C main branch feature/remote-only
  git -C main push -q origin feature/remote-only
  git -C main branch -D feature/remote-only
  git -C .bare fetch origin --quiet

  run "$WTREE_BIN" add feature/remote-only
  [ "$status" -eq 0 ] || return 1
  run git -C "$PROJECT_ROOT/feature/remote-only" rev-parse --abbrev-ref --symbolic-full-name @{u}
  [ "$output" = "origin/feature/remote-only" ]
}

@test "add refuses a duplicate worktree for the same branch" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null

  run "$WTREE_BIN" add feature/x
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"already exists"* ]]
}

@test "add refuses a nested branch name blocked by a shorter existing branch" {
  # Regression test: git stores branches like directory paths under
  # refs/heads/, so 'feature/p' and 'feature/p/1/23' can never coexist
  # - git's own raw error ("cannot lock ref ... exists") is confusing,
  # so wtree catches this before attempting the git operation.
  #
  # Every non-final assertion below ends in `|| return 1`: a bats test
  # body runs in a context where its own exit status is being tested
  # by the harness, which (per bash's set -e semantics for functions
  # called in a tested context) strips errexit from everything inside
  # it - a bare failing assertion does NOT stop or fail the test if any
  # later command (another assertion, another `run`, anything) happens
  # to exit 0 afterward. Only the test's literal last statement, or an
  # explicit `return`/`exit`, reliably determines pass/fail. Verified
  # this empirically (including inside the fix this test guards)
  # before adopting it as the house style for every test with more
  # than one assertion.
  wtree_setup_project
  "$WTREE_BIN" add feature/p >/dev/null

  run "$WTREE_BIN" add feature/p/1/23
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"'feature/p' already exists and blocks it"* ]] || return 1
  [ ! -d "$PROJECT_ROOT/feature/p/1" ]
}

@test "add refuses a short branch name blocked by a longer existing branch" {
  wtree_setup_project
  "$WTREE_BIN" add feature/p/1 >/dev/null

  run "$WTREE_BIN" add feature/p
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"'feature/p/1' already exists and blocks it"* ]]
}

@test "add still allows sibling branches under the same prefix" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null

  run "$WTREE_BIN" add feature/y
  [ "$status" -eq 0 ] || return 1
  [ -d "$PROJECT_ROOT/feature/y" ]
}

@test "rm removes a worktree and prunes" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null

  run "$WTREE_BIN" rm feature/x
  [ "$status" -eq 0 ] || return 1
  [ ! -d "$PROJECT_ROOT/feature/x" ] || return 1
  run git worktree list --porcelain
  [[ "$output" != *"feature/x"* ]]
}

@test "rm prunes stale worktree admin entries" {
  wtree_setup_project
  "$WTREE_BIN" add feature/a >/dev/null
  "$WTREE_BIN" add feature/b >/dev/null
  rm -rf "$PROJECT_ROOT/feature/b"   # simulate stale entry, bypassing wtree rm

  run "$WTREE_BIN" rm feature/a
  [ "$status" -eq 0 ] || return 1
  run git worktree list --porcelain
  [[ "$output" != *"feature/b"* ]]
}

@test "add works from a subdirectory of the project, not just the root" {
  wtree_setup_project
  cd main

  run "$WTREE_BIN" add feature/x
  [ "$status" -eq 0 ] || return 1
  [ -d "$PROJECT_ROOT/feature/x" ]
}

@test "list works from a subdirectory and shows all worktrees" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  cd feature/x

  run "$WTREE_BIN" list
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"main"* ]] || return 1
  [[ "$output" == *"feature/x"* ]]
}
