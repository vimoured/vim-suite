" text-tools: what the dotfiles use of it (g:text_tools_strip_on_save = 1, so
" every write strips; .pdbrc.py names the Normalize commands) and its README:
" the commands, and stripping on save.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('text-tools')

let s:tmp = resolve(tempname())

function! s:suite.before_each() abort
  silent! %bwipeout!
  call delete(s:tmp, 'rf')
  call mkdir(s:tmp, 'p')
  execute 'cd' fnameescape(s:tmp)
  enew
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

" Runs an Ex command; returns its error, or ''
function! s:run(cmd) abort
  let v:errmsg = ''
  try
    execute a:cmd
  catch
    return v:exception
  endtry
  return v:errmsg
endfunction

let s:sorted = ['{', '  "a": true,', '  "b": null', '}']

" Normalize

function! s:suite.normalize_python_dict() abort
  call setline(1, ["{'b': None, 'a': True}"])
  call assert_equal('', s:run('NormalizePythonDict'))
  call assert_equal(s:sorted, getline(1, '$'))
endfunction

function! s:suite.normalize_json_string() abort
  call setline(1, ['''{"b": null, "a": true}'''])
  call assert_equal('', s:run('NormalizeJsonString'))
  call assert_equal(s:sorted, getline(1, '$'))
endfunction

function! s:suite.normalize_a_range() abort
  call setline(1, ['before', "{'b': None, 'a': True}", 'after'])
  call assert_equal('', s:run('2NormalizePythonDict'))
  call assert_equal(['before'] + s:sorted + ['after'], getline(1, '$'))
endfunction

function! s:suite.normalize_keeps_text_it_cannot_read() abort
  let l:lines = ['{"a": oops}', 'keep me']
  call setline(1, l:lines)
  call assert_notequal('', s:run('1NormalizePythonDict'), 'an error')
  call assert_equal(l:lines, getline(1, '$'), 'the text as it was')
  call assert_notequal('', s:run('1NormalizeJsonString'), 'an error')
  call assert_equal(l:lines, getline(1, '$'), 'the text as it was')
endfunction

" Fold markers

function! s:suite.number_fold_markers() abort
  call setline(1, ['a {{{', 'b', 'c {{{', 'd {{{ e {{{'])
  call assert_equal('', s:run('NumberFoldMarkers'))
  call assert_equal(['a {{{ (1/4)', 'b', 'c {{{ (2/4)', 'd {{{ (3/4) e {{{ (4/4)'], getline(1, '$'))
endfunction

function! s:suite.number_fold_markers_again_renumbers() abort
  call setline(1, ['a {{{', 'b {{{'])
  NumberFoldMarkers
  call append(1, 'new {{{')
  call assert_equal('', s:run('NumberFoldMarkers'))
  call assert_equal(['a {{{ (1/3)', 'new {{{ (2/3)', 'b {{{ (3/3)'], getline(1, '$'))
endfunction

function! s:suite.strip_fold_marker_numbers() abort
  call setline(1, ['a {{{ (1/2)', 'b {{{ (2/2)', 'c'])
  call assert_equal('', s:run('StripFoldMarkerNumbers'))
  call assert_equal(['a {{{', 'b {{{', 'c'], getline(1, '$'))
endfunction

function! s:suite.fold_marker_commands_without_markers() abort
  call setline(1, ['plain'])
  call assert_equal('', s:run('NumberFoldMarkers'), 'number: no error')
  call assert_equal('', s:run('StripFoldMarkerNumbers'), 'strip: no error')
  call assert_equal(['plain'], getline(1, '$'))
endfunction

" Stripping

function! s:suite.strip_trailing_whitespace() abort
  call setline(1, ['x  ', '   ', "y\t", 'z'])
  " on a line it doesn't change (:%s alone ends on the last line it changed)
  call cursor(4, 1)
  call assert_equal('', s:run('StripTrailingWhitespace'))
  call assert_equal(['x', '   ', 'y', 'z'], getline(1, '$'))
  call assert_equal(4, line('.'), 'the cursor stays')
endfunction

function! s:suite.strip_trailing_cr() abort
  call setline(1, ["a\r", 'b', "c\r"])
  call assert_equal('', s:run('StripTrailingCR'))
  call assert_equal(['a', 'b', 'c'], getline(1, '$'))
endfunction

" On save (the dotfiles set g:text_tools_strip_on_save)

function! s:suite.dotfiles_strip_on_save() abort
  call assert_equal(1, get(g:, 'text_tools_strip_on_save', 0), 'set by the dotfiles')
endfunction

function! s:suite.saving_strips_cr_and_trailing_whitespace() abort
  edit f.txt
  call setline(1, ["a  \r", "b\t", 'c'])
  call assert_equal('', s:run('write'))
  call assert_equal(['a', 'b', 'c'], readfile('f.txt'))
endfunction

function! s:suite.saving_keeps_whitespace_when_the_buffer_says_so() abort
  edit f.txt
  let b:text_tools_strip_whitespace = 0
  call setline(1, ["a  \r", 'b  '])
  call assert_equal('', s:run('write'))
  call assert_equal(['a  ', 'b  '], readfile('f.txt'))
endfunction

function! s:suite.saving_with_stripping_off_for_the_buffer() abort
  edit f.txt
  let b:text_tools_strip_on_save = 0
  call setline(1, ["a  \r", 'b  '])
  call assert_equal('', s:run('write'))
  call assert_equal(["a  \r", 'b  ', ''], readfile('f.txt', 'b'), 'written as it is')
endfunction

function! s:suite.saving_a_buffer_that_cannot_change() abort
  edit f.txt
  call setline(1, ['a  '])
  setlocal nomodifiable
  call assert_equal('', s:run('write'), 'no error')
  call assert_equal(['a  '], readfile('f.txt'), 'written as it is')
endfunction
