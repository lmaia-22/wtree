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
#   wtree status                        Show branch/ahead-behind/dirty/identity per worktree
#   wtree switch [branch]               Print path to a worktree (fzf picker if no branch given)
#   wtree clean                         Remove broken and already-merged worktrees (with confirmation)
#   wtree pr                            Push and open a PR for the current worktree's branch
#   wtree ship                          Merge the current branch's PR and clean up (with confirmation)
#
# Run "add", "rm", "list", "status", "switch" and "clean" from anywhere
# inside a project created with "wtree clone" (i.e. from the project root
# or from inside any worktree sibling folder) - they walk up to find the
# .bare directory. "pr" and "ship" instead operate on whatever branch is
# checked out where you run them, so run those from inside the specific
# worktree.
#
# Because this repo lives under ~/Developer/company/ or ~/Developer/personal/,
# git's per-folder includeIf config picks the right identity/SSH key
# automatically - wtree just prints which one is active after each command.

set -euo pipefail

VERSION="0.1.0"

RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
RESET=$'\033[0m'
TEAL1=$'\033[38;2;0;255;136m'
TEAL2=$'\033[38;2;0;220;160m'
TEAL3=$'\033[38;2;0;185;180m'
TEAL4=$'\033[38;2;0;150;200m'
TRUNK1=$'\033[38;2;180;120;60m'
TRUNK2=$'\033[38;2;140;90;40m'
WHITE=$'\033[1;37m'
GRAY=$'\033[90m'
APPLE=$'\033[38;2;220;40;40m'

die() {
	echo "${RED}x${RESET} $*" >&2
	exit 1
}
info() { echo "${BLUE}->${RESET} $*"; }
ok() { echo "${GREEN}v${RESET} $*"; }

banner() {
	cat <<BANNER
   ${TEAL1}⢀⣠⣴⣶⣶⣦⣄⡀${RESET}
 ${TEAL2}⢀⣴⣿⣿⣿⣿⣿⣿⣿⣦⡀${RESET}     ${WHITE}wtree${RESET} ${GRAY}v${VERSION}${RESET}
${TEAL3}⢠⣿⣿⣿${APPLE}⣿${TEAL3}⣿⣿${APPLE}⣿${TEAL3}⣿⣿⡄${RESET}    ${GRAY}bare-clone git worktrees${RESET}
 ${TEAL4}⠙⠻⢿⣿⣿⣿⣿⠿⠟⠋${RESET}     ${TEAL3}without the ceremony${RESET}
      ${TRUNK1}║${RESET}
      ${TRUNK2}╩${RESET}
BANNER
}

usage() {
	banner
	cat <<USAGE

wtree - bare-clone git worktrees, without the ceremony

  wtree clone <repo-url> [dir-name]   Set up a new worktree-ready project
  wtree add <branch> [start-point]    Add a worktree for <branch>
  wtree rm <branch>                   Remove a worktree
  wtree list                          List worktrees in this project
  wtree status                        Show branch/ahead-behind/dirty/identity per worktree
  wtree switch [branch]               Print path to a worktree (fzf picker if no branch given)
  wtree clean                         Remove broken and already-merged worktrees (with confirmation)
  wtree pr                            Push and open a PR for the current worktree's branch
  wtree ship                          Merge the current branch's PR and clean up (with confirmation)
  wtree --version                     Print the wtree banner and version

Examples:
  cd ~/Developer/company
  wtree clone git@github.com:you/your-repo.git
  cd your-repo
  wtree add feature/x
  wtree add hotfix/y origin/main
  wtree rm feature/x
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

# pr/ship operate on "whatever branch is checked out here" rather than an
# explicit argument, so both need to confirm $PWD is an actual worktree
# (not the project root or .bare, which have no real checkout) and report
# which branch that is.
current_worktree_branch() {
	local root="$1"
	local cwd
	cwd=$(pwd -P)
	if [[ "$cwd" == "$root" || "$cwd" == "$root/.bare" ]] ||
		! git -C "$root" worktree list --porcelain | awk '/^worktree /{print $2}' | grep -qx "$cwd"; then
		die "run this from inside a specific worktree, not the project root"
	fi
	git rev-parse --abbrev-ref HEAD
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

	echo "gitdir: ./.bare" >.git
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
	root=$(cd "$root" && pwd -P) # resolve symlinks for comparison with git output

	printf "%-30s %-12s %-8s %s\n" "BRANCH" "AHEAD/BEHIND" "STATE" "IDENTITY"

	git -C "$root" worktree list --porcelain | awk '/^worktree /{print $2}' |
		while read -r wt; do
			[[ "$wt" == "$root/.bare" ]] && continue

			if [[ ! -d "$wt" ]]; then
				printf "%-30s %s\n" "${wt#"$root"/}" "${RED}broken — directory missing (try: git worktree repair, or wtree rm)${RESET}"
				continue
			fi

			local branch upstream ahead="" behind="" ab color word email
			branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)
			upstream=$(git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)

			if [[ -n "$upstream" ]]; then
				read -r ahead behind < <(git -C "$wt" rev-list --left-right --count "$branch...$upstream" 2>/dev/null) || true
				ab="+${ahead:-0}/-${behind:-0}"
			else
				ab="no upstream"
			fi

			if [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
				color="$YELLOW"
				word="dirty"
			else
				color="$GREEN"
				word="clean"
			fi

			email=$(git -C "$wt" config user.email 2>/dev/null || echo "?")

			printf "%-30s %-12s %s%-8s%s %s\n" "$branch" "$ab" "$color" "$word" "$RESET" "$email"
		done || true
	# The loop runs in a pipeline subshell; keeping it on the left of `||`
	# disables errexit inside the body so one unreadable worktree doesn't
	# truncate the table.
}

cmd_switch() {
	local branch="${1:-}"
	local root
	root=$(find_project_root) || die "not inside a wtree project (no .bare found)"

	if [[ -z "$branch" ]]; then
		command -v fzf >/dev/null || die "fzf not found — install it (brew install fzf) or pass a branch name"
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

cmd_clean() {
	local root
	root=$(find_project_root) || die "not inside a wtree project (no .bare found)"
	root=$(cd "$root" && pwd -P)

	info "fetching latest (--prune)"
	git -C "$root" fetch origin --prune --quiet

	local broken=() merged=() dirty=()
	local wt

	while read -r wt; do
		[[ "$wt" == "$root/.bare" ]] && continue

		if [[ ! -d "$wt" ]]; then
			broken+=("$wt")
			continue
		fi

		local branch upstream
		branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)
		upstream=$(git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)

		[[ -z "$upstream" ]] && continue # never pushed - no remote signal, leave it alone

		git -C "$wt" rev-parse --verify --quiet "$upstream" >/dev/null 2>&1 && continue # remote branch still exists

		if [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
			dirty+=("$branch")
		else
			merged+=("$branch")
		fi
	done < <(git -C "$root" worktree list --porcelain | awk '/^worktree /{print $2}') || true
	# Same reasoning as cmd_status: keeping the loop on the left of `||`
	# disables errexit inside the body so one unreadable worktree doesn't
	# abort detection partway through.

	if [[ ${#broken[@]} -eq 0 && ${#merged[@]} -eq 0 && ${#dirty[@]} -eq 0 ]]; then
		ok "nothing to clean"
		return
	fi

	local b
	if [[ ${#broken[@]} -gt 0 ]]; then
		echo "BROKEN (worktree directory missing — will remove stale registration):"
		for b in "${broken[@]}"; do echo "  ${b#"$root"/}"; done
		echo
	fi

	if [[ ${#merged[@]} -gt 0 ]]; then
		echo "MERGED (remote branch gone — will remove worktree + delete local branch):"
		printf "  %s\n" "${merged[@]}"
		echo
	fi

	if [[ ${#dirty[@]} -gt 0 ]]; then
		echo "SKIPPED (merged but has uncommitted changes — clean up manually):"
		printf "  %s\n" "${dirty[@]}"
		echo
	fi

	if [[ ${#broken[@]} -eq 0 && ${#merged[@]} -eq 0 ]]; then
		return
	fi

	local reply
	read -r -p "Clean ${#broken[@]} broken and ${#merged[@]} merged worktrees? [y/N] " reply || reply="n"
	[[ "$reply" =~ ^[Yy]$ ]] || {
		echo "aborted"
		return
	}

	if [[ ${#broken[@]} -gt 0 ]]; then
		for b in "${broken[@]}"; do
			if git -C "$root" worktree remove --force "$b" 2>/dev/null; then
				ok "removed broken worktree '${b#"$root"/}'"
			else
				echo "${RED}x${RESET} failed to remove '${b#"$root"/}'" >&2
			fi
		done
		git -C "$root" worktree prune
	fi

	if [[ ${#merged[@]} -gt 0 ]]; then
		for b in "${merged[@]}"; do
			if git -C "$root" worktree remove "$b" 2>/dev/null && git -C "$root/.bare" branch -D "$b" >/dev/null 2>&1; then
				ok "removed merged worktree and branch '$b'"
			else
				echo "${RED}x${RESET} failed to fully clean '$b'" >&2
			fi
		done
	fi
}

cmd_pr() {
	local root
	root=$(find_project_root) || die "not inside a wtree project (no .bare found)"
	root=$(cd "$root" && pwd -P)

	command -v gh >/dev/null || die "gh not found — install it (brew install gh) to use wtree pr"

	local branch
	branch=$(current_worktree_branch "$root")

	local upstream
	upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)

	if [[ -z "$upstream" ]]; then
		info "pushing '$branch' (setting upstream)"
		git push -u origin "$branch"
	else
		info "pushing '$branch'"
		git push
	fi

	gh pr create
}

cmd_ship() {
	local root
	root=$(find_project_root) || die "not inside a wtree project (no .bare found)"
	root=$(cd "$root" && pwd -P)

	command -v gh >/dev/null || die "gh not found — install it (brew install gh) to use wtree ship"

	local branch
	branch=$(current_worktree_branch "$root")

	local default_branch
	default_branch=$(git -C "$root/.bare" symbolic-ref --short HEAD 2>/dev/null || true)
	[[ "$branch" == "$default_branch" ]] && die "won't ship the default branch ('$default_branch')"

	[[ -z "$(git status --porcelain 2>/dev/null)" ]] ||
		die "uncommitted changes here — commit, stash, or discard them before shipping"

	local pr_number pr_title pr_url
	pr_number=$(gh pr view --json number -q .number 2>/dev/null) || die "no open PR for '$branch' (try: wtree pr)"
	pr_title=$(gh pr view --json title -q .title 2>/dev/null)
	pr_url=$(gh pr view --json url -q .url 2>/dev/null)

	echo "PR #$pr_number: $pr_title" >&2
	echo "  $pr_url" >&2

	local reply
	read -r -p "Merge and ship this PR? [y/N] " reply || reply="n"
	[[ "$reply" =~ ^[Yy]$ ]] || {
		echo "aborted" >&2
		exit 1
	}

	echo "merging..." >&2
	gh pr merge "$pr_number" >&2 || true
	# gh pr merge's own post-merge housekeeping tries to switch the local
	# checkout to the base branch, which always fails here because the base
	# branch already has its own worktree - so its exit code isn't
	# trustworthy. Verify the merge actually happened independently, and
	# handle branch deletion ourselves rather than relying on --delete-branch
	# (which never gets that far when the housekeeping step fails first).

	local merged_at
	merged_at=$(gh pr view "$pr_number" --json mergedAt -q .mergedAt 2>/dev/null || true)
	[[ -n "$merged_at" && "$merged_at" != "null" ]] || die "PR #$pr_number was not merged"

	git -C "$root" push origin --delete "$branch" >&2 2>&1 || true

	git -C "$root" worktree remove "$branch"
	git -C "$root/.bare" branch -D "$branch" >/dev/null 2>&1 || true

	local landing="$root/$default_branch"
	[[ -d "$landing" ]] || landing="$root"

	echo "$landing"
}

case "${1:-}" in
clone)
	shift
	cmd_clone "$@"
	;;
add)
	shift
	cmd_add "$@"
	;;
rm)
	shift
	cmd_rm "$@"
	;;
list | ls)
	shift
	cmd_list "$@"
	;;
status)
	shift
	cmd_status "$@"
	;;
switch)
	shift
	cmd_switch "$@"
	;;
clean)
	shift
	cmd_clean "$@"
	;;
pr)
	shift
	cmd_pr "$@"
	;;
ship)
	shift
	cmd_ship "$@"
	;;
-v | --version | version) banner ;;
-h | --help | "") usage ;;
*) die "unknown command '$1' (see wtree --help)" ;;
esac
