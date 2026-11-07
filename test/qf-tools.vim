" qf-tools: what the dotfiles use of it. Ported from its test/run.vim.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('qf-tools')

let s:tmp = resolve(tempname())
let s:repo = s:tmp . '/repo'
let s:place = g:suite.deps . '/vim-place'
let s:out = []

function! s:reset() abort
  silent! only!
  silent! %bwipeout!
  call setqflist([], 'f')
  call delete(s:tmp, 'rf')
  call mkdir(s:repo . '/tests', 'p')
  call system('git -C ' . shellescape(s:repo) . ' init -q')
  call writefile(['one', 'two', 'three'], s:repo . '/tests/a.py')
  call writefile(['x'], s:repo . '/b.py')
  execute 'cd' fnameescape(s:repo)
endfunction

" A list as a plugin makes one: its title, a context of its own, and data
" on each entry
function! s:list() abort
  call setqflist([], ' ', {'title': 'Tests', 'context': {'pytest': 'tests'}, 'items': [
        \ {'filename': s:repo . '/tests/a.py', 'lnum': 2, 'text': 'test_two',
        \  'user_data': {'nodeid': 'tests/a.py::test_two'}},
        \ {'filename': s:repo . '/b.py', 'lnum': 1, 'text': 'b'},
        \ {'text': 'a line of output, no file'}]})
endfunction

" assert_fails() makes vim -Es exit non-zero even when it passes
function! s:message(cmd) abort
  return execute(a:cmd)
endfunction

function! s:suite.save_and_load_a_name() abort
  call s:list()
  silent QfSave wip
  call assert_true(filereadable(s:repo . '/.git/qf-tools/wip.json'))
  " Paths in a named save are the work tree's
  call assert_match('"filename":"tests/a.py"', readfile(s:repo . '/.git/qf-tools/wip.json')[0])
  call setqflist([], ' ', {'title': 'other', 'items': []})
  silent QfLoad wip
  let l:list = getqflist({'title': 1, 'context': 0, 'items': 1})
  call assert_equal('Tests', l:list.title)
  call assert_equal({'pytest': 'tests'}, l:list.context)
  call assert_equal(3, len(l:list.items))
  call assert_equal(s:repo . '/tests/a.py', fnamemodify(bufname(l:list.items[0].bufnr), ':p'))
  call assert_equal(2, l:list.items[0].lnum)
  call assert_equal({'nodeid': 'tests/a.py::test_two'}, l:list.items[0].user_data)
  call assert_equal(0, l:list.items[2].bufnr)
  call assert_equal('a line of output, no file', l:list.items[2].text)
  " A new list: the one before it is still there
  call assert_equal(3, getqflist({'nr': '$'}).nr)
  silent colder
  call assert_equal('other', getqflist({'title': 1}).title)
endfunction

function! s:suite.a_name_is_saved_again() abort
  call s:list()
  silent QfSave wip
  call setqflist([], ' ', {'title': 'Pruned', 'items': [{'filename': s:repo . '/b.py', 'lnum': 1}]})
  silent QfSave wip
  silent QfLoad wip
  call assert_equal('Pruned', getqflist({'title': 1}).title)
endfunction

function! s:suite.names_complete() abort
  call s:list()
  silent QfSave wip
  silent QfSave work
  call assert_equal(['wip', 'work'], qf_tools#save#complete('w', '', 0))
  call assert_equal(['wip'], qf_tools#save#complete('wi', '', 0))
endfunction

function! s:suite.save_and_load_a_path() abort
  call s:list()
  let l:file = s:tmp . '/kept.json'
  execute 'silent QfSave' fnameescape(l:file)
  " Absolute paths in a save to a path
  call assert_match('"filename":"' . escape(s:repo, '/') . '/tests/a.py"', readfile(l:file)[0])
  execute 'cd' fnameescape(s:tmp)
  execute 'silent QfLoad' fnameescape(l:file)
  let l:items = getqflist()
  call assert_equal(s:repo . '/tests/a.py', fnamemodify(bufname(l:items[0].bufnr), ':p'))
endfunction

function! s:suite.a_path_is_kept_without_bang() abort
  call s:list()
  let l:file = s:tmp . '/kept.json'
  call writefile(['mine'], l:file)
  call assert_match('exists (add ! to overwrite)', s:message('QfSave ' . fnameescape(l:file)))
  call assert_equal(['mine'], readfile(l:file))
  execute 'silent QfSave!' fnameescape(l:file)
  call assert_match('qf_tools', readfile(l:file)[0])
endfunction

function! s:suite.context_not_json_is_left_out() abort
  call setqflist([], ' ', {'title': 'F', 'context': {'f': function('tr')}, 'items': [
        \ {'filename': s:repo . '/b.py', 'lnum': 1}]})
  call assert_match('1 context(s) not JSON, left out', s:message('QfSave wip'))
  silent QfLoad wip
  call assert_equal('F', getqflist({'title': 1}).title)
  call assert_equal(1, len(getqflist()))
endfunction

function! s:suite.load_errors() abort
  call assert_match('no saved list nope', s:message('QfLoad nope'))
  call writefile(['{}'], s:tmp . '/other.json')
  call assert_match('is not a list :QfSave wrote', s:message('QfLoad ' . fnameescape(s:tmp . '/other.json')))
endfunction

function! s:suite.a_name_needs_vim_place() abort
  let l:rtp = &runtimepath
  execute 'set runtimepath-=' . fnameescape(s:place)
  try
    call assert_match('needs vim-place', s:message('QfSave wip'))
    call assert_match('needs vim-place', s:message('QfLoad wip'))
  finally
    let &runtimepath = l:rtp
  endtry
endfunction

let s:failed = 0

function! s:suite.before_each() abort
  call s:reset()
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction
