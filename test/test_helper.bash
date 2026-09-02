# Shared setup for all .bats files. Loaded via: load test_helper

bats_require_minimum_version 1.5.0

# Absolute path to the wtree.sh under test — never resolved via PATH,
# since a globally-installed `wtree` on the developer's own machine is
# a real trap (it bit the shell integration work during manual testing
# earlier in this project).
WTREE_BIN="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)/wtree.sh"
WTREE_ROOT="$(dirname "$WTREE_BIN")"

# Creates a throwaway bare "origin" repo with one commit on $1 (default
# "main"), clones it with wtree, and cd's into the resulting project
# root. Prints nothing; sets PROJECT_ROOT for the caller.
wtree_setup_project() {
  local default_branch="${1:-main}"
  cd "$BATS_TEST_TMPDIR"
  mkdir origin.git
  git -C origin.git init -q --bare --initial-branch="$default_branch"

  git clone -q origin.git seed
  git -c user.name=test -c user.email=test@test.invalid -C seed commit -q --allow-empty -m init
  git -C seed push -q origin "$default_branch"
  rm -rf seed

  "$WTREE_BIN" clone "$BATS_TEST_TMPDIR/origin.git" proj >/dev/null 2>&1

  # Resolved via pwd -P, matching wtree.sh's own symlink resolution
  # (BATS_TEST_TMPDIR can be under /var/folders, a symlink to
  # /private/var/folders on macOS — comparing against an unresolved
  # path here would produce the exact same class of mismatch cmd_status
  # once had with /tmp vs /private/tmp).
  PROJECT_ROOT="$(cd "$BATS_TEST_TMPDIR/proj" && pwd -P)"
  cd "$PROJECT_ROOT"
}

# Puts a `wtree` executable (symlinked to $WTREE_BIN) at the front of
# PATH, so shell-integration tests exercise the real command under
# test via `command wtree`, not any other installed copy.
wtree_install_on_path() {
  local bindir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bindir"
  ln -sf "$WTREE_BIN" "$bindir/wtree"
  chmod +x "$bindir/wtree"
  PATH="$bindir:$PATH"
}

# Puts the mocked `gh` (test/fixtures/gh-mock/gh) at the front of PATH,
# ahead of any real gh installed on the machine running the tests.
# Behavior is controlled by GH_MOCK_* env vars set by the calling test.
wtree_install_gh_mock() {
  PATH="$WTREE_ROOT/test/fixtures/gh-mock:$PATH"
}
