" fzf-utils in a project of more than one language, like ruff: Rust crates with
" Python test data in them, beside a Python package. The picker has each
" language, and the code and tests keys search the current file's.
let s:tmp = resolve(tempname())
let s:root = s:tmp . '/mixed'
let s:files = {
      \ 'pyproject.toml': ['[project]', 'name = "mixed"', '[tool.maturin]', 'python-source = "python"', 'module-name = "mixed"'],
      \ 'Cargo.toml': ['[workspace]', 'members = ["crates/*"]'],
      \ 'crates/core/Cargo.toml': ['[package]', 'name = "core"'],
      \ 'crates/core/src/lib.rs': ['fn find_me() {}'],
      \ 'crates/core/tests/it.rs': ['fn find_me() {}'],
      \ 'crates/core/resources/fixture.py': ['def find_me(): pass'],
      \ 'python/mixed/__init__.py': ['def find_me(): pass'],
      \ 'python/mixed/test_it.py': ['def find_me(): pass'],
      \ 'notes.txt': ['find_me in the notes'],
      \ }
for [s:path, s:lines] in items(s:files)
  call mkdir(fnamemodify(s:root . '/' . s:path, ':h'), 'p')
  call writefile(s:lines, s:root . '/' . s:path)
endfor
execute 'cd' fnameescape(s:root)

let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('fzf-utils-multi-language')
let s:leader = get(g:, 'mapleader', '\')

function! s:suite.before_each() abort
  let g:suite.fzf = []
  edit python/mixed/__init__.py
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

function! s:suite.startup_has_no_error() abort
  call assert_notmatch('more than one language', execute('messages'))
endfunction

function! s:suite.scopes_have_each_language() abort
  call s:type(s:leader . 'rs')
  call assert_equal(['all', 'project', 'project python', 'project rust',
        \ 'tests', 'tests python', 'tests rust'], s:spec().source)
endfunction

function! s:suite.project_scope_is_every_languages_code() abort
  call s:type(s:leader . 'rs')
  call s:spec().sink('project')
  call assert_equal(['crates/core/resources/fixture.py', 'crates/core/src/lib.rs',
        \ 'crates/core/tests/it.rs', 'python/mixed/__init__.py', 'python/mixed/test_it.py'], s:matched())
endfunction

function! s:suite.grep_code_is_the_current_files_language() abort
  call s:type(s:leader . 'rp')
  call assert_equal(['python/mixed/__init__.py', 'python/mixed/test_it.py'], s:matched())
  edit crates/core/src/lib.rs
  let g:suite.fzf = []
  call s:type(s:leader . 'rp')
  call assert_equal(['crates/core/src/lib.rs', 'crates/core/tests/it.rs'], s:matched())
endfunction

function! s:suite.grep_tests_is_the_current_files_language() abort
  edit crates/core/src/lib.rs
  call s:type(s:leader . 'rt')
  call assert_equal(['crates/core/tests/it.rs'], s:matched())
endfunction

" Python in a Rust crate is the crate's: the Rust code is searched from it
function! s:suite.test_data_searches_its_crate() abort
  edit crates/core/resources/fixture.py
  call s:type(s:leader . 'rp')
  call assert_equal(['crates/core/src/lib.rs', 'crates/core/tests/it.rs'], s:matched())
endfunction

" In no language: every language's code
function! s:suite.a_file_of_no_language_searches_them_all() abort
  edit notes.txt
  call s:type(s:leader . 'rp')
  call assert_equal(['crates/core/resources/fixture.py', 'crates/core/src/lib.rs',
        \ 'crates/core/tests/it.rs', 'python/mixed/__init__.py', 'python/mixed/test_it.py'], s:matched())
endfunction
