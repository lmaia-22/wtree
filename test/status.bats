setup() {
  load test_helper
}

@test "status prints a header and one row per non-bare worktree" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null

  run "$WTREE_BIN" status
  [ "$status" -eq 0 ] || return 1
  local clean_output
  clean_output=$(strip_color "$output")
  [[ "$clean_output" == *"BRANCH"*"AHEAD/BEHIND"*"STATE"*"IDENTITY"* ]] || return 1
  [[ "$clean_output" == *"main"* ]] || return 1
  [[ "$clean_output" == *"feature/x"* ]] || return 1
  [[ "$clean_output" != *".bare"* ]]
}

@test "status shows real ahead/behind counts for a worktree with an upstream" {
  wtree_setup_project

  run "$WTREE_BIN" status
  local clean_output
  clean_output=$(strip_color "$output")
  [[ "$clean_output" == *"+0/-0"* ]]
}

@test "status shows 'no upstream' for a worktree with no upstream configured" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null

  run "$WTREE_BIN" status
  local clean_output
  clean_output=$(strip_color "$output")
  [[ "$clean_output" == *"no upstream"* ]]
}

@test "status marks a dirty worktree distinctly from a clean one" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  echo "uncommitted" >feature/x/scratch.txt

  run "$WTREE_BIN" status
  local clean_output
  clean_output=$(strip_color "$output")
  [[ "$clean_output" == *"dirty"* ]] || return 1
  [[ "$clean_output" == *"clean"* ]]
}

@test "status aligns the IDENTITY column under its header regardless of dirty/clean" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  echo "uncommitted" >feature/x/scratch.txt

  run "$WTREE_BIN" status
  local clean_output header_idx line char
  clean_output=$(strip_color "$output")

  # 1-based index() converted to a 0-based substring offset.
  header_idx=$(($(awk 'NR==1{print index($0, "IDENTITY")}' <<<"$clean_output") - 1))

  # At that exact offset, every data row's identity value must start —
  # the character there is non-space, AND the character immediately
  # before it is a space (a real field boundary, not just some
  # non-space byte from a shifted-left value spilling into this
  # column, which is what made an earlier version of this assertion
  # pass even against the buggy code). This is a regression test for
  # the printf color-padding bug, where the color escapes were counted
  # as part of the padded field width and shifted this column left by
  # the length of the color/reset escape sequences.
  #
  # The `|| return 1` inside the loop matters here specifically: a bats
  # test body (and any loop inside it) runs in a context where its own
  # exit status is being tested, which strips implicit errexit
  # propagation - without it, a mismatch on an early row would be
  # silently overwritten by a later, correctly-aligned row, and only
  # the LAST row would actually be checked.
  local before
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    char="${line:$header_idx:1}"
    before="${line:$((header_idx - 1)):1}"
    [[ "$char" != " " && "$before" == " " ]] || return 1
  done <<<"$(tail -n +2 <<<"$clean_output")"
}

@test "a worktree whose directory is missing renders a broken message, not a blank/crash" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  rm -rf feature/x

  run "$WTREE_BIN" status
  [ "$status" -eq 0 ] || return 1
  local clean_output
  clean_output=$(strip_color "$output")
  [[ "$clean_output" == *"broken"* ]] || return 1
  [[ "$clean_output" == *"main"* ]]
}
