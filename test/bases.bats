setup() {
  load test_helper
}

# Pushes a branch $1 to origin carrying one extra commit (message $1), so
# each base is distinguishable from main by its tip commit.
push_base_branch() {
  local b="$1"
  git -C main checkout -q -b "$b"
  git -c user.name=test -c user.email=test@test.invalid -C main commit -q --allow-empty -m "$b"
  git -C main push -q origin "$b"
  git -C main checkout -q main
  git -C main branch -q -D "$b"
}

tip_message() {
  git -C "$1" log -1 --format=%s
}

write_bases() {
  cat >"$PROJECT_ROOT/.wtree-bases"
}

@test "add branches a new pre-release/* branch from origin/staging per .wtree-bases" {
  wtree_setup_project
  push_base_branch staging
  push_base_branch master
  write_bases <<'EOF'
# pattern        base
pre-release/*    staging
release/*        master
EOF

  run "$WTREE_BIN" add pre-release/1.0
  [ "$status" -eq 0 ] || return 1
  [ "$(tip_message "$PROJECT_ROOT/pre-release/1.0")" = "staging" ] || return 1
  [[ "$(strip_color "$output")" == *"branching from origin/staging (rule: pre-release/*)"* ]]
}

@test "add branches a new release/* branch from origin/master per .wtree-bases" {
  wtree_setup_project
  push_base_branch staging
  push_base_branch master
  write_bases <<'EOF'
pre-release/*    staging
release/*        master
EOF

  run "$WTREE_BIN" add release/2.1
  [ "$status" -eq 0 ] || return 1
  [ "$(tip_message "$PROJECT_ROOT/release/2.1")" = "master" ]
}

@test "add ignores blank lines and comments in .wtree-bases and uses the first matching rule" {
  wtree_setup_project
  push_base_branch staging
  push_base_branch prod
  write_bases <<'EOF'

# release branches come from prod
release/*   prod
release/*   staging
EOF

  run "$WTREE_BIN" add release/2.1
  [ "$status" -eq 0 ] || return 1
  [ "$(tip_message "$PROJECT_ROOT/release/2.1")" = "prod" ]
}

@test "add uses the default start point for a branch no rule matches" {
  wtree_setup_project
  push_base_branch staging
  write_bases <<'EOF'
pre-release/*    staging
EOF

  run "$WTREE_BIN" add feature/x
  [ "$status" -eq 0 ] || return 1
  [ "$(tip_message "$PROJECT_ROOT/feature/x")" = "init" ] || return 1
  [[ "$output" != *"branching from"* ]]
}

@test "add lets an explicit start point override a matching rule" {
  wtree_setup_project
  push_base_branch staging
  push_base_branch hotfix-base
  write_bases <<'EOF'
pre-release/*    staging
EOF

  run "$WTREE_BIN" add pre-release/1.0 origin/hotfix-base
  [ "$status" -eq 0 ] || return 1
  [ "$(tip_message "$PROJECT_ROOT/pre-release/1.0")" = "hotfix-base" ]
}

@test "add refuses when the rule's base doesn't exist on origin, creating nothing" {
  wtree_setup_project
  write_bases <<'EOF'
pre-release/*    staging
EOF

  run "$WTREE_BIN" add pre-release/1.0
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"origin/staging"* ]] || return 1
  [[ "$output" == *"pre-release/*"* ]] || return 1
  [ ! -d "$PROJECT_ROOT/pre-release/1.0" ] || return 1
  ! git -C "$PROJECT_ROOT/.bare" show-ref --verify --quiet refs/heads/pre-release/1.0
}

@test "add ignores rules for a branch that already exists on origin and tracks it" {
  wtree_setup_project
  push_base_branch staging
  push_base_branch release/2.1
  write_bases <<'EOF'
release/*    staging
EOF

  run "$WTREE_BIN" add release/2.1
  [ "$status" -eq 0 ] || return 1
  [ "$(tip_message "$PROJECT_ROOT/release/2.1")" = "release/2.1" ] || return 1
  [[ "$output" != *"branching from"* ]] || return 1
  run git -C "$PROJECT_ROOT/release/2.1" rev-parse --abbrev-ref --symbolic-full-name @{u}
  [ "$output" = "origin/release/2.1" ]
}

@test "add warns that the start point is ignored when the branch already exists locally" {
  wtree_setup_project
  git -C .bare branch feature/existing

  run "$WTREE_BIN" add feature/existing origin/main
  [ "$status" -eq 0 ] || return 1
  [ -d "$PROJECT_ROOT/feature/existing" ] || return 1
  [[ "$(strip_color "$output")" == *"feature/existing already exists — ignoring start point origin/main"* ]]
}

@test "add warns when an existing local branch is behind its origin counterpart" {
  wtree_setup_project
  git -C .bare branch release/2.1
  git -C main checkout -q -b tmp
  git -c user.name=test -c user.email=test@test.invalid -C main commit -q --allow-empty -m one
  git -c user.name=test -c user.email=test@test.invalid -C main commit -q --allow-empty -m two
  git -C main push -q origin tmp:release/2.1
  git -C main checkout -q main
  git -C main branch -q -D tmp

  run "$WTREE_BIN" add release/2.1
  [ "$status" -eq 0 ] || return 1
  [[ "$(strip_color "$output")" == *"local release/2.1 is 2 commits behind origin/release/2.1"* ]]
}

@test "add doesn't warn about an existing local branch that's up to date with origin" {
  wtree_setup_project
  push_base_branch release/2.1
  git -C .bare branch release/2.1 origin/release/2.1

  run "$WTREE_BIN" add release/2.1
  [ "$status" -eq 0 ] || return 1
  [[ "$output" != *"behind"* ]]
}
