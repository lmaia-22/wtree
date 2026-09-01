# 🌳 wtree

Bare-clone git worktrees, without the ceremony.

`wtree` sets up a repo using the bare-clone + worktrees pattern so each branch gets its own real directory instead of stashing/switching in place.

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
