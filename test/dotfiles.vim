" dotfiles: the Vim config loads, with every plugin, without an error; and
" what the config itself provides, end to end.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('dotfiles')

let s:tmp = resolve(tempname())
let s:python = g:suite.deps . '/python/bin/python'
let s:dots = g:suite.deps . '/dotfiles/.config/shell/dots'

function! s:suite.before_each() abort
  silent! only!
  silent! tabonly!
  silent! %bwipeout!
  call delete(s:tmp, 'rf')
  call mkdir(s:tmp, 'p')
  execute 'cd' fnameescape(s:tmp)
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

" Waits up to 10s for a:cond (an expression) to hold, letting jobs and the
" terminal run meanwhile
function! s:wait(cond, what) abort
  for l:i in range(200)
    if eval(a:cond)
      return 1
    endif
    sleep 50m
  endfor
  call assert_report('timed out waiting for ' . a:what)
  return 0
endfunction

function! s:suite.starts_without_errors() abort
  call assert_equal([], g:suite.errors)
endfunction

" <leader>gj glues back the lines a terminal's scrollback broke a command into,
" in the clipboard, so it pastes as one line
function! s:suite.join_clipboard_lines() abort
  call setreg('+', "uv run pytest tests/test_ord\ner.py::TestOrder -q\n")
  call feedkeys("\<Space>gj", 'x')
  call assert_equal('uv run pytest tests/test_order.py::TestOrder -q', getreg('+'))
endfunction

" pdb's vdiff (.pdbrc.py), in a Vim :terminal, asks Vim through the terminal
" API (Tapi_PdbDiff, vim-rc/plugin/pdb_diff.vim) to diff the two values,
" normalized to sorted, indented JSON, expected left and actual right, in one
" tab it reuses
function! s:suite.pdb_vdiff_in_a_terminal_diffs_json_in_vim() abort
  call assert_true(executable(s:python), 'deps/python: run bin/fetch')
  " ~/.pdbrc.py as install.sh links it; pdbpp reads it
  call system('ln -s ' . shellescape(s:dots . '/.pdbrc.py') . ' ' . shellescape($HOME . '/.pdbrc.py'))
  call writefile([
        \ 'expected = {"name": "x", "ids": [1, 2], "ok": True}',
        \ 'actual = {"ok": False, "name": "x", "ids": [1, 3]}',
        \ 'breakpoint()',
        \ ], 't.py')
  let l:term = term_start([s:python, 't.py'], {'curwin': 1, 'term_finish': 'open'})
  call s:wait("join(getbufline(" . l:term . ", 1, '$')) =~# '(Moo++)'", 'the pdbpp prompt')

  call term_sendkeys(l:term, "vdiff expected -- actual\r")
  if s:wait("tabpagenr('$') == 2", 'the diff tab')
    call assert_equal(1, gettabvar(2, 'pdb_diff'), 'the reused diff tab')
    let l:wins = gettabinfo(2)[0].windows
    call assert_equal(2, len(l:wins))
    call assert_equal([1, 1], map(copy(l:wins), 'getwinvar(v:val, "&diff")'))
    call assert_equal(['{', '  "ids": [', '    1,', '    2', '  ],', '  "name": "x",', '  "ok": true', '}'],
          \ getbufline(winbufnr(l:wins[0]), 1, '$'), 'expected, left')
    call assert_equal(['{', '  "ids": [', '    1,', '    3', '  ],', '  "name": "x",', '  "ok": false', '}'],
          \ getbufline(winbufnr(l:wins[1]), 1, '$'), 'actual, right')
  endif

  " Again, the other way round: the same tab, new contents
  call term_sendkeys(l:term, "vdiff actual -- expected\r")
  if s:wait("tabpagenr('$') == 2 && get(getbufline(winbufnr(gettabinfo(2)[0].windows[0]), 4), 0, '') =~# '3'", 'the second diff')
    let l:wins = gettabinfo(2)[0].windows
    call assert_equal(2, tabpagenr('$'), 'no new tab')
    call assert_equal(2, len(l:wins))
    call assert_equal('    3', getbufline(winbufnr(l:wins[0]), 4)[0], 'actual now left')
    call assert_equal('    2', getbufline(winbufnr(l:wins[1]), 4)[0], 'expected now right')
  endif
  call job_stop(term_getjob(l:term), 'kill')
endfunction
