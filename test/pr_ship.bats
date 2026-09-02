setup() {
  load test_helper
}

# ── Guard clauses (no gh mock needed — these run before any gh call) ──

@test "pr refuses when run from the project root" {
  wtree_setup_project

  run --separate-stderr "$WTREE_BIN" pr
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"run this from inside a specific worktree"* ]]
}

@test "ship refuses when run from .bare" {
  wtree_setup_project
  cd .bare

  run --separate-stderr "$WTREE_BIN" ship
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"run this from inside a specific worktree"* ]]
}

@test "ship refuses on the project's default branch" {
  wtree_setup_project
  cd main

  run --separate-stderr "$WTREE_BIN" ship
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"won't ship the default branch"* ]]
}

@test "ship refuses when the current worktree has uncommitted changes" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  echo "uncommitted" >feature/x/scratch.txt
  cd feature/x

  run --separate-stderr "$WTREE_BIN" ship
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"uncommitted changes"* ]]
}

# ── pr, with mocked gh ──

@test "pr pushes with -u when the branch has no upstream, then calls gh pr create" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  cd feature/x
  wtree_install_gh_mock
  export GH_MOCK_PR_URL="https://example.invalid/pr/7"

  run "$WTREE_BIN" pr
  [ "$status" -eq 0 ]
  [[ "$output" == *"pr/7"* ]]
  run git rev-parse --abbrev-ref --symbolic-full-name @{u}
  [ "$output" = "origin/feature/x" ]
}

@test "pr uses plain git push (no -u) when the branch already has an upstream" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  cd feature/x
  git push -q -u origin feature/x
  wtree_install_gh_mock

  run "$WTREE_BIN" pr
  [ "$status" -eq 0 ]
  [[ "$output" != *"setting upstream"* ]]
}

@test "pr pushes with -u when the branch's upstream has a different name than the branch itself" {
  # Regression test: `wtree add <branch> <remote-branch>` lets git's own
  # default branch.autoSetupMerge behavior set the new branch's upstream
  # to the *start point*, even when its name differs from the new
  # branch's name (e.g. `wtree add hotfix/y origin/dev` tracks
  # origin/dev, not origin/hotfix/y). `pr` used to treat "any upstream
  # configured" as "safe to plain `git push`", which fails with git's
  # "upstream branch does not match the name of your current branch"
  # error in exactly this case.
  wtree_setup_project
  git -C main push -q origin main:dev
  "$WTREE_BIN" add hotfix/y origin/dev >/dev/null
  cd hotfix/y

  run git rev-parse --abbrev-ref --symbolic-full-name @{u}
  [ "$output" = "origin/dev" ]

  wtree_install_gh_mock
  export GH_MOCK_PR_URL="https://example.invalid/pr/9"

  run "$WTREE_BIN" pr
  [ "$status" -eq 0 ]
  [[ "$output" == *"pr/9"* ]]
  run git rev-parse --abbrev-ref --symbolic-full-name @{u}
  [ "$output" = "origin/hotfix/y" ]
}

@test "pr uses whichever logged-in gh account can see the repo, not necessarily the active one" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  cd feature/x
  wtree_install_gh_mock
  export GH_MOCK_AUTH_ACCOUNTS=$'true personal-account\nfalse work-account'
  export GH_MOCK_API_ALLOWED_TOKEN="token-for-work-account"
  export GH_MOCK_PR_URL="https://example.invalid/pr/9"

  run "$WTREE_BIN" pr
  [ "$status" -eq 0 ]
  [[ "$(strip_color "$output")" == *"identity(gh): work-account"* ]]
  [[ "$output" == *"pr/9"* ]]
}

@test "pr does not print identity(gh) or override anything when no logged-in account can see the repo" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  cd feature/x
  wtree_install_gh_mock
  export GH_MOCK_AUTH_ACCOUNTS=$'true personal-account\nfalse work-account'
  # No GH_MOCK_API_ALLOWED_TOKEN set - neither account can see the repo.

  run "$WTREE_BIN" pr
  [ "$status" -eq 0 ]
  [[ "$output" != *"identity(gh)"* ]]
}

# ── ship, with mocked gh ──

@test "ship dies with a clear message when gh pr view finds no PR" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  cd feature/x
  wtree_install_gh_mock
  export GH_MOCK_PR_VIEW_FAIL=1

  run --separate-stderr "$WTREE_BIN" ship
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"no open PR for 'feature/x'"* ]]
  [[ "$stderr" == *"wtree pr"* ]]
}

@test "ship proceeds to clean up even when gh pr merge exits non-zero, as long as mergedAt is real" {
  # Regression test for the real bug found during manual testing: gh pr
  # merge's own post-merge housekeeping (switching the local checkout to
  # the base branch) always fails in a worktree setup, so its exit code
  # cannot be trusted as the signal for "did the merge actually happen."
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  cd feature/x
  wtree_install_gh_mock
  export GH_MOCK_MERGE_EXIT=1
  export GH_MOCK_MERGED_AT="2026-01-01T00:00:00Z"

  run --separate-stderr "$WTREE_BIN" ship <<<"y"
  [ "$status" -eq 0 ]
  [ "$output" = "$PROJECT_ROOT/main" ]
  [[ "$stderr" == *"merging..."* ]]
  [ ! -d "$PROJECT_ROOT/feature/x" ]
  run git -C "$PROJECT_ROOT/.bare" branch --list feature/x
  [ -z "$output" ]
}

@test "ship dies and does not clean up when the PR genuinely was not merged" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  cd feature/x
  wtree_install_gh_mock
  export GH_MOCK_MERGE_EXIT=1
  export GH_MOCK_MERGED_AT="null"

  run --separate-stderr "$WTREE_BIN" ship <<<"y"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"was not merged"* ]]
  [ -d "$PROJECT_ROOT/feature/x" ]
}

@test "ship's stdout on success is exactly the landing path, nothing else" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  cd feature/x
  wtree_install_gh_mock
  export GH_MOCK_MERGED_AT="2026-01-01T00:00:00Z"

  run --separate-stderr "$WTREE_BIN" ship <<<"y"
  [ "$status" -eq 0 ]
  [ "$output" = "$PROJECT_ROOT/main" ]
}

@test "ship's stdout stays exactly the landing path even when resolve_gh_account finds a match" {
  # Regression guard: resolve_gh_account's "identity(gh): ..." message
  # must go to stderr, not stdout - cmd_ship's stdout is the return
  # value the shell wrapper cd's into (`cd "$(command wtree ship)"`),
  # so anything else printed to stdout here would corrupt it.
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  cd feature/x
  wtree_install_gh_mock
  export GH_MOCK_MERGED_AT="2026-01-01T00:00:00Z"
  export GH_MOCK_AUTH_ACCOUNTS=$'true personal-account\nfalse work-account'
  export GH_MOCK_API_ALLOWED_TOKEN="token-for-work-account"

  run --separate-stderr "$WTREE_BIN" ship <<<"y"
  [ "$status" -eq 0 ]
  [ "$output" = "$PROJECT_ROOT/main" ]
  [[ "$(strip_color "$stderr")" == *"identity(gh): work-account"* ]]
}

@test "declining ship's confirmation leaves the worktree and PR untouched" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  cd feature/x
  wtree_install_gh_mock
  export GH_MOCK_MERGED_AT="2026-01-01T00:00:00Z"

  run --separate-stderr "$WTREE_BIN" ship <<<"n"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"aborted"* ]]
  [ -d "$PROJECT_ROOT/feature/x" ]
}
