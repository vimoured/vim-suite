" fugitive-extras: what the dotfiles use of it (<leader>cc / <leader>cd, normal
" and visual; the shell's `vim . +BranchDiff`), what vim-prompts and gh-extras
" call (comments#list, #load, #check, complete_branch, main_ref,
" compares#list), and its README, through its commands, <Plug> maps and keys.
" :CommentsSave / :CommentsLoad keep vim-place's save contract (its README),
" with the deviations in fugitive-extras' README.
" Each test has a new repo, at a new path: comparisons are kept per git dir
" for the session.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('fugitive-extras')

let s:tmp = resolve(tempname())
let s:repos = 0
let s:leader = get(g:, 'mapleader', '\')

function! s:git(...) abort
  let l:out = system('git -C ' . shellescape(s:repo) . ' ' . join(map(copy(a:000), 'shellescape(v:val)')))
  " git ran outside fugitive, which caches HEAD by its time to the second: a
  " checkout in the same second as an earlier read would keep the old branch.
  " 0 expires it without a FugitiveChanged event
  call FugitiveDidChange(0)
  return trim(l:out)
endfunction

" main: a.txt (one two three)
function! s:reset() abort
  " A new tab: one of an earlier test's comparisons would keep its tab variable
  $tabnew
  silent! tabonly!
  silent! only!
  silent! %bwipeout!
  CommentsClear
  call setqflist([], 'f')
  call delete(s:tmp, 'rf')
  let s:repos += 1
  let s:repo = s:tmp . '/' . s:repos . '/repo'
  " Where comments outside a repository are saved
  let $XDG_STATE_HOME = s:tmp . '/state'
  call mkdir(s:repo, 'p')
  call s:git('init', '-q', '-b', 'main')
  call writefile(['one', 'two', 'three'], s:repo . '/a.txt')
  call s:git('add', 'a.txt')
  call s:git('commit', '-q', '-m', 'init')
  execute 'cd' fnameescape(s:repo)
endfunction

" Checks out feature, whose commit changes a.txt's line 2
function! s:feature() abort
  call s:git('checkout', '-q', '-b', 'feature')
  call writefile(['one', 'TWO', 'three'], s:repo . '/a.txt')
  call s:git('commit', '-q', '-am', 'change a')
endfunction

function! s:suite.before_each() abort
  call s:reset()
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

" An Ex command; returns its messages, or the error it raised
function! s:run(cmd) abort
  try
    return execute(a:cmd)
  catch
    return v:exception
  endtry
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

" Asserts out is fugitive-extras' message msg and nothing after it
function! s:only_says(msg, out, ...) abort
  call assert_equal("\nfugitive-extras: " . a:msg, a:out, get(a:, 1, ''))
endfunction

function! s:saves(branch) abort
  return glob(s:repo . '/.git/fugitive-extras/comments/' . a:branch . '/*', 1, 1)
endfunction

function! s:comments() abort
  return fugitive_extras#comments#list()
endfunction

" The comparison named name, as other plugins read it
function! s:compare(name) abort
  return get(filter(fugitive_extras#compares#list(), 'v:val.name ==# a:name'), 0, {})
endfunction

" The names of the files a comparison's tabs show, sorted
function! s:compare_files(name) abort
  return sort(map(copy(s:compare(a:name).tabs),
        \ {_, t -> fnamemodify(FugitiveReal(bufname(tabpagebuflist(t)[-1])), ':t')}))
endfunction

" The windows of this tab's diff, left to right, as you see them (with the
" dotfiles' 'splitright')
function! s:diff_wins() abort
  return filter(range(1, winnr('$')), 'getwinvar(v:val, "&diff")')
endfunction

" The revision each side shows, left to right: the commit (:0 the index) of a
" fugitive:// buffer, 'work tree' for a file
function! s:diff_revs() abort
  return map(s:diff_wins(), {_, w -> bufname(winbufnr(w)) =~# '^fugitive://'
        \ ? substitute(FugitiveParse(bufname(winbufnr(w)))[0], ':[^:]*$', '', '') : 'work tree'})
endfunction

" The first line of each side, left to right
function! s:diff_firsts() abort
  return map(s:diff_wins(), 'getbufline(winbufnr(v:val), 1)[0]')
endfunction

" Without one of its plugins: what needs it says so
function! s:without(plugin, cmd) abort
  let l:rtp = &runtimepath
  try
    execute 'set runtimepath-=' . fnameescape(g:suite.deps . '/' . a:plugin)
    return s:run(a:cmd)
  finally
    let &runtimepath = l:rtp
  endtry
endfunction

""" Diffs of a file

function! s:suite.diff_this_index_and_work_tree() abort
  call writefile(['ONE', 'two', 'three'], s:repo . '/a.txt')
  edit a.txt
  call s:type("\<Plug>(fugitive-extras-diff-this)")
  call assert_equal(['one', 'ONE'], s:diff_firsts())
  call assert_equal([':0', 'work tree'], s:diff_revs())
endfunction

" The cursor stays on the file; dp there stages that hunk, with nothing to write
function! s:suite.diff_this_dp_stages_a_hunk() abort
  call writefile(['ONE', 'two', 'THREE'], s:repo . '/a.txt')
  edit a.txt
  DiffThis
  call assert_equal(s:repo . '/a.txt', expand('%:p'), 'on the file')
  call cursor(1, 1)
  call assert_equal('', s:type('dp'))
  call assert_equal("ONE\ntwo\nthree", s:git('show', ':a.txt'), 'the first hunk only')
  call assert_equal(['ONE', 'two', 'THREE'], readfile(s:repo . '/a.txt'), 'the file is as it was')
  let l:index = filter(s:diff_wins(), 'bufname(winbufnr(v:val)) =~# "^fugitive://"')
  call assert_false(getbufvar(winbufnr(l:index[0]), '&modified'), 'the index is written')
endfunction

" With the diff closed, dp is Vim's again
function! s:suite.dp_after_diff_this_closes() abort
  call writefile(['ONE', 'two', 'three'], s:repo . '/a.txt')
  edit a.txt
  DiffThis
  DiffClose
  call assert_match('E99', s:type('dp'))
  call assert_equal("one\ntwo\nthree", s:git('show', ':a.txt'), 'nothing staged')
endfunction

" What the branch changes in this file, not what main got since it forked
function! s:suite.diff_this_bang_from_the_merge_base() abort
  call s:feature()
  let l:base = s:git('rev-parse', 'main')
  call s:git('checkout', '-q', 'main')
  call writefile(['one', 'two', 'THREE'], s:repo . '/a.txt')
  call s:git('commit', '-q', '-am', 'main moves on')
  call s:git('checkout', '-q', 'feature')
  call writefile(['one', 'TWO', 'three', 'four'], s:repo . '/a.txt')
  edit a.txt
  call s:type("\<Plug>(fugitive-extras-diff-main)")
  " Which side is which: diff_older_side_on_the_left
  call assert_equal(sort([l:base, 'work tree']), sort(s:diff_revs()))
  let l:at_base = filter(s:diff_wins(), 'bufname(winbufnr(v:val)) =~# "^fugitive://"')
  call assert_equal(['one', 'two', 'three'], getbufline(winbufnr(l:at_base[0]), 1, '$'))
endfunction

function! s:suite.diff_commit() abort
  for l:first in ['A', 'B']
    call writefile([l:first, 'two', 'three'], s:repo . '/a.txt')
    call s:git('commit', '-q', '-am', l:first)
  endfor
  " Not committed
  call writefile(['C', 'two', 'three'], s:repo . '/a.txt')
  " Which side is which: diff_older_side_on_the_left
  edit a.txt
  call s:type("\<Plug>(fugitive-extras-diff-commit)")
  call assert_equal(['A', 'B'], sort(s:diff_firsts()))
  silent! only | edit a.txt
  call s:type("\<Plug>(fugitive-extras-diff-commit-worktree)")
  call assert_equal(['A', 'C'], sort(s:diff_firsts()))
  silent! only | edit a.txt
  DiffCommit HEAD~1
  call assert_equal(['A', 'one'], sort(s:diff_firsts()))
  silent! only | edit a.txt
  DiffCommit! HEAD~1
  call assert_equal(['C', 'one'], sort(s:diff_firsts()))
endfunction

" The older side on the left, so what was added is on the right, in every diff
function! s:suite.diff_older_side_on_the_left() abort
  call s:feature()
  let l:base = s:git('rev-parse', 'main')
  call writefile(['one', 'TWO', 'three', 'four'], s:repo . '/a.txt')
  edit a.txt
  DiffThis
  call assert_equal([':0', 'work tree'], s:diff_revs(), ':DiffThis')
  silent! only | edit a.txt
  DiffThis!
  call assert_equal([l:base, 'work tree'], s:diff_revs(), ':DiffThis!')
  silent! only | edit a.txt
  DiffCommit
  call assert_equal([l:base, s:git('rev-parse', 'HEAD')], s:diff_revs(), ':DiffCommit')
  silent! only | edit a.txt
  DiffCommit!
  call assert_equal([l:base, 'work tree'], s:diff_revs(), ':DiffCommit!')
  silent! only | edit a.txt
  BranchDiff
  call assert_equal([l:base, s:git('rev-parse', 'HEAD')], s:diff_revs(), ':BranchDiff')
endfunction

" The cursor on the right, the newer side, in every diff as it opens
function! s:suite.diff_cursor_on_the_right() abort
  call s:feature()
  call writefile(['one', 'TWO', 'three', 'four'], s:repo . '/a.txt')
  for l:cmd in ['DiffThis', 'DiffThis!', 'DiffCommit', 'DiffCommit!', 'BranchDiff', 'BranchDiff!']
    silent! tabonly | silent! only | edit a.txt
    execute l:cmd
    call assert_equal(s:diff_wins()[-1], winnr(), ':' . l:cmd)
  endfor
endfunction

function! s:suite.diff_commit_refused() abort
  edit a.txt
  call s:only_says('unknown commit nope', s:run('DiffCommit nope'))
  call s:only_says('HEAD has no parent', s:run('DiffCommit'))
  call writefile(['A', 'two', 'three'], s:repo . '/a.txt')
  call s:git('commit', '-q', '-am', 'A')
  call writefile(['b'], s:repo . '/b.txt')
  edit b.txt
  call s:only_says('b.txt is not in HEAD', s:run('DiffCommit'))
  enew
  call s:only_says('not a file in the repository', s:run('DiffCommit'))
  execute 'cd' fnameescape(s:tmp)
  call s:only_says('not in a git repository', s:run('DiffCommit'))
  call assert_equal(1, winnr('$'), 'no diff opened')
endfunction

""" :BranchDiff and comparisons

function! s:suite.branch_diff_committed_or_work_tree() abort
  call s:feature()
  let l:base = s:git('rev-parse', 'main')
  " Not committed: a stash applied, say
  call writefile(['b'], s:repo . '/b.txt')
  call s:git('add', 'b.txt')
  edit a.txt
  call s:type("\<Plug>(fugitive-extras-branch-diff)")
  call assert_equal(['a.txt'], s:compare_files('feature'))
  call assert_equal({'name': 'feature', 'branch': 'feature', 'base': l:base, 'head': 'feature', 'files': 1},
        \ filter(s:compare('feature'), 'v:key =~# "^\\(name\\|branch\\|base\\|head\\|files\\)$"'))
  call assert_equal(2, tabpagenr(), 'on its first file')
  call assert_equal([l:base, s:git('rev-parse', 'feature')], s:diff_revs())
  call assert_equal([0, 0], map(filter(range(1, winnr('$')), 'getwinvar(v:val, "&diff")'),
        \ 'getbufvar(winbufnr(v:val), "&modifiable")'), 'both sides read-only')
  tabfirst
  call s:type("\<Plug>(fugitive-extras-branch-diff-worktree)")
  call assert_equal(['a.txt', 'b.txt'], s:compare_files('feature#2'), 'feature still open: a new one')
  call assert_equal('', s:compare('feature#2').head)
  call assert_equal([l:base, 'work tree'], s:diff_revs())
endfunction

function! s:suite.branch_diff_of_another_branch() abort
  call s:feature()
  call s:git('checkout', '-q', 'main')
  edit a.txt
  BranchDiff feature
  call assert_equal(['a.txt'], s:compare_files('feature'))
  call assert_equal('TWO', getline(2), 'the branch''s commit')
  call assert_equal('main', FugitiveHead(), 'not checked out')
  call assert_equal(['feature', 'main'], getcompletion('BranchDiff ', 'cmdline'), 'most recent first')
  call assert_equal(['feature'], getcompletion('BranchDiff f', 'cmdline'))
endfunction

" The shell's rv: `vim . +BranchDiff`, from netrw's listing of the work tree
function! s:suite.branch_diff_from_vim_dot() abort
  call s:feature()
  edit .
  BranchDiff
  call assert_equal(['a.txt'], s:compare_files('feature'))
endfunction

function! s:suite.branch_diff_names() abort
  call s:feature()
  edit a.txt
  BranchDiff
  tabfirst
  BranchDiff
  call assert_equal(['feature#2', 'feature'], map(fugitive_extras#compares#list(), 'v:val.name'),
        \ 'newest first')
  " One with no tabs left is reused
  DiffClose feature
  BranchDiff
  call assert_equal(['feature', 'feature#2'], map(fugitive_extras#compares#list(), 'v:val.name'))
  call assert_equal(['feature', 'feature#2'], getcompletion('DiffClose ', 'cmdline'))
endfunction

function! s:suite.branch_diff_refused() abort
  edit a.txt
  call assert_equal("\nfugitive-extras: no changes in main", s:run('BranchDiff'))
  call s:only_says('unknown branch nope (:Git fetch?)', s:run('BranchDiff nope'))
  call s:only_says(':BranchDiff! is the work tree of the checked-out branch: no branch',
        \ s:run('BranchDiff! main'))
  call s:git('checkout', '-q', '--orphan', 'other')
  call s:git('commit', '-q', '-m', 'unrelated')
  call s:only_says('no merge-base between HEAD and main', s:run('BranchDiff'))
  call s:git('branch', '-q', '-m', 'main', 'trunk')
  call s:only_says('no origin/HEAD, main or master found', s:run('BranchDiff'))
  execute 'cd' fnameescape(s:tmp)
  enew
  call s:only_says('not in a git repository', s:run('BranchDiff'))
  call assert_equal(1, tabpagenr('$'), 'no tab opened')
  call assert_equal([], getcompletion('BranchDiff ', 'cmdline'), 'no branches to complete')
endfunction

" Main is origin/HEAD, else origin/main, origin/master, main, master
function! s:suite.main_ref() abort
  edit a.txt
  call assert_equal('main', fugitive_extras#main_ref())
  call s:git('update-ref', 'refs/remotes/origin/master', 'HEAD')
  call assert_equal('origin/master', fugitive_extras#main_ref())
  call s:git('update-ref', 'refs/remotes/origin/main', 'HEAD')
  call assert_equal('origin/main', fugitive_extras#main_ref())
  call s:git('update-ref', 'refs/remotes/origin/trunk', 'HEAD')
  call s:git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/trunk')
  call assert_equal('origin/trunk', fugitive_extras#main_ref())
  call assert_equal(['main', 'origin/main', 'origin/master', 'origin/trunk'],
        \ sort(fugitive_extras#complete_branch('', '', 0)), 'origin/HEAD skipped')
  call s:git('branch', '-q', '-m', 'main', 'master')
  call s:git('symbolic-ref', '--delete', 'refs/remotes/origin/HEAD')
  call s:git('update-ref', '-d', 'refs/remotes/origin/main')
  call s:git('update-ref', '-d', 'refs/remotes/origin/master')
  call s:git('update-ref', '-d', 'refs/remotes/origin/trunk')
  call assert_equal('master', fugitive_extras#main_ref())
endfunction

function! s:suite.diff_refresh() abort
  call s:feature()
  edit a.txt
  BranchDiff!
  " An agent's edits, outside Vim: a.txt again, and a new file
  call writefile(['one', 'TWO', 'three', 'four'], s:repo . '/a.txt')
  call writefile(['b'], s:repo . '/b.txt')
  call s:git('add', 'b.txt')
  let l:tabs = tabpagenr('$')
  call s:type("\<Plug>(fugitive-extras-diff-refresh)")
  call assert_equal(['a.txt', 'b.txt'], s:compare_files('feature'))
  call assert_equal(1, len(fugitive_extras#compares#list()), 'the same comparison')
  call assert_equal(l:tabs + 1, tabpagenr('$'))
  " Back on a.txt, its work tree side, read again
  call assert_equal(s:repo . '/a.txt', expand('%:p'))
  call assert_equal(['one', 'TWO', 'three', 'four'], getline(1, '$'))
  " Unsaved changes stop it
  call setline(1, 'edited')
  call s:only_says('tab 2 of feature has unsaved changes: write or discard them first',
        \ s:run('DiffRefresh'))
  call assert_equal(['a.txt', 'b.txt'], s:compare_files('feature'))
endfunction

" From a new merge-base: main merged into the branch, a.txt is no longer
" changed; with only the comparison's tabs open, no empty tab is left
function! s:suite.diff_refresh_from_a_new_merge_base() abort
  call s:feature()
  call writefile(['b'], s:repo . '/b.txt')
  call s:git('add', 'b.txt')
  call s:git('commit', '-q', '-m', 'add b')
  edit a.txt
  BranchDiff
  1tabclose
  call assert_equal(2, tabpagenr('$'), 'only its tabs')
  call s:git('checkout', '-q', 'main')
  call s:git('merge', '-q', '--ff-only', 'feature~1')
  call s:git('checkout', '-q', 'feature')
  execute (index(s:compare_files('feature'), 'a.txt') + 1) . 'tabnext'
  DiffRefresh
  call assert_equal(['b.txt'], s:compare_files('feature'))
  call assert_equal(1, tabpagenr('$'))
  call assert_match('b\.txt$', FugitiveReal(bufname()), 'on its first file')
endfunction

function! s:suite.diff_refresh_of_a_branch_gone() abort
  call s:feature()
  call s:git('checkout', '-q', 'main')
  BranchDiff feature
  call s:git('branch', '-q', '-D', 'feature')
  call s:only_says('unknown branch feature (:Git fetch?)', s:run('DiffRefresh'))
  call assert_equal(['a.txt'], s:compare_files('feature'), 'its tabs stay')
endfunction

function! s:suite.diff_refresh_outside_a_comparison() abort
  edit a.txt
  DiffThis
  " Outside Vim, as an agent would, a moment later (fugitive goes by the
  " index's time, to the second): the file changed and staged
  sleep 1
  call writefile(['ONE', 'two', 'three'], s:repo . '/a.txt')
  call s:git('add', 'a.txt')
  DiffRefresh
  call assert_equal(['ONE', 'ONE'], s:diff_firsts())
endfunction

function! s:suite.diff_close_a_comparison() abort
  call s:feature()
  call writefile(['b'], s:repo . '/b.txt')
  call s:git('add', 'b.txt')
  call s:git('commit', '-q', '-m', 'add b')
  edit a.txt
  let l:from = win_getid()
  BranchDiff
  call assert_equal(3, tabpagenr('$'))
  call s:type("\<Plug>(fugitive-extras-diff-close)")
  call assert_equal(1, tabpagenr('$'))
  call assert_equal(l:from, win_getid(), 'back where :BranchDiff was run')
  " Even after moving to another window of that tab meanwhile
  split other.txt
  let l:other = win_getid()
  call win_gotoid(l:from)
  BranchDiff
  tabfirst
  call win_gotoid(l:other)
  tablast
  DiffClose
  call assert_equal(l:from, win_getid(), 'back where :BranchDiff was run, again')
  only
  call assert_equal([], s:compare('feature').tabs, 'still listed')
  call assert_equal("\nfugitive-extras: no tabs of feature open", s:run('DiffClose feature'))
  call s:only_says('no comparison nope in :Compares', s:run('DiffClose nope'))
  " By name, from elsewhere, with only its tabs open: one empty tab is left
  BranchDiff
  1tabclose
  DiffClose feature
  call assert_equal(1, tabpagenr('$'))
  call assert_equal('', bufname())
endfunction

function! s:suite.diff_close_keeps_a_tab_with_unsaved_changes() abort
  call s:feature()
  call writefile(['b'], s:repo . '/b.txt')
  call s:git('add', 'b.txt')
  BranchDiff!
  for l:tab in s:compare('feature').tabs
    if FugitiveReal(bufname(tabpagebuflist(l:tab)[-1])) =~# 'a\.txt$'
      execute l:tab . 'tabnext'
    endif
  endfor
  execute s:diff_wins()[-1] . 'wincmd w'
  call setline(1, 'edited')
  call s:only_says('1 tab(s) of feature left open: unsaved changes', s:run('DiffClose'))
  call assert_equal(['a.txt'], s:compare_files('feature'))
endfunction

function! s:suite.diff_close_outside_a_comparison() abort
  call writefile(['ONE', 'two', 'three'], s:repo . '/a.txt')
  edit a.txt
  DiffThis
  DiffClose
  call assert_equal(1, winnr('$'))
  call assert_equal(s:repo . '/a.txt', expand('%:p'))
  call assert_false(&diff)
  " A diff of two files: both stay, out of diff mode
  call writefile(['b'], s:repo . '/b.txt')
  vertical diffsplit b.txt
  DiffClose
  call assert_equal([2, 0, 0], [winnr('$'), getwinvar(1, '&diff'), getwinvar(2, '&diff')])
endfunction

function! s:suite.compares_list() abort
  call s:feature()
  let [l:base, l:head] = [s:git('rev-parse', 'main'), 'feature']
  edit a.txt
  BranchDiff
  tabfirst
  BranchDiff!
  tabfirst
  call s:type("\<Plug>(fugitive-extras-compares)")
  call assert_equal('fugitive-extras://compares/repo', bufname())
  call assert_equal('Comparisons (2)  <CR> open  dd remove  / filter  r refresh  q close',
        \ getline(1))
  call assert_match('^feature#2 \+' . l:base[:6] . '\.\.work tree \+1 files \+1 open \+\d\+s$', getline(2))
  call assert_match('^feature \+' . l:base[:6] . '\.\.feature \+1 files \+1 open', getline(3))
  call assert_equal(2, line('.'))
  call feedkeys("/work\<CR>", 'x')
  call assert_equal(2, line('$'))
  call assert_match('^feature#2 ', getline(2))
  normal q
  Compares
  call cursor(3, 1)
  normal r
  call assert_equal(3, line('.'), 'r keeps the cursor on its comparison')
  call cursor(2, 1)
  " dd removes it; its tab stays open
  let l:tabs = tabpagenr('$')
  normal dd
  call assert_equal(['feature'], map(fugitive_extras#compares#list(), 'v:val.name'))
  call assert_equal(l:tabs, tabpagenr('$'))
  call s:type("\<CR>")
  call assert_false(bufexists('fugitive-extras://compares/repo'), 'the list closed')
  call assert_equal(2, len(s:compare('feature').tabs), 'its files again')
  Compares
  normal q
  call assert_false(bufexists('fugitive-extras://compares/repo'))
endfunction

function! s:suite.compares_enter_on_the_heading() abort
  call s:feature()
  BranchDiff
  tabfirst
  Compares
  call cursor(1, 1)
  call assert_notmatch('E\d\+:\|fugitive-extras:', s:type("\<CR>"))
  call assert_equal('fugitive-extras://compares/repo', bufname())
endfunction

function! s:suite.compares_refused() abort
  call s:only_says(':Compares needs vim-lists, which is not installed', s:without('vim-lists', 'Compares'))
  execute 'cd' fnameescape(s:tmp)
  enew
  call s:only_says('not in a git work tree', s:run('Compares'))
endfunction

function! s:suite.compares_list_of_another_repo() abort
  call s:feature()
  BranchDiff
  let l:dir = FugitiveGitDir()
  tabfirst
  execute 'cd' fnameescape(s:tmp)
  enew
  call assert_equal(['feature'], map(fugitive_extras#compares#list(l:dir), 'v:val.name'))
  call assert_equal([], fugitive_extras#compares#list())
endfunction

""" :BranchCommits

function! s:suite.branch_commits_list() abort
  call s:feature()
  call writefile(['b'], s:repo . '/b.txt')
  call s:git('add', 'b.txt')
  call s:git('commit', '-q', '-m', 'add b')
  edit a.txt
  call s:type("\<Plug>(fugitive-extras-branch-commits)")
  call assert_equal('fugitive-extras://commits/repo', bufname())
  call assert_equal('Commits on feature not on main (2)  <CR> commit  dd hide  u undo  / filter  r refresh  q close',
        \ getline(1))
  call assert_match('^\x\{7,}  t \+\S.* ago \+add b (HEAD -> feature)$', getline(2))
  call assert_match('  change a$', getline(3))
  call assert_equal(2, line('.'))
  " <CR>: the commit in fugitive, in the window above
  call s:type("\<CR>")
  call assert_match('^fugitive://.*' . s:git('rev-parse', 'HEAD') . '$', bufname())
  call assert_equal('fugitive-extras://commits/repo', bufname(winbufnr(winnr('j'))))
  wincmd j
  " / filters on the subject
  call feedkeys("/chg\<CR>", 'x')
  call assert_equal(2, line('$'))
  call assert_match('change a$', getline(2))
  normal q
  " An option picking commits
  BranchCommits --grep=add
  call assert_equal(2, line('$'))
  call assert_match('add b', getline(2))
  normal q
  " One that adds lines leaves each commit one line
  BranchCommits --stat
  call assert_equal(3, line('$'))
  normal q
endfunction

function! s:suite.branch_commits_enter_with_the_list_the_only_window() abort
  call s:feature()
  BranchCommits
  only
  call cursor(1, 1)
  call assert_notmatch('E\d\+:\|fugitive-extras:', s:type("\<CR>"), 'on the heading: nothing')
  call assert_equal(1, winnr('$'))
  call cursor(2, 1)
  call s:type("\<CR>")
  call assert_equal(2, winnr('$'))
  call assert_match('^fugitive://', bufname())
  call assert_equal('fugitive-extras://commits/repo', bufname(winbufnr(winnr('j'))))
endfunction

function! s:suite.branch_commits_args() abort
  call s:feature()
  call writefile(['notes'], s:repo . '/my notes.txt')
  call s:git('add', 'my notes.txt')
  call s:git('commit', '-q', '-m', 'add notes')
  call s:git('checkout', '-q', 'main')
  " A typo in the branch is an unknown branch, not a path for git log
  call s:only_says('unknown branch featur (:Git fetch?)', s:run('BranchCommits featur'))
  " The branch, then a path
  BranchCommits feature -- a.txt
  call assert_equal(2, line('$'))
  call assert_match('  change a$', getline(2))
  normal q
  call assert_equal(['feature', 'main'], getcompletion('BranchCommits ', 'cmdline'))
  call assert_equal(['a.txt'], getcompletion('BranchCommits feature -- a', 'cmdline'))
  " A path is relative to the current directory, as on any command line
  call mkdir(s:repo . '/sub')
  execute 'cd' fnameescape(s:repo . '/sub')
  BranchCommits feature -- ../a.txt
  call assert_equal(2, line('$'))
  call assert_match('  change a$', getline(2))
  normal q
  " The current directory outside the repo, the buffer in it
  execute 'cd' fnameescape(s:tmp)
  execute 'edit' fnameescape(s:repo . '/a.txt')
  execute 'BranchCommits feature --' fnameescape(fnamemodify(s:repo . '/a.txt', ':.'))
  call assert_equal(2, line('$'))
  call assert_match('  change a$', getline(2))
  normal q
  execute 'cd' fnameescape(s:repo)
  " A path with a space is one path; % is this buffer's file
  call s:git('checkout', '-q', 'feature')
  edit my\ notes.txt
  BranchCommits -- %
  call assert_equal(2, line('$'))
  call assert_match('  add notes (HEAD -> feature)$', getline(2))
  normal q
endfunction

function! s:suite.branch_commits_refused() abort
  call s:feature()
  call assert_match("^\nfugitive-extras: git log: .*bogus", s:run('BranchCommits --bogus'))
  call s:only_says(':BranchCommits needs vim-lists, which is not installed',
        \ s:without('vim-lists', 'BranchCommits'))
endfunction

""" Review comments

function! s:suite.comment_with_the_dotfiles_keys() abort
  edit a.txt
  call assert_match('Review comments: 1', s:type('2G' . s:leader . "ccon two\<CR>"))
  call assert_match('Review comments: 2', s:type('1GVj' . s:leader . "ccon both\<CR>"))
  call assert_equal([{'path': 'a.txt', 'start': 2, 'end': 2, 'body': 'on two'},
        \ {'path': 'a.txt', 'start': 1, 'end': 2, 'body': 'on both'}], s:comments())
endfunction

function! s:suite.comment_prompt() abort
  edit a.txt
  " Left with <Esc>: kept for the next :Comment on those lines
  call assert_match('Comment kept: :Comment or :CommentDraft on a.txt:2 goes on from it',
        \ s:type("2G:Comment\<CR>half\<Esc>"))
  call assert_equal([], s:comments())
  call s:type("2G:Comment\<CR> done\<CR>")
  call assert_equal([{'path': 'a.txt', 'start': 2, 'end': 2, 'body': 'half done'}], s:comments())
  " Empty: nothing
  call assert_notmatch('Review comments', s:type("3G:Comment\<CR>\<CR>"))
  call assert_equal(1, len(s:comments()))
endfunction

function! s:suite.comment_draft() abort
  edit a.txt
  call s:type('2G' . s:leader . 'cd')
  call assert_equal('fugitive-extras://comment/a.txt:2', bufname())
  call assert_equal('markdown', &filetype)
  call assert_equal(10, winheight(0))
  call assert_match('a\.txt$', bufname(winbufnr(winnr('k'))), 'below the file')
  call setline(1, ['a longer', 'comment'])
  write
  call assert_match('Review comments: 1', execute('quit'))
  call assert_equal([{'path': 'a.txt', 'start': 2, 'end': 2, 'body': "a longer\ncomment"}], s:comments())
  " A range; :q! adds nothing
  call s:type('1GVj' . s:leader . 'cd')
  call assert_equal('fugitive-extras://comment/a.txt:1-2', bufname())
  call setline(1, 'dropped')
  quit!
  call assert_equal(1, len(s:comments()))
endfunction

function! s:suite.comment_draft_goes_on_from_the_prompt() abort
  edit a.txt
  call s:type("2G:Comment\<CR>half\<Esc>")
  call s:type('2G' . s:leader . 'cd')
  call assert_equal(['half'], getline(1, '$'))
  quit!
  call s:type("2G:Comment\<CR>\<CR>")
  call assert_equal([], s:comments(), 'taken by the draft')
  CommentDraft given
  call assert_equal(['given'], getline(1, '$'))
  quit!
endfunction

function! s:suite.comment_refused() abort
  call s:feature()
  edit a.txt
  BranchDiff
  " The merge-base side
  execute (&splitright ? 1 : 2) . 'wincmd w'
  call s:only_says('comment on the branch side of the diff, not the merge-base', s:run('Comment no'))
  tabfirst
  enew
  call s:only_says('not a file in the git work tree', s:run('Comment no'))
  call s:only_says('not a file in the git work tree', s:run('CommentDraft'))
  call assert_equal([], s:comments())
  edit a.txt
  call s:only_says(':Comment needs vim-place, which is not installed', s:without('vim-place', 'Comment no'))
  call s:only_says(':CommentDraft needs vim-place, which is not installed', s:without('vim-place', 'CommentDraft'))
  call s:only_says(':CommentDraft needs vim-draft, which is not installed', s:without('vim-draft', 'CommentDraft'))
  call s:only_says(':CommentsSave needs vim-review, which is not installed', s:without('vim-review', 'CommentsSave'))
  call s:only_says(':CommentsLoad needs vim-place, which is not installed', s:without('vim-place', 'CommentsLoad'))
  call assert_equal(1, winnr('$'), 'no draft')
endfunction

" On the branch side of :BranchDiff of another branch: that branch's comments
" (origin/feature's are feature's)
function! s:suite.comments_on_the_compared_branch() abort
  call s:feature()
  call s:git('checkout', '-q', 'main')
  call s:git('update-ref', 'refs/remotes/origin/feature', 'feature')
  BranchDiff origin/feature
  2Comment on feature's side
  CommentsSave
  call assert_equal(2, len(s:saves('feature')))
  call assert_equal([], s:saves('main'))
endfunction

function! s:suite.comments_list_and_c_to_change() abort
  edit a.txt
  " Other quickfix lists, made before and since
  call setqflist([], ' ', {'title': 'grep', 'items': [{'filename': 'a.txt', 'lnum': 3, 'text': 'earlier'}]})
  2Comment first
  call setqflist([], ' ', {'title': 'grep', 'items': [{'filename': 'a.txt', 'lnum': 1, 'text': 'grep hit'}]})
  Comments
  call assert_equal('Review', getqflist({'title': 1}).title)
  call assert_equal('qf', &filetype)
  call s:type('c')
  call assert_equal('fugitive-extras://comment/a.txt:2', bufname())
  call assert_equal(['first'], getline(1, '$'))
  call setline(1, 'changed')
  write
  call assert_match('Comment changed', execute('quit'))
  call assert_equal([{'path': 'a.txt', 'start': 2, 'end': 2, 'body': 'changed'}], s:comments())
endfunction

function! s:suite.comments_c_in_another_list_or_an_empty_one() abort
  edit a.txt
  Comments
  call s:type('c')
  call assert_equal('qf', &filetype, 'empty: nothing to change')
  cclose
  call setqflist([], ' ', {'title': 'grep', 'items': [{'filename': 'a.txt', 'lnum': 1, 'text': 'grep hit'}]})
  copen
  call s:type('c')
  call assert_equal('qf', &filetype, 'not Review: c is Vim''s')
  call assert_equal(1, winnr('$') - 1)
endfunction

function! s:suite.comment_changed_after_it_left_the_list() abort
  edit a.txt
  2Comment first
  Comments
  call s:type('c')
  CommentsClear
  call setline(1, 'changed')
  write
  call assert_match('Comment no longer in the list: added again, changed', execute('quit'))
  call assert_equal([{'path': 'a.txt', 'start': 2, 'end': 2, 'body': 'changed'}], s:comments())
endfunction

function! s:suite.save_and_load_back_where_the_lines_are() abort
  edit a.txt
  2Comment check this
  call assert_match('^\nSaved 1 review comments to ', s:run('CommentsSave'))
  let l:saves = s:saves('main')
  call assert_equal(2, len(l:saves))
  call assert_match('/\d\{8}-\d\{6}\.txt$', l:saves[0])
  call assert_equal(['a.txt:2: check this'], readfile(l:saves[0]))
  call assert_equal(l:saves[0] . '.anchors', l:saves[1])
  call assert_equal([fnamemodify(l:saves[0], ':t:r')], getcompletion('CommentsLoad 2', 'cmdline'))
  call assert_equal(['./a.txt'], getcompletion('CommentsLoad ./a', 'cmdline'), 'a path: files')

  CommentsClear
  call assert_equal([], s:comments())
  call writefile(['zero', '  one', '    two', 'three'], s:repo . '/a.txt')
  edit!
  call assert_match('\V\nReview comments: 1 from ' . fnamemodify(l:saves[0], ':~')
        \ . ', 1 moved to where their lines are now\$', s:run('CommentsLoad'))
  call assert_equal(['quickfix', 'Review'], [&buftype, getqflist({'title': 1}).title], 'the list open')
  call assert_equal([{'path': 'a.txt', 'start': 3, 'end': 3, 'body': 'check this'}], s:comments(),
        \ 'indentation ignored')
endfunction

function! s:suite.load_with_indentation_changed() abort
  call writefile(['def f():', '    return 1', 'x'], s:repo . '/c.py')
  edit c.py
  2Comment why 1
  CommentsSave
  CommentsClear
  call writefile(['class A:', '  def f():', '      return 1', 'x'], s:repo . '/c.py')
  edit!
  CommentsLoad
  call assert_equal([{'path': 'c.py', 'start': 3, 'end': 3, 'body': 'why 1'}], s:comments())
endfunction

function! s:suite.load_a_range_to_the_best_match() abort
  call writefile(['x', 'a', 'b', 'y', 'x', 'a', 'b', 'z'], s:repo . '/c.txt')
  edit c.txt
  6,7Comment the second
  CommentsSave
  CommentsClear
  " Both a-b pairs move: the one followed by z matches more of the context
  call writefile(['new', 'x', 'a', 'b', 'y', 'x', 'a', 'b', 'z'], s:repo . '/c.txt')
  edit!
  CommentsLoad
  call assert_equal([{'path': 'c.txt', 'start': 7, 'end': 8, 'body': 'the second'}], s:comments())
  " Its pair moved up, the other down near its old line: context wins
  cclose
  call writefile(['x', 'a', 'b', 'z', 'p', 'p', 'x', 'a', 'b', 'y'], s:repo . '/c.txt')
  edit!
  CommentsLoad
  call assert_equal([{'path': 'c.txt', 'start': 2, 'end': 3, 'body': 'the second'}], s:comments())
endfunction

function! s:suite.load_with_lines_gone_and_back() abort
  edit a.txt
  2Comment on two
  CommentsSave
  CommentsClear
  call writefile(['one', 'three'], s:repo . '/a.txt')
  edit!
  call assert_match("\nReview comments: 1 from .*, 1 whose lines are gone (W)$", s:run('CommentsLoad'))
  cclose
  call assert_equal([{'path': 'a.txt', 'start': 2, 'end': 2, 'body': 'on two', 'orphaned': 1}], s:comments())
  " Saved again, it keeps its anchor: found once its lines come back
  CommentsSave
  CommentsClear
  call writefile(['zero', 'one', 'two', 'three'], s:repo . '/a.txt')
  edit!
  CommentsLoad
  call assert_equal([{'path': 'a.txt', 'start': 3, 'end': 3, 'body': 'on two'}], s:comments())
endfunction

" A file of comments in vim-review's format, an agent's say, as vim-prompts
" loads it
function! s:suite.load_a_file() abort
  call writefile(['a.txt:1-2: from the agent', "\tsecond line"], s:tmp . '/agent.txt')
  call writefile(['not json'], s:tmp . '/agent.txt.anchors')
  edit a.txt
  call fugitive_extras#comments#load(s:tmp . '/agent.txt')
  call assert_equal([{'path': 'a.txt', 'start': 1, 'end': 2, 'body': "from the agent\nsecond line"}],
        \ s:comments())
  execute 'CommentsSave' fnameescape(s:tmp . '/mine.txt')
  call assert_equal(['a.txt:1-2: from the agent', "\tsecond line"], readfile(s:tmp . '/mine.txt'))
  call assert_true(filereadable(s:tmp . '/mine.txt.anchors'))
endfunction

function! s:suite.save_with_no_comments() abort
  edit a.txt
  1Comment one
  execute 'CommentsSave' fnameescape(s:tmp . '/r.txt')
  CommentsClear
  execute 'CommentsSave' fnameescape(s:tmp . '/r.txt')
  call assert_equal([[], 0], [readfile(s:tmp . '/r.txt'), filereadable(s:tmp . '/r.txt.anchors')])
endfunction

""" :CommentsSave / :CommentsLoad: vim-place's save contract

" An existing directory, or a path ending in /: a new file in it, with its
" anchors beside it
function! s:suite.save_to_a_directory() abort
  edit a.txt
  2Comment kept
  call mkdir(s:tmp . '/existing')
  execute 'CommentsSave' fnameescape(s:tmp . '/existing')
  execute 'CommentsSave' fnameescape(s:tmp . '/existing')
  execute 'CommentsSave' fnameescape(s:tmp . '/new/dir/')
  let l:existing = glob(s:tmp . '/existing/*.txt', 1, 1)
  call assert_equal(2, len(l:existing), 'a new file each time')
  for l:file in l:existing
    call assert_match('/existing/\d\{8}-\d\{6}\(-2\)\=\.txt$', l:file)
    call assert_equal(['a.txt:2: kept'], readfile(l:file))
    call assert_true(filereadable(l:file . '.anchors'))
  endfor
  let l:new = glob(s:tmp . '/new/dir/*', 1, 1)
  call assert_equal(2, len(l:new))
  call assert_match('/new/dir/\d\{8}-\d\{6}\.txt$', l:new[0])
  call assert_equal([], s:saves('main'), 'nothing in the branch''s directory')
endfunction

" With no argument: a new file, then the same one again; the file the
" comments were loaded from; and each branch's own file
function! s:suite.save_with_no_argument() abort
  edit a.txt
  2Comment first
  CommentsSave
  let l:saves = s:saves('main')
  call assert_equal(2, len(l:saves))
  1Comment second
  CommentsSave
  call assert_equal(l:saves, s:saves('main'), 'the same file')
  call assert_equal(2, len(review#read(l:saves[0]).comments))
  " Loaded, the comments save back to their file
  let l:file = s:tmp . '/kept.txt'
  call writefile(['a.txt:3: from a file'], l:file)
  execute 'CommentsLoad' fnameescape(l:file)
  cclose
  3Comment added
  CommentsSave
  call assert_equal(['a.txt:3: from a file', 'a.txt:3: added'], readfile(l:file))
  call assert_equal(l:saves, s:saves('main'))
  " Another branch: a file of its own
  CommentsClear
  silent Git checkout -q -b feature
  1Comment on feature
  CommentsSave
  call assert_equal(2, len(s:saves('feature')))
  call assert_equal(['a.txt:3: from a file', 'a.txt:3: added'], readfile(l:file))
endfunction

function! s:suite.save_and_load_a_name() abort
  edit a.txt
  2Comment in wip
  CommentsSave wip
  let l:wip = s:repo . '/.git/fugitive-extras/comments/main/wip.txt'
  call assert_equal(['a.txt:2: in wip'], readfile(l:wip))
  call assert_true(filereadable(l:wip . '.anchors'))
  " Saved over without !
  CommentsClear
  1Comment wip again
  CommentsSave wip
  call assert_equal(['a.txt:1: wip again'], readfile(l:wip))
  CommentsClear
  call assert_match('\V\nReview comments: 1 from ' . fnamemodify(l:wip, ':~') . '\$', s:run('CommentsLoad wip'))
  call assert_equal([{'path': 'a.txt', 'start': 1, 'end': 1, 'body': 'wip again'}], s:comments())
  cclose
  " Starting with .: a path
  CommentsSave ./k.txt
  call assert_equal(['a.txt:1: wip again'], readfile(s:repo . '/k.txt'))
endfunction

function! s:suite.names_complete_newest_first() abort
  edit a.txt
  1Comment one
  CommentsSave work
  sleep 1100m
  CommentsSave wip
  call assert_equal(['wip', 'work'], getcompletion('CommentsLoad w', 'cmdline'))
  call assert_equal(['wip'], getcompletion('CommentsSave wi', 'cmdline'))
  call assert_equal(['./a.txt'], getcompletion('CommentsSave ./a', 'cmdline'), 'a path: files')
  CommentsClear
  CommentsLoad
  call assert_equal([], glob(s:repo . '/.git/fugitive-extras/comments/main/2*', 1, 1), 'no new file')
  call system('touch -t 202001010000 ' . shellescape(s:repo . '/.git/fugitive-extras/comments/main/wip.txt'))
  call assert_equal(['work', 'wip'], getcompletion('CommentsLoad w', 'cmdline'))
  call assert_match("\nReview comments: 1 from .*/work\\.txt$", s:run('CommentsLoad'), 'the newest')
endfunction

" Another file at a path is kept without !; the comments stay unsaved
function! s:suite.a_path_is_kept_without_bang() abort
  edit a.txt
  1Comment mine
  let l:file = s:tmp . '/other.txt'
  call writefile(['theirs'], l:file)
  call s:only_says(fnamemodify(l:file, ':~') . ' exists (add ! to overwrite)',
        \ s:run('CommentsSave ' . fnameescape(l:file)))
  call assert_equal(['theirs'], readfile(l:file))
  call assert_match('unsaved review comments from main', execute('Git checkout -q -b feature'))
  silent Git checkout -q main
  execute 'CommentsSave!' fnameescape(l:file)
  call assert_equal(['a.txt:1: mine'], readfile(l:file))
  " Its own file again: no !
  2Comment more
  call assert_match('^\nSaved 2 review comments to ', s:run('CommentsSave ' . fnameescape(l:file)))
endfunction

" A failed write: the comments stay unsaved, and the file isn't theirs
function! s:suite.save_failing() abort
  edit a.txt
  1Comment one
  call mkdir(s:tmp . '/locked')
  call setfperm(s:tmp . '/locked', 'r-xr-xr-x')
  call assert_match('E482: ', s:run('CommentsSave ' . fnameescape(s:tmp . '/locked/x.txt')))
  call setfperm(s:tmp . '/locked', 'rwxr-xr-x')
  call assert_equal([{'path': 'a.txt', 'start': 1, 'end': 1, 'body': 'one'}], s:comments())
  CommentsSave
  call assert_equal([], glob(s:tmp . '/locked/*', 1, 1), 'not taken for their file')
  call assert_equal(2, len(s:saves('main')))
endfunction

function! s:suite.load_a_name_refused() abort
  edit a.txt
  call s:only_says('no saved comments nope for main', s:run('CommentsLoad nope'))
endfunction

function! s:suite.load_refused() abort
  edit a.txt
  call s:only_says('no saved comments for main', s:run('CommentsLoad'))
  call s:only_says('no review file ' . fnamemodify(s:tmp . '/none.txt', ':~'),
        \ s:run('CommentsLoad ' . fnameescape(s:tmp . '/none.txt')))
endfunction

function! s:suite.comments_outside_a_repository() abort
  for l:dir in ['notes', 'talks']
    call mkdir(s:tmp . '/' . l:dir)
    call writefile(['first', 'second'], s:tmp . '/' . l:dir . '/b.txt')
  endfor
  execute 'cd' fnameescape(s:tmp . '/notes')
  edit b.txt
  2Comment in notes
  CommentsSave
  CommentsClear
  CommentsLoad
  call assert_equal([{'path': 'b.txt', 'start': 2, 'end': 2, 'body': 'in notes'}], s:comments())
  " A file outside the current directory
  execute 'edit' fnameescape(s:tmp . '/talks/b.txt')
  call s:only_says('not a file under ' . fnamemodify(s:tmp . '/notes', ':~'), s:run('Comment elsewhere'))
  " Another directory's saves are its own
  CommentsClear
  execute 'cd' fnameescape(s:tmp . '/talks')
  call s:only_says('no saved comments', s:run('CommentsLoad'))
endfunction

function! s:suite.comments_per_branch() abort
  edit a.txt
  1Comment on main
  silent Git checkout -q -b feature
  call assert_equal("\nfugitive-extras: unsaved review comments from main (:CommentsSave)\nReview comments: 2",
        \ execute('2Comment on feature'))
  CommentsClear
  2Comment on feature
  CommentsSave
  " Saved, so they leave the list with their branch
  call assert_match("\nfugitive-extras: saved review comments of feature left the list (:CommentsLoad on feature)$",
        \ execute('Git checkout -q main'))
  call assert_equal([], s:comments())
  1Comment on main
  CommentsSave
  CommentsClear
  CommentsLoad
  call assert_equal([{'path': 'a.txt', 'start': 1, 'end': 1, 'body': 'on main'}], s:comments())
  silent Git checkout -q feature
  call assert_equal([], s:comments())
  CommentsLoad
  call assert_equal([{'path': 'a.txt', 'start': 2, 'end': 2, 'body': 'on feature'}], s:comments())
endfunction

" As gh-extras calls it after checking a PR out
function! s:suite.check_after_a_checkout_outside_fugitive() abort
  edit a.txt
  1Comment on main
  call s:git('checkout', '-q', '-b', 'feature')
  call assert_equal("\nfugitive-extras: unsaved review comments from main (:CommentsSave)",
        \ execute('call fugitive_extras#comments#check()'))
endfunction

function! s:suite.comment_changed_after_save_stays() abort
  edit a.txt
  silent Git checkout -q -b feature
  2Comment first
  CommentsSave
  Comments
  call s:type('c')
  call setline(1, 'changed')
  write
  quit
  call assert_match("\nfugitive-extras: unsaved review comments from feature (:CommentsSave)$",
        \ execute('Git checkout -q main'))
  call assert_equal([{'path': 'a.txt', 'start': 2, 'end': 2, 'body': 'changed'}], s:comments())
endfunction

" Without vim-place there are no saves: :Git commands go on as before
function! s:suite.git_commands_without_vim_place() abort
  edit a.txt
  call assert_notmatch('E\d\+:\|fugitive-extras:', s:without('vim-place', 'Git branch -q other'))
endfunction

function! s:suite.deleted_branch_saves_go() abort
  edit a.txt
  silent Git checkout -q -b feature
  1Comment on feature
  CommentsSave
  call assert_equal(2, len(s:saves('feature')))
  silent Git checkout -q main
  call assert_match("\nfugitive-extras: removed the saved comments of deleted branches: feature$",
        \ execute('Git branch -q -D feature'))
  call assert_equal([], s:saves('feature'))
  call assert_false(isdirectory(s:repo . '/.git/fugitive-extras/comments/feature'))
endfunction

" Deleted outside Vim: gone the first time comments are used in the session;
" a tag or a remote branch of that name keeps them
function! s:suite.deleted_branch_saves_go_on_first_use() abort
  for l:branch in ['gone', 'tagged', 'pushed']
    call s:git('checkout', '-q', '-b', l:branch, 'main')
    edit! a.txt
    1Comment saved
    CommentsSave
    CommentsClear
  endfor
  call s:git('checkout', '-q', 'main')
  call s:git('tag', 'tagged', 'tagged')
  call s:git('update-ref', 'refs/remotes/origin/pushed', 'pushed')
  call s:git('branch', '-q', '-D', 'gone', 'tagged', 'pushed')
  " A new repo path: this session hasn't used comments in it
  let l:old = s:repo
  let s:repo = s:tmp . '/moved/repo'
  call mkdir(fnamemodify(s:repo, ':h'), 'p')
  call rename(l:old, s:repo)
  execute 'cd' fnameescape(s:repo)
  edit! a.txt
  call assert_match('removed the saved comments of deleted branches: gone\n', s:run('2Comment new'))
  call assert_equal([[], 2, 2], [s:saves('gone'), len(s:saves('tagged')), len(s:saves('pushed'))])
endfunction
