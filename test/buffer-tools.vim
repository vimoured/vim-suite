" buffer-tools: what the dotfiles use of it. Ported from its test/run.vim.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('buffer-tools')

let s:tmp = resolve(tempname())
let s:out = []

function! s:reset() abort
  silent! only!
  silent! %bwipeout!
  call delete(s:tmp, 'rf')
  call mkdir(s:tmp, 'p')
  execute 'cd' fnameescape(s:tmp)
endfunction

function! s:suite.gb_skips_a_terminal_alternate() abort
  edit a.txt
  terminal ++curwin sleep 60
  edit b.txt
  normal gb
  call assert_equal('a.txt', bufname('%'))
endfunction

function! s:suite.gb_with_only_a_terminal_left() abort
  terminal ++curwin sleep 60
  edit a.txt
  call assert_equal("\nNo alternate buffer", execute('normal gb'))
  call assert_equal('a.txt', bufname('%'))
endfunction

let s:failed = 0

function! s:suite.before_each() abort
  call s:reset()
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction
