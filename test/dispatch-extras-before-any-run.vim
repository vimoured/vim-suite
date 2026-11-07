" dispatch-extras in a Vim where nothing has been dispatched yet (vim-dispatch
" keeps its runs for the session): the maps say so and do nothing. With runs:
" test/dispatch-extras.vim.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('dispatch-extras-before-any-run')

let s:tmp = resolve(tempname())

function! s:suite.before_each() abort
  call delete(s:tmp, 'rf')
  call mkdir(s:tmp, 'p')
  execute 'cd' fnameescape(s:tmp)
  edit x.py
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

function! s:type(keys) abort
  let v:errmsg = ''
  try
    let l:out = execute('call g:suite.feed(' . string(a:keys) . ')')
  catch
    return v:exception
  endtry
  return empty(v:errmsg) ? l:out : l:out . "\n" . v:errmsg
endfunction

function! s:suite.repeat_start_says_there_is_none() abort
  call assert_equal("\nNo previous dispatch command to repeat", s:type('_rs'))
endfunction

" One test, log first: today repeat-dispatch starts a run (b:dispatch or :Make),
" which would leave a run behind
function! s:suite.log_and_repeat_dispatch_say_there_is_none() abort
  call assert_match('^\nNo previous dispatch', s:type('_dl'), 'log: a message, no error')
  call assert_equal(1, tabpagenr('$'), 'log: nothing opens')
  " :Dispatch with no arguments would run b:dispatch (in a python buffer, the
  " dotfiles' pytest runner) or :Make
  call assert_match('^\nNo previous dispatch', s:type('_rd'), 'repeat: a message')
  call assert_equal('', getqflist({'title': 1}).title, 'repeat: nothing dispatched')
endfunction
