" glow-preview in a Vim outside tmux and WezTerm (env.vim clears both): live
" mode falls back to the static preview. Inside tmux: test/glow-preview.vim.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('glow-preview-outside-tmux')

let s:tmp = resolve(tempname())

function! s:suite.before_each() abort
  silent! only!
  silent! %bwipeout!
  call delete(s:tmp, 'rf')
  call mkdir(s:tmp, 'p')
  execute 'cd' fnameescape(s:tmp)
  call writefile(['# Title', '', 'Hello **glow**'], 'a.md')
  edit a.md
endfunction

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

function! s:suite.live_preview_falls_back_to_static() abort
  call assert_true(executable('entr'), 'entr installed: live mode is possible')
  let g:glow_preview_live = 1
  call g:suite.feed('_p')
  call assert_equal(2, winnr('$'))
  call assert_equal(1, len(filter(getbufinfo(), 'v:val.name =~# "__glow_preview"')), 'the static preview')
endfunction
