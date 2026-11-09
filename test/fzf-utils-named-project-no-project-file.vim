" fzf-utils in a project nothing recognises, named by its .vim.custom: the name
" alone gives the scope keys the named folder.
let s:tmp = resolve(tempname())
let s:root = s:tmp . '/flask'
for s:dir in ['blog', 'scripts', 'tests']
  call mkdir(s:root . '/' . s:dir, 'p')
endfor
call writefile(['let g:project_name = "blog"'], s:root . '/.vim.custom')
call writefile(['find_me'], s:root . '/blog/views.txt')
call writefile(['find_me'], s:root . '/scripts/tool.txt')
call writefile(['find_me'], s:root . '/tests/views.txt')
execute 'cd' fnameescape(s:root)

let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('fzf-utils-named-project-no-project-file')
let s:leader = get(g:, 'mapleader', '\')

function! s:suite.before_each() abort
  let g:suite.fzf = []
  edit blog/views.txt
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

function! s:type(keys) abort
  return execute('call g:suite.feed(' . string(a:keys) . ')')
endfunction

" The files the live grep fzf was last given matches find_me in
function! s:matched() abort
  let l:opts = g:suite.fzf[-1].options
  let l:opts = type(l:opts) == v:t_list ? join(l:opts, ' ') : l:opts
  let l:cmd = substitute(matchstr(l:opts, "'start:reload:\\zs.\\{-}\\ze' '"), "'\\\\''", "'", 'g')
  let l:lines = systemlist('cd ' . shellescape(s:root) . ' && ' . l:cmd . 'find_me')
  return uniq(sort(map(l:lines, 'matchstr(substitute(v:val, "\\e\\[[0-9;]*m", "", "g"), "^[^:]*")')))
endfunction

function! s:suite.scopes() abort
  call s:type(s:leader . 'rs')
  call assert_equal(['all', 'project', 'tests'], g:suite.fzf[-1].source)
endfunction

function! s:suite.grep_code_is_the_named_folder() abort
  call assert_equal('', s:type(s:leader . 'rp'))
  call assert_equal(['blog/views.txt'], s:matched())
endfunction

function! s:suite.grep_tests() abort
  call assert_equal('', s:type(s:leader . 'rt'))
  call assert_equal(['tests/views.txt'], s:matched())
endfunction
