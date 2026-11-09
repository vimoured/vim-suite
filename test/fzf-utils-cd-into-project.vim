" fzf-utils in a Vim started outside the project, which then :cd's into it.
" Started in the project: test/fzf-utils-named-project.vim.
let s:tmp = resolve(tempname())
let s:root = s:tmp . '/flask'
call mkdir(s:root . '/blog', 'p')
call mkdir(s:tmp . '/elsewhere', 'p')
call writefile(['[project]', 'name = "blog"'], s:root . '/pyproject.toml')
call writefile([], s:root . '/blog/__init__.py')
call writefile(['def find_me(): pass'], s:root . '/blog/views.py')
execute 'cd' fnameescape(s:tmp . '/elsewhere')

let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('fzf-utils-cd-into-project')
let s:leader = get(g:, 'mapleader', '\')

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

function! s:suite.grep_code_after_cd_into_the_project() abort
  let g:suite.fzf = []
  execute 'cd' fnameescape(s:root)
  let l:said = execute('call g:suite.feed(' . string(s:leader . 'rp') . ')')
  call assert_equal('', l:said)
  call assert_equal(1, len(g:suite.fzf), 'a live grep')
endfunction
