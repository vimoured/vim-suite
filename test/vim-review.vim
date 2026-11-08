" vim-review: review#read() and review#write(), as fugitive-extras and
" vim-prompts call them, and its README.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('vim-review')

let s:tmp = resolve(tempname())
call mkdir(s:tmp, 'p')
let s:file = s:tmp . '/comments.txt'

function! s:reset() abort
  call delete(s:file)
endfunction

function! s:suite.read() abort
  call writefile([
        \ 'src/app.py:12: check the None case',
        \ 'src/app.py:20-24: is this loop needed?',
        \ "\tIt seems to repeat line 8.",
        \ "\t",
        \ "\tAnd line 9.",
        \ ], s:file)
  call assert_equal({'skipped': 0, 'comments': [
        \ {'path': 'src/app.py', 'start': 12, 'end': 12, 'body': 'check the None case'},
        \ {'path': 'src/app.py', 'start': 20, 'end': 24,
        \  'body': "is this loop needed?\nIt seems to repeat line 8.\n\nAnd line 9."},
        \ ]}, review#read(s:file))
endfunction

function! s:suite.read_counts_lines_not_in_the_format() abort
  call writefile([
        \ 'Here are my comments:',
        \ '',
        \ 'a.py:3: one',
        \ 'a.py: no line',
        \ ], s:file)
  call assert_equal({'skipped': 2, 'comments': [
        \ {'path': 'a.py', 'start': 3, 'end': 3, 'body': 'one'},
        \ ]}, review#read(s:file))
endfunction

" A tab-indented line before any comment isn't one; a comment's text may
" name another place
function! s:suite.read_edge_cases() abort
  call writefile([
        \ "\tstray",
        \ 'a.py:3: like b.py:5: here',
        \ ], s:file)
  call assert_equal({'skipped': 1, 'comments': [
        \ {'path': 'a.py', 'start': 3, 'end': 3, 'body': 'like b.py:5: here'},
        \ ]}, review#read(s:file))
endfunction

function! s:suite.write_and_read_back() abort
  let l:comments = [{'path': 'a.py', 'start': 1, 'end': 2, 'body': "\nafter a blank line"}]
  call review#write(s:file, l:comments)
  call assert_equal(['a.py:1-2: ', "\tafter a blank line"], readfile(s:file))
  call assert_equal({'skipped': 0, 'comments': l:comments}, review#read(s:file))
endfunction

function! s:suite.write() abort
  call review#write(s:file, [
        \ {'path': 'a.py', 'start': 3, 'end': 3, 'body': 'one'},
        \ {'path': 'dir/b.vim', 'start': 5, 'end': 7, 'body': "two\n\nthree"},
        \ ])
  call assert_equal([
        \ 'a.py:3: one',
        \ 'dir/b.vim:5-7: two',
        \ "\t",
        \ "\tthree",
        \ ], readfile(s:file))
endfunction

function! s:suite.before_each() abort
  call s:reset()
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction
