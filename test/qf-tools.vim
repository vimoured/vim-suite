" qf-tools: its keys in quickfix and location-list windows (dd, 3dd, visual
" d, u) and the User QfToolsChanged event vim-prompts listens to, the toggle,
" :QfSave / :QfLoad (vim-place's save contract), and its README,
" through its commands and keys.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('qf-tools')

let s:tmp = resolve(tempname())
let s:repo = s:tmp . '/repo'
let s:place = g:suite.deps . '/vim-place'
let s:changed = []
augroup qf_tools_spec
  autocmd!
  autocmd User QfToolsChanged call add(s:changed, [&buftype, len(getwininfo(win_getid())[0].loclist
        \ ? getloclist(0) : getqflist())])
augroup END

function! s:reset() abort
  let s:changed = []
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

" An Ex command; returns its messages, or the error it raised
function! s:message(cmd) abort
  try
    return execute(a:cmd)
  catch
    return v:exception
  endtry
endfunction

" Keys as typed
function! s:type(keys) abort
  return execute('call g:suite.feed(' . string(a:keys) . ')')
endfunction

" Five entries, line n's text 'n'
function! s:five(...) abort
  let l:items = map(range(1, 5), '{"filename": "b.py", "lnum": 1, "text": string(v:val)}')
  if a:0
    call setloclist(0, [], ' ', {'title': 'Five', 'items': l:items})
  else
    call setqflist([], ' ', {'title': 'Five', 'items': l:items})
  endif
endfunction

function! s:texts() abort
  return map(getwininfo(win_getid())[0].loclist ? getloclist(0) : getqflist(), 'v:val.text')
endfunction

""" In a list window

function! s:suite.dd_removes_in_place() abort
  call setqflist([], ' ', {'title': 'Before', 'items': [{'text': 'x'}]})
  call s:five()
  copen
  call cursor(2, 1)
  call s:type('dd')
  call assert_equal(['1', '3', '4', '5'], s:texts())
  call assert_equal([2, 'Five'], [line('.'), getqflist({'title': 1}).title])
  call assert_equal(2, getqflist({'nr': '$'}).nr, 'no new list in the history')
  call s:type('3dd')
  call assert_equal(['1'], s:texts(), '3dd: three')
  call assert_equal(1, line('.'))
  call s:type('dd')
  call s:type('dd')
  call assert_equal([], s:texts(), 'dd on an empty list: nothing')
  call s:five()
  call cursor(4, 1)
  call s:type('3dd')
  call assert_equal(['1', '2', '3'], s:texts(), '3dd on the last two: those')
endfunction

function! s:suite.visual_d_removes_the_selection() abort
  call s:five()
  copen
  call cursor(2, 1)
  call s:type('Vjd')
  call assert_equal(['1', '4', '5'], s:texts())
endfunction

function! s:suite.u_puts_back_then_goes_to_the_older_list() abort
  call setqflist([], ' ', {'title': 'Before', 'items': [{'text': 'x'}]})
  call s:five()
  copen
  call cursor(2, 1)
  call s:type('2dd')
  call cursor(1, 1)
  call s:type('Vd')
  call s:type('u')
  call assert_equal(['1', '4', '5'], s:texts(), 'the last removal first')
  call assert_equal(1, line('.'))
  call s:type('u')
  call assert_equal(['1', '2', '3', '4', '5'], s:texts(), 'both of 2dd')
  call assert_equal(2, line('.'))
  call s:type('u')
  call assert_equal('Before', getqflist({'title': 1}).title, 'nothing to put back: :colder')
endfunction

" What u puts back is that list's: another list in the window starts afresh
function! s:suite.u_after_the_list_changed() abort
  call s:five()
  copen
  call s:type('dd')
  call setqflist([], ' ', {'title': 'Other', 'items': [{'text': 'a'}, {'text': 'b'}]})
  call s:type('u')
  call assert_equal('Five', getqflist({'title': 1}).title, ':colder, not the other list''s undo')
endfunction

function! s:suite.in_a_location_list() abort
  call setloclist(0, [], ' ', {'title': 'Before', 'items': [{'text': 'x'}]})
  call s:five(1)
  lopen
  call s:type('dd')
  call assert_equal(['2', '3', '4', '5'], s:texts())
  call assert_equal([], getqflist(), 'the quickfix list untouched')
  call s:type('u')
  call s:type('u')
  call assert_equal('Before', getloclist(0, {'title': 1}).title, ':lolder')
endfunction

function! s:suite.changed_event_with_the_list_window_current() abort
  call s:five()
  copen
  call s:type('dd')
  call s:type('Vjd')
  call s:type('u')
  call assert_equal([['quickfix', 4], ['quickfix', 2], ['quickfix', 4]], s:changed)
endfunction

function! s:suite.dd_elsewhere_is_vims() abort
  call s:five()
  edit b.py
  call setline(1, ['x', 'y'])
  call s:type('dd')
  call assert_equal(['y'], getline(1, '$'))
  call assert_equal(5, len(getqflist()))
endfunction

""" The quickfix window

function! s:suite.toggle() abort
  call s:five()
  call s:type("\<Plug>(qf-tools-toggle)")
  call assert_equal(['quickfix', 2], [&buftype, winnr('$')])
  wincmd p
  call s:type("\<Plug>(qf-tools-toggle)")
  call assert_equal(1, winnr('$'))
  QfToggle
  call assert_equal(2, winnr('$'))
endfunction

" A location list window isn't the quickfix window
function! s:suite.toggle_with_a_location_list_open() abort
  call s:five()
  call s:five(1)
  lopen
  QfToggle
  call assert_equal(['quickfix', 3], [&buftype, winnr('$')], 'the quickfix window opens')
  call assert_equal(0, getwininfo(win_getid())[0].loclist)
endfunction

""" :QfSave / :QfLoad

function! s:suite.save_and_load_a_name() abort
  call s:list()
  silent QfSave wip
  call assert_true(filereadable(s:repo . '/.git/qf-tools/wip.json'))
  " Paths in a named save are the work tree's
  call assert_match('"filename":"tests/a.py"', readfile(s:repo . '/.git/qf-tools/wip.json')[0])
  call setqflist([], ' ', {'title': 'other', 'items': []})
  " From a subdirectory: the paths are still the work tree's
  cd tests
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

function! s:suite.save_and_load_say_how_many() abort
  call s:list()
  let l:wip = fnamemodify(s:repo . '/.git/qf-tools/wip.json', ':~')
  call assert_equal("\nQfSave: wrote " . l:wip . ' (3 entries)', s:message('QfSave wip'))
  call assert_equal("\nQfLoad: read " . l:wip . ' (3 entries)', s:message('QfLoad wip'))
  call assert_equal('quickfix', &buftype, 'the list open')
  execute 'cd' fnameescape(s:tmp)
  call assert_equal("\nQfSave: wrote " . fnamemodify(s:tmp . '/k.json', ':~') . ' (3 entries)',
        \ s:message('QfSave ./k.json'))
  call assert_equal("\nQfSave: wrote " . fnamemodify(s:tmp . '/.k.json', ':~') . ' (3 entries)',
        \ s:message('QfSave .k.json'), 'starting with .: a path')
endfunction

" A plugin's buffer (fugitive://) is kept as named, and a file outside the
" work tree by its full path
function! s:suite.save_keeps_other_names() abort
  call setqflist([], ' ', {'title': 'Mixed', 'items': [
        \ {'filename': 'fugitive://' . s:repo . '/.git//0/b.py', 'lnum': 1},
        \ {'filename': s:tmp . '/elsewhere.txt', 'lnum': 1}]})
  silent QfSave wip
  call setqflist([], ' ', {'title': 'other', 'items': []})
  silent QfLoad wip
  call assert_equal(['fugitive://' . s:repo . '/.git//0/b.py', s:tmp . '/elsewhere.txt'],
        \ map(getqflist(), 'bufname(v:val.bufnr)'))
endfunction

" With no name or path: a new file, then the same one again; and the file a
" list was loaded from
function! s:suite.save_with_no_argument() abort
  call s:list()
  silent QfSave
  let l:saves = glob(s:repo . '/.git/qf-tools/*.json', 1, 1)
  call assert_equal(1, len(l:saves))
  call assert_match('/\d\{8}-\d\{6}\.json$', l:saves[0])
  call assert_match('"filename":"tests/a.py"', readfile(l:saves[0])[0], 'paths the work tree''s')
  copen
  call s:type('dd')
  silent QfSave
  call assert_equal(l:saves, glob(s:repo . '/.git/qf-tools/*.json', 1, 1), 'the same file')
  call assert_equal(2, len(json_decode(readfile(l:saves[0])[0]).items))
  " Another list: a file of its own, even in the same second
  call setqflist([], ' ', {'title': 'Other', 'items': [{'text': 'o'}]})
  silent QfSave
  call assert_equal(2, len(glob(s:repo . '/.git/qf-tools/*.json', 1, 1)))
  " Loaded, a list saves back to its file
  let l:file = s:tmp . '/kept.json'
  execute 'silent QfSave' fnameescape(l:file)
  execute 'silent QfLoad' fnameescape(l:file)
  copen
  call s:type('dd')
  silent QfSave
  call assert_equal(0, len(json_decode(readfile(l:file)[0]).items))
endfunction

function! s:suite.save_to_a_directory() abort
  call s:list()
  execute 'silent QfSave' fnameescape(s:tmp . '/lists/')
  call mkdir(s:tmp . '/existing')
  execute 'silent QfSave' fnameescape(s:tmp . '/existing')
  call assert_match('/lists/\d\{8}-\d\{6}\.json$', get(glob(s:tmp . '/lists/*', 1, 1), 0, ''))
  call assert_equal(1, len(glob(s:tmp . '/existing/*.json', 1, 1)))
  call assert_match('"filename":"' . escape(s:repo, '/') . '/tests/a.py"',
        \ readfile(glob(s:tmp . '/existing/*.json', 1, 1)[0])[0], 'absolute paths')
endfunction

function! s:suite.load_with_no_argument_the_newest() abort
  call s:list()
  silent QfSave older
  call setqflist([], ' ', {'title': 'Newer', 'items': [{'text': 'n'}]})
  sleep 1100m
  silent QfSave newer
  call setqflist([], ' ', {'title': 'other', 'items': []})
  call assert_match('^\nQfLoad: read .*newer\.json (1 entries)$', s:message('QfLoad'))
  call assert_equal('Newer', getqflist({'title': 1}).title)
endfunction

" A path saved to before needs no !; a failed write loses nothing
function! s:suite.save_again_to_a_path_and_failing() abort
  call s:list()
  let l:file = s:tmp . '/kept.json'
  execute 'silent QfSave' fnameescape(l:file)
  call assert_match('^\nQfSave: wrote ', s:message('QfSave ' . fnameescape(l:file)), 'its own file')
  call mkdir(s:tmp . '/locked')
  call setfperm(s:tmp . '/locked', 'r-xr-xr-x')
  call assert_match('E482: ', s:message('QfSave ' . fnameescape(s:tmp . '/locked/x.json')))
  call setfperm(s:tmp . '/locked', 'rwxr-xr-x')
  call assert_equal(['Tests', 3], [getqflist({'title': 1}).title, len(getqflist())], 'the list as it was')
  silent QfSave
  call assert_equal([], glob(s:tmp . '/locked/*', 1, 1), 'not taken for its file')
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
  silent QfSave work
  sleep 1100m
  silent QfSave wip
  call assert_equal(['wip', 'work'], getcompletion('QfLoad w', 'cmdline'), 'newest first')
  call system('touch -t 202001010000 ' . shellescape(s:repo . '/.git/qf-tools/wip.json'))
  call assert_equal(['work', 'wip'], getcompletion('QfLoad w', 'cmdline'))
  call assert_equal(['wip'], getcompletion('QfSave wi', 'cmdline'))
  call assert_equal(['./b.py'], getcompletion('QfLoad ./b', 'cmdline'), 'a path: files')
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
  call assert_equal('Vim(echoerr):QfSave: ' . fnamemodify(l:file, ':~') . ' exists (add ! to overwrite)',
        \ s:message('QfSave ' . fnameescape(l:file)))
  call assert_equal(['mine'], readfile(l:file))
  execute 'silent QfSave!' fnameescape(l:file)
  call assert_match('qf_tools', readfile(l:file)[0])
endfunction

function! s:suite.context_not_json_is_left_out() abort
  call setqflist([], ' ', {'title': 'F', 'context': {'f': function('tr')}, 'items': [
        \ {'filename': s:repo . '/b.py', 'lnum': 1}]})
  call assert_match(' (1 entries, 1 context(s) not JSON, left out)$', s:message('QfSave wip'))
  silent QfLoad wip
  call assert_equal('F', getqflist({'title': 1}).title)
  call assert_equal(1, len(getqflist()))
endfunction

function! s:suite.entry_data_not_json_is_left_out() abort
  call setqflist([], ' ', {'title': 'F', 'items': [
        \ {'filename': s:repo . '/b.py', 'lnum': 1, 'user_data': function('tr')},
        \ {'filename': s:repo . '/b.py', 'lnum': 1, 'user_data': {'kept': 1}}]})
  call assert_match(' (2 entries, 1 context(s) not JSON, left out)$', s:message('QfSave wip'))
  silent QfLoad wip
  call assert_equal(['', {'kept': 1}], map(getqflist(), 'v:val.user_data'))
endfunction

function! s:suite.load_errors() abort
  call assert_equal('Vim(echoerr):QfLoad: no saved list nope', s:message('QfLoad nope'))
  call assert_equal('Vim(echoerr):QfLoad: no ' . fnamemodify(s:tmp . '/none.json', ':~'),
        \ s:message('QfLoad ' . fnameescape(s:tmp . '/none.json')))
  call assert_equal('Vim(echoerr):QfLoad: nothing saved in ' . fnamemodify(s:repo . '/.git/qf-tools', ':~'),
        \ s:message('QfLoad'))
  for l:text in ['{}', 'not json']
    call writefile([l:text], s:tmp . '/other.json')
    call assert_equal('Vim(echoerr):QfLoad: ' . fnamemodify(s:tmp . '/other.json', ':~') . ' is not a list :QfSave wrote',
          \ s:message('QfLoad ' . fnameescape(s:tmp . '/other.json')), l:text)
  endfor
  call assert_equal([], getqflist(), 'nothing loaded')
endfunction

function! s:suite.a_name_needs_vim_place() abort
  let l:rtp = &runtimepath
  execute 'set runtimepath-=' . fnameescape(s:place)
  try
    for [l:cmd, l:what] in [['QfSave wip', ':QfSave of a name'], ['QfLoad wip', ':QfLoad of a name'],
          \ ['QfSave', ':QfSave without a path'], ['QfLoad', ':QfLoad without a path']]
      call assert_equal("\nqf-tools: " . l:what . ' needs vim-place (with vim-fugitive), which is not installed',
            \ s:message(l:cmd), l:cmd)
    endfor
    call assert_match('^\nQfSave: wrote ', s:message('QfSave ./k.json'), 'a path needs no vim-place')
    call assert_equal(['./b.py'], getcompletion('QfLoad ./b', 'cmdline'), 'paths still complete')
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
