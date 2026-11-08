" fzf-utils in a Vim started outside any project (project-detect looks once,
" at VimEnter): the scope keys fall back to a plain live grep, or say there's
" no such scope. In a project: test/fzf-utils.vim.
let s:tmp = resolve(tempname())
call mkdir(s:tmp . '/notes', 'p')
call writefile(['find_me'], s:tmp . '/notes/a.txt')
execute 'cd' fnameescape(s:tmp . '/notes')

let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('fzf-utils-outside-a-project')
let s:leader = get(g:, 'mapleader', '\')

function! s:suite.before_each() abort
  let g:suite.fzf = []
  silent! %bwipeout!
  edit a.txt
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

function! s:type(keys) abort
  return execute('call g:suite.feed(' . string(a:keys) . ')')
endfunction

function! s:query(spec) abort
  let l:opts = type(a:spec.options) == v:t_list ? join(a:spec.options, ' ') : a:spec.options
  return matchstr(l:opts, "'--query' '\\zs[^']*\\ze'")
endfunction

" One scope, all: no picking, a live grep
function! s:suite.grep_scope_is_a_plain_grep() abort
  call s:type(s:leader . 'rs')
  call assert_equal(1, len(g:suite.fzf))
  let l:opts = g:suite.fzf[0].options
  call assert_match('start:reload:rg ', type(l:opts) == v:t_list ? join(l:opts) : l:opts)
  call cursor(1, 1)
  call s:type(s:leader . 'rS')
  call assert_equal('\bfind_me\b', s:query(g:suite.fzf[-1]))
endfunction

function! s:suite.grep_code_or_tests_say_there_is_none() abort
  call assert_equal("\nGrep: no scope \"project\" in this project", s:type(s:leader . 'rp'))
  call assert_equal("\nGrep: no scope \"tests\" in this project", s:type(s:leader . 'rt'))
  call assert_equal([], g:suite.fzf, 'no grep')
endfunction
