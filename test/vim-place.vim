" vim-place: what the dotfiles use of it. Ported from its test/run.vim.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('vim-place')

" Only this plugin and fugitive, which finds git dirs for it ($FUGITIVE,
" else vim-plug's copy): Vim's own ones aren't all quiet in silent Ex mode

let s:tmp = resolve(tempname())
call mkdir(s:tmp . '/repo', 'p')
call system('git -C ' . shellescape(s:tmp . '/repo') . ' init -q')
call system('git -C ' . shellescape(s:tmp . '/repo') . ' -c user.name=t -c user.email=t@t'
      \ . ' commit -q --allow-empty -m init')
call system('git -C ' . shellescape(s:tmp . '/repo') . ' worktree add -q '
      \ . shellescape(s:tmp . '/linked'))
call mkdir(s:tmp . '/plain/sub', 'p')
let g:roumail_place_dir = s:tmp . '/saves'
let s:out = []

function! s:reset() abort
  silent! only!
  silent! %bwipeout!
  execute 'cd' fnameescape(s:tmp . '/plain')
endfunction

" What vim-place names a directory outside a repository by
function! s:place(dir) abort
  return fnamemodify(a:dir, ':t') . '-' . sha256(a:dir)[:7]
endfunction

function! s:suite.dir() abort
  let l:git = s:tmp . '/repo/.git'
  execute 'edit' fnameescape(s:tmp . '/repo/file.txt')
  call assert_equal(l:git . '/my-plugin/x', roumail_place#dir('my-plugin/x'))
  call assert_true(isdirectory(l:git . '/my-plugin/x'))
  " A linked work tree: the common git dir, else its own
  execute 'edit' fnameescape(s:tmp . '/linked/file.txt')
  call assert_equal(l:git . '/p', roumail_place#dir('p'))
  call assert_equal(l:git . '/worktrees/linked/p', roumail_place#dir('p', {'worktree': 1}))
  " Another buffer's repository
  let l:linked = bufnr()
  execute 'edit' fnameescape(s:tmp . '/outside.txt')
  call assert_equal(l:git . '/worktrees/linked/q', roumail_place#dir('q', {'bufnr': l:linked, 'worktree': 1}))
  " Outside a repository: one directory per current directory
  call assert_equal(g:roumail_place_dir . '/' . s:place(s:tmp . '/plain') . '/my-plugin/x',
        \ roumail_place#dir('my-plugin/x'))
  cd sub
  call assert_equal(g:roumail_place_dir . '/' . s:place(s:tmp . '/plain/sub') . '/my-plugin/x',
        \ roumail_place#dir('my-plugin/x'))
  call delete(g:roumail_place_dir, 'rf')
endfunction

function! s:suite.dir_xdg() abort
  let l:saved = [g:roumail_place_dir, $XDG_STATE_HOME]
  unlet g:roumail_place_dir
  let $XDG_STATE_HOME = s:tmp . '/state'
  try
    execute 'edit' fnameescape(s:tmp . '/outside.txt')
    let l:dir = s:tmp . '/state/' . s:place(s:tmp . '/plain') . '/my-plugin'
    call assert_equal(l:dir, roumail_place#dir('my-plugin'))
    call assert_true(isdirectory(l:dir))
  finally
    let [g:roumail_place_dir, $XDG_STATE_HOME] = l:saved
    call delete(s:tmp . '/state', 'rf')
  endtry
endfunction

" A file outside any repository, with the current directory in one: both
" say the current directory's repository
function! s:suite.get_and_dir_agree() abort
  execute 'edit' fnameescape(s:tmp . '/plain/file.txt')
  execute 'cd' fnameescape(s:tmp . '/repo')
  call assert_equal({'dir': s:tmp . '/repo', 'repo': 1}, roumail_place#get())
  call assert_equal(s:tmp . '/repo/.git/p', roumail_place#dir('p'))
  " A buffer of a repository fugitive hasn't seen yet: by its path
  execute 'badd' fnameescape(s:tmp . '/linked/other.txt')
  let l:linked = bufnr(s:tmp . '/linked/other.txt')
  call assert_equal({'dir': s:tmp . '/linked', 'repo': 1}, roumail_place#get(l:linked))
  call assert_equal(s:tmp . '/repo/.git/worktrees/linked/q',
        \ roumail_place#dir('q', {'bufnr': l:linked, 'worktree': 1}))
endfunction

function! s:suite.get() abort
  execute 'edit' fnameescape(s:tmp . '/repo/file.txt')
  call assert_equal({'dir': s:tmp . '/repo', 'repo': 1}, roumail_place#get())
  execute 'edit' fnameescape(s:tmp . '/linked/file.txt')
  call assert_equal({'dir': s:tmp . '/linked', 'repo': 1}, roumail_place#get())
  let l:linked = bufnr()
  execute 'edit' fnameescape(s:tmp . '/outside.txt')
  call assert_equal({'dir': s:tmp . '/linked', 'repo': 1}, roumail_place#get(l:linked))
  call assert_equal({'dir': s:tmp . '/plain', 'repo': 0}, roumail_place#get())
  " Outside a repository, the current directory's, if it is in one
  execute 'cd' fnameescape(s:tmp . '/repo')
  call assert_equal({'dir': s:tmp . '/repo', 'repo': 1}, roumail_place#get())
endfunction

let s:failed = 0

function! s:suite.before_each() abort
  call s:reset()
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction
