" vim-draft: what the dotfiles use of it (:Scratch, also from the shell's
" `scratch` alias, `vim -c Scratch -c only`; :DraftSave), what other plugins
" call (roumail_draft#open: fugitive-extras', gh-extras' and vim-prompts'
" drafts), and its README, through its commands. Saved scratches go to
" vim-draft/ in the XDG state directory, in env.vim's private HOME; drafts
" where vim-place keeps plugins' files.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('vim-draft')

let s:tmp = resolve(tempname())
let s:scratches = $XDG_STATE_HOME . '/vim-draft'
let g:roumail_place_dir = s:tmp . '/places'
let s:sent = []

function! s:Send(text) abort
  call add(s:sent, a:text)
endfunction

function! s:Fail(text) abort
  throw 'network down'
endfunction

" A repo, a linked work tree of it, and a plain directory with a subdirectory
function! s:reset() abort
  let s:sent = []
  silent! only!
  silent! %bwipeout!
  call delete(s:tmp, 'rf')
  call delete(s:scratches, 'rf')
  call mkdir(s:tmp . '/repo', 'p')
  call system('git -C ' . shellescape(s:tmp . '/repo') . ' init -q')
  call system('git -C ' . shellescape(s:tmp . '/repo') . ' commit -q --allow-empty -m init')
  call mkdir(s:tmp . '/plain/sub', 'p')
  execute 'cd' fnameescape(s:tmp . '/plain')
endfunction

function! s:suite.before_each() abort
  call s:reset()
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

" What vim-place names a directory outside a repository by
function! s:place(dir) abort
  return fnamemodify(a:dir, ':t') . '-' . sha256(a:dir)[:7]
endfunction

function! s:draft(...) abort
  call roumail_draft#open('test://draft', get(a:, 1, ['one', 'two']), function('s:Send'),
        \ get(a:, 2, {}))
endfunction

" An Ex command; returns its messages, or the error it raised
function! s:run(cmd) abort
  try
    return execute(a:cmd)
  catch
    return v:exception
  endtry
endfunction

function! s:saves(dir) abort
  return sort(glob(a:dir . '/*', 1, 1))
endfunction

" Without vim-place: what needs it says so
function! s:without_place(cmd) abort
  let l:rtp = &runtimepath
  try
    execute 'set runtimepath-=' . fnameescape(g:suite.deps . '/vim-place')
    return s:run(a:cmd)
  finally
    let &runtimepath = l:rtp
  endtry
endfunction

""" A draft, as another plugin opens it

function! s:suite.open() abort
  call s:draft()
  call assert_equal('test://draft', bufname())
  call assert_equal(['one', 'two'], getline(1, '$'))
  call assert_equal([2, 3], [line('.'), col('.')], 'at the end of its text')
  call assert_equal('n', mode(), 'in normal mode')
  call assert_equal(2, winnr('$'))
  call assert_equal(2, winnr(), 'split below')
  call assert_false(&modified)
endfunction

function! s:suite.open_with_options() abort
  call s:draft(['x'], {'split': 'botright vnew', 'saved': 'Note saved', 'empty': 'Note empty'})
  call assert_equal([2, winwidth(0) < &columns], [winnr('$'), 1], 'a vertical split')
  call assert_equal("\nNote saved", s:run('write'))
  call setline(1, '')
  call assert_equal("\nNote empty", s:run('write'))
endfunction

function! s:suite.write_says_whether_closing_hands_it_on() abort
  call s:draft()
  call assert_equal("\nDraft saved: closing hands it on", s:run('write'))
  call setline(1, ['', ''])
  call assert_equal("\nDraft empty: closing hands nothing on", s:run('write'))
endfunction

function! s:suite.wq_hands_on_saved_text() abort
  call s:draft([])
  call setline(1, ['', 'hello', 'world', '', ''])
  write
  call append('$', 'not saved')
  quit!
  call assert_equal(["hello\nworld"], s:sent, 'what :w saved, without the blank lines around it')
  call assert_equal(1, winnr('$'))
endfunction

function! s:suite.quit_before_write_drops() abort
  call s:draft()
  quit!
  call assert_equal([], s:sent)
endfunction

function! s:suite.empty_hands_on_nothing() abort
  call s:draft(['x'])
  write
  " A saved draft is dropped by emptying it
  call setline(1, [' ', ''])
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
  edit from.txt
  call s:draft()
  write
  only
  quit
  " Still running: the buffer it was opened from took the window
  call assert_equal(["one\ntwo"], s:sent)
  call assert_equal(['from.txt'], map(range(1, winnr('$')), 'bufname(winbufnr(v:val))'))
  " Opened from a buffer gone since: an empty one
  call s:draft()
  only
  bwipeout! from.txt
  write
  quit
  call assert_equal([1, ''], [winnr('$'), bufname()])
endfunction

function! s:suite.failed_hand_on_keeps_text() abort
  execute 'edit' fnameescape(s:tmp . '/repo/file.txt')
  call roumail_draft#open('test://draft', ['reply'], function('s:Fail'))
  setfiletype markdown
  call setline(1, ['reply', 'second line'])
  write
  call assert_match('^vim-draft: handing on failed (network down); text kept in .*/vim-draft/\d\{8}-\d\{6}\.md$',
        \ s:run('quit'))
  call assert_false(bufexists('test://draft'))
  let l:files = s:saves(s:tmp . '/repo/.git/vim-draft')
  call assert_equal(1, len(l:files))
  call assert_equal(['reply', 'second line'], readfile(get(l:files, 0, '/nonexistent')))
endfunction

" Where the file can't be written: the unnamed register
function! s:suite.failed_hand_on_keeps_text_in_the_register() abort
  call mkdir(s:tmp . '/places', 'p')
  call writefile([], s:tmp . '/places/' . s:place(s:tmp . '/plain'))
  call roumail_draft#open('test://draft', ['reply'], function('s:Fail'))
  write
  call assert_equal('vim-draft: handing on failed (network down); text kept in the unnamed register',
        \ s:run('quit'))
  call assert_equal("reply\n", getreg('"'))
endfunction

""" Scratches

function! s:suite.scratch() abort
  Scratch
  call assert_equal(2, winnr('$'))
  call assert_true(winwidth(0) < &columns, 'a vertical split')
  call assert_equal('scratch1', bufname())
  call assert_equal(['nofile', 'wipe'], [&buftype, &bufhidden])
  Scratch
  call assert_equal(3, winnr('$'))
  call assert_equal('scratch2', bufname())
  " ! in the current window: scratch2 is dropped, and its name free again
  Scratch!
  call assert_equal([3, 'scratch2'], [winnr('$'), bufname()], '! in the current window')
  " Closing drops it
  call setline(1, 'gone')
  quit
  call assert_false(bufexists('scratch2'))
endfunction

" The shell's scratch alias
function! s:suite.scratch_alone() abort
  Scratch
  only
  call assert_equal([1, 'scratch1'], [winnr('$'), bufname()])
endfunction

function! s:suite.scratch_from() abort
  ScratchFrom printf 'a\nb\n'
  call assert_equal(['a', 'b'], getline(1, '$'))
  call assert_equal(['nofile', 1], [&buftype, winnr('$')])
  call assert_notequal(-1, index(getcompletion('ScratchFrom printf', 'cmdline'), 'printf'), 'a command')
  call writefile([], s:tmp . '/plain/notes.txt')
  call assert_equal(['notes.txt'], getcompletion('ScratchFrom cat no', 'cmdline'), 'then files')
endfunction

function! s:suite.scratch_buf() abort
  edit code.py
  call setline(1, ['x', 'y', 'z'])
  2,3ScratchBuf
  call assert_equal(['y', 'z'], getline(1, '$'))
  call assert_equal(['python', 'nofile', 2], [&filetype, &buftype, winnr('$')])
  only
  " No range: all of it
  edit code.py
  2
  ScratchBuf!
  call assert_equal(['x', 'y', 'z'], getline(1, '$'))
  " Another buffer, whole: by name, number or #
  edit other.txt
  ScratchBuf code.py
  call assert_equal(['x', 'y', 'z'], getline(1, '$'))
  only
  execute 'ScratchBuf!' bufnr('code.py')
  call assert_equal([['x', 'y', 'z'], 1], [getline(1, '$'), winnr('$')])
  edit other.txt
  edit code.py
  ScratchBuf! #
  call assert_equal([''], getline(1, '$'), 'other.txt')
endfunction

function! s:suite.scratch_buf_file() abort
  call writefile(['# title'], s:tmp . '/notes.md')
  execute 'ScratchBuf!' fnameescape(s:tmp . '/notes.md')
  call assert_equal(['# title'], getline(1, '$'))
  call assert_equal(['markdown', 1], [&filetype, winnr('$')])
  call assert_match('^Vim(echoerr):ScratchBuf: no buffer or file matching nope$', s:run('ScratchBuf nope'))
  edit code.py
  call writefile([], s:tmp . '/plain/code.txt')
  call assert_equal(['code.py', 'code.txt'], getcompletion('ScratchBuf code', 'cmdline'),
        \ 'buffers, then files')
endfunction

""" Saving

function! s:suite.save_scratch() abort
  Scratch!
  call setline(1, ['kept'])
  call assert_match('^\nDraftSave: wrote .*/vim-draft/\d\{8}-\d\{6}\.txt$', s:run('DraftSave'))
  let l:files = s:saves(s:scratches)
  call assert_equal(1, len(l:files))
  call assert_equal(['kept'], readfile(get(l:files, 0, '/nonexistent')))
  " Still a scratch, and saving again updates the same file
  call assert_equal('nofile', &buftype)
  call setline(1, ['kept again'])
  DraftSave
  call assert_equal(l:files, s:saves(s:scratches))
  call assert_equal(['kept again'], readfile(l:files[0]))
  " Another, in the same second: a file of its own
  Scratch!
  DraftSave
  Scratch!
  DraftSave
  call assert_equal(3, len(s:saves(s:scratches)))
endfunction

function! s:suite.save_to_dir_and_path() abort
  Scratch!
  setfiletype markdown
  call setline(1, ['x'])
  execute 'DraftSave' fnameescape(s:tmp . '/kept/')
  call assert_match('/kept/\d\{8}-\d\{6}\.md$', get(s:saves(s:tmp . '/kept'), 0, ''))
  call mkdir(s:tmp . '/existing')
  execute 'DraftSave' fnameescape(s:tmp . '/existing')
  call assert_equal(1, len(s:saves(s:tmp . '/existing')), 'an existing directory')
  execute 'DraftSave' fnameescape(s:tmp . '/named.md')
  call assert_equal(['x'], readfile(s:tmp . '/named.md'))
  " Another buffer's file isn't overwritten without !
  Scratch!
  call setline(1, ['y'])
  call assert_match('^Vim(echoerr):DraftSave: .*named\.md exists (add ! to overwrite)$',
        \ s:run('DraftSave ' . fnameescape(s:tmp . '/named.md')))
  call assert_equal(['x'], readfile(s:tmp . '/named.md'))
  execute 'DraftSave!' fnameescape(s:tmp . '/named.md')
  call assert_equal(['y'], readfile(s:tmp . '/named.md'))
  call mkdir(s:tmp . '/locked')
  call setfperm(s:tmp . '/locked', 'r-xr-xr-x')
  call assert_match('E482: Can''t create file .*/locked/x\.txt$',
        \ s:run('DraftSave ' . fnameescape(s:tmp . '/locked/x.txt')))
  call setfperm(s:tmp . '/locked', 'rwxr-xr-x')
endfunction

function! s:suite.save_draft_keeps_handing_on() abort
  execute 'edit' fnameescape(s:tmp . '/repo/file.txt')
  call s:draft(['reply'])
  setfiletype markdown
  call setline(1, ['reply, edited'])
  DraftSave
  let l:files = s:saves(s:tmp . '/repo/.git/vim-draft')
  call assert_equal(1, len(l:files))
  call assert_match('\.md$', get(l:files, 0, ''))
  call assert_equal(['reply, edited'], readfile(get(l:files, 0, '/nonexistent')))
  " Saving left the draft as it was: still to :w, and :wq hands it on
  call assert_equal('acwrite', &buftype)
  call assert_true(&modified)
  wq
  call assert_equal(['reply, edited'], s:sent)
endfunction

function! s:suite.save_draft_outside_git() abort
  execute 'edit' fnameescape(s:tmp . '/outside.txt')
  call s:draft(['x'])
  DraftSave
  call assert_equal(1, len(s:saves(g:roumail_place_dir . '/' . s:place(s:tmp . '/plain') . '/vim-draft')))
  DraftList
  call assert_equal(['x'], map(getloclist(0), 'v:val.text'))
  lclose
  " Another directory's drafts are its own
  call setloclist(0, [])
  cd sub
  call assert_match('^\nDraftList: nothing saved in ', s:run('DraftList'))
  call assert_equal([], getloclist(0))
endfunction

" Any other buffer, a plugin's output say, is saved as a draft of its own
" repository
function! s:suite.save_other_buffer_in_repository() abort
  let l:dir = s:tmp . '/repo/.git/vim-draft'
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
  call assert_equal([], s:saves(s:scratches))
endfunction

function! s:suite.list() abort
  call mkdir(s:scratches, 'p')
  call writefile(['older'], s:scratches . '/a.txt')
  call writefile(['newer'], s:scratches . '/b.txt')
  call system('touch -t 202001010000 ' . shellescape(s:scratches . '/a.txt'))
  call system('touch -t 202101010000 ' . shellescape(s:scratches . '/b.txt'))
  " From a draft: the drafts of the buffer it was opened from
  execute 'edit' fnameescape(s:tmp . '/repo/file.txt')
  call s:draft(['in the repo'])
  DraftSave
  DraftList
  call assert_equal(['in the repo', 'newer', 'older'], map(getloclist(0), 'v:val.text'))
  call assert_equal('DraftList', getloclist(0, {'title': 1}).title)
endfunction

function! s:suite.without_vim_place() abort
  call s:draft(['x'])
  call assert_equal("\nvim-draft: :DraftSave of a draft needs vim-place (with vim-fugitive), which is not installed",
        \ s:without_place('DraftSave'))
  call assert_equal("\nvim-draft: :DraftList needs vim-place (with vim-fugitive), which is not installed",
        \ s:without_place('DraftList'))
  " A scratch, and a draft to a path, need no vim-place
  call assert_match('^\nDraftSave: wrote ', s:without_place('DraftSave ' . fnameescape(s:tmp . '/d.txt')))
  Scratch!
  call assert_match('^\nDraftSave: wrote ', s:without_place('DraftSave'))
endfunction
