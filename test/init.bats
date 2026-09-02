setup() {
  load test_helper
}

@test "init refuses when run outside a git repo entirely" {
  cd "$BATS_TEST_TMPDIR"
  mkdir plain
  cd plain

  run "$WTREE_BIN" init
  [ "$status" -ne 0 ]
  [[ "$output" == *"not inside a git repo"* ]]
}

@test "init refuses when the repo is already bare" {
  cd "$BATS_TEST_TMPDIR"
  mkdir bare.git
  git init -q --bare bare.git
  cd bare.git

  run "$WTREE_BIN" init
  [ "$status" -ne 0 ]
  [[ "$output" == *"already a bare repository"* ]]
}

@test "init refuses when already inside a wtree project" {
  wtree_setup_project
  cd main

  run "$WTREE_BIN" init
  [ "$status" -ne 0 ]
  [[ "$output" == *"already a wtree project"* ]]
}

@test "init refuses on detached HEAD" {
  wtree_setup_plain_repo
  git -C "$REPO_DIR" checkout -q --detach

  run "$WTREE_BIN" init
  [ "$status" -ne 0 ]
  [[ "$output" == *"detached"* ]]
}

@test "init refuses when the working tree has uncommitted tracked changes" {
  wtree_setup_plain_repo
  echo tracked >"$REPO_DIR/tracked.txt"
  git -C "$REPO_DIR" add tracked.txt
  git -c user.name=test -c user.email=test@test.invalid -C "$REPO_DIR" commit -q -m tracked
  echo more >>"$REPO_DIR/tracked.txt"

  run "$WTREE_BIN" init
  [ "$status" -ne 0 ]
  [[ "$output" == *"dirty"* ]]
}

@test "init refuses when the working tree has untracked files" {
  wtree_setup_plain_repo
  touch "$REPO_DIR/untracked.txt"

  run "$WTREE_BIN" init
  [ "$status" -ne 0 ]
  [[ "$output" == *"dirty"* ]]
}

@test "init refuses when there is a stash entry on an otherwise clean tree" {
  wtree_setup_plain_repo
  touch "$REPO_DIR/stashme.txt"
  git -C "$REPO_DIR" add -A
  git -c user.name=test -c user.email=test@test.invalid -C "$REPO_DIR" stash

  run "$WTREE_BIN" init
  [ "$status" -ne 0 ]
  [[ "$output" == *"stash"* ]]
}

@test "init refuses when there is no origin remote" {
  wtree_setup_plain_repo
  git -C "$REPO_DIR" remote remove origin

  run "$WTREE_BIN" init
  [ "$status" -ne 0 ]
  [[ "$output" == *"no 'origin' remote"* ]]
}

@test "init refuses when the target directory already exists" {
  wtree_setup_plain_repo
  mkdir "$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")-wtree"

  run "$WTREE_BIN" init
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}
