" vim-draft: what the dotfiles use of it. Ported from its test/run.vim.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('vim-draft')

" Only this plugin, vim-place, where drafts are saved ($VIM_PLACE), and
" fugitive, which finds git dirs for it ($FUGITIVE), else vim-plug's copies:
" Vim's own ones aren't all quiet in silent Ex mode

let s:tmp = resolve(tempname())
call mkdir(s:tmp . '/repo', 'p')
call system('git -C ' . shellescape(s:tmp . '/repo') . ' init -q')
call system('git -C ' . shellescape(s:tmp . '/repo') . ' -c user.name=t -c user.email=t@t'
      \ . ' commit -q --allow-empty -m init')
call system('git -C ' . shellescape(s:tmp . '/repo') . ' worktree add -q '
      \ . shellescape(s:tmp . '/linked'))
call mkdir(s:tmp . '/plain/sub', 'p')
let g:roumail_draft_save_dir = s:tmp . '/saves'
let g:roumail_place_dir = s:tmp . '/places'
let s:sent = []
let s:out = []

function! s:Send(text) abort
  call add(s:sent, a:text)
endfunction

function! s:reset() abort
  let s:sent = []
  silent! only!
  silent! %bwipeout!
  execute 'cd' fnameescape(s:tmp . '/plain')
endfunction

" What vim-place names a directory outside a repository by
function! s:place(dir) abort
  return fnamemodify(a:dir, ':t') . '-' . sha256(a:dir)[:7]
endfunction

function! s:draft(...) abort
  call roumail_draft#open('test://draft', get(a:, 1, ['one', 'two']), function('s:Send'))
endfunction

" assert_fails() makes vim -Es exit non-zero even when it passes
function! s:fails(cmd, pattern) abort
  try
    execute a:cmd
    call assert_report(a:cmd . ': no error')
  catch
    call assert_match(a:pattern, v:exception)
  endtry
endfunction

function! s:saves(dir) abort
  return sort(glob(a:dir . '/*', 1, 1))
endfunction

" Drafts

function! s:suite.open() abort
  call s:draft()
  call assert_equal('test://draft', bufname())
  call assert_equal('acwrite', &buftype)
  call assert_equal(['one', 'two'], getline(1, '$'))
  call assert_equal([2, 3], [line('.'), col('.')])
  call assert_equal(2, winnr('$'))
  call assert_false(&modified)
endfunction

function! s:suite.wq_sends_saved_text() abort
  call s:draft([])
  call setline(1, ['', 'hello', 'world', '', ''])
  write
  call append('$', 'not saved')
  quit!
  call assert_equal(["hello\nworld"], s:sent)
  call assert_equal(1, winnr('$'))
endfunction

function! s:suite.quit_before_write_drops() abort
  call s:draft()
  quit!
  call assert_equal([], s:sent)
endfunction

function! s:suite.empty_sends_nothing() abort
  call s:draft([' ', ''])
  wq
  call assert_equal([], s:sent)
endfunction

function! s:suite.unique_name() abort
  call s:draft()
  let l:first = bufnr()
  call s:draft()
  call assert_equal('test://draft/' . bufnr(), bufname())
  call assert_notequal(l:first, bufnr())
endfunction

function! s:suite.last_window_keeps_vim() abort
  call s:draft()
  write
  only
  quit
  " Still running: the buffer it was opened from took the window
  call assert_equal(["one\ntwo"], s:sent)
  call assert_equal(1, winnr('$'))
endfunction

function! s:Fail(text) abort
  throw 'network down'
endfunction

function! s:suite.failed_hand_on_keeps_text() abort
  let l:dir = s:tmp . '/repo/.git/vim-draft'
  execute 'edit' fnameescape(s:tmp . '/repo/file.txt')
  call roumail_draft#open('test://draft', ['reply'], function('s:Fail'))
  setfiletype markdown
  call setline(1, ['reply', 'second line'])
  write
  call s:fails('quit', 'handing on failed (network down); text kept in .*/vim-draft/\d\{8}-\d\{6}\.md$')
  call assert_false(bufexists('test://draft'))
  let l:files = s:saves(l:dir)
  call assert_equal(1, len(l:files))
  call assert_equal(['reply', 'second line'], readfile(get(l:files, 0, '/nonexistent')))
  call delete(l:dir, 'rf')
endfunction

" Scratches

function! s:suite.scratch() abort
  Scratch
  call assert_equal(2, winnr('$'))
  call assert_equal('scratch1', bufname())
  call assert_equal(['nofile', 'wipe'], [&buftype, &bufhidden])
  Scratch
  call assert_equal(3, winnr('$'))
  call assert_equal('scratch2', bufname())
  Scratch!
  call assert_equal(3, winnr('$'))
endfunction

function! s:suite.scratch_from() abort
  ScratchFrom printf 'a\nb\n'
  call assert_equal(['a', 'b'], getline(1, '$'))
  call assert_equal('nofile', &buftype)
endfunction

function! s:suite.scratch_buf_range() abort
  call setline(1, ['x', 'y', 'z'])
  setfiletype python
  2,3ScratchBuf
  call assert_equal(['y', 'z'], getline(1, '$'))
  call assert_equal('python', &filetype)
  call assert_equal('nofile', &buftype)
endfunction

function! s:suite.scratch_buf_file() abort
  call writefile(['# title'], s:tmp . '/notes.md')
  execute 'ScratchBuf!' fnameescape(s:tmp . '/notes.md')
  call assert_equal(['# title'], getline(1, '$'))
  call assert_equal('markdown', &filetype)
  call assert_equal(1, winnr('$'))
endfunction

" Saving

function! s:suite.save_scratch() abort
  let l:dir = g:roumail_draft_save_dir
  Scratch!
  call setline(1, ['kept'])
  DraftSave
  let l:files = s:saves(l:dir)
  call assert_equal(1, len(l:files))
  call assert_match('/\d\{8}-\d\{6}\.txt$', get(l:files, 0, ''))
  call assert_equal(['kept'], readfile(get(l:files, 0, '/nonexistent')))
  " Still a scratch, and saving again updates the same file
  call assert_equal('nofile', &buftype)
  call setline(1, ['kept again'])
  DraftSave
  call assert_equal(l:files, s:saves(l:dir))
  call assert_equal(['kept again'], readfile(l:files[0]))
  call delete(l:dir, 'rf')
endfunction

function! s:suite.save_to_dir_and_path() abort
  Scratch!
  setfiletype markdown
  call setline(1, ['x'])
  execute 'DraftSave' fnameescape(s:tmp . '/kept/')
  call assert_match('/kept/\d\{8}-\d\{6}\.md$', get(s:saves(s:tmp . '/kept'), 0, ''))
  execute 'DraftSave' fnameescape(s:tmp . '/named.md')
  call assert_equal(['x'], readfile(s:tmp . '/named.md'))
  " Another buffer's file isn't overwritten without !
  Scratch!
  call setline(1, ['y'])
  call s:fails('DraftSave ' . fnameescape(s:tmp . '/named.md'), 'exists')
  call assert_equal(['x'], readfile(s:tmp . '/named.md'))
  execute 'DraftSave!' fnameescape(s:tmp . '/named.md')
  call assert_equal(['y'], readfile(s:tmp . '/named.md'))
endfunction

function! s:suite.save_draft_keeps_sending() abort
  execute 'edit' fnameescape(s:tmp . '/repo/file.txt')
  call s:draft(['reply'])
  setfiletype markdown
  call setline(1, ['reply, edited'])
  DraftSave
  let l:files = s:saves(s:tmp . '/repo/.git/vim-draft')
  call assert_equal(1, len(l:files))
  call assert_match('\.md$', get(l:files, 0, ''))
  call assert_equal(['reply, edited'], readfile(get(l:files, 0, '/nonexistent')))
  " Saving left the draft as it was: still to :w, and :wq sends
  call assert_equal('acwrite', &buftype)
  call assert_true(&modified)
  wq
  call assert_equal(['reply, edited'], s:sent)
endfunction

function! s:suite.save_draft_outside_git() abort
  let l:dir = g:roumail_place_dir
  execute 'edit' fnameescape(s:tmp . '/outside.txt')
  call s:draft(['x'])
  DraftSave
  call assert_equal(1, len(s:saves(l:dir . '/' . s:place(s:tmp . '/plain') . '/vim-draft')))
  DraftList
  call assert_equal(['x'], map(getloclist(0), 'v:val.text'))
  lclose
  " Another directory's drafts are its own
  call setloclist(0, [])
  cd sub
  silent DraftList
  call assert_equal([], getloclist(0))
  call delete(l:dir, 'rf')
endfunction

function! s:suite.save_scratch_xdg() abort
  let l:saved = [g:roumail_draft_save_dir, $XDG_STATE_HOME]
  unlet g:roumail_draft_save_dir
  let $XDG_STATE_HOME = s:tmp . '/state'
  try
    Scratch!
    call setline(1, ['x'])
    DraftSave
    call assert_equal(1, len(s:saves(s:tmp . '/state/vim-draft')))
  finally
    let [g:roumail_draft_save_dir, $XDG_STATE_HOME] = l:saved
    call delete(s:tmp . '/state', 'rf')
  endtry
endfunction

function! s:suite.save_other_buffer_in_repository() abort
  let l:dir = s:tmp . '/repo/.git/vim-draft'
  " Saves of the other tests in this repository
  call delete(l:dir, 'rf')
  execute 'cd' fnameescape(s:tmp . '/repo')
  new
  setlocal buftype=nofile bufhidden=hide noswapfile
  silent file ai-oneoff://question
  call setline(1, ['answer'])
  DraftSave
  let l:files = s:saves(l:dir)
  call assert_equal(1, len(l:files))
  call assert_equal(['answer'], readfile(get(l:files, 0, '/nonexistent')))
  call setline(1, ['answer again'])
  DraftSave
  call assert_equal(l:files, s:saves(l:dir))
  call assert_equal(['answer again'], readfile(l:files[0]))
  call assert_equal([], s:saves(g:roumail_draft_save_dir))
  call delete(l:dir, 'rf')
endfunction

function! s:suite.list() abort
  call mkdir(g:roumail_draft_save_dir, 'p')
  call writefile(['older'], g:roumail_draft_save_dir . '/a.txt')
  call writefile(['newer'], g:roumail_draft_save_dir . '/b.txt')
  call system('touch -t 202001010000 ' . shellescape(g:roumail_draft_save_dir . '/a.txt'))
  DraftList
  call assert_equal(['newer', 'older'], map(getloclist(0), 'v:val.text'))
  lclose
  call delete(g:roumail_draft_save_dir, 'rf')
endfunction

let s:failed = 0

function! s:suite.before_each() abort
  call s:reset()
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction
