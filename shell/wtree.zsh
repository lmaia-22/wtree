# wtree shell integration for zsh.
# Source this file in your .zshrc:
#   source /path/to/wtree.zsh

wtree() {
  case "${1:-}" in
    switch|ship)
      local dest
      dest="$(command wtree "$@")" || return $?
      [[ -n "$dest" ]] && cd "$dest"
      ;;
    "")
      local dest
      dest="$(command wtree switch)" || return $?
      [[ -n "$dest" ]] && cd "$dest"
      ;;
    *)
      command wtree "$@"
      ;;
  esac
}

_wtree_project_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.bare" ]]; then
      print -r -- "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

_wtree_branches() {
  local root
  root="$(_wtree_project_root)" || return 1
  git -C "$root/.bare" for-each-ref --format='%(refname:short)' refs/heads
}

# Branches that actually have a worktree checked out — the only valid
# arguments to `switch` and `rm`. Mirrors cmd_switch's own fzf source:
# a wtree worktree always lives at <root>/<branch>.
# Approximate for `rm`: a leftover directory with no registered
# worktree (the "broken" state cmd_clean/cmd_status report) still
# gets offered — `git worktree remove` then rejects it, which is the
# same outcome as before and better than offering every branch.
_wtree_worktrees() {
  local root b
  root="$(_wtree_project_root)" || return 1
  git -C "$root/.bare" for-each-ref --format='%(refname:short)' refs/heads |
    while IFS= read -r b; do
      if [[ -d "$root/$b" ]]; then
        print -r -- "$b"
      fi
    done
}

_wtree() {
  local -a subcmds
  subcmds=(clone init add rm status switch list clean pr ship doctor)

  if (( CURRENT == 2 )); then
    compadd -a subcmds
    return
  fi

  case "${words[2]}" in
    switch|rm)
      compadd -- ${(f)"$(_wtree_worktrees)"}
      ;;
    add)
      compadd -- ${(f)"$(_wtree_branches)"}
      ;;
  esac
}
(( $+functions[compdef] )) && compdef _wtree wtree
