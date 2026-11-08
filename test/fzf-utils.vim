" fzf-utils: what the dotfiles use of it (<leader><leader>, <leader>r* in
" normal and visual mode, <C-x><C-f> / <C-x><C-l> / <C-x><C-a> in insert mode,
" :Rg as :RgRaw), vim-prompts' file picker (fzf_utils#pick_files), and its
" README, in a Python project (project-detect looks once, at VimEnter: the
" project is made, and Vim cd'd into it, before the config loads). Outside a
" project: test/fzf-utils-outside-a-project.vim.
"
" fzf itself never runs (g:suite.fzf has what it was asked to show): the
" fd / rg command each search hands fzf is run here, for real, in the project,
" and picking in fzf is calling the sink fzf would call.
let s:tmp = resolve(tempname())
let s:root = s:tmp . '/proj'
for s:dir in ['src/pkg', 'tests', '.venv/lib', '__pycache__']
  call mkdir(s:root . '/' . s:dir, 'p')
endfor
call mkdir(s:tmp . '/shared', 'p')
call writefile(['[project]', 'name = "pkg"'], s:root . '/pyproject.toml')
call writefile(['def find_me():', '    return 1'], s:root . '/src/pkg/code.py')
call writefile(['from pkg.code import find_me'], s:root . '/tests/test_code.py')
call writefile(['find_me in the docs'], s:root . '/README.md')
call writefile(['find_me hidden'], s:root . '/.hidden.py')
call writefile(['find_me cached'], s:root . '/__pycache__/code.py')
call writefile(['find_me ignored'], s:root . '/.venv/lib/dep.py')
call writefile(['find_me shared'], s:tmp . '/shared/linked.py')
call writefile(['.venv/'], s:root . '/.gitignore')
call system('cd ' . shellescape(s:root) . ' && git init -q && ln -s ../shared shared')
execute 'cd' fnameescape(s:root)

let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('fzf-utils')
let s:leader = get(g:, 'mapleader', '\')

function! s:suite.before_each() abort
  let g:suite.fzf = []
  let g:fzf_utils_include_ignored = 0
  silent! only!
  silent! %bwipeout!
  execute 'cd' fnameescape(s:root)
  edit src/pkg/code.py
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

" Keys as typed; returns the messages they gave
function! s:type(keys) abort
  return execute('call g:suite.feed(' . string(a:keys) . ')')
endfunction

" What fzf was last asked to show
function! s:spec() abort
  return get(g:suite.fzf, -1, {})
endfunction

" The output of a command fzf was given, run in dir (default: here), colours
" taken out
function! s:output(cmd, ...) abort
  let l:dir = a:0 ? a:1 : getcwd()
  return map(systemlist('cd ' . shellescape(l:dir) . ' && ' . a:cmd),
        \ 'substitute(v:val, "\\e\\[[0-9;]*m", "", "g")')
endfunction

" The files a listing (fd's, or rg --files) shows, sorted
function! s:listed(cmd, ...) abort
  return sort(call('s:output', [a:cmd] + a:000))
endfunction

" The command a live grep starts with: fzf's start:reload binding
function! s:grep_command(spec) abort
  let l:opts = type(a:spec.options) == v:t_list ? join(a:spec.options, ' ') : a:spec.options
  let l:cmd = matchstr(l:opts, "'start:reload:\\zs.\\{-}\\ze' '")
  return substitute(l:cmd, "'\\\\''", "'", 'g')
endfunction

" The files a grep command matches in, sorted and unique
function! s:matched(cmd) abort
  return uniq(sort(map(s:output(a:cmd), 'matchstr(v:val, "^[^:]*")')))
endfunction

" What fzf was given as its query
function! s:query(spec) abort
  let l:opts = type(a:spec.options) == v:t_list ? join(a:spec.options, ' ') : a:spec.options
  return matchstr(l:opts, "'--query' '\\zs[^']*\\ze'")
endfunction

let s:files = ['.gitignore', '.hidden.py', 'README.md', 'pyproject.toml', 'shared/linked.py',
      \ 'src/pkg/code.py', 'tests/test_code.py']
let s:with_ignored = sort(s:files + ['.venv/lib/dep.py'])
let s:grep_files = ['.hidden.py', 'README.md', 'shared/linked.py', 'src/pkg/code.py', 'tests/test_code.py']

""" The files searched, and including ignored ones

function! s:suite.files_with_the_dotfiles_key() abort
  call s:type(s:leader . s:leader)
  call assert_equal(s:files, s:listed(s:spec().source),
        \ 'dotfiles and symlinks in; .git, __pycache__ and ignored files out')
endfunction

function! s:suite.toggle_includes_ignored_files_everywhere() abort
  call assert_equal("\nfzf-utils include ignored: on", execute('FzfToggleIgnored'))
  FdFiles
  call assert_equal(s:with_ignored, s:listed(s:spec().source), ':FdFiles')
  Grep find_me
  call assert_equal(sort(s:grep_files + ['.venv/lib/dep.py']), s:matched(s:grep_command(s:spec())), ':Grep')
  Rg find_me
  call assert_equal(sort(s:grep_files + ['.venv/lib/dep.py']), s:matched(s:spec().default_command), ':Rg (:RgRaw)')
  call assert_equal("\nfzf-utils include ignored: off", execute('FzfToggleIgnored'))
  FdFiles
  call assert_equal(s:files, s:listed(s:spec().source))
endfunction

" A project's own config can start with them included
function! s:suite.included_from_the_start() abort
  let g:fzf_utils_include_ignored = 1
  FdFiles
  call assert_equal(s:with_ignored, s:listed(s:spec().source))
endfunction

function! s:suite.fdfiles_in_a_directory() abort
  FdFiles src
  call assert_equal(['pkg/code.py'], s:listed(s:spec().source, s:root . '/' . s:spec().dir))
endfunction

" vim-prompts' @ picker: the same listing, absolute paths to the callback
function! s:suite.pick_files() abort
  let s:picked = []
  call fzf_utils#pick_files('src', {files -> extend(s:picked, files)})
  let l:spec = s:spec()
  call assert_equal(['pkg/code.py'], s:listed(l:spec.source, l:spec.dir))
  call l:spec['sink*'](['', 'pkg/code.py'])
  call assert_equal([s:root . '/src/pkg/code.py'], s:picked)
  let g:fzf_utils_include_ignored = 1
  call fzf_utils#pick_files('.', {files -> 0})
  call assert_equal(s:with_ignored, s:listed(s:spec().source, s:spec().dir))
endfunction

""" Live grep

function! s:suite.grep_with_the_dotfiles_key() abort
  call s:type(s:leader . 'r/')
  let l:spec = s:spec()
  call assert_equal('', s:query(l:spec))
  call assert_equal(s:grep_files, s:matched(s:grep_command(l:spec) . 'find_me'),
        \ 'the files searched: as :FdFiles lists them')
  " Regex, fixed string and word modes
  let l:opts = l:spec.options
  for [l:key, l:flag] in [['ctrl-r', '-e'], ['ctrl-f', '-F -e'], ['ctrl-w', '-w -e']]
    call assert_match("'" . l:key . ':change-prompt([A-Za-z]\+> )+reload(rg .* ' . l:flag . ' {q})', l:opts, l:key)
  endfor
endfunction

function! s:suite.grep_a_pattern_with_options_and_paths() abort
  Grep find_me -- -g *.md
  call assert_equal('find_me', s:query(s:spec()))
  call assert_equal(['README.md'], s:matched(s:grep_command(s:spec())))
  Grep find_me -- tests/
  call assert_equal(['tests/test_code.py'], s:matched(s:grep_command(s:spec())))
  " A path with a space is one path
  call mkdir(s:root . '/my notes')
  call writefile(['spaced_word'], s:root . '/my notes/n.md')
  try
    Grep spaced_word -- my\ notes/
    call assert_equal(['my notes/n.md'], s:matched(s:grep_command(s:spec())))
  finally
    call delete(s:root . '/my notes', 'rf')
  endtry
  Grep -- -t py
  call assert_equal('', s:query(s:spec()))
  Grep two words
  call assert_equal('two words', s:query(s:spec()), 'no --: all of it the pattern')
  call assert_equal(['__pycache__/', 'shared/', 'src/', 'tests/'],
        \ sort(filter(getcompletion('Grep x -- ', 'cmdline'), 'v:val !~# "^\\."')), 'after --, directories')
  call assert_equal([], getcompletion('Grep x', 'cmdline'), 'before --, nothing')
endfunction

function! s:suite.grep_the_word_or_the_selection() abort
  call cursor(1, 5)
  call s:type(s:leader . 'r?')
  call assert_equal('\bfind_me\b', s:query(s:spec()))
  call assert_equal(s:grep_files, s:matched(s:grep_command(s:spec())))
  call s:type('0vf(' . s:leader . 'r?')
  call assert_equal('\bdef find_me\(\b', s:query(s:spec()), 'regex characters escaped')
endfunction

function! s:suite.grep_the_buffers_directory() abort
  call s:type(s:leader . 'r.')
  call assert_equal(['src/pkg/code.py'], s:matched(s:grep_command(s:spec()) . 'find_me'))
endfunction

" The accepted query goes to the search register and history; replay runs
" the last grep again with it
function! s:suite.grep_query_kept_and_replayed() abort
  Grep find -- tests/
  let l:spec = s:spec()
  let l:opts = type(l:spec.options) == v:t_list ? join(l:spec.options, ' ') : l:spec.options
  let l:history = matchstr(l:opts, "'--history' '\\zs[^']*\\ze'")
  " fzf writes the query it was accepted with there, then exits
  call writefile(['find_me'], l:history)
  call l:spec.exit(0)
  call assert_equal(['find_me', 'find_me'], [getreg('/'), histget('/', -1)])
  call s:type(s:leader . 'rr')
  call assert_equal('find_me', s:query(s:spec()))
  call assert_equal(['tests/test_code.py'], s:matched(s:grep_command(s:spec())), 'its options too')
  " Left without a pick, or accepted with no query: nothing kept
  call setreg('/', 'before')
  call s:spec().exit(130)
  call assert_equal('before', getreg('/'))
  call writefile(['find_me', ''], l:history)
  call s:spec().exit(0)
  call assert_equal('before', getreg('/'))
endfunction

" The dotfiles' :Rg is :RgRaw (raw rg arguments) in place of fzf.vim's
function! s:suite.rg_is_rgraw() abort
  Rg -g *.md find_me
  call assert_equal(['README.md'], s:matched(s:spec().default_command))
  Rg find_me
  call assert_equal(s:grep_files, s:matched(s:spec().default_command), 'the same files as :Grep')
endfunction

""" Project scopes

function! s:suite.grep_scope_picks_a_scope() abort
  call s:type(s:leader . 'rs')
  call assert_equal(['all', 'project', 'project python', 'tests', 'tests python'], s:spec().source)
  call s:spec().sink('tests python')
  call assert_equal(['tests/test_code.py'], s:matched(s:grep_command(s:spec()) . 'find_me'))
  call cursor(1, 5)
  call s:type(s:leader . 'rS')
  call s:spec().sink('project')
  call assert_equal('\bfind_me\b', s:query(s:spec()))
  call assert_equal(['src/pkg/code.py'], s:matched(s:grep_command(s:spec())))
  GrepScope find
  call s:spec().sink('all')
  call assert_equal('find', s:query(s:spec()))
endfunction

function! s:suite.grep_code_and_tests() abort
  call s:type(s:leader . 'rp')
  call assert_equal(['src/pkg/code.py'], s:matched(s:grep_command(s:spec()) . 'find_me'))
  call s:type(s:leader . 'rt')
  call assert_equal(['tests/test_code.py'], s:matched(s:grep_command(s:spec()) . 'find_me'))
  call cursor(1, 5)
  call s:type(s:leader . 'rP')
  call assert_equal('\bfind_me\b', s:query(s:spec()))
  call s:type('V' . s:leader . 'rT')
  call assert_equal('\bdef find_me\(\):\b', s:query(s:spec()))
endfunction

" From a subdirectory, the project's places are still found
function! s:suite.grep_code_from_a_subdirectory() abort
  cd tests
  call s:type(s:leader . 'rp')
  call assert_equal([s:root . '/src/pkg/code.py'], s:matched(s:grep_command(s:spec()) . 'find_me'))
  cd ../src
  call s:type(s:leader . 'rt')
  call assert_equal([s:root . '/tests/test_code.py'], s:matched(s:grep_command(s:spec()) . 'find_me'),
        \ 'tests: a directory and file globs')
endfunction

""" Completion and pickers

function! s:suite.complete_path_lists_the_same_files() abort
  call s:type("i\<C-x>\<C-f>")
  call assert_equal(s:files, s:listed(s:spec().source), 'as :FdFiles lists them')
  let g:fzf_utils_include_ignored = 1
  call s:type("i\<C-x>\<C-f>")
  call assert_equal(s:with_ignored, s:listed(s:spec().source), 'following the toggle')
endfunction

function! s:suite.complete_line() abort
  call s:type("o\<C-x>\<C-l>")
  call assert_true(!empty(g:suite.fzf), 'fzf asked')
  call assert_match('def find_me', join(s:spec().source))
endfunction

" The dotfiles' <C-x><C-a>: vim-prompts' asks, through fzf_utils#complete#with
function! s:suite.complete_with_another_plugins_spec() abort
  call s:type("o\<C-x>\<C-a>")
  call assert_false(empty(g:suite.fzf), 'fzf asked')
endfunction

" In the command-line window (q:) fzf can't open (E11): Vim's own completion
" (which a Vim without a screen doesn't run, so only that fzf isn't asked), or
" a message
function! s:suite.completion_in_the_command_line_window() abort
  call assert_notmatch('E\d\+:', s:type("q:izz\<C-x>\<C-f>\<Esc>\<Esc>:q\<CR>"))
  call assert_notmatch('E\d\+:', s:type("q:izz\<C-x>\<C-l>\<Esc>\<Esc>:q\<CR>"))
  call assert_equal([], g:suite.fzf, 'fzf not asked')
  " Typed outside execute(), so the message is kept in :messages
  messages clear
  call g:suite.feed("q:i\<C-x>\<C-a>\<Esc>\<Esc>:q\<CR>")
  call assert_match('fzf completion is not available in the command-line window', execute('messages'))
  call assert_equal([], g:suite.fzf, 'fzf not asked')
endfunction

function! s:suite.bd_wipes_out_the_buffers_picked() abort
  edit README.md
  edit pyproject.toml
  BD
  let l:spec = s:spec()
  call assert_equal(3, len(l:spec.source))
  call l:spec['sink*'](filter(copy(l:spec.source), 'v:val =~# "README\\|pyproject"'))
  call assert_equal([0, 0, 1], [bufexists('README.md'), bufexists('pyproject.toml'), bufexists('src/pkg/code.py')])
endfunction

function! s:suite.td_closes_the_tabs_picked() abort
  tabnew README.md
  tabnew pyproject.toml
  TD
  call assert_equal(["1\tcode.py", "2\tREADME.md", "3\tpyproject.toml"], s:spec().source)
  call s:spec()['sink*'](["2\tREADME.md"])
  call assert_equal(2, tabpagenr('$'))
  " All of them: one empty tab left
  TD
  call s:spec()['sink*'](s:spec().source)
  call assert_equal([1, ''], [tabpagenr('$'), bufname()])
  " One with unsaved changes stays
  tabnew README.md
  call setline(1, 'changed')
  setlocal nohidden
  TD
  call assert_equal("\nfzf-utils: 1 tab(s) left open: unsaved changes",
        \ execute('call s:spec()["sink*"](["2\tREADME.md"])'))
  call assert_equal(2, tabpagenr('$'))
endfunction

function! s:suite.commands_only_with_fd_and_rg() abort
  call themis#helper('assert').skip('TODO: needs a Vim started without fd or rg on PATH (CI has both)')
endfunction
