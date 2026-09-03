#!/usr/bin/env bash
#
# wtree - set up a git repo using the bare-clone + worktrees pattern,
# and manage worktrees inside it.
#
# Pattern: https://dev.to/metal3d/git-worktree-like-a-boss-2j1b
#
# Usage:
#   wtree clone <repo-url> [dir-name]   Clone a repo as a worktree-ready project
#   wtree init [dir-name]               Convert the repo you're standing in into a wtree project
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

VERSION="0.4.0"

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
warn() { echo "${YELLOW}!${RESET} $*"; }

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
  wtree init [dir-name]               Convert the repo you're standing in into a wtree project
  wtree add <branch> [start-point]    Add a worktree for <branch>
  wtree rm <branch>                   Remove a worktree
  wtree list                          List worktrees in this project
  wtree status                        Show branch/ahead-behind/dirty/identity per worktree
  wtree switch [branch]               Print path to a worktree (fzf picker if no branch given)
  wtree clean                         Remove broken and already-merged worktrees (with confirmation)
  wtree pr                            Push and open a PR for the current worktree's branch
  wtree ship                          Merge the current branch's PR and clean up (with confirmation)
  wtree doctor                        Check for optional dependencies (fzf, gh)
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

# Bare-clones <source> into ./.bare (must be run with cwd already inside
# the target directory), writes the .git pointer file, and sets the
# standard fetch refspec. Does not fetch or create any worktree —
# callers do that afterward, since clone and init disagree on which
# branch gets the first worktree.
bare_clone_into() {
	local source="$1"
	info "bare-cloning $source into .bare"
	git clone --bare "$source" .bare
	echo "gitdir: ./.bare" >.git
	git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
}

# Refuses to let a name argument escape its intended sibling directory
# via a path separator - shared by clone and init's [name] argument.
# Must be an if/fi (not `[[ cond ]] && die`): as the last statement of
# a function called as a bare statement, a false && chain would leak
# its own non-zero exit status and silently kill the script under
# `set -e`, even though nothing actually failed.
require_plain_name() {
	if [[ "$1" == */* ]]; then
		die "name must be a plain directory name, not a path"
	fi
}

# Runs `git fetch origin --quiet` with cwd already inside the
# just-created target directory; on failure, removes that directory so
# a retry isn't blocked by a stale, incomplete project - the fetch is
# the first step in clone/init that can fail after mkdir due to
# something outside our control (network, permissions on the remote).
fetch_or_cleanup() {
	info "fetching all branches"
	if ! git fetch origin --quiet; then
		local target_path
		target_path=$(pwd)
		cd "$(dirname "$target_path")"
		rm -rf "$target_path"
		die "fetch failed — removed incomplete $(basename "$target_path")"
	fi
}

cmd_clone() {
	local url="${1:?repo url required}"
	local name="${2:-}"

	if [[ -z "$name" ]]; then
		name="${url%/}"
		name="${name##*/}"
		name="${name%.git}"
	fi
	require_plain_name "$name"

	[[ -e "$name" ]] && die "'$name' already exists here"

	info "looking up default branch"
	local default_branch
	default_branch=$(git ls-remote --symref "$url" HEAD | awk '/^ref:/{sub(".*refs/heads/", "", $2); print $2}')
	if [[ -z "$default_branch" ]]; then
		default_branch="main"
	fi

	mkdir "$name"
	cd "$name"

	bare_clone_into "$url"
	fetch_or_cleanup

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
	run_add_hook "$root" "$branch"
	whoami_here "$root/$branch"
}

# Runs $root/.wtree-hook (if present) with the new worktree as cwd and
# the branch name as $1. Never at project root nor under any worktree,
# so it's local-only by construction — nothing here is git-tracked.
run_add_hook() {
	local root="$1" branch="$2"
	local hook="$root/.wtree-hook"

	[[ -e "$hook" ]] || return 0

	if [[ ! -x "$hook" ]]; then
		warn ".wtree-hook exists but is not executable — skipping (chmod +x to enable)"
		return 0
	fi

	local rc=0
	(cd "$root/$branch" && "$hook" "$branch") || rc=$?
	if [[ $rc -eq 0 ]]; then
		ok "hook completed"
	else
		warn ".wtree-hook exited $rc — worktree created, but setup may be incomplete"
	fi
}

cmd_init() {
	local name="${1:-}"

	git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repo"

	local existing_root
	if existing_root=$(find_project_root); then
		die "already a wtree project (found .bare at $existing_root)"
	fi

	[[ "$(git rev-parse --is-bare-repository)" == "true" ]] && die "already a bare repository"

	local src
	src=$(git rev-parse --show-toplevel)

	git -C "$src" symbolic-ref -q HEAD >/dev/null || die "HEAD is detached — check out a branch before running wtree init"
	git -C "$src" rev-parse --verify -q HEAD >/dev/null || die "source repo has no commits yet"

	local dirty
	dirty=$(git -C "$src" status --porcelain)
	if [[ -n "$dirty" ]]; then
		die "working tree is dirty — commit or stash your changes first:
$dirty"
	fi
	if [[ -n "$(git -C "$src" stash list)" ]]; then
		die "you have a stash entry — commit or drop it first (git -C $src stash list)"
	fi

	local origin_url
	origin_url=$(git -C "$src" remote get-url origin 2>/dev/null) || die "no 'origin' remote configured — wtree init requires one"

	local branch
	branch=$(git -C "$src" rev-parse --abbrev-ref HEAD)

	local target="$name"
	[[ -z "$target" ]] && target="$(basename "$src")-wtree"
	require_plain_name "$target"
	local target_path
	target_path="$(dirname "$src")/$target"

	[[ -e "$target_path" ]] && die "'$target' already exists"

	mkdir "$target_path"
	cd "$target_path"

	bare_clone_into "$src"
	git -C .bare remote set-url origin "$origin_url"
	fetch_or_cleanup

	info "creating worktree for '$branch'"
	git worktree add "$branch" "$branch"

	if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
		git branch --set-upstream-to="origin/$branch" "$branch" >/dev/null
	fi

	ok "project ready at $(pwd)"
	whoami_here "$(pwd)/$branch"
	info "original directory left untouched — remove it yourself once you've verified the new project: rm -rf $src"
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

# Determines "owner/repo" for the current project's origin remote,
# independent of URL style (scp-like SSH, ssh://, or https).
repo_owner_slug() {
	local url
	url=$(git remote get-url origin) || return 1
	url="${url%.git}"
	if [[ "$url" == *"://"* ]]; then
		url="${url#*://}"
		url="${url#*/}"
	else
		url="${url#*:}"
	fi
	echo "$url"
}

# Picks whichever logged-in gh account can actually see the current
# repo and exports GH_TOKEN for it, scoped to this process only - never
# touches gh's global "active account" (gh auth switch changes that for
# every terminal). Falls back to gh's own active account (no override)
# whenever detection is inconclusive, so this is purely additive over
# gh's default behavior, never a new failure mode.
resolve_gh_account() {
	local slug
	slug=$(repo_owner_slug) || return 0

	local accounts
	accounts=$(gh auth status --hostname github.com --json hosts --jq \
		'.hosts["github.com"][] | "\(.active) \(.login)"' 2>/dev/null) || return 0
	[[ -n "$accounts" ]] || return 0

	local line login token
	while IFS= read -r line; do
		login="${line#* }"
		[[ -n "$login" ]] || continue
		token=$(gh auth token --hostname github.com --user "$login" 2>/dev/null) || continue
		if GH_TOKEN="$token" gh api "repos/$slug" >/dev/null 2>&1; then
			GH_TOKEN="$token"
			export GH_TOKEN
			# stderr, not stdout: cmd_ship's stdout must stay exactly the
			# landing path for the shell wrapper's `cd "$(command wtree
			# ship)"` to work.
			echo "${YELLOW}identity(gh):${RESET} $login" >&2
			return 0
		fi
	done < <(sort -r <<<"$accounts")
}

cmd_pr() {
	local root
	root=$(find_project_root) || die "not inside a wtree project (no .bare found)"
	root=$(cd "$root" && pwd -P)

	command -v gh >/dev/null || die "gh not found — install it (brew install gh) to use wtree pr"
	resolve_gh_account

	local branch
	branch=$(current_worktree_branch "$root")

	# Check for a matching remote branch by name, not merely "does an
	# upstream exist" - `wtree add <branch> <remote-branch>` lets git's own
	# branch.autoSetupMerge track a differently-named start point (e.g.
	# `wtree add hotfix/y origin/dev` tracks origin/dev), and a plain
	# `git push` then fails because the upstream's name doesn't match the
	# branch's own name.
	if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
		info "pushing '$branch'"
		git push
	else
		info "pushing '$branch' (setting upstream)"
		git push -u origin "$branch"
	fi

	gh pr create
}

cmd_ship() {
	local root
	root=$(find_project_root) || die "not inside a wtree project (no .bare found)"
	root=$(cd "$root" && pwd -P)

	command -v gh >/dev/null || die "gh not found — install it (brew install gh) to use wtree ship"
	resolve_gh_account

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

cmd_doctor() {
	local git_version
	git_version=$(git --version 2>/dev/null | awk '{print $3}') || die "git not found — wtree requires git"
	ok "git $git_version"

	if command -v fzf >/dev/null 2>&1; then
		ok "fzf $(fzf --version 2>/dev/null | awk '{print $1}') (used by: wtree switch, no-argument picker)"
	else
		warn "fzf not found — 'wtree switch' with no argument won't work (brew install fzf)"
	fi

	if command -v gh >/dev/null 2>&1; then
		ok "gh $(gh --version 2>/dev/null | awk 'NR==1{print $3}') (used by: wtree pr, wtree ship)"
	else
		warn "gh not found — 'wtree pr' and 'wtree ship' won't work (brew install gh)"
	fi
}

case "${1:-}" in
clone)
	shift
	cmd_clone "$@"
	;;
init)
	shift
	cmd_init "$@"
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
doctor)
	shift
	cmd_doctor "$@"
	;;
-v | --version | version) banner ;;
-h | --help | "") usage ;;
*) die "unknown command '$1' (see wtree --help)" ;;
esac
