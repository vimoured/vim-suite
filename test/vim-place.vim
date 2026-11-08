" vim-place: roumail_place#dir() and #get(), as the plugins that keep files
" call them (fugitive-extras, qf-tools, vim-draft, vim-prompts, ...), and its
" README.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('vim-place')

let s:tmp = resolve(tempname())
call mkdir(s:tmp . '/repo', 'p')
call system('git -C ' . shellescape(s:tmp . '/repo') . ' init -q')
call system('git -C ' . shellescape(s:tmp . '/repo') . ' -c user.name=t -c user.email=t@t'
      \ . ' commit -q --allow-empty -m init')
call system('git -C ' . shellescape(s:tmp . '/repo') . ' worktree add -q '
      \ . shellescape(s:tmp . '/linked'))
call mkdir(s:tmp . '/plain/sub', 'p')
let $XDG_STATE_HOME = s:tmp . '/state'

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
  " Outside a repository: the XDG state directory, one place per current
  " directory
  call assert_equal($XDG_STATE_HOME . '/' . s:place(s:tmp . '/plain') . '/my-plugin/x',
        \ roumail_place#dir('my-plugin/x'))
  call assert_true(isdirectory($XDG_STATE_HOME . '/' . s:place(s:tmp . '/plain') . '/my-plugin/x'))
  cd sub
  call assert_equal($XDG_STATE_HOME . '/' . s:place(s:tmp . '/plain/sub') . '/my-plugin/x',
        \ roumail_place#dir('my-plugin/x'))
  " No XDG state directory set: ~/.local/state
  let l:state = $XDG_STATE_HOME
  try
    unlet $XDG_STATE_HOME
    call assert_equal(expand('~/.local/state') . '/' . s:place(s:tmp . '/plain/sub') . '/p', roumail_place#dir('p'))
  finally
    let $XDG_STATE_HOME = l:state
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

" A buffer that isn't a file (a list, a draft) is in the current
" directory's, whatever its name looks like
function! s:suite.a_buffer_not_a_file_is_the_current_directorys() abort
  enew
  setlocal buftype=nofile
  execute 'silent file' fnameescape(s:tmp . '/linked/list')
  call assert_equal({'dir': s:tmp . '/plain', 'repo': 0}, roumail_place#get())
  execute 'cd' fnameescape(s:tmp . '/repo')
  call assert_equal(s:tmp . '/repo/.git/p', roumail_place#dir('p'))
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

function! s:suite.before_each() abort
  call s:reset()
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction
