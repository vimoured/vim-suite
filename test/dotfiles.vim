" dotfiles: the Vim config loads, with every plugin, without an error.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('dotfiles')

function! s:suite.starts_without_errors() abort
  call assert_equal([], g:suite.errors)
endfunction
