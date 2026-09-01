# wtree

Bare-clone git worktrees, without the ceremony.

`wtree` sets up a repo using the bare-clone + worktrees pattern
(https://dev.to/metal3d/git-worktree-like-a-boss-2j1b), so each branch
gets its own real directory instead of stashing/switching in place.

## Install

### Homebrew (macOS)

```bash
brew tap lmaia-22/wtree
brew install wtree
```

Then source the shell integration for your shell (the formula prints
this on install too):

```bash
# zsh (~/.zshrc)
source "$(brew --prefix)/share/wtree/wtree.zsh"

# bash (~/.bashrc)
source "$(brew --prefix)/share/wtree/wtree.bash"
```

Restart your shell.

### Manual

```bash
git clone https://github.com/lmaia-22/wtree.git
ln -s "$PWD/wtree/wtree.sh" ~/bin/wtree   # anywhere on your PATH
source ~/path/to/wtree/shell/wtree.zsh    # or wtree.bash
```

Requires [`fzf`](https://github.com/junegunn/fzf) for `wtree switch`
with no argument.

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
wtree rm feature/x               # remove a worktree
wtree list                       # raw `git worktree list`
```

Run `add`, `rm`, `status`, `switch`, and `list` from anywhere inside a
project created with `wtree clone` — they walk up to find the project
root automatically.

## Why

Plain `git worktree` works, but juggling worktree paths by hand gets
old. `wtree` wraps the bare-clone + worktrees pattern so every branch
is a real directory, `status` gives you an at-a-glance view across all
of them, and `switch` (with shell integration) makes moving between
them a single command.

## License

MIT
