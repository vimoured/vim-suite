#!/bin/sh
# Runs in the smoke image, with the dotfiles at /dotfiles: sets Vim up as the
# dotfiles' install.sh does, installs every plugin they Plug, then starts a
# real Vim on a terminal. Fails when Vim reports an error or a plugin is
# missing. With $SMOKE_PIN ("<plugin> <commit>"), that plugin is checked out
# at that commit once installed: a plugin's pull request.
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
if [ -n "${SMOKE_PIN:-}" ]; then
  set -- $SMOKE_PIN
  if [ -d "$HOME/.vim/plugged/$1/.git" ]; then
    git -C "$HOME/.vim/plugged/$1" fetch --quiet --depth 1 origin "$2"
    git -C "$HOME/.vim/plugged/$1" checkout --quiet --detach FETCH_HEAD
    echo "pinned $1 at $(git -C "$HOME/.vim/plugged/$1" rev-parse --short HEAD)"
  else
    echo "$1 isn't one of the dotfiles' plugins: nothing to pin"
  fi
fi

echo "### startup"
printf '# smoke\n' >"$HOME/smoke.md"
script -qec "vim -i NONE -c 'source /smoke/check.vim' smoke.md" /tmp/typescript >/dev/null </dev/null || status=$?
cat /tmp/smoke.out
exit "${status:-0}"
