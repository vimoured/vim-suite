# A lean Linux dev environment for the smoke test: Vim and what the dotfiles'
# Vim config and plugins run, based on dockstation's base stage. The dotfiles
# are mounted at /dotfiles when it runs (bin/smoke).
FROM debian:stable-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      vim-nox git curl ca-certificates ripgrep fzf python3 util-linux \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSLo /root/.vim/autoload/plug.vim --create-dirs \
      https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

# A UTF-8 terminal, as any real one is (the dotfiles' listchars need it)
ENV TERM=xterm-256color LANG=C.UTF-8 LC_ALL=C.UTF-8
WORKDIR /root
COPY run.sh check.vim /smoke/
ENTRYPOINT ["/smoke/run.sh"]
