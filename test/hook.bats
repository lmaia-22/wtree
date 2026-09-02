setup() {
  load test_helper
}

@test "add runs an executable .wtree-hook in the new worktree with the branch name as \$1" {
  wtree_setup_project
  cat >"$PROJECT_ROOT/.wtree-hook" <<'EOF'
#!/usr/bin/env bash
pwd >.hook-cwd
echo "$1" >.hook-branch
EOF
  chmod +x "$PROJECT_ROOT/.wtree-hook"

  run "$WTREE_BIN" add feature/x
  [ "$status" -eq 0 ]
  [ "$(cat "$PROJECT_ROOT/feature/x/.hook-cwd")" = "$PROJECT_ROOT/feature/x" ]
  [ "$(cat "$PROJECT_ROOT/feature/x/.hook-branch")" = "feature/x" ]
}

@test "add prints a warning but keeps the worktree when the hook exits non-zero" {
  wtree_setup_project
  cat >"$PROJECT_ROOT/.wtree-hook" <<'EOF'
#!/usr/bin/env bash
exit 3
EOF
  chmod +x "$PROJECT_ROOT/.wtree-hook"

  run "$WTREE_BIN" add feature/x
  [ "$status" -eq 0 ]
  [ -d "$PROJECT_ROOT/feature/x" ]
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
  [ "$status" -eq 0 ]
  [ -d "$PROJECT_ROOT/feature/x" ]
  [ ! -f "$PROJECT_ROOT/feature/x/should-not-run.txt" ]
  [[ "$output" == *"not executable"* ]]
}

@test "add behaves exactly as before when no .wtree-hook exists" {
  wtree_setup_project

  run "$WTREE_BIN" add feature/x
  [ "$status" -eq 0 ]
  [[ "$output" != *"hook"* ]]
}
