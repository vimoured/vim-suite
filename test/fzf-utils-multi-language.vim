" fzf-utils in a project of more than one language, even with a name from its
" .vim.custom: no project, an error at startup, and the scope keys have no
" scope to search.
let s:tmp = resolve(tempname())
let s:root = s:tmp . '/mixed'
call mkdir(s:root . '/blog', 'p')
call writefile([], s:root . '/requirements.txt')
call writefile(['module example.com/app'], s:root . '/go.mod')
call writefile(['let g:project_name = "blog"'], s:root . '/.vim.custom')
call writefile(['def find_me(): pass'], s:root . '/blog/views.py')
execute 'cd' fnameescape(s:root)

let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('fzf-utils-multi-language')
let s:leader = get(g:, 'mapleader', '\')

function! s:suite.before_each() abort
  let g:suite.fzf = []
  edit blog/views.py
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

function! s:suite.startup_says_so() abort
  call assert_match('more than one language', execute('messages'))
endfunction

function! s:suite.grep_code_has_no_scope() abort
  call assert_equal("\nGrep: no scope \"project\" in this project",
        \ execute('call g:suite.feed(' . string(s:leader . 'rp') . ')'))
  call assert_equal([], g:suite.fzf, 'no grep')
endfunction
