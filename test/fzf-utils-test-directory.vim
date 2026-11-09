let s:tmp = resolve(tempname())
let s:root = s:tmp . '/proj'
for [s:path, s:lines] in items({
      \ 'pyproject.toml': ['[project]', 'name = "pkg"'],
      \ 'pkg/__init__.py': ['def find_me(): pass'],
      \ 'test/conftest.py': ['def find_me(): pass'],
      \ 'test/notes.txt': ['find_me in the notes'],
      \ })
  call mkdir(fnamemodify(s:root . '/' . s:path, ':h'), 'p')
  call writefile(s:lines, s:root . '/' . s:path)
endfor
execute 'cd' fnameescape(s:root)

let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('fzf-utils-test-directory')

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

function! s:suite.grep_tests_searches_the_test_directory() abort
  let g:suite.fzf = []
  edit pkg/__init__.py
  call execute('call g:suite.feed(' . string(get(g:, 'mapleader', '\') . 'rt') . ')')
  let l:options = g:suite.fzf[-1].options
  call assert_equal(['test/conftest.py'], uniq(sort(map(systemlist('cd ' . shellescape(s:root) . ' && '
        \ . substitute(matchstr(type(l:options) == v:t_list ? join(l:options, ' ') : l:options,
        \   "'start:reload:\\zs.\\{-} -e \\ze"), "'\\\\''", "'", 'g') . 'find_me'),
        \ 'matchstr(substitute(v:val, "\\e\\[[0-9;]*m", "", "g"), "^[^:]*")'))))
endfunction
