" vim-prompts in a repository, on a branch with a change: what :AiPreview
" shows an ask would send and run, :Ai's one-offs, :AiDraft, :AiPersonas,
" :AiSources and the completion of :Ai. Outside a repository:
" test/vim-prompts-outside-a-repository.vim; with Copilot:
" test/vim-prompts-copilot.vim.
"
" Your personas are in ~/.config/vim-prompts/personas, a team's handbook (its
" personas and task rules) is named in the repository's config. The agent is
" `true`, so nothing answers but in the one-off tests.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('vim-prompts')

let s:tmp = resolve(tempname())
let s:app = s:tmp . '/app'
let s:handbook = s:tmp . '/handbook'
let s:personas = $HOME . '/.config/vim-prompts/personas'
call writefile(['[vim-prompts]', "\tpersonas = ~/.config/vim-prompts/personas"], $HOME . '/.gitconfig')

let g:prompts_agent_table = {'fake': {'cmd': ['true'], 'prompt': [], 'dir': '--add-dir',
      \ 'modes': {'ask': [], 'plan': [], 'agent': [], 'auto': []}}}

function! s:git(...) abort
  let l:out = system('git -C ' . shellescape(s:app) . ' ' . join(map(copy(a:000), 'shellescape(v:val)')))
  if v:shell_error
    throw 'git ' . join(a:000) . ': ' . l:out
  endif
endfunction

function! s:write(file, lines) abort
  call mkdir(fnamemodify(a:file, ':h'), 'p')
  call writefile(a:lines, a:file)
endfunction

" app.py on branch feature, changed from main
function! s:suite.before_each() abort
  silent! only!
  silent! %bwipeout!
  cd /
  call delete(s:tmp, 'rf')
  call delete(s:personas, 'rf')
  call s:write(s:personas . '/review.md', ['{base}', '', 'Also check the error messages read well.'])
  call s:write(s:handbook . '/personas/review/pr.md',
        \ ['---', 'context: [+testing]', '---', '{base}', '', 'Check that each change comes with a test.'])
  call s:write(s:handbook . '/personas/tests.md',
        \ ['---', 'context: [here, +testing]', '---', 'Write tests for this file.', '', '{query}'])
  call s:write(s:handbook . '/task-rules/testing.md', ['- Tests run against the shared fixtures.'])
  call s:write(s:handbook . '/task-rules/test-setup.md', ['- Start the database with make db.'])
  call s:write(s:app . '/app.py', ['def add(a, b):', '    return a + b'])
  call s:git('init', '-q', '-b', 'main')
  call s:git('config', 'vim-prompts.personas', s:handbook . '/personas')
  call s:git('config', 'vim-prompts.task-rules', s:handbook . '/task-rules')
  call s:git('add', '.')
  call s:git('commit', '-q', '-m', 'init')
  call s:git('checkout', '-q', '-b', 'feature')
  call writefile(['def add(a, b):', '    return a - b'], s:app . '/app.py')
  call s:git('commit', '-qam', 'subtract')
  execute 'cd' fnameescape(s:app)
  edit app.py
  let g:prompts_agent = 'fake'
  messages clear
endfunction

function! s:suite.after() abort
  silent! %bwipeout!
  cd /
  call delete(s:tmp, 'rf')
endfunction

" vim-prompts' errors since the last call
function! s:errors() abort
  let l:errors = filter(split(execute('messages'), "\n"), 'v:val =~# "^vim-prompts: "')
  messages clear
  return map(l:errors, 'v:val[13:]')
endfunction

" [range]AiPreview[!] {args}: the prompt it shows, the command line it would
" run, and the errors, as {prompt, line, errors}
function! s:preview(args, ...) abort
  messages clear
  silent! bwipeout ai-preview://
  execute get(a:, 1, '') . 'AiPreview' . get(a:, 2, '') . ' ' . a:args
  let l:result = {'prompt': '', 'line': '', 'errors': s:errors()}
  if bufname() ==# 'ai-preview://'
    let l:result.prompt = join(getline(1, '$'), "\n")
    let l:result.line = &l:statusline
    wincmd p
  endif
  return l:result
endfunction

" The :AiPersonas line of /{name}
function! s:personas_line(name) abort
  return get(filter(getline(1, '$'), 'v:val =~# "^  /' . a:name . ' "'), 0, '')
endfunction

" :AiSources' line of {source}
function! s:sources_line(source) abort
  return get(filter(getline(1, '$'), 'v:val =~# "^  ' . a:source . '"'), 0, '')
endfunction

" Personas: yours, the handbook's, and the bundled ones they build on

function! s:suite.variant_builds_on_the_persona_and_each_layer() abort
  let l:r = s:preview('/review:pr')
  call assert_equal([], l:r.errors)
  " The bundled /review, yours on it, the handbook's variant on that, and the
  " bundled variant's change
  call assert_match('I am reviewing code in Vim', l:r.prompt)
  call assert_match('Also check the error messages read well', l:r.prompt)
  call assert_match('Check that each change comes with a test', l:r.prompt)
  call assert_match('Changes on this branch since it forked from main', l:r.prompt)
endfunction

function! s:suite.variant_sends_the_rules_and_the_branch_its_context_names() abort
  let l:r = s:preview('/review:pr')
  call assert_match('Tests run against the shared fixtures', l:r.prompt)
  call assert_match('- M app.py', l:r.prompt)
endfunction

function! s:suite.persona_on_a_selection_sends_neither_the_branch_nor_the_variant() abort
  let l:r = s:preview('/review', '%')
  call assert_equal([], l:r.errors)
  call assert_match('Selected lines, app.py:1-2', l:r.prompt)
  call assert_notmatch('Changes on this branch', l:r.prompt)
  call assert_notmatch('Check that each change comes with a test', l:r.prompt)
endfunction

function! s:suite.review_without_anything_to_work_on_refuses() abort
  let l:r = s:preview('/review is this right')
  call assert_equal('', l:r.prompt)
  call assert_equal(['/review needs something to work on: a selection, an @file or a #source;'
        \ . ' --force sends it without'], l:r.errors)
endfunction

function! s:suite.review_with_force_sends_without_anything_to_work_on() abort
  let l:r = s:preview('/review --force is this right')
  call assert_equal([], l:r.errors)
  call assert_match('is this right', l:r.prompt)
endfunction

function! s:suite.review_of_a_file() abort
  let l:r = s:preview('/review @app.py')
  call assert_equal([], l:r.errors)
  call assert_match('app.py', l:r.prompt)
endfunction

function! s:suite.variant_on_main_needs_a_diff_or_changes() abort
  call s:git('checkout', '-q', 'main')
  let l:r = s:preview('/review:pr')
  call assert_equal('', l:r.prompt)
  call assert_equal(['/review:pr needs a diff (:DiffThis, :BranchDiff), or a comparison listed in'
        \ . ' :Compares, or changes (on this branch; #changes:staged; #changes:<branch>);'
        \ . ' --force sends it without'], l:r.errors)
endfunction

function! s:suite.typed_source_replaces_the_personas() abort
  call writefile(['def add(a, b):', '    return b - a'], s:app . '/app.py')
  call s:git('add', 'app.py')
  let l:r = s:preview('/review:pr #changes:staged')
  call assert_equal([], l:r.errors)
  call assert_match('Staged changes', l:r.prompt)
  call assert_notmatch('since it forked from main', l:r.prompt)
endfunction

" [#diff_pairs #changes]: with a diff open, the diff, not the branch
function! s:suite.alternatives_take_the_first_with_something() abort
  Gdiffsplit main
  let l:r = s:preview('/review:pr')
  call assert_equal([], l:r.errors)
  call assert_match('Diffs open in Vim', l:r.prompt)
  call assert_notmatch('Changes on this branch', l:r.prompt)
endfunction

function! s:suite.persona_rule_is_sent() abort
  let l:r = s:preview('/tests')
  call assert_equal([], l:r.errors)
  call assert_match('Tests run against the shared fixtures', l:r.prompt)
endfunction

function! s:suite.persona_with_a_missing_rule_refuses() abort
  call s:write(s:personas . '/strict.md', ['---', 'context: [here, +nope]', '---', 'Check it.'])
  let l:r = s:preview('/strict')
  call assert_equal('', l:r.prompt)
  call assert_equal(['/strict: +nope has nothing: needs a rules file in'
        \ . ' vim-prompts.task-rules: +<Tab>'], l:r.errors)
endfunction

" --force is for nothing to work on, not for a missing rule
function! s:suite.force_does_not_send_without_a_missing_rule() abort
  call s:write(s:personas . '/strict.md', ['---', 'context: [here, +nope]', '---', 'Check it.'])
  call assert_equal(['/strict: +nope has nothing: needs a rules file in'
        \ . ' vim-prompts.task-rules: +<Tab>'], s:preview('/strict --force').errors)
endfunction

function! s:suite.optional_rule_is_sent_where_there_is_one() abort
  call s:write(s:personas . '/lenient.md', ['---', 'context: [here, +nope?, "+testing?"]', '---', 'Check it.'])
  let l:r = s:preview('/lenient')
  call assert_equal([], l:r.errors)
  call assert_match('Tests run against the shared fixtures', l:r.prompt)
endfunction

function! s:suite.malformed_front_matter_refuses() abort
  for [l:lines, l:error] in [
        \ [['context: [here?]'], 'context: only a rule may be missing (+name?), not here?'],
        \ [['context: [[+testing, here]]'], 'context: +testing is always sent, not one of [alternatives]'],
        \ [['context: [[[here]]]'], 'context: one level of [alternatives], of sources'],
        \ [['input: maybe'], 'input: required or optional'],
        \ [['answer: later'], 'answer: oneoff or session'],
        \ ]
    call s:write(s:personas . '/bad.md', ['---'] + l:lines + ['---', 'x'])
    call assert_equal(['~/.config/vim-prompts/personas/bad.md: ' . l:error], s:preview('/bad').errors)
  endfor
endfunction

function! s:suite.variant_with_base_needs_its_persona() abort
  call s:write(s:personas . '/lonely/one.md', ['{base}', 'x'])
  call assert_equal(['~/.config/vim-prompts/personas/lonely/one.md: {base}, but no /lonely below it'],
        \ s:preview('/lonely:one').errors)
endfunction

function! s:suite.variant_without_base_stands_alone() abort
  call s:write(s:personas . '/lonely/one.md', ['Stand alone.'])
  call assert_match('Stand alone.', s:preview('/lonely:one').prompt)
endfunction

function! s:suite.persona_of_a_variant_alone_is_no_persona() abort
  call s:write(s:personas . '/lonely/one.md', ['Stand alone.'])
  call assert_equal(['no persona /lonely (:AiPersonas)'], s:preview('/lonely').errors)
endfunction

" One-offs and sessions: :AiPreview's line, -p for a one-off

function! s:suite.review_is_a_oneoff_with_its_comments_in_the_answer() abort
  let l:r = s:preview('/review', '%')
  call assert_match(' -p <prompt>', l:r.line)
  call assert_match('```vim-prompts-comments', l:r.prompt)
  call assert_notmatch('write each comment', l:r.prompt)
endfunction

function! s:suite.variant_is_a_oneoff_like_its_persona() abort
  call assert_match(' -p <prompt>', s:preview('/review:pr').line)
endfunction

function! s:suite.bang_makes_review_a_session_writing_its_comments() abort
  let l:r = s:preview('/review', '%', '!')
  call assert_notmatch(' -p ', l:r.line)
  call assert_match('write each comment .* to `' . s:app . '/.git/vim-prompts/comments/', l:r.prompt)
endfunction

function! s:suite.agent_comments_in_a_repository_go_to_its_git_dir() abort
  let l:r = s:preview('#agent_comments', '%')
  call assert_notmatch(' -p ', l:r.line)
  call assert_match('to `' . s:app . '/.git/vim-prompts/comments/', l:r.prompt)
  call assert_notmatch('--add-dir', l:r.line)
endfunction

function! s:suite.bang_makes_a_session_ask_a_oneoff() abort
  let l:r = s:preview('#agent_comments is this right', '%', '!')
  call assert_match(' -p <prompt>', l:r.line)
  call assert_match('```vim-prompts-comments', l:r.prompt)
endfunction

" The dotfiles start sessions in auto mode (g:prompts_mode)
function! s:suite.session_starts_in_the_mode_the_dotfiles_set() abort
  let g:prompts_agent_table.modal = {'cmd': ['true'], 'prompt': ['-i'],
        \ 'modes': {'ask': ['--ask'], 'auto': ['--auto']}, 'oneoff_modes': {'auto': ['--yes']}}
  let g:prompts_agent = 'modal'
  call assert_match('true --auto -i <prompt>', s:preview('-- hi').line)
endfunction

function! s:suite.oneoff_runs_in_its_auto_mode() abort
  let g:prompts_agent_table.modal = {'cmd': ['true'], 'prompt': ['-i'],
        \ 'modes': {'ask': ['--ask'], 'auto': ['--auto']}, 'oneoff_modes': {'auto': ['--yes']}}
  let g:prompts_agent = 'modal'
  call assert_match('true --yes -p <prompt>', s:preview('-- hi', '', '!').line)
endfunction

function! s:suite.oneoff_runs_in_the_mode_asked_for() abort
  let g:prompts_agent_table.modal = {'cmd': ['true'], 'prompt': ['-i'],
        \ 'modes': {'ask': ['--ask'], 'auto': ['--auto']}, 'oneoff_modes': {'auto': ['--yes']}}
  let g:prompts_agent = 'modal'
  call assert_match('true --ask -p <prompt>', s:preview('--ask-mode -- hi', '', '!').line)
endfunction

" A one-off that answers: its comments are saved for :AiComments

" %Ai /review with an agent printing an answer and two comments; the one-off's
" buffer once it's done
function! s:answered_review() abort
  let l:answer = 'It subtracts.\n```vim-prompts-comments\napp.py:2: 1. [blocking] minus\n'
        \ . '\tshould be plus\napp.py:1-2: 2. [nit] name it\n```\n'
  let g:prompts_agent_table.answers = {'cmd': ['sh', '-c', 'printf ''' . l:answer . '''', 'sh'],
        \ 'oneoff': [], 'prompt': [], 'modes': {'ask': []}}
  let g:prompts_agent = 'answers'
  %Ai /review
  let l:bufnr = bufnr('ai-oneoff://*')
  for l:i in range(100)
    if getbufvar(l:bufnr, 'prompts_oneoff') !~# 'answering'
      break
    endif
    sleep 20m
  endfor
  return l:bufnr
endfunction

function! s:suite.oneoff_says_it_saved_the_comments() abort
  let l:bufnr = s:answered_review()
  call assert_equal('answers: done, 2 comments for :AiComments', getbufvar(l:bufnr, 'prompts_oneoff'))
endfunction

function! s:suite.oneoff_shows_the_answer_without_its_comments_block() abort
  let l:lines = getbufline(s:answered_review(), 1, '$')
  call assert_equal(1, len(filter(copy(l:lines), 'v:val =~# "^It subtracts"')))
  call assert_equal([], filter(copy(l:lines), 'v:val =~# "```"'))
endfunction

function! s:suite.oneoff_writes_the_comments_where_its_note_says() abort
  let l:note = filter(getbufline(s:answered_review(), 1, '$'), 'v:val =~# "^(2 comments saved to "')
  call assert_equal(1, len(l:note))
  call assert_equal(['app.py:2: 1. [blocking] minus', "\tshould be plus", 'app.py:1-2: 2. [nit] name it'],
        \ readfile(expand(matchstr(get(l:note, 0, ''), 'saved to \zs\S\+\ze:'))))
endfunction

function! s:suite.ai_comments_lists_the_oneoffs_comments() abort
  call s:answered_review()
  AiComments
  call assert_equal([], s:errors())
  call assert_equal([2, 1], map(getqflist(), 'v:val.lnum'))
endfunction

" Rules for the task: +name

function! s:suite.plus_sends_a_task_rule() abort
  let l:r = s:preview('/review +testing', '%')
  call assert_equal([], l:r.errors)
  call assert_match('Tests run against the shared fixtures', l:r.prompt)
endfunction

function! s:suite.a_rule_is_not_a_source() abort
  call assert_equal(['a rule is +name, not #rule: +testing; text after -- is taken as is'],
        \ s:preview('/review #rule:testing', '%').errors)
endfunction

function! s:suite.plus_without_a_rule_refuses() abort
  call assert_equal(['+nope has nothing: needs a rules file in vim-prompts.task-rules: +<Tab>'],
        \ s:preview('/review +nope', '%').errors)
endfunction

function! s:suite.plus_before_anything_but_a_letter_is_text() abort
  call assert_match('+1 on this', s:preview('+1 on this', '%').prompt)
endfunction

" #here: the file and line you ask from

function! s:suite.here_is_the_file_and_line_you_ask_from() abort
  call assert_match('Current file: `app.py`, line \d', s:preview('#here x').prompt)
endfunction

function! s:suite.file_source_points_at_here_and_at_path() abort
  call assert_equal(['the file and line you ask from is #here, not #file; files are @path;'
        \ . ' text after -- is taken as is'], s:preview('#file x').errors)
endfunction

function! s:suite.here_from_a_listing_refuses() abort
  enew
  setlocal buftype=nofile
  call assert_equal(['#here has nothing: needs a file to ask from, not a listing or a scratch buffer'],
        \ s:preview('#here x').errors)
endfunction

" Opened from a listing, sent once a file is open in its window
function! s:suite.draft_asks_from_where_it_is_sent() abort
  enew
  setlocal buftype=nofile
  AiDraft! #here what is this
  call assert_equal('ai-draft://ask', bufname())
  wincmd p
  edit app.py
  wincmd p
  messages clear
  wq
  sleep 50m
  call assert_equal([], s:errors())
  call assert_true(bufnr('ai-oneoff://*') > 0, 'the one-off went')
endfunction

" Completion of :Ai, and the dotfiles' <c-x><c-a> in a draft

function! s:suite.ai_completes_personas_variants_rules_and_flags() abort
  for [l:cmdline, l:matches] in [
        \ ['Ai /rev', ['/review', '/review:']],
        \ ['Ai /review:', ['/review:pr']],
        \ ['Ai --f', ['--force']],
        \ ['Ai +te', ['+test-setup', '+testing']],
        \ ]
    call assert_equal(l:matches, getcompletion(l:cmdline, 'cmdline'), l:cmdline)
  endfor
endfunction

function! s:suite.hash_completes_no_rule() abort
  call assert_equal([], filter(getcompletion('Ai #', 'cmdline'), 'v:val =~# "rule"'))
endfunction

" A word that completes to nothing: every token, to pick from
function! s:suite.draft_picker_offers_variants_and_rules() abort
  AiDraft
  let g:suite.fzf = []
  call g:suite.feed("Gonothing\<c-x>\<c-a>")
  let l:source = get(get(g:suite.fzf, -1, {}), 'source', [])
  call assert_true(index(l:source, '/review:pr') >= 0, string(l:source))
  call assert_true(index(l:source, '+testing') >= 0, string(l:source))
endfunction

" :AiPersonas

" The handbook's, on the bundled one, on yours, on the bundled /review
function! s:suite.personas_list_shows_what_each_builds_on() abort
  AiPersonas
  call assert_match('handbook/personas/review/pr\.md .*#agent_comments \[#diff_pairs #changes\]'
        \ . ' +testing  on {base} \S*/personas/review/pr\.md  on {base} \~/\.config/'
        \ . 'vim-prompts/personas/review\.md  on {base} \S*/personas/review\.md$', s:personas_line('review:pr'))
endfunction

function! s:suite.personas_list_shows_what_a_persona_lacks() abort
  call s:write(s:personas . '/strict.md', ['---', 'context: [+nope, +gone?]', '---', 'x'])
  AiPersonas
  call assert_match('/strict .*+nope +gone?  /strict: +nope has nothing', s:personas_line('strict'))
endfunction

function! s:suite.personas_list_shows_a_bad_variant_name() abort
  call s:write(s:personas . '/review/no.good.md', ['x'])
  AiPersonas
  call assert_equal(['error: ~/.config/vim-prompts/personas/review/no.good.md: name must be letters,'
        \ . ' digits, - and _'], filter(getline(1, '$'), 'v:val =~# "no\\.good"'))
endfunction

" :AiSources, judged from app.py on a branch with a change

function! s:suite.sources_list_what_to_work_on_then_how() abort
  AiSources
  let l:lines = getline(1, '$')
  call assert_match('^Sources (12)', l:lines[0])
  let l:what = index(l:lines, 'what to work on')
  let l:how = index(l:lines, 'how to work on it')
  call assert_true(l:what > 0 && l:how > l:what, string(l:lines))
  let l:after = l:lines[l:how + 1 :]
  call assert_equal(2, len(l:after))
  call assert_match('^  #agent_comments ', get(l:after, 0, ''))
  call assert_match('^  +name .*+testing .*(:AiRules)$', get(l:after, 1, ''))
endfunction

function! s:suite.sources_list_says_which_have_something_here() abort
  AiSources
  call assert_match('^  #changes\[:arg\] .*  has something here$', s:sources_line('#changes'))
  call assert_match('^  #quickfix .*  nothing here: needs a quickfix list', s:sources_line('#quickfix'))
  call assert_match('^  @path ', s:sources_line('@path'))
  call assert_match('^  #url:arg .*  a link: ', s:sources_line('#url'))
endfunction

" A copy on 'runtimepath' before the bundled one hides it (its functions only
" from the next Vim: the bundled file is loaded already)
function! s:suite.sources_list_shows_a_source_hidden_by_a_copy() abort
  let l:dir = s:tmp . '/mine'
  call s:write(l:dir . '/autoload/prompts/sources/quickfix.vim',
        \ readfile(g:suite.deps . '/vim-prompts/autoload/prompts/sources/quickfix.vim'))
  execute 'set runtimepath^=' . fnameescape(l:dir)
  try
    AiSources
    normal r
    let l:qf = filter(getline(1, '$'), 'v:val =~# "^  #quickfix"')
    call assert_equal(2, len(l:qf))
    call assert_match('^  #quickfix \+\S*/mine/autoload/prompts/sources/quickfix\.vim ', get(l:qf, 0, ''))
    call assert_match('/vim-prompts/autoload/prompts/sources/quickfix\.vim \+hidden by \S*/mine/',
          \ get(l:qf, 1, ''))
  finally
    execute 'set runtimepath-=' . fnameescape(l:dir)
    " :AiPersonas! loads the sources again
    AiPersonas!
  endtry
endfunction
