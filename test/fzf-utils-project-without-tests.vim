" fzf-utils in a project without tests, a Vim plugin with no test/ (a Python
" project always has some: its test_*.py globs), and project-detect looks once,
" at VimEnter: no tests scopes. With tests: test/fzf-utils.vim.
let s:tmp = resolve(tempname())
call mkdir(s:tmp . '/proj/plugin', 'p')
call writefile(['let g:find_me = 1'], s:tmp . '/proj/plugin/proj.vim')
execute 'cd' fnameescape(s:tmp . '/proj')

let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('fzf-utils-project-without-tests')
let s:leader = get(g:, 'mapleader', '\')

function! s:suite.before_each() abort
  let g:suite.fzf = []
  edit plugin/proj.vim
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

function! s:type(keys) abort
  return execute('call g:suite.feed(' . string(a:keys) . ')')
endfunction

function! s:suite.scopes_without_tests() abort
  call s:type(s:leader . 'rs')
  call assert_equal(['all', 'project', 'project vim'], g:suite.fzf[-1].source)
endfunction

function! s:suite.grep_tests_says_there_are_none() abort
  call assert_equal("\nGrep: no scope \"tests vim\" in this project", s:type(s:leader . 'rt'))
  call assert_equal([], g:suite.fzf)
endfunction
