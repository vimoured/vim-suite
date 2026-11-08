" vim-lists: roumail_lists#open() and the functions plugins call from their
" lists' keys (gh-extras, fugitive-extras, vim-prompts), the keys every list
" has, and its README.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('vim-lists')

let s:root = g:suite.deps . '/vim-lists'

function! s:reset() abort
  silent! only
  silent! %bwipeout!
  let g:words = ['apple', 'banana', 'cherry']
  let g:picked = ''
endfunction

" A list of words, under a 'fruit' heading row when grouped
function! s:open(...) abort
  let l:grouped = a:0 && a:1
  call roumail_lists#open('test://words', {
        \ 'fetch': {-> g:words is v:null ? v:null : copy(g:words)},
        \ 'heading': {items -> ['Words (' . len(items) . ')']},
        \ 'rows': {items -> (l:grouped ? [{'lines': ['fruit'], 'group': 'fruit'}] : [])
        \   + map(copy(items), {_, w -> {'lines': [w], 'item': {'w': w}}})},
        \ 'id': {item -> item.w}, 'match': {item -> item.w},
        \ 'delete': {item -> filter(g:words, 'v:val !=# item.w')},
        \ 'keys': [{'key': 'x', 'hint': 'pick',
        \   'call': {-> execute('let g:picked = roumail_lists#item().w')}},
        \          {'key': ':Cmd'}]}, {'mine': 1})
endfunction

function! s:suite.open() abort
  call s:open()
  call assert_equal('test://words', bufname())
  call assert_equal(1, b:mine, 'vars are buffer variables')
  call assert_equal(['Words (3)  x pick  :Cmd  dd remove  / filter  r refresh  q close',
        \ 'apple', 'banana', 'cherry'], getline(1, '$'))
  call assert_equal(2, line('.'), 'on the first item')
  call assert_equal('nofile', &buftype)
  call assert_equal(4, winheight(0))
  call assert_equal(2, winnr('$'), 'a window of its own')
  call assert_equal(winnr('$'), winnr(), 'at the bottom')
endfunction

function! s:suite.items_and_keys() abort
  call s:open()
  call cursor(1, 1)
  call assert_equal({}, roumail_lists#item(), 'the heading has no item')
  call assert_equal({}, roumail_lists#row())
  call cursor(3, 1)
  normal x
  call assert_equal('banana', g:picked)
  call assert_equal('', maparg(':Cmd', 'n'), 'a hint only maps nothing')
endfunction

" A plugin's key asking outside a list: nothing
function! s:suite.outside_a_list() abort
  edit plain.txt
  call assert_equal([{}, {}], [roumail_lists#row(), roumail_lists#item()])
endfunction

" As tall as the list, up to 15 lines
function! s:suite.height() abort
  let g:words = map(range(30), '"w" . v:val')
  call s:open()
  call assert_equal(15, winheight(0))
endfunction

function! s:suite.colon_q_closes_only_the_list() abort
  call s:open()
  quit
  call assert_equal(1, winnr('$'))
  call assert_false(bufexists('test://words'))
endfunction

" Fuzzy, as fzf: each word's letters in order, not necessarily together; all
" the words
function! s:suite.filter_fuzzily() abort
  let g:words = ['banana', 'bandana', 'cabin']
  call s:open()
  call feedkeys("/bnn\<CR>", 'x')
  call assert_equal(['banana', 'bandana'], getline(2, '$'))
  call feedkeys("/\<C-u>bn d\<CR>", 'x')
  call assert_equal(['bandana'], getline(2, '$'))
  call assert_match('^Words (3), 1 matching ''bn d''  ', getline(1))
  " <C-u>, then <CR>: unfiltered
  call feedkeys("/\<C-u>\<CR>", 'x')
  call assert_equal(['Words (3)', 4], [matchstr(getline(1), '^Words (3)'), line('$')])
  call assert_notmatch('matching', getline(1))
endfunction

function! s:suite.group_rows() abort
  call s:open(1)
  call assert_equal(3, line('.'), 'on the first item, past the group row')
  call cursor(2, 1)
  call assert_equal({}, roumail_lists#item())
  call assert_equal('fruit', roumail_lists#row().group)
  " No items: the line after the heading
  let g:words = []
  normal q
  call s:open(1)
  call assert_equal(2, line('.'))
endfunction

function! s:suite.refresh_keeps_item() abort
  call s:open()
  call cursor(3, 1)
  let g:words = ['zebra', 'apple', 'banana']
  normal r
  call assert_equal('banana', getline('.'))
  " Gone: the same line
  let g:words = ['zebra', 'apple']
  normal r
  call assert_equal(3, line('.'))
  " A fetch failing leaves the list as it was
  let g:words = v:null
  normal r
  call assert_equal(['zebra', 'apple'], getline(2, '$'))
endfunction

function! s:suite.set_and_draw() abort
  call s:open()
  call roumail_lists#set(['kiwi'])
  call assert_equal(['Words (1)  x pick  :Cmd  dd remove  / filter  r refresh  q close', 'kiwi'],
        \ getline(1, '$'))
  call assert_equal(2, winheight(0))
endfunction

function! s:suite.filter() abort
  call s:open()
  call feedkeys("/an\<CR>", 'x')
  call assert_equal(['Words (3), 1 matching ''an''  x pick  :Cmd  dd remove  / filter  r refresh  q close',
        \ 'banana'], getline(1, '$'))
  " r keeps it
  normal r
  call assert_equal(2, line('$'))
  " <Esc> goes back to the filter it had
  call feedkeys("/\<C-u>zz\<Esc>", 'x')
  call assert_equal(2, line('$'))
  call feedkeys("/\<BS>\<BS>\<CR>", 'x')
  call assert_equal(4, line('$'))
  call feedkeys("/xyz\<C-w>ch\<CR>", 'x')
  call assert_equal('cherry', getline(2))
endfunction

function! s:suite.delete() abort
  call s:open()
  call cursor(3, 1)
  normal dd
  call assert_equal(['apple', 'cherry'], g:words)
  call assert_equal(['apple', 'cherry'], getline(2, '$'))
  call assert_equal(3, line('.'))
  " On the heading: nothing goes
  call cursor(1, 1)
  normal dd
  call assert_equal(['apple', 'cherry'], g:words)
endfunction

function! s:suite.no_match_no_filter_key() abort
  call roumail_lists#open('test://plain', {'fetch': {-> [1]},
        \ 'heading': {_ -> ['Plain']}, 'rows': {items -> [{'lines': ['one'], 'item': {}}]},
        \ 'id': {_ -> 1}, 'keys': []}, {})
  call assert_equal('Plain  r refresh  q close', getline(1))
  call assert_equal('', maparg('/', 'n'))
  call assert_equal('', maparg('dd', 'n'), 'no delete, no dd')
endfunction

function! s:suite.close() abort
  call s:open()
  normal q
  call assert_false(bufexists('test://words'))
  call assert_equal(1, winnr('$'))
  " The only window: it stays, empty
  call s:open()
  only
  normal q
  call assert_equal(1, winnr('$'))
  call assert_false(bufexists('test://words'))
endfunction

function! s:suite.reopen_reuses_window() abort
  call s:open()
  wincmd p
  call s:open()
  call assert_equal(2, winnr('$'))
endfunction

function! s:suite.before_each() abort
  call s:reset()
endfunction
