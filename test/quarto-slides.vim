" quarto-slides: what the dotfiles use of it (_p, _r and _o in .qmd buffers,
" their <localleader> keys, from vim-rc/after/ftplugin/quarto.vim) and its
" README, with the test/bin/quarto and test/bin/open stand-ins. The preview
" runs in the background, inside WezTerm or tmux too: no window or pane.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('quarto-slides')

let s:tmp = resolve(tempname())
let $QUARTO_LOG = s:tmp . '-quarto.log'
let $OPEN_LOG = s:tmp . '-open.log'

" quarto preview jobs still running
function! s:previews() abort
  return filter(job_info(), 'job_status(v:val) ==# "run" && join(job_info(v:val).cmd) =~# " preview "')
endfunction

function! s:suite.before_each() abort
  SlidesStop
  call s:wait('empty(s:previews())', 'the preview to end')
  " vim-dispatch's exit callback deletes its terminal's buffer: E516 if wiped
  call s:wait('empty(filter(term_list(), ''job_status(term_getjob(v:val)) ==# "run"''))', 'the terminals to end')
  unlet! $QUARTO_FAIL
  silent! only!
  silent! %bwipeout!
  call delete(s:tmp, 'rf')
  call mkdir(s:tmp, 'p')
  call delete($QUARTO_LOG)
  call delete($OPEN_LOG)
  execute 'cd' fnameescape(s:tmp)
  call writefile(['---', 'title: Lorem', 'format: revealjs', '---', '', '## Ipsum'], 'a.qmd')
  call writefile(['---', 'title: Dolor', 'format: revealjs', '---'], 'b.qmd')
  edit a.qmd
endfunction

function! s:suite.after() abort
  SlidesStop
  cd /
  call delete(s:tmp, 'rf')
  call delete($QUARTO_LOG)
  call delete($OPEN_LOG)
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

function! s:log(file) abort
  return filereadable(a:file) ? readfile(a:file) : []
endfunction

function! s:suite.dotfiles_bind_preview_not_glow_in_qmd_buffers() abort
  call assert_equal('<Plug>(quarto-slides-preview)', maparg('_p', 'n'))
  call assert_equal('<Plug>(quarto-slides-render)', maparg('_r', 'n'))
  call assert_equal('<Plug>(quarto-slides-open)', maparg('_o', 'n'))
  edit c.md
  call assert_equal('<Plug>(glow-preview)', maparg('_p', 'n'), 'markdown keeps glow')
endfunction

" Preview

function! s:suite.preview_runs_in_the_background() abort
  let l:bufs = len(getbufinfo())
  call assert_equal("\nSlides preview: a.qmd, :w reloads the browser", s:type('_p'))
  call assert_equal(1, winnr('$'), 'no window opens')
  call assert_equal(l:bufs, len(getbufinfo()), 'no buffer, hidden or not')
  call assert_equal('a.qmd', bufname('%'))
  call assert_equal(1, len(s:previews()))
  call s:wait('!empty(s:log($QUARTO_LOG))', 'quarto to start')
  call assert_equal(['quarto preview ' . s:tmp . '/a.qmd'], s:log($QUARTO_LOG))
endfunction

function! s:suite.preview_inside_wezterm_or_tmux_opens_no_pane() abort
  " Read at call time if at all: set them, and no multiplexer is asked
  let $WEZTERM_PANE = '0'
  let $TERM_PROGRAM = 'WezTerm'
  let $TMUX = '/nonexistent,1,0'
  try
    call assert_equal("\nSlides preview: a.qmd, :w reloads the browser", s:type('_p'))
    call assert_equal(1, len(s:previews()))
  finally
    unlet $WEZTERM_PANE $TERM_PROGRAM $TMUX
  endtry
endfunction

function! s:suite.preview_again_stops_it() abort
  call s:type('_p')
  call assert_equal("\nSlides preview stopped", s:type('_p'))
  call s:wait('empty(s:previews())', 'the preview to end')
endfunction

function! s:suite.preview_of_another_deck_replaces_it() abort
  call s:type('_p')
  edit b.qmd
  call assert_match('Slides preview: b.qmd', s:type('_p'))
  call s:wait('len(s:previews()) == 1', 'one preview')
  call assert_match('/b\.qmd$', join(job_info(s:previews()[0]).cmd))
endfunction

function! s:suite.slides_stop_stops_it() abort
  SlidesPreview
  SlidesStop
  call s:wait('empty(s:previews())', 'the preview to end')
endfunction

function! s:suite.quitting_vim_stops_it() abort
  call s:type('_p')
  doautocmd <nomodeline> VimLeavePre
  call s:wait('empty(s:previews())', 'the preview to end')
endfunction

function! s:suite.stopping_it_is_no_error() abort
  call s:type('_p')
  SlidesStop
  call s:wait('empty(s:previews())', 'the preview to end')
  " Let its exit callback run
  sleep 200m
  call assert_notmatch('exited', execute('messages'))
endfunction

function! s:suite.preview_that_fails_says_so() abort
  let $QUARTO_FAIL = 'bad deck'
  messages clear
  call s:type('_p')
  call s:wait("execute('messages') =~# 'exited'", 'the error')
  call assert_match('quarto-slides: quarto preview exited (1), :SlidesLog shows why', execute('messages'))
  call assert_equal(1, winnr('$'), 'no window opens')
endfunction

function! s:suite.preview_without_quarto() abort
  let l:path = $PATH
  try
    let $PATH = s:tmp
    call assert_match('quarto-slides: quarto not found on PATH', s:type('_p'))
  finally
    let $PATH = l:path
  endtry
  call assert_equal([], s:previews())
endfunction

" Log

function! s:suite.log_shows_the_output_in_a_scratch() abort
  call s:type('_p')
  call s:wait('!empty(s:log($QUARTO_LOG))', 'quarto to start')
  sleep 200m
  SlidesLog
  call assert_equal(2, winnr('$'), 'a split')
  call assert_match('^scratch\d\+$', bufname('%'))
  call assert_equal('nofile', &buftype)
  call assert_equal(['Preview of ' . s:tmp . '/a.qmd'], getline(1, '$'))
endfunction

function! s:suite.log_of_a_failed_preview_shows_why() abort
  let $QUARTO_FAIL = 'bad deck'
  messages clear
  call s:type('_p')
  call s:wait("execute('messages') =~# 'exited'", 'the error')
  SlidesLog
  call assert_equal(['ERROR: bad deck'], getline(1, '$'))
endfunction

" Outside a .qmd buffer: the commands refuse

function! s:suite.commands_outside_a_qmd_buffer() abort
  edit notes.txt
  for l:cmd in ['SlidesPreview', 'SlidesRender', 'SlidesOpen']
    call assert_match('quarto-slides: not a .qmd file', execute(l:cmd), l:cmd)
  endfor
  call assert_equal([], s:previews())
  call assert_equal([], s:log($QUARTO_LOG))
endfunction

" Render and open

function! s:suite.render_writes_the_html() abort
  call setline(6, '## Changed')
  call s:type('_r')
  call assert_equal(0, &modified, 'the deck is saved first')
  call s:wait("filereadable('a.html')", 'a.html')
  call assert_equal(['quarto render ' . s:tmp . '/a.qmd'], s:log($QUARTO_LOG))
endfunction

function! s:suite.open_before_render() abort
  call assert_match('quarto-slides: a.html not rendered yet; render first', s:type('_o'))
  call assert_equal([], s:log($OPEN_LOG))
endfunction

function! s:suite.open_after_render() abort
  SlidesRender
  call s:wait("filereadable('a.html')", 'a.html')
  call s:type('_o')
  call s:wait("!empty(s:log($OPEN_LOG))", 'the browser to be asked')
  call assert_equal([s:tmp . '/a.html'], s:log($OPEN_LOG))
endfunction

function! s:suite.open_follows_output_file() abort
  call setline(3, 'format:')
  call append(3, ['  revealjs:', '    output-file: "talk.html"  # the deck'])
  call writefile([], 'talk.html')
  SlidesOpen
  call s:wait("!empty(s:log($OPEN_LOG))", 'the browser to be asked')
  call assert_equal([s:tmp . '/talk.html'], s:log($OPEN_LOG))
endfunction
