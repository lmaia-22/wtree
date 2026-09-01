# wtree shell integration for zsh.
# Source this file in your .zshrc:
#   source /path/to/wtree.zsh

wtree() {
  case "${1:-}" in
    switch)
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

_wtree() {
  local -a subcmds
  subcmds=(clone add rm status switch list)

  if (( CURRENT == 2 )); then
    compadd -a subcmds
    return
  fi

  case "${words[2]}" in
    switch|rm|add)
      compadd -- ${(f)"$(_wtree_branches)"}
      ;;
  esac
}
compdef _wtree wtree
