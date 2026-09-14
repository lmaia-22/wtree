# wtree shell integration for bash.
# Source this file in your .bashrc:
#   source /path/to/wtree.bash

wtree() {
	case "${1:-}" in
	switch | ship)
		local dest
		dest="$(command wtree "$@")" || return $?
		[[ -n "$dest" ]] || return 0
		cd "$dest" || return $?
		;;
	"")
		local dest
		dest="$(command wtree switch)" || return $?
		[[ -n "$dest" ]] || return 0
		cd "$dest" || return $?
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
			printf '%s\n' "$dir"
			return 0
		fi
		dir=$(dirname "$dir")
	done
	return 1
}

_wtree_branches() {
	local root
	root=$(_wtree_project_root) || return 1
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
	root=$(_wtree_project_root) || return 1
	git -C "$root/.bare" for-each-ref --format='%(refname:short)' refs/heads |
		while IFS= read -r b; do
			if [[ -d "$root/$b" ]]; then
				printf '%s\n' "$b"
			fi
		done
}

_wtree_compreply_from() {
	COMPREPLY=()
	local line
	while IFS= read -r line; do
		COMPREPLY+=("$line")
	done < <(compgen -W "$1" -- "$2")
}

_wtree_complete() {
	local cur
	cur="${COMP_WORDS[COMP_CWORD]}"
	if [[ $COMP_CWORD -eq 1 ]]; then
		_wtree_compreply_from "clone init add rm status switch list clean pr ship doctor" "$cur"
		return
	fi
	case "${COMP_WORDS[1]}" in
	switch | rm)
		_wtree_compreply_from "$(_wtree_worktrees)" "$cur"
		;;
	add)
		_wtree_compreply_from "$(_wtree_branches)" "$cur"
		;;
	esac
}
complete -F _wtree_complete wtree
