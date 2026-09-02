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

Run `add`, `rm`, `status`, `switch`, `clean`, and `list` from anywhere
inside a project created with `wtree clone` — they walk up to find the
project root automatically. `pr` and `ship` instead operate on whatever
branch is checked out where you run them, so run those from inside the
specific worktree.

## Why

Plain `git worktree` works, but juggling worktree paths by hand gets
old. `wtree` wraps the bare-clone + worktrees pattern so every branch
is a real directory, `status` gives you an at-a-glance view across all
of them, and `switch` (with shell integration) makes moving between
them a single command.

## License

MIT
