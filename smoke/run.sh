#!/bin/sh
# Runs in the smoke image, with the dotfiles at /dotfiles: sets Vim up as the
# dotfiles' install.sh does, installs every plugin they Plug, checks starship's
# prompt, then starts a real Vim on a terminal. Fails on the wrong prompt, when
# Vim reports an error or a plugin is missing. With $SMOKE_PIN ("<plugin> <commit>",
# any number of pairs), those plugins are checked out at those commits once
# installed: a pull request, and the branches of the same name.
set -eu
dots=/dotfiles

# install.sh, for Vim: vim-rc/ linked file by file into ~/.vim (link_tree),
# ~/.vimrc, and the backup and swap directories
cd "$dots/vim-rc"
find . -type f | while read -r file; do
  mkdir -p "$HOME/.vim/$(dirname "$file")"
  ln -sfn "$dots/vim-rc/$file" "$HOME/.vim/$file"
done
cd "$HOME"
ln -sfn "$HOME/.vim/.vimrc" "$HOME/.vimrc"
mkdir -p "$HOME/.vim/backup" "$HOME/.vim/swap"

echo "### plugins"
# Ex mode skips the vimrc unless -u names it
vim -Es -u "$HOME/.vimrc" -i NONE +PlugInstall +qall </dev/null || true
ls "$HOME/.vim/plugged"
set -- ${SMOKE_PIN:-}
while [ $# -gt 0 ]; do
  if [ -d "$HOME/.vim/plugged/$1/.git" ]; then
    git -C "$HOME/.vim/plugged/$1" fetch --quiet --depth 1 origin "$2"
    git -C "$HOME/.vim/plugged/$1" checkout --quiet --detach FETCH_HEAD
    echo "pinned $1 at $(git -C "$HOME/.vim/plugged/$1" rev-parse --short HEAD)"
  else
    echo "$1 isn't one of the dotfiles' plugins: nothing to pin"
  fi
  shift 2
done

echo "### prompt"
# install.sh, for starship
mkdir -p "$HOME/.config"
ln -sfn "$dots/config/starship/starship.toml" "$HOME/.config/starship.toml"
# Without its config, or with one it can't parse, starship still prints a
# prompt, its default, so only the exact text tells them apart
prompt=$(starship prompt 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
expected='
 ~   ❯ '
if [ "$prompt" != "$expected" ]; then
  printf 'prompt: expected [%s], got [%s]\n' "$expected" "$prompt"
  exit 1
fi
echo "prompt ok"

echo "### startup"
printf '# smoke\n' >"$HOME/smoke.md"
script -qec "vim -i NONE -c 'source /smoke/check.vim' smoke.md" /tmp/typescript >/dev/null </dev/null || status=$?
cat /tmp/smoke.out
exit "${status:-0}"
