setup() {
  load test_helper
}

@test "add runs an executable .wtree-hook in the new worktree with the branch name as \$1 and the project root as \$2" {
  wtree_setup_project
  cat >"$PROJECT_ROOT/.wtree-hook" <<'EOF'
#!/usr/bin/env bash
pwd >.hook-cwd
echo "$1" >.hook-branch
echo "$2" >.hook-root
EOF
  chmod +x "$PROJECT_ROOT/.wtree-hook"

  run "$WTREE_BIN" add feature/x
  [ "$status" -eq 0 ] || return 1
  [ "$(cat "$PROJECT_ROOT/feature/x/.hook-cwd")" = "$PROJECT_ROOT/feature/x" ] || return 1
  [ "$(cat "$PROJECT_ROOT/feature/x/.hook-branch")" = "feature/x" ] || return 1
  [ "$(cat "$PROJECT_ROOT/feature/x/.hook-root")" = "$PROJECT_ROOT" ]
}

@test "add's \$2 project root lets a hook find a sibling worktree regardless of branch nesting depth" {
  # Regression test: a hook that reaches a sibling via a fixed number of
  # ../ segments breaks the moment a branch name's slash-depth differs
  # (e.g. fix-abc vs feature/x vs feature/deeply/nested/thing) - $2
  # gives the hook an absolute anchor that works for any branch name.
  wtree_setup_project
  echo "SECRET=1" >"$PROJECT_ROOT/main/.env"
  cat >"$PROJECT_ROOT/.wtree-hook" <<'EOF'
#!/usr/bin/env bash
cp "$2/main/.env" .
EOF
  chmod +x "$PROJECT_ROOT/.wtree-hook"

  run "$WTREE_BIN" add feature/deeply/nested/thing
  [ "$status" -eq 0 ] || return 1
  [ "$(cat "$PROJECT_ROOT/feature/deeply/nested/thing/.env")" = "SECRET=1" ]
}

@test "add prints a warning but keeps the worktree when the hook exits non-zero" {
  wtree_setup_project
  cat >"$PROJECT_ROOT/.wtree-hook" <<'EOF'
#!/usr/bin/env bash
exit 3
EOF
  chmod +x "$PROJECT_ROOT/.wtree-hook"

  run "$WTREE_BIN" add feature/x
  [ "$status" -eq 0 ] || return 1
  [ -d "$PROJECT_ROOT/feature/x" ] || return 1
  [[ "$output" == *".wtree-hook exited 3"* ]]
}

@test "add warns and skips a .wtree-hook that exists but isn't executable" {
  wtree_setup_project
  cat >"$PROJECT_ROOT/.wtree-hook" <<'EOF'
#!/usr/bin/env bash
touch should-not-run.txt
EOF
  # deliberately not chmod +x

  run "$WTREE_BIN" add feature/x
  [ "$status" -eq 0 ] || return 1
  [ -d "$PROJECT_ROOT/feature/x" ] || return 1
  [ ! -f "$PROJECT_ROOT/feature/x/should-not-run.txt" ] || return 1
  [[ "$output" == *"not executable"* ]]
}

@test "add behaves exactly as before when no .wtree-hook exists" {
  wtree_setup_project

  run "$WTREE_BIN" add feature/x
  [ "$status" -eq 0 ] || return 1
  [[ "$output" != *"hook"* ]]
}
