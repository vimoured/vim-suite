" fugitive-extras: what the dotfiles use of it. Ported from its test/run.vim.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('fugitive-extras')

let s:tmp = resolve(tempname())
let s:repo = s:tmp . '/repo'
let g:roumail_place_dir = s:tmp . '/saves'
let s:out = []

function! s:git(...) abort
  call system('git -C ' . shellescape(s:repo) . ' -c user.name=t -c user.email=t@t '
        \ . join(map(copy(a:000), 'shellescape(v:val)')))
  " git ran outside fugitive, which caches HEAD by its time to the second: a
  " checkout in the same second as an earlier test's read of the same path
  " would keep the old branch. 0 expires it without a FugitiveChanged event
  call FugitiveDidChange(0)
endfunction

function! s:reset() abort
  silent! tabonly!
  for l:compare in fugitive_extras#compares#list()
    call fugitive_extras#compares#remove(l:compare.dir, l:compare.name)
  endfor
  silent! %bwipeout!
  CommentsClear
  call delete(s:tmp, 'rf')
  call mkdir(s:repo, 'p')
  call s:git('init', '-q', '-b', 'main')
  call writefile(['one', 'two', 'three'], s:repo . '/a.txt')
  call s:git('add', 'a.txt')
  call s:git('commit', '-q', '-m', 'init')
  execute 'cd' fnameescape(s:repo)
endfunction

function! s:saves(branch) abort
  return glob(s:repo . '/.git/fugitive-extras/comments/' . a:branch . '/*', 1, 1)
endfunction

function! s:suite.save_and_load_back_where_the_lines_are() abort
  edit a.txt
  2Comment check this
  CommentsSave
  let l:saves = s:saves('main')
  call assert_equal(2, len(l:saves))
  call assert_match('/\d\{8}-\d\{6}\.txt$', l:saves[0])
  call assert_equal(['a.txt:2: check this'], readfile(l:saves[0]))
  call assert_equal(l:saves[0] . '.anchors', l:saves[1])

  CommentsClear
  call assert_equal([], fugitive_extras#comments#list())
  call writefile(['zero', 'one', 'two', 'three'], s:repo . '/a.txt')
  edit!
  CommentsLoad
  call assert_equal([{'path': 'a.txt', 'start': 3, 'end': 3, 'body': 'check this'}],
        \ fugitive_extras#comments#list())
endfunction

function! s:suite.load_agent_comments() abort
  call writefile(['a.txt:1-2: from the agent', "\tsecond line"], s:tmp . '/agent.txt')
  edit a.txt
  execute 'CommentsLoad' fnameescape(s:tmp . '/agent.txt')
  call assert_equal([{'path': 'a.txt', 'start': 1, 'end': 2, 'body': "from the agent\nsecond line"}],
        \ fugitive_extras#comments#list())
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
  call assert_equal([{'path': 'b.txt', 'start': 2, 'end': 2, 'body': 'in notes'}],
        \ fugitive_extras#comments#list())
  " A file outside the current directory
  execute 'edit' fnameescape(s:tmp . '/talks/b.txt')
  call assert_equal("\nfugitive-extras: not a file under " . fnamemodify(s:tmp . '/notes', ':~'),
        \ execute('Comment elsewhere'))
  " Another directory's saves are its own
  CommentsClear
  execute 'cd' fnameescape(s:tmp . '/talks')
  call assert_equal("\nfugitive-extras: no saved comments", execute('CommentsLoad'))
endfunction

function! s:suite.comments_per_branch() abort
  edit a.txt
  1Comment on main
  silent Git checkout -q -b feature
  call assert_equal("\nfugitive-extras: unsaved review comments from main (:CommentsSave)\nReview comments: 2",
        \ execute('2Comment on feature'))
  call fugitive_extras#comments#clear()
  2Comment on feature
  CommentsSave
  " Saved, so they leave the list with their branch
  call assert_match("\nfugitive-extras: saved review comments of feature left the list (:CommentsLoad on feature)$",
        \ execute('Git checkout -q main'))
  call assert_equal([], fugitive_extras#comments#list())
  1Comment on main
  CommentsSave
  CommentsClear
  CommentsLoad
  call assert_equal([{'path': 'a.txt', 'start': 1, 'end': 1, 'body': 'on main'}],
        \ fugitive_extras#comments#list())
  silent Git checkout -q feature
  call assert_equal([], fugitive_extras#comments#list())
  CommentsLoad
  call assert_equal([{'path': 'a.txt', 'start': 2, 'end': 2, 'body': 'on feature'}],
        \ fugitive_extras#comments#list())
endfunction

function! s:suite.comment_changed_after_save_stays() abort
  edit a.txt
  silent Git checkout -q -b feature
  2Comment first
  CommentsSave
  Comments
  execute "normal c"
  call setline(1, 'changed')
  write
  quit
  call assert_match("\nfugitive-extras: unsaved review comments from feature (:CommentsSave)$",
        \ execute('Git checkout -q main'))
  call assert_equal([{'path': 'a.txt', 'start': 2, 'end': 2, 'body': 'changed'}],
        \ fugitive_extras#comments#list())
endfunction

function! s:suite.deleted_branch_saves_go() abort
  edit a.txt
  silent Git checkout -q -b feature
  1Comment on feature
  CommentsSave
  call assert_equal(2, len(s:saves('feature')))
  silent Git checkout -q main
  silent Git branch -q -D feature
  call assert_equal([], s:saves('feature'))
  call assert_false(isdirectory(s:repo . '/.git/fugitive-extras/comments/feature'))
endfunction

function! s:suite.compares_list() abort
  call s:git('checkout', '-q', '-b', 'feature')
  call writefile(['one', 'TWO', 'three'], s:repo . '/a.txt')
  call s:git('commit', '-q', '-am', 'change')
  let l:base = trim(system('git -C ' . shellescape(s:repo) . ' rev-parse main'))
  let l:head = trim(system('git -C ' . shellescape(s:repo) . ' rev-parse feature'))
  call fugitive_extras#compares#open(FugitiveGitDir(), 'feature', l:base, l:head)
  call assert_equal(2, tabpagenr('$'), 'one tab for the changed file')
  tabfirst
  Compares
  call assert_equal('fugitive-extras://compares/repo', bufname())
  call assert_equal('Comparisons (1)  <CR> open  dd remove  / filter  r refresh  q close',
        \ getline(1))
  call assert_match('^feature \+' . l:base[:6] . '\.\.' . l:head[:6] . '\x* \+1 files \+1 open',
        \ getline(2))
  call assert_equal(2, line('.'))
  call assert_equal('feature', roumail_lists#item().name)
  normal dd
  call assert_equal(['Comparisons (0)  <CR> open  dd remove  / filter  r refresh  q close'],
        \ getline(1, '$'))
  call assert_equal([], fugitive_extras#compares#list())
  normal q
  call assert_false(bufexists('fugitive-extras://compares/repo'))
  silent! tabonly!
endfunction

" The names of the files a comparison's tabs show, sorted
function! s:compare_files(name) abort
  let l:compare = filter(fugitive_extras#compares#list(), 'v:val.name ==# a:name')[0]
  return sort(map(copy(l:compare.tabs),
        \ {_, t -> fnamemodify(FugitiveReal(bufname(tabpagebuflist(t)[-1])), ':t')}))
endfunction

function! s:suite.branch_diff_committed_or_work_tree() abort
  call s:git('checkout', '-q', '-b', 'feature')
  call writefile(['one', 'TWO', 'three'], s:repo . '/a.txt')
  call s:git('commit', '-q', '-am', 'change')
  " Not committed: a stash applied, say
  call writefile(['b'], s:repo . '/b.txt')
  call s:git('add', 'b.txt')
  edit a.txt
  BranchDiff
  call assert_equal(['a.txt'], s:compare_files('feature'))
  call assert_equal('feature', fugitive_extras#compares#list()[0].head)
  " The merge-base on the left, the branch's commit on the right
  let l:sides = map(tabpagebuflist(fugitive_extras#compares#list()[0].tabs[0]),
        \ 'FugitiveParse(bufname(v:val))[0]')
  call assert_true(fugitive_extras#is_base(l:sides[0]), 'left: ' . l:sides[0])
  call assert_false(fugitive_extras#is_base(l:sides[-1]), 'right: ' . l:sides[-1])
  tabfirst
  BranchDiff!
  call assert_equal(['a.txt', 'b.txt'], s:compare_files('feature#2'))
  call assert_equal('', fugitive_extras#compares#list()[0].head)
  call assert_match('no branch', execute('BranchDiff! main'))
  silent! tabonly!
endfunction

function! s:suite.diff_refresh() abort
  call s:git('checkout', '-q', '-b', 'feature')
  call writefile(['one', 'TWO', 'three'], s:repo . '/a.txt')
  call s:git('commit', '-q', '-am', 'change')
  edit a.txt
  BranchDiff!
  call assert_equal(['a.txt'], s:compare_files('feature'))
  " An agent's edits, outside Vim: a.txt again, and a new file
  call writefile(['one', 'TWO', 'three', 'four'], s:repo . '/a.txt')
  call writefile(['b'], s:repo . '/b.txt')
  call s:git('add', 'b.txt')
  let l:tabs = tabpagenr('$')
  DiffRefresh
  call assert_equal(['a.txt', 'b.txt'], s:compare_files('feature'))
  call assert_equal(1, len(fugitive_extras#compares#list()), 'the same comparison')
  call assert_equal(l:tabs + 1, tabpagenr('$'))
  " Back on a.txt, its work tree side, read again
  call assert_equal(s:repo . '/a.txt', expand('%:p'))
  call assert_equal(['one', 'TWO', 'three', 'four'], getline(1, '$'))
  " Unsaved changes stop it
  call setline(1, 'edited')
  call assert_match('unsaved changes', execute('DiffRefresh'))
  call assert_equal(['a.txt', 'b.txt'], s:compare_files('feature'))
  silent! tabonly!
endfunction

function! s:suite.diff_refresh_outside_a_comparison() abort
  edit a.txt
  DiffThis
  " Outside Vim, as an agent would: the file changed and staged
  call writefile(['ONE', 'two', 'three'], s:repo . '/a.txt')
  call s:git('add', 'a.txt')
  DiffRefresh
  " The first line: in silent Ex mode, fugitive's index buffer lacks its last
  let l:sides = map(filter(tabpagebuflist(), 'getbufvar(v:val, "&diff")'),
        \ 'getbufline(v:val, 1)')
  call assert_equal([['ONE'], ['ONE']], l:sides)
endfunction

" The first line of each side of this tab's diff, left to right
" The first line of each side, older first. Which side the older one is on
" follows 'splitright' (on in the dotfiles), as for fugitive's :Gvdiffsplit.
function! s:diff_firsts() abort
  let l:firsts = map(filter(range(1, winnr('$')), 'getwinvar(v:val, "&diff")'),
        \ 'getbufline(winbufnr(v:val), 1)[0]')
  return &splitright ? reverse(l:firsts) : l:firsts
endfunction

function! s:suite.diff_commit() abort
  for l:first in ['A', 'B']
    call writefile([l:first, 'two', 'three'], s:repo . '/a.txt')
    call s:git('commit', '-q', '-am', l:first)
  endfor
  " Not committed
  call writefile(['C', 'two', 'three'], s:repo . '/a.txt')
  edit a.txt
  DiffCommit
  call assert_equal(['A', 'B'], s:diff_firsts())
  silent! only | edit a.txt
  DiffCommit!
  call assert_equal(['A', 'C'], s:diff_firsts())
  silent! only | edit a.txt
  DiffCommit HEAD~1
  call assert_equal(['one', 'A'], s:diff_firsts())
  silent! only | edit a.txt
  call assert_match('unknown commit nope', execute('DiffCommit nope'))
  call assert_match('HEAD\~2 has no parent', execute('DiffCommit HEAD~2'))
  call writefile(['b'], s:repo . '/b.txt')
  edit b.txt
  call assert_match('b.txt is not in HEAD', execute('DiffCommit'))
  silent! only
endfunction

function! s:suite.branch_commits_args() abort
  call s:git('checkout', '-q', '-b', 'feature')
  call writefile(['notes'], s:repo . '/my notes.txt')
  call s:git('add', 'my notes.txt')
  call s:git('commit', '-q', '-m', 'add notes')
  call writefile(['one', 'TWO', 'three'], s:repo . '/a.txt')
  call s:git('commit', '-q', '-am', 'change a')
  " A typo in the branch is an unknown branch, not a path for git log
  call assert_match('unknown branch featur ', execute('BranchCommits featur'))
  " A path with a space is one path
  edit my\ notes.txt
  BranchCommits -- %
  call assert_equal(2, line('$'))
  call assert_match('add notes$', getline(2))
  normal q
  " The branch, then a path
  BranchCommits feature -- a.txt
  call assert_equal(2, line('$'))
  call assert_match('  change a ', getline(2))
  normal q
  silent! only
endfunction

function! s:suite.branch_commits_list() abort
  call s:git('checkout', '-q', '-b', 'feature')
  call writefile(['one', 'TWO', 'three'], s:repo . '/a.txt')
  call s:git('commit', '-q', '-am', 'change a')
  call writefile(['b'], s:repo . '/b.txt')
  call s:git('add', 'b.txt')
  call s:git('commit', '-q', '-m', 'add b')
  " main is local here, with no origin
  edit a.txt
  BranchCommits
  call assert_equal('fugitive-extras://commits/repo', bufname())
  call assert_equal('Commits on feature not on main (2)  <CR> commit  / filter  r refresh  q close',
        \ getline(1))
  call assert_match('^\x\{7,}  t \+\S.* ago \+add b (HEAD -> feature)$', getline(2))
  call assert_match('  change a$', getline(3))
  call assert_equal(2, line('.'))
  call assert_equal('add b', roumail_lists#item().subject)
  " <CR>: the commit in fugitive, in the window above
  let l:sha = roumail_lists#item().sha
  execute "normal \<CR>"
  call assert_match('^fugitive://.*' . l:sha . '$', bufname())
  wincmd p
  " / filters on the subject
  call feedkeys("/chg\<CR>", 'x')
  call assert_equal(2, line('$'))
  call assert_match('change a$', getline(2))
  normal q
  " Paths: only the commits that change this file
  edit a.txt
  BranchCommits -- %
  call assert_equal(2, line('$'))
  call assert_match('change a$', getline(2))
  normal q
  " An option picking commits
  BranchCommits --grep=add
  call assert_equal(2, line('$'))
  call assert_match('add b', getline(2))
  " One that adds lines leaves each commit one line
  normal q
  BranchCommits --stat
  call assert_equal(3, line('$'))
  normal q
  silent! only
endfunction

function! s:suite.before_each() abort
  call s:reset()
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction
