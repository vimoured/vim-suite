" pytest.vim: what the dotfiles use of it (maplocalleader _: _r*, _t* and _d*
" in test files and in the test lists, :RunPytest, :TracePytest, :PytestTests,
" :PytestOutline, :ParsePytestFailures, qf-tools' dd / :QfSave / :QfLoad on
" the lists), with real runs: pytest from deps/python, through the dotfiles'
" chkpyt.sh (g:project_detect_runners), dispatched by vim-dispatch. A
" conftest.py records the tests pytest ran. Without pytest in deps/python (CI
" installs it for Python-related pull requests only) the runs are TODO skips.
"
" A Python project, the current directory before project-detect looks (once,
" at VimEnter)
let s:tmp = resolve(tempname())
let s:root = s:tmp . '/proj'
call mkdir(s:root . '/tests', 'p')
call mkdir(s:root . '/src/pkg', 'p')
call writefile(['[project]', 'name = "pkg"'], s:root . '/pyproject.toml')
call writefile([], s:root . '/src/pkg/__init__.py')
call writefile(['def test_not_a_test_file():', '    pass'], s:root . '/src/pkg/code.py')
call writefile([
      \ 'import os',
      \ 'import pytest',
      \ '',
      \ '@pytest.fixture(autouse=True)',
      \ 'def _record(request):',
      \ '    with open(os.environ["RAN"], "a") as f:',
      \ '        f.write(request.node.nodeid + "\n")',
      \ ], s:root . '/tests/conftest.py')
let s:sample = [
      \ 'import pytest',
      \ '',
      \ 'def helper():',
      \ '    return 1',
      \ '',
      \ 'def test_one():',
      \ '    assert helper()',
      \ '',
      \ 'class TestThing:',
      \ '    def setup_method(self):',
      \ '        pass',
      \ '',
      \ '    @pytest.mark.parametrize("x", [1, 2])',
      \ '    def test_a(self, x):',
      \ '        def inner():',
      \ '            pass',
      \ '        assert x',
      \ '',
      \ '    def test_b(self):',
      \ '        pass',
      \ '',
      \ 'class Helper:',
      \ '    def test_ignored(self):',
      \ '        pass',
      \ '',
      \ 'def test_two(',
      \ '    tmp_path,',
      \ '):',
      \ '    pass',
      \ ]
call writefile(s:sample, s:root . '/tests/test_sample.py')
let s:other = ['def test_other():', '    pass', '', 'def test_fails():', '    assert 1 == 2']
call writefile(s:other, s:root . '/tests/test_other.py')
call writefile(['class TestAsync:', '    async def test_c(self):', '        pass', '',
      \ 'class TestNoMethods:', '    x = 1'], s:root . '/tests/test_async.py')
execute 'cd' fnameescape(s:root)
" A repository, as projects are: its files are listed with git ls-files
call system('git init -q')

let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('pytest.vim')

" pytest from the suite's venv, the dotfiles' chkpyt.sh
let s:venv = g:suite.deps . '/python/bin'
let s:has_pytest = executable(s:venv . '/pytest')
let $PATH = s:venv . ':' . g:suite.deps . '/dotfiles/.config/shell/bin:' . $PATH
let $RAN = s:tmp . '/ran.txt'
let s:lead = get(g:, 'maplocalleader', '\')

function! s:suite.before_each() abort
  call setqflist([], 'f')
  silent! tabonly!
  silent! only!
  silent! %bwipeout!
  execute 'cd' fnameescape(s:root)
  call writefile(s:sample, s:root . '/tests/test_sample.py')
  call writefile(s:other, s:root . '/tests/test_other.py')
  call delete($RAN)
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

function! s:needs_pytest() abort
  if !s:has_pytest
    call themis#helper('assert').skip('TODO: needs pytest in deps/python (CI installs it for Python-related pull requests)')
  endif
endfunction

" Keys as typed; returns the messages they gave
function! s:type(keys) abort
  return execute('call g:suite.feed(' . string(a:keys) . ')')
endfunction

" Waits up to 20s (or a:1 times 50ms) for a:cond (an expression) to hold
function! s:wait(cond, what, ...) abort
  for l:i in range(a:0 ? a:1 : 400)
    if eval(a:cond)
      return 1
    endif
    sleep 50m
  endfor
  call assert_report('timed out waiting for ' . a:what)
  return 0
endfunction

" The tests pytest ran since the last call, sorted
function! s:ran() abort
  let l:ran = filereadable($RAN) ? sort(readfile($RAN)) : []
  call delete($RAN)
  return l:ran
endfunction

" Types keys that dispatch a run, waits for it to finish; returns the command
" it ran and the tests pytest ran
function! s:dispatched(keys) abort
  let l:before = get(dispatch#request(), 'file', '')
  let l:out = s:type(a:keys)
  " Started at once, or not at all (a message instead)
  let l:started = 'get(dispatch#request(), "file", "") !=# ' . string(l:before)
  if !s:wait(l:started, 'the run of ' . a:keys . ' to start', 40)
        \ || !s:wait('dispatch#completed(0)', 'the run of ' . a:keys)
    return [l:out, []]
  endif
  return [dispatch#request().command, s:ran()]
endfunction

" The terminal a --trace session runs in: waits for the debugger's prompt in
" it, quits the debugger and returns its first line
function! s:traced() abort
  if !s:wait('!empty(filter(term_list(), "term_getstatus(v:val) =~# ''running''"))', 'a terminal')
    return ''
  endif
  let l:buf = filter(term_list(), 'term_getstatus(v:val) =~# "running"')[0]
  call s:wait('join(getbufline(' . l:buf . ', 1, "$")) =~# "(Pdb"', 'the debugger prompt')
  let l:name = bufname(l:buf)
  call term_sendkeys(l:buf, "q\r")
  call s:wait('term_getstatus(' . l:buf . ') !~# "running"', 'the debugger to quit')
  return l:name
endfunction

""" Keys in a test file

function! s:suite.run_the_method() abort
  call s:needs_pytest()
  edit tests/test_sample.py
  call cursor(14, 1)
  let [l:cmd, l:ran] = s:dispatched(s:lead . 'rm')
  call assert_match('chkpyt\.sh .*tests/test_sample\.py::TestThing::test_a$', l:cmd,
        \ 'the dotfiles'' runner')
  call assert_equal(['tests/test_sample.py::TestThing::test_a[1]',
        \ 'tests/test_sample.py::TestThing::test_a[2]'], l:ran, 'parametrised: one test')
  " A function nested in a method is part of it
  call cursor(16, 1)
  call assert_equal(2, len(s:dispatched(s:lead . 'rm')[1]))
  call cursor(19, 1)
  call assert_equal(['tests/test_sample.py::TestThing::test_b'], s:dispatched(s:lead . 'rm')[1])
endfunction

function! s:suite.run_the_class() abort
  call s:needs_pytest()
  edit tests/test_sample.py
  call cursor(17, 1)
  call assert_equal(['tests/test_sample.py::TestThing::test_a[1]', 'tests/test_sample.py::TestThing::test_a[2]',
        \ 'tests/test_sample.py::TestThing::test_b'], s:dispatched(s:lead . 'rc')[1])
endfunction

function! s:suite.run_the_function() abort
  call s:needs_pytest()
  edit tests/test_sample.py
  call cursor(7, 1)
  call assert_equal(['tests/test_sample.py::test_one'], s:dispatched(s:lead . 'rf')[1])
  " Its arguments over several lines
  call cursor(28, 1)
  call assert_equal(['tests/test_sample.py::test_two'], s:dispatched(s:lead . 'rf')[1])
endfunction

function! s:suite.run_the_file() abort
  call s:needs_pytest()
  edit tests/test_sample.py
  call cursor(4, 1)
  call assert_equal(['tests/test_sample.py::TestThing::test_a[1]', 'tests/test_sample.py::TestThing::test_a[2]',
        \ 'tests/test_sample.py::TestThing::test_b', 'tests/test_sample.py::test_one',
        \ 'tests/test_sample.py::test_two'], s:dispatched(s:lead . 'rt')[1])
endfunction

" Where the scope isn't: a message, nothing run
function! s:suite.run_no_such_scope() abort
  edit tests/test_sample.py
  let l:before = dispatch#request()
  for [l:lnum, l:keys, l:scope] in [[4, 'rf', 'function'], [14, 'rf', 'function'], [29, 'rc', 'class'],
        \ [9, 'rm', 'method'], [1, 'rm', 'method']]
    call cursor(l:lnum, 1)
    call assert_equal("\nCould not determine test path for scope: " . l:scope, s:type(s:lead . l:keys),
          \ 'line ' . l:lnum . ' ' . l:keys)
  endfor
  call assert_equal(l:before, dispatch#request(), 'nothing dispatched')
endfunction

function! s:suite.a_failure_in_the_quickfix_list() abort
  call s:needs_pytest()
  edit tests/test_other.py
  call s:dispatched(s:lead . 'rt')
  let l:failed = filter(getqflist(), 'v:val.valid')
  call assert_equal([['tests/test_other.py', 5]],
        \ map(l:failed, '[bufname(v:val.bufnr), v:val.lnum]'), 'test_fails, at its assert')
endfunction

function! s:suite.trace_keys() abort
  call s:needs_pytest()
  edit tests/test_sample.py
  call cursor(7, 1)
  call s:type(s:lead . 'tf')
  call assert_match('chkpyt\.sh --no-default-addopts tests/test_sample\.py::test_one --trace', s:traced(),
        \ 'the dotfiles'' debug command, in a terminal')
  call cursor(19, 1)
  call s:type(s:lead . 'tm')
  call assert_match('tests/test_sample\.py::TestThing::test_b --trace', s:traced())
  call s:type(s:lead . 'tc')
  call assert_match('tests/test_sample\.py::TestThing --trace', s:traced())
  call s:type(s:lead . 'tt')
  call assert_match('tests/test_sample\.py --trace', s:traced())
endfunction

" --pdb stops only at a failure, so these tests fail
let s:broken = ['class TestBroken:', '    def test_m(self):', '        assert 0', '',
      \ 'def test_f():', '    assert 0']

function! s:suite.debug_keys() abort
  call s:needs_pytest()
  call writefile(s:broken, s:root . '/tests/test_broken.py')
  try
    edit tests/test_broken.py
    call cursor(6, 1)
    call s:type(s:lead . 'df')
    call assert_match('chkpyt\.sh --no-default-addopts tests/test_broken\.py::test_f --pdb', s:traced(),
          \ 'the dotfiles'' debug command, in a terminal')
    call cursor(3, 1)
    call s:type(s:lead . 'dm')
    call assert_match('tests/test_broken\.py::TestBroken::test_m --pdb', s:traced())
    call s:type(s:lead . 'dc')
    call assert_match('tests/test_broken\.py::TestBroken --pdb', s:traced())
    call s:type(s:lead . 'dt')
    call assert_match('tests/test_broken\.py --pdb', s:traced())
  finally
    call delete(s:root . '/tests/test_broken.py')
  endtry
endfunction

function! s:end_terminals() abort
  for l:buf in term_list()
    call job_stop(term_getjob(l:buf), 'kill')
  endfor
  call s:wait('empty(filter(term_list(), "term_getstatus(v:val) =~# ''running''"))', 'the terminals to end', 60)
endfunction

" A --trace session inside tmux (a private server here), with dispatch-extras'
" _cs toggled to tmux: in a Vim terminal whatever :Start's strategy, and so is
" a:1, keys that repeat it
function! s:trace_in_tmux(...) abort
  call s:needs_pytest()
  if !executable('tmux')
    call themis#helper('assert').skip('TODO: needs tmux (CI has none)')
  endif
  let l:tmux = 'tmux -L vim-suite-pytest -f /dev/null '
  call system(l:tmux . 'kill-server')
  call system(l:tmux . 'new-session -d -s suite -x 200 -y 50')
  let [l:saved, l:windows] = [g:dispatch_no_tmux_start, len(systemlist(l:tmux . 'list-windows -a'))]
  try
    let $TMUX = trim(system(l:tmux . "display -p '#{socket_path},#{pid},0'"))
    let g:dispatch_no_tmux_start = 0
    edit tests/test_sample.py
    call cursor(7, 1)
    call s:type(s:lead . 'tf')
    call assert_true(s:wait('!empty(filter(term_list(), "term_getstatus(v:val) =~# ''running''"))',
          \ 'a Vim terminal', 60), 'in a Vim terminal')
    if a:0
      " vim-dispatch goes back to a session still running instead of repeating it
      call s:end_terminals()
      call s:type(a:1)
      call assert_true(s:wait('!empty(filter(term_list(), "term_getstatus(v:val) =~# ''running''"))',
            \ 'a Vim terminal again', 60), 'repeated in a Vim terminal')
    endif
    call assert_equal(l:windows, len(systemlist(l:tmux . 'list-windows -a')), 'not in a tmux window')
  finally
    let g:dispatch_no_tmux_start = l:saved
    unlet $TMUX
    call system(l:tmux . 'kill-server')
    call s:end_terminals()
  endtry
endfunction

function! s:suite.trace_in_a_terminal_whatever_the_start_strategy() abort
  call s:trace_in_tmux()
endfunction

function! s:suite.repeating_a_trace_in_a_terminal_whatever_the_start_strategy() abort
  call s:trace_in_tmux('_rs')
endfunction

" Only the project's test files have the keys
function! s:suite.keys_only_in_test_files() abort
  edit tests/test_sample.py
  call assert_notequal('', maparg(s:lead . 'rm', 'n'))
  call assert_notequal('', maparg(s:lead . 'df', 'n'))
  edit src/pkg/code.py
  call assert_equal(['', '', ''], [maparg(s:lead . 'rm', 'n'), maparg(s:lead . 'tf', 'n'), maparg(s:lead . 'df', 'n')])
endfunction

""" Commands

function! s:suite.run_pytest_with_arguments() abort
  call s:needs_pytest()
  edit tests/test_sample.py
  call assert_equal(['tests/test_other.py::test_other'],
        \ s:dispatched(':RunPytest tests/test_other.py::test_other' . "\<CR>")[1])
  call assert_equal(['tests/test_sample.py::test_one'], s:dispatched(':RunPytest! -k test_one' . "\<CR>")[1],
        \ '! in the background')
endfunction

" A plain :Dispatch in a Python buffer runs pytest too (b:dispatch)
function! s:suite.dispatch_runs_pytest() abort
  call s:needs_pytest()
  edit tests/test_other.py
  let [l:cmd, l:ran] = s:dispatched(":Dispatch\<CR>")
  call assert_match('chkpyt\.sh', l:cmd)
  call assert_equal(8, len(l:ran), 'every test')
endfunction

function! s:suite.trace_pytest_with_arguments() abort
  call s:needs_pytest()
  edit tests/test_sample.py
  call s:type(":TracePytest -k test_one\<CR>")
  call assert_match('chkpyt\.sh --no-default-addopts -k test_one --trace', s:traced())
endfunction

function! s:suite.trace_needs_project_detect() abort
  edit tests/test_sample.py
  let l:rtp = &runtimepath
  try
    execute 'set runtimepath-=' . fnameescape(g:suite.deps . '/project-detect')
    call assert_match("^\npytest.vim: A --trace .*session needs project-detect, which is not installed$",
          \ execute('TracePytest'))
    call assert_equal("\npytest.vim: :PytestTests needs project-detect, which is not installed",
          \ execute('PytestTests'))
  finally
    let &runtimepath = l:rtp
  endtry
  call assert_equal([], term_list(), 'no terminal')
endfunction

""" The test lists

function! s:nodeids(items) abort
  return sort(map(copy(a:items), 'v:val.user_data.nodeid'))
endfunction

" A run's results are the quickfix list now: back to the Tests list, as :colder
" does
function! s:back_to_tests() abort
  while getqflist({'title': 1}).title !=# 'Tests' && getqflist({'nr': 0}).nr > 1
    silent colder
  endwhile
  copen
endfunction

function! s:on(nodeid) abort
  call cursor(index(map(getqflist(), 'v:val.user_data.nodeid'), a:nodeid) + 1, 1)
endfunction

function! s:suite.tests_list() abort
  call setqflist([], ' ', {'title': 'grep', 'items': [{'text': 'made before'}]})
  call assert_equal("\nTests: 7", execute('PytestTests'))
  call assert_equal(['quickfix', 'Tests'], [&buftype, getqflist({'title': 1}).title])
  " Only test files, not src/; what pytest collects, async methods too
  call assert_equal(['tests/test_async.py::TestAsync::test_c', 'tests/test_other.py::test_fails',
        \ 'tests/test_other.py::test_other', 'tests/test_sample.py::TestThing::test_a',
        \ 'tests/test_sample.py::TestThing::test_b', 'tests/test_sample.py::test_one',
        \ 'tests/test_sample.py::test_two'], s:nodeids(getqflist()))
  " Again: the same list, made current, not a new one
  call setqflist([], ' ', {'title': 'grep'})
  PytestTests
  call assert_equal([3, 'Tests'], [getqflist({'nr': '$'}).nr, getqflist({'title': 1}).title])
endfunction

" Not in a git repository: the test files are found all the same
function! s:suite.tests_list_without_git() abort
  call rename(s:root . '/.git', s:root . '/.git-away')
  try
    PytestTests
  finally
    call rename(s:root . '/.git-away', s:root . '/.git')
  endtry
  call assert_equal(7, len(getqflist()))
endfunction

" An empty outline: the keys say there's no entry
function! s:suite.keys_on_an_empty_list() abort
  edit src/pkg/__init__.py
  PytestOutline
  call assert_equal([0, 1], [len(getloclist(0)), getwininfo(win_getid())[0].loclist])
  call assert_equal("\nno entry here", s:type(s:lead . 'rf'))
endfunction

function! s:suite.tests_list_keys() abort
  call s:needs_pytest()
  PytestTests
  call s:on('tests/test_sample.py::TestThing::test_a')
  call assert_equal(['tests/test_sample.py::TestThing::test_a[1]', 'tests/test_sample.py::TestThing::test_a[2]'],
        \ s:dispatched(s:lead . 'rm')[1])
  call s:back_to_tests()
  call s:on('tests/test_sample.py::TestThing::test_a')
  call assert_equal(3, len(s:dispatched(s:lead . 'rc')[1]), 'its class')
  call s:back_to_tests()
  call s:on('tests/test_other.py::test_other')
  call assert_equal(['tests/test_other.py::test_other'], s:dispatched(s:lead . 'rf')[1])
  call s:back_to_tests()
  call s:on('tests/test_other.py::test_other')
  call assert_equal(['tests/test_other.py::test_fails', 'tests/test_other.py::test_other'],
        \ s:dispatched(s:lead . 'rt')[1], 'its file')
  call s:back_to_tests()
  call s:on('tests/test_sample.py::TestThing::test_b')
  call assert_equal("\nCould not determine test path for scope: function", s:type(s:lead . 'rf'),
        \ 'a method has no function scope, as in the file')
  call s:type(s:lead . 'tm')
  call assert_match('TestThing::test_b --trace', s:traced())
endfunction

function! s:suite.tests_list_debug_keys() abort
  call s:needs_pytest()
  PytestTests
  call s:on('tests/test_other.py::test_fails')
  call s:type(s:lead . 'df')
  call assert_match('tests/test_other\.py::test_fails --pdb', s:traced())
endfunction

function! s:suite.outline() abort
  edit tests/test_sample.py
  let l:win = win_getid()
  call assert_equal("\nTests: 4 in tests/test_sample.py", execute('PytestOutline'))
  call assert_equal([1, 'Tests: tests/test_sample.py'],
        \ [getwininfo(win_getid())[0].loclist, getloclist(0, {'title': 1}).title])
  call assert_equal(['test_one', 'TestThing::test_a', 'TestThing::test_b', 'test_two'],
        \ map(getloclist(0), 'v:val.text'))
  " Again: replaced, not stacked
  call win_gotoid(l:win)
  PytestOutline
  call assert_equal(1, getloclist(0, {'nr': '$'}).nr)
endfunction

function! s:suite.outline_keys() abort
  call s:needs_pytest()
  edit tests/test_sample.py
  PytestOutline
  call cursor(2, 1)
  call assert_equal(3, len(s:dispatched(s:lead . 'rc')[1]))
endfunction

" A list's entry finds its test where it is now; gone, it says so
function! s:suite.list_entry_moved_or_gone() abort
  call s:needs_pytest()
  edit tests/test_other.py
  PytestTests
  " As a checkout leaves it: the file changed on disk, read again
  call writefile(['def test_added():', '    pass', '', ''] + s:other, s:root . '/tests/test_other.py')
  call win_gotoid(bufwinid('tests/test_other.py'))
  edit!
  call s:back_to_tests()
  call s:on('tests/test_other.py::test_other')
  call assert_equal(['tests/test_other.py::test_other'], s:dispatched(s:lead . 'rf')[1])
  " And gone
  call writefile(['def test_added():', '    pass'], s:root . '/tests/test_other.py')
  call win_gotoid(bufwinid('tests/test_other.py'))
  edit!
  call s:back_to_tests()
  call s:on('tests/test_other.py::test_other')
  let l:before = dispatch#request()
  call assert_equal("\ntests/test_other.py::test_other is gone: :PytestTests (or :PytestOutline) again",
        \ s:type(s:lead . 'rf'))
  call assert_equal(l:before, dispatch#request(), 'nothing dispatched')
endfunction

function! s:suite.unsaved_edits_count() abort
  edit tests/test_other.py
  call append(line('$'), ['', 'def test_new():', '    pass'])
  PytestTests
  call assert_notequal(-1, index(s:nodeids(getqflist()), 'tests/test_other.py::test_new'))
endfunction

" In another list window the keys are nothing of pytest.vim's
function! s:suite.keys_only_in_test_lists() abort
  " Another plugin's list, with a context of its own
  call setqflist([], ' ', {'title': 'grep', 'context': {'other': 1},
        \ 'items': [{'filename': 'tests/test_sample.py', 'lnum': 14, 'text': 'x'}]})
  copen
  let l:before = dispatch#request()
  let v:errmsg = ''
  silent! let l:out = execute('call g:suite.feed(' . string(s:lead . 'rm') . ')')
  call assert_notmatch('gone\|Could not\|no entry', l:out . v:errmsg, 'nothing of pytest.vim''s')
  call assert_equal(l:before, dispatch#request())
  call assert_equal([], s:ran())
endfunction

" qf-tools: dd prunes the list to the tests you're working on, :QfSave keeps
" it across rebuilds, :QfLoad brings it back, and the keys work on it
function! s:suite.prune_save_and_load_the_tests_list() abort
  call s:needs_pytest()
  PytestTests
  call s:on('tests/test_other.py::test_fails')
  call s:type('dd')
  call s:on('tests/test_async.py::TestAsync::test_c')
  call s:type('dd')
  call assert_equal(5, len(getqflist()))
  silent QfSave mine
  PytestTests
  call assert_equal(7, len(getqflist()), 'rebuilt')
  silent QfLoad mine
  call assert_equal(5, len(getqflist()))
  call s:on('tests/test_sample.py::test_one')
  call assert_equal(['tests/test_sample.py::test_one'], s:dispatched(s:lead . 'rf')[1])
endfunction

""" :ParsePytestFailures

" Real pytest output, as pasted from a run
function! s:suite.parse_failures() abort
  call s:needs_pytest()
  call writefile([
        \ 'import pytest',
        \ 'class TestA:',
        \ '    def test_x(self): assert 0',
        \ '    def test_y(self): assert 0',
        \ 'class TestB:',
        \ '    def test_z(self): assert 0',
        \ '@pytest.mark.parametrize("n", [1, 2])',
        \ 'def test_p(n): assert 0',
        \ ], s:root . '/tests/test_fail.py')
  try
    let l:out = systemlist('chkpyt.sh tests/test_fail.py tests/test_other.py')
  finally
    call delete(s:root . '/tests/test_fail.py')
  endtry
  enew
  call setline(1, l:out)
  ParsePytestFailures
  call assert_equal(['tests/test_other.py::test_fails', '',
        \ 'tests/test_fail.py::TestA::test_x', 'tests/test_fail.py::TestA::test_y',
        \ 'tests/test_fail.py::TestB::test_z', 'tests/test_fail.py::test_p'], getline(1, '$'),
        \ 'one line per test, a block per file, smallest first')
  %delete _
  call setline(1, l:out)
  ParsePytestFailures!
  call assert_equal(['tests/test_fail.py::TestB::test_z', '', 'tests/test_fail.py::test_p', '',
        \ 'tests/test_other.py::test_fails', '',
        \ 'tests/test_fail.py::TestA::test_x', 'tests/test_fail.py::TestA::test_y'], getline(1, '$'),
        \ '!: a block per class')
endfunction

" More lines out than in: blocks get blank lines between them
function! s:suite.parse_failures_grows_the_range() abort
  enew
  call setline(1, ['before', 'FAILED tests/b.py::test_1 - x', 'FAILED tests/a.py::test_2 - y', 'after'])
  2,3ParsePytestFailures
  call assert_equal(['before', 'tests/a.py::test_2', '', 'tests/b.py::test_1', 'after'], getline(1, '$'))
endfunction

" Coverage contexts, and a range
function! s:suite.parse_coverage_contexts_in_a_range() abort
  enew
  call setline(1, ['keep me', 'tests/a.py::test_b[x-1]|run', '', 'tests/a.py::test_b[x-2]|setup',
        \ 'tests/a.py::test_a|teardown', 'keep me too'])
  2,5ParsePytestFailures
  call assert_equal(['keep me', 'tests/a.py::test_a', 'tests/a.py::test_b', 'keep me too'], getline(1, '$'))
endfunction
