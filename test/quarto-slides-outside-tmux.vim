" quarto-slides in a Vim outside tmux and WezTerm (env.vim clears both): the
" preview runs in a hidden Vim terminal. Also _r (render, through vim-dispatch)
" and _o (open), as the dotfiles bind them in .qmd buffers, with the
" test/bin/quarto and test/bin/open stand-ins. Inside tmux:
" test/quarto-slides.vim.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('quarto-slides-outside-tmux')

let s:tmp = resolve(tempname())
let $QUARTO_LOG = s:tmp . '-quarto.log'
let $OPEN_LOG = s:tmp . '-open.log'

function! s:previews() abort
  return filter(getbufinfo(), 'v:val.name =~# "__quarto_preview"')
endfunction

function! s:running() abort
  return filter(term_list(), 'job_status(term_getjob(v:val)) ==# "run"')
endfunction

function! s:suite.before_each() abort
  SlidesStop
  " vim-dispatch's exit callback deletes its terminal's buffer: E516 if wiped
  call s:wait('empty(s:running())', 'the terminals to end')
  silent! only!
  silent! %bwipeout!
  call delete(s:tmp, 'rf')
  call mkdir(s:tmp, 'p')
  call delete($QUARTO_LOG)
  call delete($OPEN_LOG)
  execute 'cd' fnameescape(s:tmp)
  call writefile(['---', 'title: Lorem', 'format: revealjs', '---', '', '## Ipsum'], 'a.qmd')
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

" Preview

function! s:suite.preview_runs_in_a_hidden_terminal() abort
  call assert_equal("\nSlides preview: a.qmd (term), :w reloads the browser", s:type('_p'))
  call assert_equal(1, winnr('$'), 'no window opens')
  call assert_equal('a.qmd', bufname('%'))
  call assert_equal(1, len(s:previews()))
  let l:preview = s:previews()[0]
  call assert_equal(1, l:preview.hidden)
  call assert_equal('running', term_getstatus(l:preview.bufnr))
  call s:wait("join(getbufline(" . l:preview.bufnr . ", 1, '$')) =~# 'Preview of'", 'quarto in the terminal')
  call assert_equal(['quarto preview ' . s:tmp . '/a.qmd'], s:log($QUARTO_LOG))
endfunction

function! s:suite.preview_again_stops_it() abort
  call s:type('_p')
  " Not assert_equal: fzf.vim's BufDelete autocmd raises an E716 under
  " silent! as the terminal is wiped, which execute() still captures
  call assert_match('Slides preview stopped', s:type('_p'))
  call assert_equal([], s:previews())
endfunction

function! s:suite.quitting_vim_stops_it() abort
  call s:type('_p')
  doautocmd <nomodeline> VimLeavePre
  call assert_equal([], s:previews())
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

function! s:suite.preview_in_wezterm() abort
  " TODO: needs a headless wezterm-mux-server on CI, as glow-preview's
  call themis#helper('assert').skip('TODO: the WezTerm preview pane')
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
