" fzf-utils in a Python project only g:project_name can name, as a project's
" .vim.custom sets it: pyproject.toml declares no name and several packages sit
" at the root, so the name says which one is the code. A name with no folder:
" test/project-detect.vim.
let s:tmp = resolve(tempname())
let s:root = s:tmp . '/flask'
for s:dir in ['blog', 'scripts', 'tests']
  call mkdir(s:root . '/' . s:dir, 'p')
endfor
call writefile([], s:root . '/pyproject.toml')
call writefile([], s:root . '/blog/__init__.py')
call writefile([], s:root . '/scripts/__init__.py')
call writefile(['let g:project_name = "blog"'], s:root . '/.vim.custom')
call writefile(['def find_me(): pass'], s:root . '/blog/views.py')
call writefile(['find_me in the notes'], s:root . '/blog/notes.txt')
call writefile(['def find_me(): pass'], s:root . '/scripts/tool.py')
call writefile(['def find_me(): pass'], s:root . '/tests/test_views.py')
execute 'cd' fnameescape(s:root)

let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('fzf-utils-named-project')
let s:leader = get(g:, 'mapleader', '\')

function! s:suite.before_each() abort
  let g:suite.fzf = []
  edit blog/views.py
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

function! s:type(keys) abort
  return execute('call g:suite.feed(' . string(a:keys) . ')')
endfunction

function! s:spec() abort
  return get(g:suite.fzf, -1, {})
endfunction

" The files the live grep fzf was last given matches find_me in
function! s:matched() abort
  let l:opts = type(s:spec().options) == v:t_list ? join(s:spec().options, ' ') : s:spec().options
  let l:cmd = substitute(matchstr(l:opts, "'start:reload:\\zs.\\{-}\\ze' '"), "'\\\\''", "'", 'g')
  let l:lines = systemlist('cd ' . shellescape(s:root) . ' && ' . l:cmd . 'find_me')
  return uniq(sort(map(l:lines, 'matchstr(substitute(v:val, "\\e\\[[0-9;]*m", "", "g"), "^[^:]*")')))
endfunction

function! s:suite.scopes() abort
  call s:type(s:leader . 'rs')
  call assert_equal(['all', 'project', 'project python', 'tests', 'tests python'], s:spec().source)
endfunction

" The named package's Python, without the other package's
function! s:suite.grep_code_is_the_named_package() abort
  call s:type(s:leader . 'rp')
  call assert_equal(['blog/views.py'], s:matched())
endfunction

function! s:suite.grep_tests() abort
  call s:type(s:leader . 'rt')
  call assert_equal(['tests/test_views.py'], s:matched())
endfunction

function! s:suite.project_scope_has_every_file_of_the_package() abort
  call s:type(s:leader . 'rs')
  call s:spec().sink('project')
  call assert_equal(['blog/notes.txt', 'blog/views.py'], s:matched())
endfunction
