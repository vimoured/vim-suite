" gh-extras: what the dotfiles use of it (:PRs, also from the shell's
" `vim . +PRs`; <leader>cc / <leader>cd in thread lists, its reply <Plug>s) and
" its README. gh is test/bin/gh, canned answers about the repo built here
" (GitHub's o/r): open PRs #7 (branch fix-login) and #8, merged #5 and #4.
" What gh-extras sends GitHub is read back from the fake's log.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('gh-extras')

let s:tmp = resolve(tempname())
let $GH_LOG = s:tmp . '/gh.log'
" Each test's repo is new, at a new path: fugitive remembers repos by path
let s:repos = 0
let s:leader = get(g:, 'mapleader', '\')

function! s:git(args) abort
  return trim(system('git -C ' . shellescape(s:repo) . ' ' . a:args))
endfunction

function! s:numbered(prefix, count) abort
  return map(range(1, a:count), 'a:prefix . v:val')
endfunction

" main has a.py and b.py; fix-login (PR #7) changes b.py at lines 3 and 18
" (two hunks) and a.py at 9. The work tree is on main
function! s:reset() abort
  silent! tabonly!
  silent! only!
  silent! %bwipeout!
  unlet! g:gh_extras_pr_authors
  call fugitive_extras#comments#clear()
  call delete(s:tmp, 'rf')
  let s:repos += 1
  let s:repo = s:tmp . '/' . s:repos . '/repo'
  call mkdir(s:repo, 'p')
  call s:git('init -q -b main')
  call s:git('remote add origin https://github.com/o/r')
  call writefile(s:numbered('a', 20), s:repo . '/a.py')
  call writefile(s:numbered('b', 20), s:repo . '/b.py')
  call writefile(['x'], s:repo . '/x.txt')
  call s:git('add -A')
  call s:git('commit -q -m base')
  call s:git('checkout -q -b fix-login')
  let l:b = s:numbered('b', 20)
  let [l:b[2], l:b[17]] = ['b3 fixed', 'b18 fixed']
  call writefile(l:b, s:repo . '/b.py')
  let l:a = s:numbered('a', 20)
  let l:a[8] = 'a9 fixed'
  call writefile(l:a, s:repo . '/a.py')
  call s:git('commit -q -am fix')
  " Pushed: what GitHub has of the PR
  call s:git('update-ref refs/remotes/origin/fix-login fix-login')
  call s:git('checkout -q main')
  call writefile([], $GH_LOG)
  execute 'cd' fnameescape(s:repo)
  execute 'edit' fnameescape(s:repo . '/x.txt')
endfunction

function! s:suite.before_each() abort
  call s:reset()
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

" Keys or an Ex command; returns the messages, and any error
function! s:type(keys) abort
  let v:errmsg = ''
  try
    let l:out = execute('call g:suite.feed(' . string(a:keys) . ')')
  catch
    return v:exception
  endtry
  return empty(v:errmsg) ? l:out : l:out . "\n" . v:errmsg
endfunction

function! s:run(cmd) abort
  let v:errmsg = ''
  try
    return execute(a:cmd)
  catch
    return v:exception
  endtry
endfunction

" What gh was asked, and sent
function! s:sent() abort
  return join(readfile($GH_LOG), "\n")
endfunction

function! s:on(text) abort
  call cursor(search(a:text, 'cw'), 1)
endfunction

" :PRs

function! s:suite.prs() abort
  PRs
  call assert_equal('gh-extras://prs/repo', bufname())
  call assert_match('^Open PRs (2)  <CR> checkout  t threads  o browser  / filter  r refresh  q close$',
        \ getline(1))
  call assert_match('^#\s\+who\s\+title\s\+branch\s\+state\s\+age', getline(2))
  call assert_match('^#7 \+mira \+Fix login \+fix-login \+approved \+\d\+d$', getline(3))
  call assert_match('^#8 \+sam \+Add search \+search \+draft ', getline(4))
  call assert_equal(3, line('.'))
  call feedkeys("/search\<CR>", 'x')
  call assert_match('^Open PRs (2), 1 matching ''search''', getline(1))
  call assert_equal(3, line('$'))
  call assert_match('^#8 ', getline('.'))
endfunction

function! s:suite.prs_count() abort
  PRs
  call assert_match('-F count=20 ', s:sent(), 'default 20')
  PRs 300
  call assert_match('-F count=100 ', s:sent(), 'at most 100')
endfunction

function! s:suite.prs_author_names_from_the_file() abort
  let g:gh_extras_pr_authors = s:tmp . '/authors.txt'
  " A # line is skipped: a commented-out entry too
  call writefile(['#Old Name: sam', 'Mira Dev: MIRA'], g:gh_extras_pr_authors)
  PRs
  call assert_match('^#7 \+Mira Dev \+Fix login', getline(3), 'a name, for a login in any case')
  call assert_match('^#8 \+sam ', getline(4), 'the # line skipped')
endfunction

function! s:suite.prs_enter_checks_out() abort
  PRs
  call s:on('^#7 ')
  call assert_match('Checked out #7 (:BranchDiff, :BranchCommits to review)', s:type("\<CR>"))
  call assert_equal('fix-login', s:git('branch --show-current'))
  call assert_notmatch('^gh-extras://', bufname(), 'the list is closed')
endfunction

function! s:suite.prs_enter_warns_of_unsaved_comments() abort
  edit a.py
  2Comment a note
  PRs
  call s:on('^#7 ')
  call assert_match('unsaved review comments', s:type("\<CR>"))
endfunction

function! s:suite.prs_t_o_r_q() abort
  PRs
  call s:on('^#8 ')
  call s:type('r')
  call assert_match('^#8 ', getline('.'), 'r keeps the cursor on its PR')
  call s:type('o')
  call assert_match('gh pr view --web 8', s:sent())
  call s:on('^#7 ')
  call s:type('t')
  call assert_equal('gh-extras://thread/repo', bufname())
  call assert_match('^#7: ', getline(1))
  " q goes back to the list t was pressed in, then closes it
  call s:type('q')
  call assert_equal('gh-extras://prs/repo', bufname())
  call s:type('q')
  call assert_notmatch('^gh-extras://', bufname())
endfunction

" :MergedPRs

function! s:suite.merged_prs() abort
  MergedPRs
  call assert_equal('gh-extras://merged-prs/repo', bufname())
  call assert_match('^Merged PRs (2)  <CR> commit', getline(1))
  call assert_match('^#\s\+who\s\+title\s\+branch\s\+commit\s\+merged', getline(2))
  call assert_match('^#5 \+mira \+Tidy up \+tidy \+' . s:git('rev-parse --short=7 main') . ' \+\d\+d$',
        \ getline(3), 'latest merged first, its merge commit')
  call assert_match('^#4 \+sam \+Old work \+old \+deadbee ', getline(4))
  call assert_match('-F count=50 ', s:sent(), 'default 50')
endfunction

function! s:suite.merged_prs_enter_shows_the_merge_commit() abort
  MergedPRs
  call s:on('^#5 ')
  call assert_notmatch('E\d\+:\|gh-extras:', s:type("\<CR>"))
  call assert_match('^fugitive://.*//' . s:git('rev-parse main') . '$', bufname())
  call assert_equal(2, winnr('$'), 'in the window above the list')
endfunction

function! s:suite.merged_prs_enter_without_the_commit() abort
  MergedPRs
  call s:on('^#4 ')
  call assert_match('commit deadbee is not here; :Git fetch first', s:type("\<CR>"))
endfunction

" :Thread, :Threads

function! s:suite.thread() abort
  Thread 7
  call assert_equal('gh-extras://thread/repo', bufname())
  call assert_equal(['#7: 3 open, 1 your turn  = open/close  <CR> file  :Reply  x resolve'
        \ . '  u resolved  o browser  / filter  r refresh  q close',
        \ 'a.py:9  open  (1)  me: nit',
        \ 'b.py:3  your turn  (2)  mira: because',
        \ 'b.py:5  open, outdated  (1)  me: pending one'], getline(1, '$'))
  call assert_equal(2, line('.'))
  " = opens the thread under the cursor, which stays on it
  call cursor(3, 1)
  normal =
  call assert_equal(['b.py:3  your turn', '    me (', '      why?'],
        \ [getline(3), getline(4)[:7], getline(5)])
  call assert_equal(3, line('.'))
  normal =
  call assert_equal(4, line('$'))
  " u shows the resolved thread, in file order
  normal u
  call assert_equal('a.py:1  resolved  (1)  sam: done', getline(2))
  " Opening the list again, from the file, keeps u and opened threads
  call s:on('^b.py:3 ')
  normal =
  wincmd p
  Thread 7
  call assert_equal('a.py:1  resolved  (1)  sam: done', getline(2), 'u kept')
  call assert_match('^    me (', getline(5), '= kept')
  call feedkeys("/sam\<CR>", 'x')
  call assert_equal(['a.py:1  resolved  (1)  sam: done'], getline(2, '$'))
endfunction

function! s:suite.thread_pending_comment() abort
  Thread 7
  call s:on('^b.py:5 ')
  normal =
  call assert_match('^    me (.*, pending)$', getline(line('.') + 1))
endfunction

function! s:suite.thread_of_the_branch() abort
  call assert_match('no PR for this branch; pass its number', s:run('Thread'))
  call s:git('checkout -q fix-login')
  Thread
  call assert_match('^#7: ', getline(1))
endfunction

function! s:suite.threads() abort
  Threads
  call assert_equal('gh-extras://threads/repo', bufname())
  call assert_match('^Your threads: 4 open, 1 your turn  = open/close', getline(1))
  call assert_equal(['#7  fix-login  Fix login', '  a.py:9  open  (1)  me: nit',
        \ '  b.py:3  your turn  (2)  mira: because', '  b.py:5  open, outdated  (1)  me: pending one',
        \ '#8  search  Add search', '  c.py:2  open  (1)  me: see here'], getline(2, '$'))
  call assert_equal(3, line('.'), 'on the first thread, not its PR')
  " o on a PR's line: that PR
  call cursor(6, 1)
  call s:type('o')
  call assert_match('gh pr view --web 8', s:sent())
endfunction

function! s:suite.thread_enter_on_the_branch_checked_out() abort
  call s:git('checkout -q fix-login')
  Thread 7
  call s:on('^b.py:3 ')
  call assert_notmatch('E\d\+:\|gh-extras:', s:type("\<CR>"))
  call assert_equal(s:repo . '/b.py', bufname(), 'the work tree file')
  call assert_equal(3, line('.'))
endfunction

function! s:suite.thread_enter_on_another_branch() abort
  Thread 7
  call s:on('^b.py:3 ')
  call s:type("\<CR>")
  call assert_match('^fugitive://.*//' . s:git('rev-parse fix-login') . '/b\.py$', bufname(), 'as of the PR''s head')
  call assert_equal('b3 fixed', getline('.'))
endfunction

function! s:suite.thread_enter_outdated() abort
  Thread 7
  call s:on('^b.py:5 ')
  call s:type("\<CR>")
  call assert_match('^fugitive://.*//' . s:git('rev-parse main') . '/b\.py$', bufname(), 'as of its commit')
  call assert_equal(5, line('.'))
endfunction

function! s:suite.thread_enter_without_the_commit() abort
  Thread 8
  call s:on('^c.py:2 ')
  call assert_match('commit deadbee is not here; :Git fetch first', s:type("\<CR>"))
endfunction

" A thread on a whole file has no line
function! s:suite.whole_file_thread_shows_its_path() abort
  Thread 8
  call assert_equal('a.py  your turn  (1)  sam: about this file', getline(search('^a\.py', 'cw')))
endfunction

function! s:suite.whole_file_thread_opens_the_file_at_line_1() abort
  Thread 8
  call s:on('^a\.py ')
  call s:type("\<CR>")
  call assert_match('a\.py$', bufname())
  call assert_equal(1, line('.'))
endfunction

function! s:suite.thread_x_resolves_and_unresolves() abort
  Thread 7
  call s:on('^b.py:3 ')
  call s:type('x')
  call assert_match('resolveReviewThread.*"thread":"T1"', s:sent())
  normal u
  call s:on('^a.py:1 ')
  call s:type('x')
  call assert_match('unresolveReviewThread.*"thread":"T2"', s:sent())
endfunction

" Replying

function! s:suite.reply_with_the_dotfiles_key() abort
  Thread 7
  call s:on('^b.py:3 ')
  call assert_match('Reply posted', s:type(s:leader . "ccthanks\<CR>"))
  call assert_match('addPullRequestReviewThreadReply.*"body":"thanks".*"thread":"T1"\|"thread":"T1".*"body":"thanks"', s:sent())
endfunction

function! s:suite.reply_to_a_pending_review() abort
  Thread 7
  call s:on('^b.py:5 ')
  call assert_match('Reply added to your pending review; submit it on GitHub to post it',
        \ s:run('Reply later'))
endfunction

function! s:suite.reply_left_at_the_prompt_is_kept() abort
  Thread 7
  call s:on('^b.py:3 ')
  call assert_match('Reply kept: :Reply or :ReplyDraft on b.py:3 goes on from it',
        \ s:type(s:leader . "cc\<CR>half done\<Esc>"))
  call assert_notmatch('addPullRequestReviewThreadReply', s:sent(), 'nothing posted')
  call s:type(s:leader . 'cd')
  call assert_equal(['half done'], getline(1, '$'), ':ReplyDraft goes on from it')
endfunction

function! s:suite.reply_draft_posts_when_closed() abort
  Thread 7
  call s:on('^b.py:3 ')
  call s:type(s:leader . 'cd')
  call assert_equal('gh-extras://reply/7/b.py:3', bufname())
  call assert_equal('markdown', &filetype)
  call assert_equal(10, winheight(0))
  call assert_equal(3, winnr('$'), 'above the list')
  call setline(1, 'drafted reply')
  write
  quit
  call assert_match('"body":"drafted reply"', s:sent())
endfunction

function! s:suite.reply_draft_empty_posts_nothing() abort
  Thread 7
  call s:on('^b.py:3 ')
  call s:type(s:leader . 'cd')
  quit!
  call assert_notmatch('addPullRequestReviewThreadReply', s:sent())
endfunction

function! s:suite.reply_that_fails_is_in_the_unnamed_register() abort
  Thread 7
  call s:on('^b.py:3 ')
  call assert_match('reply not posted; its text is in the unnamed register', s:run('Reply FAIL here'))
  call assert_equal('FAIL here', getreg('"'))
endfunction

function! s:suite.reply_draft_outside_a_thread_list() abort
  call assert_match('not in a :Thread or :Threads list', s:type("\<Plug>(gh-extras-reply-draft)"))
endfunction

" :CommentsSubmit (fugitive-extras' :Comment makes the comments)

function! s:on_the_pr_branch() abort
  call s:git('checkout -q fix-login')
  edit! b.py
endfunction

function! s:suite.submit_posts_a_pending_review_of_head() abort
  call s:on_the_pr_branch()
  3Comment one line
  2,4Comment a range
  call assert_match('Pending review of ' . s:git('rev-parse --short=7 HEAD') . ' with 2 comments: https://github.com/o/r/pull/7#pullrequestreview-1',
        \ s:run('CommentsSubmit'))
  let l:review = json_decode(matchstr(s:sent(), 'input: \zs{"co[^\n]*'))
  call assert_equal(s:git('rev-parse HEAD'), l:review.commit_id)
  call assert_equal([
        \ {'path': 'b.py', 'body': 'one line', 'line': 3, 'side': 'RIGHT'},
        \ {'path': 'b.py', 'body': 'a range', 'line': 4, 'side': 'RIGHT', 'start_line': 2, 'start_side': 'RIGHT'}],
        \ sort(l:review.comments, {a, b -> a.line - b.line}))
endfunction

function! s:suite.submit_without_comments() abort
  call s:on_the_pr_branch()
  call assert_match('no review comments', s:run('CommentsSubmit'))
endfunction

function! s:suite.submit_with_a_file_changed_since_head() abort
  call s:on_the_pr_branch()
  3Comment one line
  call setline(10, 'changed')
  write
  call assert_match('comments on files changed since HEAD, so their lines are not its: b.py; commit or stash',
        \ s:run('CommentsSubmit'))
  call assert_notmatch('/reviews', s:sent())
endfunction

function! s:suite.submit_with_a_comment_whose_lines_are_gone() abort
  call s:on_the_pr_branch()
  3Comment one line
  CommentsSave
  CommentsClear
  call setline(3, 'something else entirely')
  write
  call s:git('commit -q -am change')
  CommentsLoad
  call assert_match('1 comments whose lines are gone (W in :Comments)', s:run('CommentsSubmit'))
  call assert_notmatch('/reviews', s:sent())
endfunction

function! s:suite.submit_outside_the_diff() abort
  call s:on_the_pr_branch()
  10Comment between the hunks
  3,18Comment across both hunks
  call assert_match('2 comments on lines outside the PR''s diff, which GitHub rejects: b.py:10, b.py:3-18\|2 comments on lines outside the PR''s diff, which GitHub rejects: b.py:3-18, b.py:10',
        \ s:run('CommentsSubmit'))
  call assert_notmatch('/reviews', s:sent())
endfunction

function! s:suite.submit_with_head_not_in_the_pr() abort
  call s:on_the_pr_branch()
  3Comment one line
  " An unpushed commit, not on the commented file: the review is of the PR's head
  call writefile(['new'], 'new.py')
  call s:git('add new.py')
  call s:git('commit -q -m unpushed')
  call assert_match('Pending review of ' . s:git('rev-parse --short=7 HEAD~1'), s:run('CommentsSubmit'))
  " One on the commented file: refused
  call s:reset()
  call s:on_the_pr_branch()
  3Comment one line
  call setline(20, 'b20 more')
  write
  call s:git('commit -q -am unpushed')
  call assert_match('is not in PR 7, and its head .* has these commented files different: b.py; push, or check out the PR',
        \ s:run('CommentsSubmit'))
endfunction

function! s:suite.commands_only_with_gh() abort
  call themis#helper('assert').skip('TODO: needs a Vim started without gh on PATH (CI has gh)')
endfunction
