#!/usr/bin/env bash
#
# wtree - set up a git repo using the bare-clone + worktrees pattern,
# and manage worktrees inside it.
#
# Pattern: https://dev.to/metal3d/git-worktree-like-a-boss-2j1b
#
# Usage:
#   wtree clone <repo-url> [dir-name]   Clone a repo as a worktree-ready project
#   wtree add <branch> [start-point]    Add a worktree for <branch>
#   wtree rm <branch>                   Remove a worktree
#   wtree list                          List worktrees in this project
#
# Run "add", "rm" and "list" from anywhere inside a project created with
# "wtree clone" (i.e. from the project root or from inside any worktree
# sibling folder) - they walk up to find the .bare directory.
#
# Because this repo lives under ~/Developer/company/ or ~/Developer/personal/,
# git's per-folder includeIf config picks the right identity/SSH key
# automatically - wtree just prints which one is active after each command.

set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RESET=$'\033[0m'

die()  { echo "${RED}x${RESET} $*" >&2; exit 1; }
info() { echo "${BLUE}->${RESET} $*"; }
ok()   { echo "${GREEN}v${RESET} $*"; }

usage() {
  cat <<'USAGE'
wtree - bare-clone git worktrees, without the ceremony

  wtree clone <repo-url> [dir-name]   Set up a new worktree-ready project
  wtree add <branch> [start-point]    Add a worktree for <branch>
  wtree rm <branch>                   Remove a worktree
  wtree list                          List worktrees in this project
  wtree status                         Show branch/ahead-behind/dirty/identity per worktree
  wtree switch [branch]               Print path to a worktree (fzf picker if no branch given)

Examples:
  cd ~/Developer/company
  wtree clone git@github.com:mediaprobe/api.git
  cd api
  wtree add feature/qpx-v3
  wtree add hotfix/login origin/main
  wtree rm feature/qpx-v3
USAGE
}

# Walk up from $PWD until a .bare dir is found (the project root).
find_project_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.bare" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# Show which git identity applies at a path - the whole point of keeping
# company/ and personal/ separate.
whoami_here() {
  local name email
  name=$(git -C "$1" config user.name 2>/dev/null || echo "?")
  email=$(git -C "$1" config user.email 2>/dev/null || echo "?")
  echo "${YELLOW}identity:${RESET} $name <$email>"
}

cmd_clone() {
  local url="${1:?repo url required}"
  local name="${2:-}"

  if [[ -z "$name" ]]; then
    name="${url%/}"
    name="${name##*/}"
    name="${name%.git}"
  fi

  [[ -e "$name" ]] && die "'$name' already exists here"

  info "looking up default branch"
  local default_branch
  default_branch=$(git ls-remote --symref "$url" HEAD | awk '/^ref:/{sub(".*refs/heads/", "", $2); print $2}')
  if [[ -z "$default_branch" ]]; then
    default_branch="main"
  fi

  mkdir "$name"
  cd "$name"

  info "bare-cloning $url into .bare"
  git clone --bare "$url" .bare

  echo "gitdir: ./.bare" > .git
  git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

  info "fetching all branches"
  git fetch origin --quiet

  info "creating worktree for '$default_branch'"
  git worktree add "$default_branch"

  if git show-ref --verify --quiet "refs/remotes/origin/$default_branch"; then
    git branch --set-upstream-to="origin/$default_branch" "$default_branch" >/dev/null
  fi

  ok "project ready at $(pwd)"
  whoami_here "$(pwd)/$default_branch"
  echo
  echo "  cd $name/$default_branch"
}

cmd_add() {
  local branch="${1:?branch name required}"
  local start="${2:-}"
  local root
  root=$(find_project_root) || die "not inside a wtree project (no .bare found)"
  cd "$root"

  info "fetching latest"
  git fetch origin --quiet

  if git worktree list --porcelain | grep -qx "worktree $root/$branch"; then
    die "worktree '$branch' already exists at $root/$branch"
  fi

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$branch" "$branch"
  elif [[ -n "$start" ]]; then
    git worktree add -b "$branch" "$branch" "$start"
  elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git worktree add -b "$branch" "$branch" "origin/$branch"
  else
    git worktree add -b "$branch" "$branch"
  fi

  ok "worktree ready: $root/$branch"
  whoami_here "$root/$branch"
}

cmd_rm() {
  local branch="${1:?branch name required}"
  local root
  root=$(find_project_root) || die "not inside a wtree project (no .bare found)"
  cd "$root"
  git worktree remove "$branch" "${@:2}"
  git worktree prune
  ok "removed worktree '$branch'"
}

cmd_list() {
  local root
  root=$(find_project_root) || die "not inside a wtree project (no .bare found)"
  git -C "$root" worktree list
}

cmd_status() {
  local root
  root=$(find_project_root) || die "not inside a wtree project (no .bare found)"
  root=$(cd "$root" && pwd -P)  # resolve symlinks for comparison with git output

  printf "%-30s %-12s %-8s %s\n" "BRANCH" "AHEAD/BEHIND" "STATE" "IDENTITY"

  git -C "$root" worktree list --porcelain | awk '/^worktree /{print $2}' |
  while read -r wt; do
    [[ "$wt" == "$root/.bare" ]] && continue

    local branch upstream ahead behind ab state email
    branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)
    upstream=$(git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)

    if [[ -n "$upstream" ]]; then
      read -r ahead behind < <(git -C "$wt" rev-list --left-right --count "$branch...$upstream" 2>/dev/null) || true
      ab="+${ahead:-0}/-${behind:-0}"
    else
      ab="no upstream"
    fi

    if [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
      state="${YELLOW}dirty${RESET}"
    else
      state="${GREEN}clean${RESET}"
    fi

    email=$(git -C "$wt" config user.email 2>/dev/null || echo "?")

    printf "%-30s %-12s %-8b %s\n" "$branch" "$ab" "$state" "$email"
  done || true
  # ^ a `while read` loop that ends via EOF always exits 1, which would
  #   trip `set -e` and abort the script right after printing the table.
}

cmd_switch() {
  local branch="${1:-}"
  local root
  root=$(find_project_root) || die "not inside a wtree project (no .bare found)"

  if [[ -z "$branch" ]]; then
    branch=$(
      git -C "$root/.bare" for-each-ref --format='%(refname:short)' refs/heads |
      while read -r b; do if [[ -d "$root/$b" ]]; then echo "$b"; fi; done |
      fzf --prompt="switch> " --preview="git -C '$root'/{} log -1 --oneline 2>/dev/null"
    ) || exit 1
    [[ -z "$branch" ]] && exit 1
  fi

  local dest="$root/$branch"
  [[ -d "$dest" ]] || die "no worktree for branch '$branch' (try: wtree add $branch)"

  echo "$dest"
}

case "${1:-}" in
  clone)        shift; cmd_clone "$@" ;;
  add)          shift; cmd_add "$@" ;;
  rm)           shift; cmd_rm "$@" ;;
  list|ls)      shift; cmd_list "$@" ;;
  status)       shift; cmd_status "$@" ;;
  switch)       shift; cmd_switch "$@" ;;
  -h|--help|"") usage ;;
  *)            die "unknown command '$1' (see wtree --help)" ;;
esac
