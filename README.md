<p align="center">
  <img src="logo.svg" width="140" alt="wtree logo">
</p>

<h1 align="center">wtree</h1>
<p align="center">bare-clone git worktrees, without the ceremony.</p>

`wtree` sets up a repo using the bare-clone + worktrees pattern so each branch gets its own real directory instead of stashing/switching in place.

<p align="center">
  <img src="demo.gif" alt="wtree demo" width="700">
</p>

## Install

### Homebrew (macOS)

```bash
brew tap lmaia-22/wtree
brew trust lmaia-22/wtree   # newer Homebrew requires trusting third-party taps before install
brew install wtree
```

Then add the shell integration line to your shell's rc file (the
formula prints this on install too) — don't just run it standalone,
since that only sources it for the current shell session:

```bash
# zsh: add this line to ~/.zshrc
source "$(brew --prefix)/opt/wtree/share/wtree/wtree.zsh"

# bash: add this line to ~/.bash_profile (macOS Terminal.app reads this
# for login shells) or ~/.bashrc, depending on which your setup uses
source "$(brew --prefix)/opt/wtree/share/wtree/wtree.bash"
```

Then restart your shell (or open a new terminal tab) for it to take effect.

### Manual

```bash
git clone https://github.com/lmaia-22/wtree.git ~/wtree
mkdir -p ~/bin && ln -s ~/wtree/wtree.sh ~/bin/wtree   # make sure ~/bin is on your PATH
```

Then add the following `source` line to your shell's rc file (`~/.zshrc`
for zsh, `~/.bash_profile` or `~/.bashrc` for bash) and restart your
shell:

```bash
source ~/wtree/shell/wtree.zsh   # or ~/wtree/shell/wtree.bash
```

Requires [`fzf`](https://github.com/junegunn/fzf) for `wtree switch`
with no argument, and [`gh`](https://cli.github.com/) for `wtree pr`
and `wtree ship`.

## Usage

```bash
cd ~/Developer/some-folder
wtree clone git@github.com:you/your-repo.git
cd your-repo
wtree add feature/x              # new worktree, new branch
wtree add hotfix/y origin/main   # new worktree, branched from origin/main
wtree status                     # branch / ahead-behind / dirty / identity, per worktree
wtree switch feature/x           # cd into that worktree (shell integration required)
wtree switch                     # fzf picker, then cd into your pick
wtree clean                      # remove broken and already-merged worktrees (with confirmation)
wtree rm feature/x               # remove a worktree
wtree list                       # raw `git worktree list`
wtree doctor                     # check for optional dependencies (fzf, gh)
wtree --version                  # print the wtree version

cd feature/x
wtree pr                         # push and open a PR for this branch
wtree ship                       # merge the PR and clean up (with confirmation)
```

Already have the repo checked out locally? `cd` into it and run
`wtree init` instead of `clone` — it creates a new sibling
`<repo>-wtree` project from your existing checkout (leaving the
original directory untouched) rather than cloning fresh from a URL.

Run `add`, `rm`, `status`, `switch`, `clean`, and `list` from anywhere
inside a project created with `wtree clone` or `wtree init` — they walk
up to find the project root automatically. `pr` and `ship` instead
operate on whatever branch is checked out where you run them, so run
those from inside the specific worktree.

## Hooks

New worktrees start empty — no `.env`, no `node_modules`, no local
config. To fix that, drop an executable `.wtree-hook` script at the
project root (next to `.bare`):

```bash
#!/usr/bin/env bash
# $1 is the branch name; cwd is already the new worktree.
cp ../main/.env .
npm install
```

`wtree add` runs it automatically, with the new worktree as the working
directory. It only lives at the project root, never inside any
worktree, so it's local-only by construction — nothing commits it,
nothing a cloned repo can plant on you. A failing hook prints a warning
but never removes the worktree it just created.

`.wtree-hook` has no file extension, so most editors show it as a
generic file with no syntax highlighting. In VS Code, add this to your
[user settings](https://code.visualstudio.com/docs/getstarted/settings)
(applies to every project, not just one) to get shell syntax
highlighting and a shell-script icon instead:

```json
"files.associations": {
  ".wtree-hook": "shellscript"
}
```

## Why

Plain `git worktree` works, but juggling worktree paths by hand gets
old. `wtree` wraps the bare-clone + worktrees pattern so every branch
is a real directory, `status` gives you an at-a-glance view across all
of them, and `switch` (with shell integration) makes moving between
them a single command.

## Development

Requires [`bats-core`](https://github.com/bats-core/bats-core),
[`shellcheck`](https://www.shellcheck.net/), [`shfmt`](https://github.com/mvdan/sh),
[`gh`](https://cli.github.com/), and `zsh` — `brew install bats-core
shellcheck shfmt gh zsh` (zsh ships with macOS already; the brew formula
is only needed on Linux). `gh` is required even to run the guard-clause
tests in `pr_ship.bats`, since `cmd_pr`/`cmd_ship` check for it before
anything else, and `zsh` is required for `shell_integration.bats` to run
at all.

```bash
bats test/                             # run the test suite
shellcheck wtree.sh shell/wtree.bash   # lint (zsh isn't shellcheck-compatible)
shfmt -d wtree.sh shell/wtree.bash     # check formatting
shfmt -w wtree.sh shell/wtree.bash     # auto-format
```

CI runs all of the above (plus a `zsh -n` syntax check) on every push
and PR, on both Linux and macOS.

## License

MIT
