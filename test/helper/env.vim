" Sourced by every spec. Loads the dotfiles' Vim config the way Vim would at
" startup, with every plugin in plugins.txt on the runtimepath (what vim-plug
" would add), in a private HOME. Startup happens in the current directory: a
" spec that needs Vim started in a project (project-detect looks once, at
" VimEnter) makes the project and cds into it before sourcing this.
"
" g:suite.deps      the checkouts ($SUITE_DEPS, default deps/)
" g:suite.errors    errors raised while loading; test/dotfiles.vim wants none
" g:suite.fzf       the spec of every fzf#run call (fzf itself never runs)
" $SUITE_PROFILE    a directory: profile the frozen plugins into it
" $SUITE_SKIP       a pattern: startup files matching it are not sourced (to
"                   find which part of the config a failure comes from)
if exists('g:suite')
  finish
endif
let g:suite = {'errors': [], 'fzf': []}
let g:suite.root = expand('<sfile>:p:h:h:h')
let g:suite.deps = empty($SUITE_DEPS) ? g:suite.root . '/deps' : fnamemodify($SUITE_DEPS, ':p:s?/$??')
set nocompatible hidden noswapfile encoding=utf-8

let g:suite.plugins = []
let g:suite.frozen = []
for s:line in readfile(g:suite.root . '/plugins.txt')
  let [s:name, s:repo, s:role] = (split(s:line) + ['', '', ''])[:2]
  if s:line =~# '^\s*\%(#\|$\)' || s:role ==# 'config' || s:role ==# 'runner'
    continue
  endif
  call add(g:suite.plugins, s:name)
  if s:role ==# 'frozen'
    call add(g:suite.frozen, s:name)
  endif
endfor

if !empty($SUITE_PROFILE)
  call mkdir($SUITE_PROFILE, 'p')
  execute 'profile start' fnameescape($SUITE_PROFILE . '/' . fnamemodify(get(g:, 'suite_spec', 'spec'), ':t:r') . '.prof')
  for s:name in g:suite.frozen
    execute 'profile! file' fnameescape(resolve(g:suite.deps . '/' . s:name)) . '/*'
  endfor
endif

" A private HOME: no ~/.vim.local, and what plugins save goes under it
let g:suite.home = resolve(tempname()) . '-home'
call mkdir(g:suite.home, 'p')
" What install.sh makes there for Vim ('backupdir', 'directory')
call mkdir(g:suite.home . '/.vim/backup', 'p')
call mkdir(g:suite.home . '/.vim/swap', 'p')
let $HOME = g:suite.home
let $XDG_STATE_HOME = g:suite.home . '/.local/state'
let $XDG_CONFIG_HOME = g:suite.home . '/.config'
let $GIT_CONFIG_NOSYSTEM = '1'
let $GIT_AUTHOR_NAME = 't' | let $GIT_AUTHOR_EMAIL = 't@t'
let $GIT_COMMITTER_NAME = 't' | let $GIT_COMMITTER_EMAIL = 't@t'
let $PATH = g:suite.root . '/test/bin:' . $PATH
" Outside any terminal multiplexer, whatever runs bin/test: a spec that needs
" one starts its own (a pane split here would land in your real terminal)
for s:var in ['TMUX', 'TMUX_PANE', 'TERM_PROGRAM', 'WEZTERM_PANE', 'WEZTERM_UNIX_SOCKET', 'WEZTERM_EXECUTABLE']
  execute 'unlet $' . s:var
endfor

execute 'source' fnameescape(g:suite.root . '/test/helper/autoload/plug.vim')

let g:suite.vimrc = g:suite.deps . '/dotfiles/vim-rc'
let s:dirs = [g:suite.vimrc] + map(copy(g:suite.plugins), 'g:suite.deps . "/" . v:val')
      \ + [g:suite.root . '/test/stub']
for s:dir in reverse(copy(s:dirs))
  execute 'set runtimepath^=' . fnameescape(s:dir)
endfor
for s:dir in s:dirs
  if isdirectory(s:dir . '/after')
    execute 'set runtimepath+=' . fnameescape(s:dir . '/after')
  endif
endfor

function! s:source(file) abort
  if !empty($SUITE_SKIP) && a:file =~# $SUITE_SKIP
    return
  endif
  try
    execute 'source' fnameescape(a:file)
  catch
    call add(g:suite.errors, a:file . ': ' . v:exception)
  endtry
endfunction

" Vim's startup order: vimrc, plugin/ in runtimepath order (the plugins, then
" Vim's own, e.g. netrw where it isn't a package yet), then after/plugin/
let $MYVIMRC = g:suite.vimrc . '/.vimrc'
call s:source($MYVIMRC)
filetype plugin on
for s:dir in s:dirs + [$VIMRUNTIME]
  for s:file in glob(s:dir . '/plugin/**/*.vim', 1, 1)
    call s:source(s:file)
  endfor
endfor
for s:dir in s:dirs
  for s:file in glob(s:dir . '/after/plugin/**/*.vim', 1, 1)
    call s:source(s:file)
  endfor
endfor
" The VimEnter autocommands of the config and plugins (Themis has had its own)
for s:group in uniq(sort(map(filter(autocmd_get({'event': 'VimEnter'}),
      \ 'get(v:val, "group", "themis") !~# "themis"'), 'v:val.group')))
  try
    execute 'doautocmd <nomodeline>' s:group 'VimEnter'
  catch
    call add(g:suite.errors, 'VimEnter ' . s:group . ': ' . v:exception)
  endtry
endfor

" fzf never runs: g:suite.fzf records what it was asked to show
execute 'source' fnameescape(g:suite.root . '/test/helper/autoload/fzf.vim')

" The last fzf#run spec's source command (a string, or '' for a list)
function! g:suite.source() abort
  let l:source = get(get(g:suite.fzf, -1, {}), 'source', '')
  return type(l:source) == v:t_string ? l:source : ''
endfunction

" Feeds keys as typed, mappings included
function! g:suite.feed(keys) abort
  call feedkeys(a:keys, 'xt')
endfunction
