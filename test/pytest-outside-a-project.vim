" pytest.vim in a Vim started outside any project (project-detect looks once,
" at VimEnter): no keys in a test-looking file, no project's tests. In a
" project: test/pytest.vim.
let s:tmp = resolve(tempname())
call mkdir(s:tmp . '/scratch', 'p')
call writefile(['def test_here():', '    pass'], s:tmp . '/scratch/test_here.py')
execute 'cd' fnameescape(s:tmp . '/scratch')

let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('pytest.vim-outside-a-project')
let s:lead = get(g:, 'maplocalleader', '\')

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

function! s:suite.no_project_no_tests_list() abort
  call assert_equal("\nPytestTests: no project here (project-detect)", execute('PytestTests'))
  call assert_equal(1, winnr('$'), 'no list opened')
endfunction

function! s:suite.no_keys_but_the_commands() abort
  edit test_here.py
  call assert_equal('', maparg(s:lead . 'rf', 'n'))
  call assert_equal(2, exists(':RunPytest'))
  call assert_equal(['test_here'], map(execute('PytestOutline') is# '' ? [] : getloclist(0), 'v:val.text'))
endfunction
