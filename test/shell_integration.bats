setup() {
  load test_helper
}

# ── zsh ──

@test "zsh: sourcing shell/wtree.zsh defines a wtree function" {
  run zsh -fc "source '$WTREE_ROOT/shell/wtree.zsh'; whence -w wtree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wtree: function"* ]]
}

@test "zsh: wtree switch <branch> changes the shell's PWD" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  wtree_install_on_path
  cd feature/x

  run zsh -c "
    source '$WTREE_ROOT/shell/wtree.zsh'
    wtree switch main
    pwd
  "
  [ "$status" -eq 0 ]
  [ "$output" = "$PROJECT_ROOT/main" ]
}

@test "zsh: wtree switch <nonexistent> does not change PWD and returns non-zero" {
  wtree_setup_project
  wtree_install_on_path
  cd main

  run zsh -c "
    source '$WTREE_ROOT/shell/wtree.zsh'
    wtree switch does-not-exist
    echo \"exit:\$?\"
    pwd
  "
  [[ "$output" == *"exit:1"* ]]
  [[ "$output" == *"$PROJECT_ROOT/main"* ]]
}

@test "zsh: wtree ship (mocked gh, merged) changes PWD to the landing path" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  wtree_install_on_path
  wtree_install_gh_mock
  cd feature/x

  GH_MOCK_MERGED_AT="2026-01-01T00:00:00Z" run zsh -c "
    source '$WTREE_ROOT/shell/wtree.zsh'
    wtree ship <<<'y'
    pwd
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"$PROJECT_ROOT/main"* ]]
}

@test "zsh: sourcing under a bare zsh -f (no compinit) prints no compdef error" {
  # The guard (( $+functions[compdef] )) leaves `source`'s own exit
  # status at 1 when compinit hasn't run (a known, accepted quirk —
  # harmless, no error text) — so this only asserts on output, not
  # exit status.
  run zsh -fc "source '$WTREE_ROOT/shell/wtree.zsh'"
  [[ "$output" != *"compdef"* ]]
}

@test "zsh: _wtree_branches lists the project's local branches" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null

  run zsh -fc "
    source '$WTREE_ROOT/shell/wtree.zsh'
    cd '$PROJECT_ROOT/main'
    _wtree_branches
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"main"* ]]
  [[ "$output" == *"feature/x"* ]]
}

# A zsh `compadd` mock deterministic enough for direct-invocation
# completion tests: real completion supplies candidates either as
# positional args after `--`, or (as `_wtree` does for the top-level
# subcommand list) as `-a <arrayname>`, which must be dereferenced
# rather than treated as a literal candidate.
ZSH_COMPADD_MOCK='
compadd() {
  local -a args=("$@")
  local i=1
  while (( i <= $#args )); do
    case "${args[i]}" in
      -a)
        i=$((i+1))
        local arrname="${args[i]}"
        local -a vals
        vals=("${(P)arrname[@]}")
        print -rl -- "${vals[@]}"
        ;;
      -*) ;;
      *) print -r -- "${args[i]}" ;;
    esac
    i=$((i+1))
  done
}
'

@test "zsh: _wtree completion offers subcommands at the first word" {
  run zsh -fc "
    source '$WTREE_ROOT/shell/wtree.zsh'
    $ZSH_COMPADD_MOCK
    words=(wtree '')
    CURRENT=2
    _wtree
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean"* ]]
  [[ "$output" == *"switch"* ]]
  [[ "$output" == *"ship"* ]]
}

@test "zsh: _wtree completion offers branch names after 'switch'" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null

  run zsh -fc "
    cd '$PROJECT_ROOT/main'
    source '$WTREE_ROOT/shell/wtree.zsh'
    $ZSH_COMPADD_MOCK
    words=(wtree switch '')
    CURRENT=3
    _wtree
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature/x"* ]]
}

# ── bash ──

@test "bash: sourcing shell/wtree.bash defines a wtree function" {
  run bash -c "source '$WTREE_ROOT/shell/wtree.bash'; type -t wtree"
  [ "$status" -eq 0 ]
  [ "$output" = "function" ]
}

@test "bash: wtree switch <branch> changes the shell's PWD" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  wtree_install_on_path
  cd feature/x

  run bash -c "
    source '$WTREE_ROOT/shell/wtree.bash'
    wtree switch main
    pwd
  "
  [ "$status" -eq 0 ]
  [ "$output" = "$PROJECT_ROOT/main" ]
}

@test "bash: wtree switch <nonexistent> does not change PWD and returns non-zero" {
  wtree_setup_project
  wtree_install_on_path
  cd main

  run bash -c "
    source '$WTREE_ROOT/shell/wtree.bash'
    wtree switch does-not-exist
    echo \"exit:\$?\"
    pwd
  "
  [[ "$output" == *"exit:1"* ]]
  [[ "$output" == *"$PROJECT_ROOT/main"* ]]
}

@test "bash: wtree ship (mocked gh, merged) changes PWD to the landing path" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null
  wtree_install_on_path
  wtree_install_gh_mock
  cd feature/x

  GH_MOCK_MERGED_AT="2026-01-01T00:00:00Z" run bash -c "
    source '$WTREE_ROOT/shell/wtree.bash'
    wtree ship <<<'y'
    pwd
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"$PROJECT_ROOT/main"* ]]
}

@test "bash: completion offers subcommands at COMP_CWORD=1" {
  run bash -c "
    source '$WTREE_ROOT/shell/wtree.bash'
    COMP_WORDS=(wtree '')
    COMP_CWORD=1
    _wtree_complete
    printf '%s\n' \"\${COMPREPLY[@]}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean"* ]]
  [[ "$output" == *"switch"* ]]
  [[ "$output" == *"ship"* ]]
}

@test "bash: completion offers branch names after 'switch'" {
  wtree_setup_project
  "$WTREE_BIN" add feature/x >/dev/null

  run bash -c "
    cd '$PROJECT_ROOT/main'
    source '$WTREE_ROOT/shell/wtree.bash'
    COMP_WORDS=(wtree switch '')
    COMP_CWORD=2
    _wtree_complete
    printf '%s\n' \"\${COMPREPLY[@]}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature/x"* ]]
}
