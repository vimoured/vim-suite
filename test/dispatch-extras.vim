" dispatch-extras: what the dotfiles use of it (_rd, _rs, _dl, _cs in python
" buffers, their <localleader> maps; g:dispatch_no_tmux_start = 1) and its
" README, with real vim-dispatch runs. Before anything has run (a fresh Vim):
" test/dispatch-extras-before-any-run.vim.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('dispatch-extras')

let s:tmp = resolve(tempname())

function! s:running() abort
  return filter(term_list(), 'job_status(term_getjob(v:val)) ==# "run"')
endfunction

function! s:suite.before_each() abort
  " vim-dispatch's exit callback deletes its terminal's buffer: E516 if wiped
  for l:buf in s:running()
    call job_stop(term_getjob(l:buf), 'kill')
  endfor
  call s:wait('empty(s:running())', 'the terminals to end')
  silent! tabonly!
  silent! only!
  silent! %bwipeout!
  let g:dispatch_no_tmux_start = 1
  call delete(s:tmp, 'rf')
  call mkdir(s:tmp, 'p')
  execute 'cd' fnameescape(s:tmp)
  edit x.py
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

" Keys as typed; returns the messages they gave, and any error
function! s:type(keys) abort
  let v:errmsg = ''
  try
    let l:out = execute('call g:suite.feed(' . string(a:keys) . ')')
  catch
    return v:exception
  endtry
  return empty(v:errmsg) ? l:out : l:out . "\n" . v:errmsg
endfunction

" Waits up to 10s for a:cond (an expression) to hold
function! s:wait(cond, what) abort
  for l:i in range(200)
    if eval(a:cond)
      return 1
    endif
    sleep 50m
  endfor
  call assert_report('timed out waiting for ' . a:what)
  return 0
endfunction

function! s:lines(file) abort
  return filereadable(a:file) ? len(readfile(a:file)) : 0
endfunction

function! s:suite.repeat_start_reruns_the_last_start() abort
  Start! sh -c 'echo ran >> started'
  call s:wait("s:lines('started') == 1", 'the :Start')
  " vim-dispatch goes back to a :Start still running instead of repeating it
  call s:wait('empty(s:running())', 'the :Start to end')
  call assert_notmatch('E\d\+:', s:type('_rs'), 'no error')
  call s:wait("s:lines('started') == 2", 'the :Start again')
endfunction

function! s:suite.repeat_dispatch_reruns_the_last_dispatch() abort
  Dispatch sh -c 'echo ran >> dispatched; echo done'
  call s:wait("s:lines('dispatched') == 1", 'the :Dispatch')
  cclose
  call assert_notmatch('E\d\+:', s:type('_rd'), 'no error')
  call s:wait("s:lines('dispatched') == 2", 'the :Dispatch again')
endfunction

function! s:suite.log_opens_the_last_output() abort
  Dispatch sh -c 'echo the-output; touch done'
  call s:wait("filereadable('done')", 'the :Dispatch')
  sleep 500m
  cclose
  call assert_notmatch('E\d\+:', s:type('_dl'), 'no error')
  call assert_equal(2, tabpagenr('$'), 'in a new tab')
  call assert_match('the-output', join(getline(1, '$')))
endfunction

function! s:suite.toggle_start_strategy() abort
  call s:type('_cs')
  call assert_equal(0, g:dispatch_no_tmux_start, ':Start in tmux')
  call s:type('_cs')
  call assert_equal(1, g:dispatch_no_tmux_start, ':Start in a terminal')
endfunction

function! s:suite.toggle_start_strategy_says_which() abort
  call assert_equal("\nDefault Start strategy set to terminal: off", s:type('_cs'))
  call assert_equal("\nDefault Start strategy set to terminal: on", s:type('_cs'))
endfunction
