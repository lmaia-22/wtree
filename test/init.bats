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

@test "init creates <repo>-wtree by default with a worktree for the checked-out (non-default) branch" {
  wtree_setup_plain_repo
  git -C "$REPO_DIR" checkout -q -b feature/x

  run "$WTREE_BIN" init
  [ "$status" -eq 0 ]
  local target
  target="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")-wtree"
  [ -d "$target/.bare" ]
  [ -d "$target/feature/x" ]
  run git -C "$target/feature/x" rev-parse --abbrev-ref HEAD
  [ "$output" = "feature/x" ]
}

@test "init works from a subdirectory of the existing repo, not just its root" {
  wtree_setup_plain_repo
  mkdir -p "$REPO_DIR/sub/deeper"
  cd "$REPO_DIR/sub/deeper"

  run "$WTREE_BIN" init
  [ "$status" -eq 0 ]
  local target
  target="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")-wtree"
  [ -d "$target/main" ]
}

@test "init accepts an explicit name argument, overriding the default" {
  wtree_setup_plain_repo

  run "$WTREE_BIN" init custom-name
  [ "$status" -eq 0 ]
  [ -d "$(dirname "$REPO_DIR")/custom-name/main" ]
}

@test "init sets the new bare clone's origin to the source's real remote URL" {
  wtree_setup_plain_repo
  local expected_origin
  expected_origin="$(git -C "$REPO_DIR" remote get-url origin)"

  run "$WTREE_BIN" init
  [ "$status" -eq 0 ]
  local target
  target="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")-wtree"
  run git -C "$target/.bare" remote get-url origin
  [ "$output" = "$expected_origin" ]
}

@test "init sets upstream tracking when a matching origin branch exists" {
  wtree_setup_plain_repo

  run "$WTREE_BIN" init
  [ "$status" -eq 0 ]
  local target
  target="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")-wtree"
  run git -C "$target/main" rev-parse --abbrev-ref --symbolic-full-name @{u}
  [ "$output" = "origin/main" ]
}

@test "init leaves the branch untracked when there is no matching origin branch" {
  wtree_setup_plain_repo
  git -C "$REPO_DIR" checkout -q -b local-only

  run "$WTREE_BIN" init
  [ "$status" -eq 0 ]
  local target
  target="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")-wtree"
  [ -d "$target/local-only" ]
  run git -C "$target/local-only" rev-parse --abbrev-ref --symbolic-full-name @{u}
  [ "$status" -ne 0 ]
}

@test "the source directory is unchanged after init runs" {
  wtree_setup_plain_repo
  local before_head
  before_head="$(git -C "$REPO_DIR" rev-parse HEAD)"

  run "$WTREE_BIN" init
  [ "$status" -eq 0 ]

  [ -d "$REPO_DIR/.git" ]
  [ ! -d "$REPO_DIR/.bare" ]
  run git -C "$REPO_DIR" rev-parse --is-bare-repository
  [ "$output" = "false" ]
  run git -C "$REPO_DIR" rev-parse HEAD
  [ "$output" = "$before_head" ]
  run git -C "$REPO_DIR" status --porcelain
  [ -z "$output" ]
}
