" glow-preview: what the dotfiles use of it (_p and _P in markdown buffers,
" their <localleader>p / P) and its README, with real glow, in a Vim running
" inside tmux (a private tmux server, so live mode splits a pane there). Vim
" outside tmux: test/glow-preview-outside-tmux.vim.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('glow-preview')

let s:tmp = resolve(tempname())
let s:tmux = 'tmux -L vim-suite-glow -f /dev/null '
call system(s:tmux . 'kill-server')
call system(s:tmux . 'new-session -d -s suite -x 200 -y 50')
" glow-preview reads $TMUX when it loads, before any test calls it
let $TMUX = trim(system(s:tmux . "display -p '#{socket_path},#{pid},0'"))

function! s:panes() abort
  return systemlist(s:tmux . "list-panes -t suite -F '#{pane_id} #{pane_start_command}'")
endfunction

function! s:screen(pane) abort
  return system(s:tmux . 'capture-pane -p -t ' . a:pane)
endfunction

function! s:suite.before_each() abort
  silent! only!
  silent! %bwipeout!
  " Only the session's first pane
  for l:pane in s:panes()[1:]
    call system(s:tmux . 'kill-pane -t ' . split(l:pane)[0])
  endfor
  let g:glow_preview_live = 0
  call delete(s:tmp, 'rf')
  call mkdir(s:tmp, 'p')
  execute 'cd' fnameescape(s:tmp)
  call writefile(['# Title', '', 'Hello **glow**'], 'a.md')
  edit a.md
endfunction

function! s:suite.after() abort
  call system(s:tmux . 'kill-server')
  cd /
  call delete(s:tmp, 'rf')
endfunction

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

" Skips the test as a TODO when a program it runs isn't installed (CI has no
" glow, entr or tmux: a TODO there; they run where they're installed)
function! s:needs(...) abort
  let l:missing = filter(copy(a:000), '!executable(v:val)')
  if !empty(l:missing)
    call themis#helper('assert').skip('TODO: needs ' . join(l:missing, ', ') . ' installed')
  endif
endfunction

function! s:previews() abort
  return filter(getbufinfo(), 'v:val.name =~# "__glow_preview"')
endfunction

" Static

function! s:suite.preview_renders_the_file_beside_it() abort
  call s:needs('glow')
  call assert_notmatch('E\d\+:', s:type('_p'), 'no error')
  call assert_equal(2, winnr('$'))
  call assert_equal('a.md', bufname('%'), 'the cursor stays in the file')
  call assert_equal(1, len(s:previews()))
  let l:preview = s:previews()[0].bufnr
  call assert_equal('terminal', getbufvar(l:preview, '&buftype'))
  call assert_equal('glow', getbufvar(l:preview, '&filetype'))
  call s:wait("join(getbufline(" . l:preview . ", 1, '$')) =~# 'Hello glow'", 'glow rendering the file')
  call assert_equal(1, len(s:panes()), 'no tmux pane')
endfunction

function! s:suite.preview_again_replaces_it() abort
  call s:needs('glow')
  call s:type('_p')
  call s:type('_p')
  call assert_equal(1, len(s:previews()))
  call assert_equal(2, winnr('$'))
endfunction

function! s:suite.preview_without_glow() abort
  let l:path = $PATH
  try
    let $PATH = s:tmp
    call assert_match('glow-preview: glow not found on PATH', s:type('_p'))
  finally
    let $PATH = l:path
  endtry
  call assert_equal(1, winnr('$'), 'nothing opens')
endfunction

" Live

function! s:suite.toggle_live() abort
  call assert_equal("\nGlow preview: LIVE", s:type('_P'))
  call assert_equal("\nGlow preview: STATIC", s:type('_P'))
endfunction

function! s:suite.live_preview_in_a_tmux_pane_rerenders_on_save() abort
  call s:needs('glow', 'entr', 'tmux')
  let g:glow_preview_live = 1
  call assert_notmatch('E\d\+:', s:type('_p'), 'no error')
  call assert_equal(1, winnr('$'), 'no window in Vim')
  if s:wait('len(s:panes()) == 2', 'the tmux pane')
    let [l:pane; l:cmd] = split(s:panes()[1])
    call assert_match('a\.md.*entr.*glow', join(l:cmd))
    call s:wait("s:screen('" . l:pane . "') =~# 'Hello glow'", 'glow in the pane')
    call setline(3, 'Changed **text**')
    write
    call s:wait("s:screen('" . l:pane . "') =~# 'Changed text'", 'the pane re-rendering on save')
  endif
endfunction

function! s:suite.live_preview_again_replaces_the_pane() abort
  call s:needs('glow', 'entr', 'tmux')
  let g:glow_preview_live = 1
  call s:type('_p')
  call s:wait('len(s:panes()) == 2', 'the tmux pane')
  call s:type('_p')
  sleep 1
  call assert_equal(2, len(s:panes()), 'one live pane')
endfunction

function! s:suite.live_preview_without_entr_falls_back_to_static() abort
  call s:needs('glow')
  let g:glow_preview_live = 1
  let l:bin = s:tmp . '/bin'
  call mkdir(l:bin)
  call system('ln -s ' . shellescape(exepath('glow')) . ' ' . shellescape(l:bin . '/glow'))
  let l:path = $PATH
  try
    let $PATH = l:bin
    call assert_match('requires entr', s:type('_p'))
  finally
    let $PATH = l:path
  endtry
  call assert_equal(1, len(s:previews()), 'the static preview')
  call assert_equal(1, len(s:panes()), 'no tmux pane')
endfunction

function! s:suite.live_preview_in_wezterm() abort
  " TODO: my setup. Needs a headless wezterm-mux-server on CI; until then its
  " code is kept out of the peel-back by name (see the handoff).
  call themis#helper('assert').skip('TODO: the WezTerm live pane')
endfunction

" Commands

function! s:suite.commands() abort
  call s:needs('glow')
  GlowPreviewToggleLive
  call assert_equal(1, g:glow_preview_live)
  GlowPreviewToggleLive
  GlowPreview
  call assert_equal(1, len(s:previews()))
endfunction
