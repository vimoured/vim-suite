" buffer-tools: what the dotfiles use of it, through the keys they reach it by
" (gb, <leader>bc) and its commands, as its README states it.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('buffer-tools')

let s:tmp = resolve(tempname())
" The dotfiles map <leader>bc to <Plug>(buffer-tools-close)
let s:close = get(g:, 'mapleader', '\') . 'bc'

function! s:reset() abort
  silent! only!
  silent! %bwipeout!
  call delete(s:tmp, 'rf')
  call mkdir(s:tmp, 'p')
  execute 'cd' fnameescape(s:tmp)
endfunction

" Keys as typed; returns the messages they gave, and any error (an error in
" a mapping only shows in v:errmsg)
function! s:type(keys) abort
  let v:errmsg = ''
  try
    let l:out = execute('call g:suite.feed(' . string(a:keys) . ')')
  catch
    return v:exception
  endtry
  return empty(v:errmsg) ? l:out : l:out . "\n" . v:errmsg
endfunction

" 'lastused' counts seconds: visits a second apart are ordered
function! s:visit(name) abort
  sleep 1100m
  execute 'edit' fnameescape(a:name)
endfunction

function! s:file(name, lines) abort
  call writefile(map(range(1, a:lines), '"line " . v:val'), a:name)
endfunction

" A netrw listing of the current directory, as the dotfiles show it
function! s:netrw() abort
  edit .
  call assert_equal('netrw', &filetype, 'netrw is loaded')
  return bufnr('%')
endfunction

function! s:suite.before_each() abort
  call s:reset()
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

" gb / :BufferAlt

function! s:suite.gb_goes_to_the_alternate_file() abort
  edit a.txt
  edit b.txt
  call s:type('gb')
  call assert_equal('a.txt', bufname('%'))
endfunction

function! s:suite.gb_skips_a_terminal_alternate() abort
  edit a.txt
  terminal ++curwin sleep 60
  " A running terminal is left with :hide ('hidden' is off in the dotfiles)
  hide edit b.txt
  call s:type('gb')
  call assert_equal('a.txt', bufname('%'))
endfunction

function! s:suite.gb_skips_a_netrw_listing() abort
  edit a.txt
  let l:listing = s:netrw()
  edit b.txt
  call assert_equal(l:listing, bufnr('#'), 'the listing is the alternate')
  call s:type('gb')
  call assert_equal('a.txt', bufname('%'))
endfunction

function! s:suite.gb_falls_back_to_the_most_recently_used() abort
  edit a.txt
  call s:visit('b.txt')
  sleep 1100m
  terminal ++curwin sleep 60
  hide edit c.txt
  " The alternate is the terminal; b.txt was used after a.txt
  call s:type('gb')
  call assert_equal('b.txt', bufname('%'))
endfunction

function! s:suite.gb_with_only_a_terminal_left() abort
  terminal ++curwin sleep 60
  hide edit a.txt
  call assert_equal("\nNo alternate buffer", s:type('gb'))
  call assert_equal('a.txt', bufname('%'))
endfunction

function! s:suite.gb_in_a_netrw_listing() abort
  edit a.txt
  edit b.txt
  call s:netrw()
  " netrw maps gb itself (its bookmarks); buffer-tools takes it back
  call s:type('gb')
  call assert_equal('b.txt', bufname('%'))
endfunction

function! s:suite.bufferalt_command() abort
  edit a.txt
  edit b.txt
  BufferAlt
  call assert_equal('a.txt', bufname('%'))
endfunction

" <leader>bc / :BufferClose

function! s:suite.close_keeps_the_window() abort
  " Another window, with another buffer: :bdelete alone would close this one
  edit a.txt
  split other.txt
  wincmd p
  edit b.txt
  let l:b = bufnr('%')
  let l:win = win_getid()
  call assert_equal('', s:type(s:close))
  call assert_equal(2, winnr('$'), 'both windows stay')
  call assert_equal(l:win, win_getid(), 'in the same window')
  call assert_notequal(l:b, bufnr('%'), 'showing another buffer')
  call assert_false(buflisted(l:b), 'b.txt is deleted')
endfunction

function! s:suite.close_shows_the_last_used() abort
  edit one.txt
  call s:visit('two.txt')
  call s:visit('three.txt')
  call s:visit('one.txt')
  call s:visit('three.txt')
  call s:type(s:close)
  call assert_equal('one.txt', bufname('%'))
endfunction

function! s:suite.close_skips_terminal_nofile_and_netrw() abort
  edit a.txt
  sleep 1100m
  terminal ++curwin sleep 60
  sleep 1100m
  hide enew
  setlocal buftype=nofile
  sleep 1100m
  call s:netrw()
  call s:visit('b.txt')
  call s:type(s:close)
  call assert_equal('a.txt', bufname('%'))
endfunction

function! s:suite.close_the_only_buffer() abort
  edit solo.txt
  let l:solo = bufnr('%')
  call assert_equal('', s:type(s:close))
  call assert_equal(1, winnr('$'), 'the window stays')
  call assert_equal(['', ''], [bufname('%'), &buftype], 'an empty buffer')
  call assert_false(buflisted(l:solo), 'solo.txt is deleted')
endfunction

function! s:suite.close_with_only_a_terminal_left() abort
  terminal ++curwin sleep 60
  let l:term = bufnr('%')
  " Keys typed in a terminal go to its job: first Terminal-Normal mode, by the
  " dotfiles' <C-w>n
  call assert_equal('', s:type("\<C-w>n" . s:close), 'no error')
  call assert_equal(1, winnr('$'), 'the window stays')
  call assert_equal(['', ''], [bufname('%'), &buftype], 'an empty buffer')
  call assert_false(buflisted(l:term), 'the terminal is deleted')
endfunction

function! s:suite.close_keeps_unsaved_changes() abort
  edit a.txt
  call s:visit('b.txt')
  call setline(1, 'unsaved change')
  let l:b = bufnr('%')
  call assert_equal("\nb.txt has unsaved changes", s:type(s:close))
  call assert_equal(l:b, bufnr('%'), 'it stays in the window')
  call assert_equal(['unsaved change'], getbufline(l:b, 1, '$'))
endfunction

function! s:suite.close_a_running_terminal_with_another_buffer_left() abort
  edit a.txt
  sleep 1100m
  terminal ++curwin sleep 60
  let l:term = bufnr('%')
  call assert_equal('', s:type("\<C-w>n" . s:close), 'no error')
  call assert_equal('a.txt', bufname('%'))
  call assert_false(buflisted(l:term), 'the terminal is deleted')
endfunction

function! s:suite.bufferclose_command() abort
  edit a.txt
  call s:visit('b.txt')
  let l:b = bufnr('%')
  BufferClose
  call assert_equal('a.txt', bufname('%'))
  call assert_false(buflisted(l:b), 'b.txt is deleted')
endfunction

" Files keep their place

function! s:suite.a_file_keeps_its_view_when_it_comes_back() abort
  call s:file('long.txt', 200)
  edit long.txt
  call cursor(150, 4)
  normal! zt
  let l:view = winsaveview()
  edit other.txt
  call s:type('gb')
  call assert_equal('long.txt', bufname('%'))
  call assert_equal([150, 3, 150], [l:view.lnum, l:view.col, l:view.topline])
  call assert_equal([l:view.lnum, l:view.col, l:view.topline],
        \ [winsaveview().lnum, winsaveview().col, winsaveview().topline])
endfunction

function! s:suite.a_file_reopens_where_the_cursor_was() abort
  call s:file('long.txt', 50)
  edit long.txt
  call cursor(30, 1)
  edit other.txt
  bdelete long.txt
  edit long.txt
  call assert_equal(30, line('.'))
endfunction

function! s:suite.a_commit_message_opens_at_the_top() abort
  call s:file('COMMIT_EDITMSG', 50)
  edit COMMIT_EDITMSG
  call assert_equal('gitcommit', &filetype)
  call cursor(30, 1)
  edit other.txt
  bdelete COMMIT_EDITMSG
  edit COMMIT_EDITMSG
  call assert_equal(1, line('.'))
endfunction
