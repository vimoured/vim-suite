" quarto-slides: what the dotfiles use of it (_p in .qmd buffers, their
" <localleader>p, from vim-rc/after/ftplugin/quarto.vim) and its README, in a
" Vim running inside tmux (a private tmux server, so the preview splits a pane
" there), with the test/bin/quarto stand-in. Vim outside tmux, render and
" open: test/quarto-slides-outside-tmux.vim.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('quarto-slides')

let s:tmp = resolve(tempname())
let s:tmux = 'tmux -L vim-suite-quarto -f /dev/null '
call system(s:tmux . 'kill-server')
call system(s:tmux . 'new-session -d -s suite -x 200 -y 50')
" quarto-slides reads $TMUX when it loads, before any test calls it
let $TMUX = trim(system(s:tmux . "display -p '#{socket_path},#{pid},0'"))

" Every pane but the session's first: [[id, width, command], ...]
function! s:panes() abort
  return map(systemlist(s:tmux . "list-panes -t suite -F '#{pane_id} #{pane_width} #{pane_start_command}'")[1:],
        \ 'split(v:val, " ", 1)')
endfunction

function! s:suite.before_each() abort
  " What the last test left running: a pane, and the plugin's record of it
  SlidesStop
  silent! only!
  silent! %bwipeout!
  for l:pane in s:panes()
    call system(s:tmux . 'kill-pane -t ' . l:pane[0])
  endfor
  let g:quarto_slides_pane_percent = 25
  call delete(s:tmp, 'rf')
  call mkdir(s:tmp, 'p')
  execute 'cd' fnameescape(s:tmp)
  call writefile(['---', 'title: Lorem', 'format: revealjs', '---', '', '## Ipsum'], 'a.qmd')
  call writefile(['---', 'title: Dolor', 'format: revealjs', '---'], 'b.qmd')
  edit a.qmd
endfunction

function! s:suite.after() abort
  SlidesStop
  call system(s:tmux . 'kill-server')
  cd /
  call delete(s:tmp, 'rf')
endfunction

if !executable('tmux')
  " CI has no tmux: every test is a TODO there; they run where it's installed
  function! s:suite.before_each() abort
    call themis#helper('assert').skip('TODO: needs tmux installed')
  endfunction
endif

" Keys as typed; returns the messages they gave, and any error
function! s:type(keys) abort
  let v:errmsg = ''
  try
    let l:out = execute('call g:suite.feed(' . string(a:keys) . ')')
  catch
    return v:exception
  endtry
  return empty(v:errmsg) ? l:out : l:out . "\n" . v:errmsg
endfunction

" Waits up to 10s for a:cond (an expression) to hold
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

function! s:suite.dotfiles_bind_preview_not_glow_in_qmd_buffers() abort
  call assert_equal('<Plug>(quarto-slides-preview)', maparg('_p', 'n'))
  call assert_equal('<Plug>(quarto-slides-render)', maparg('_r', 'n'))
  call assert_equal('<Plug>(quarto-slides-open)', maparg('_o', 'n'))
  edit c.md
  call assert_equal('<Plug>(glow-preview)', maparg('_p', 'n'), 'markdown keeps glow')
endfunction

function! s:suite.preview_opens_a_pane_running_quarto_preview() abort
  call assert_equal("\nSlides preview: a.qmd (tmux), :w reloads the browser", s:type('_p'))
  call assert_equal(1, winnr('$'), 'no window in Vim')
  call assert_equal('a.qmd', bufname('%'))
  if s:wait('len(s:panes()) == 1', 'the tmux pane')
    let l:cmd = join(s:panes()[0][2:])
    call assert_match('quarto.* preview .*' . s:tmp . '/a\.qmd', l:cmd)
    call s:wait("system(s:tmux . 'capture-pane -p -t " . s:panes()[0][0] . "') =~# 'Preview of'", 'quarto in the pane')
  endif
endfunction

function! s:suite.preview_pane_width() abort
  let g:quarto_slides_pane_percent = 40
  call s:type('_p')
  if s:wait('len(s:panes()) == 1', 'the tmux pane')
    " 40% of 200 columns, give or take the border
    call assert_true(abs(s:panes()[0][1] - 80) <= 2, 'width ' . s:panes()[0][1])
  endif
endfunction

function! s:suite.preview_again_closes_the_pane() abort
  call s:type('_p')
  call s:wait('len(s:panes()) == 1', 'the tmux pane')
  call assert_equal("\nSlides preview stopped", s:type('_p'))
  call assert_equal(0, len(s:panes()))
endfunction

function! s:suite.preview_of_another_deck_replaces_the_pane() abort
  call s:type('_p')
  call s:wait('len(s:panes()) == 1', 'the tmux pane')
  edit b.qmd
  call s:type('_p')
  call assert_equal(1, len(s:panes()), 'one preview pane')
  call assert_match('b\.qmd', join(s:panes()[0][2:]))
endfunction

function! s:suite.preview_after_the_pane_was_closed_opens_a_new_one() abort
  call s:type('_p')
  call s:wait('len(s:panes()) == 1', 'the tmux pane')
  call system(s:tmux . 'kill-pane -t ' . s:panes()[0][0])
  call assert_match('Slides preview: a.qmd', s:type('_p'))
  call assert_equal(1, len(s:panes()))
endfunction

function! s:suite.slides_stop_closes_the_pane() abort
  SlidesPreview
  call s:wait('len(s:panes()) == 1', 'the tmux pane')
  SlidesStop
  call assert_equal(0, len(s:panes()))
endfunction

function! s:suite.quitting_vim_closes_the_pane() abort
  call s:type('_p')
  call s:wait('len(s:panes()) == 1', 'the tmux pane')
  doautocmd <nomodeline> VimLeavePre
  call assert_equal(0, len(s:panes()))
endfunction
