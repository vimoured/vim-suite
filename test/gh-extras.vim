" gh-extras: what the dotfiles use of it. Ported from its test/run.vim.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('gh-extras')

let s:root = g:suite.deps . '/gh-extras'

let s:tmp = resolve(tempname())
let s:repo = s:tmp . '/repo'
let s:out = []

function! s:reset() abort
  silent! %bwipeout!
  call delete(s:tmp, 'rf')
  call mkdir(s:repo, 'p')
  call system('git -C ' . shellescape(s:repo) . ' init -q -b main && git -C '
        \ . shellescape(s:repo) . ' remote add origin https://github.com/o/r')
  execute 'cd' fnameescape(s:repo)
  execute 'edit' fnameescape(s:repo . '/x.txt')
endfunction

function! s:lines() abort
  return getline(1, '$')
endfunction

function! s:suite.prs() abort
  PRs
  call assert_equal('gh-extras://prs/repo', bufname())
  call assert_match('^Open PRs (2)  <CR> checkout  t threads  o browser  / filter  r refresh  q close$',
        \ getline(1))
  call assert_match('^#\s\+who\s\+title', getline(2))
  call assert_match('^#7 \+mira \+Fix login \+fix-login \+approved ', getline(3))
  call assert_match('^#8 \+sam \+Add search \+search \+draft ', getline(4))
  call assert_equal(3, line('.'))
  call feedkeys("/search\<CR>", 'x')
  call assert_match('^Open PRs (2), 1 matching ''search''', getline(1))
  call assert_equal(3, line('$'))
  call assert_match('^#8 ', getline('.'))
endfunction

function! s:suite.thread() abort
  Thread 7
  call assert_equal('gh-extras://thread/repo', bufname())
  call assert_equal(['#7: 2 open, 1 your turn  = open/close  <CR> file  :Reply  x resolve'
        \ . '  u resolved  o browser  / filter  r refresh  q close',
        \ 'a.py:9  open  (1)  me: nit',
        \ 'b.py:3  your turn  (2)  mira: because'], s:lines())
  call assert_equal(2, line('.'))
  " = opens the thread under the cursor, which stays on it
  call cursor(3, 1)
  normal =
  call assert_equal(['b.py:3  your turn', '    me (', '      why?'],
        \ [getline(3), getline(4)[:7], getline(5)])
  call assert_equal(3, line('.'))
  call assert_equal('T1', roumail_lists#item().id)
  normal =
  call assert_equal(3, line('$'))
  " u shows the resolved thread, in file order
  normal u
  call assert_equal('a.py:1  resolved  (1)  sam: done', getline(2))
  call assert_equal('T1', roumail_lists#item().id, 'still on its thread')
  " Opening it again, from the file, keeps u
  wincmd p
  Thread 7
  call assert_equal('gh-extras://thread/repo', bufname())
  call assert_equal(4, line('$'))
  call feedkeys("/sam\<CR>", 'x')
  call assert_equal(['a.py:1  resolved  (1)  sam: done'], getline(2, '$'))
endfunction

function! s:suite.threads() abort
  Threads
  call assert_equal('gh-extras://threads/repo', bufname())
  call assert_match('^Your threads: 2 open, 1 your turn  = open/close', getline(1))
  call assert_equal(['#7  fix-login  Fix login', '  a.py:9  open  (1)  me: nit',
        \ '  b.py:3  your turn  (2)  mira: because'], getline(2, '$'))
  call assert_equal(3, line('.'), 'on the first thread, not its PR')
  call cursor(2, 1)
  call assert_equal({}, roumail_lists#item())
  call assert_equal(7, roumail_lists#row().pr)
  " :Reply needs a thread under the cursor
  call assert_true(exists(':Reply') == 2)
endfunction

function! s:suite.before_each() abort
  call s:reset()
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction
