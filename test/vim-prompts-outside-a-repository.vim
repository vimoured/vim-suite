" vim-prompts asked from a file outside any repository: the agent's comments
" go where vim-place keeps files for that directory, which the agent is given.
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('vim-prompts-outside-a-repository')

let s:tmp = resolve(tempname())
let s:plain = s:tmp . '/plain'
let $XDG_STATE_HOME = s:tmp . '/state'
let s:comments = $XDG_STATE_HOME . '/plain-' . sha256(s:plain)[:7] . '/vim-prompts/comments'
let g:prompts_agent_table = {'fake': {'cmd': ['true'], 'prompt': [], 'dir': '--add-dir',
      \ 'modes': {'ask': [], 'plan': [], 'agent': [], 'auto': []}}}
let g:prompts_agent = 'fake'

function! s:suite.before_each() abort
  silent! %bwipeout!
  cd /
  call delete(s:tmp, 'rf')
  call mkdir(s:plain, 'p')
  call writefile(['notes'], s:plain . '/notes.txt')
  execute 'cd' fnameescape(s:plain)
  edit notes.txt
endfunction

function! s:suite.after() abort
  silent! %bwipeout!
  cd /
  call delete(s:tmp, 'rf')
endfunction

" %AiPreview! #agent_comments: the session's prompt and the command line
function! s:preview() abort
  silent! bwipeout ai-preview://
  %AiPreview! #agent_comments
  let l:result = {'prompt': join(getline(1, '$'), "\n"), 'line': &l:statusline}
  wincmd p
  return l:result
endfunction

function! s:suite.agent_comments_go_to_the_place_of_the_directory() abort
  let l:prompt = s:preview().prompt
  call assert_match('write each comment .* to `' . s:comments . '/', l:prompt)
  call assert_match('relative to `' . s:plain . '`', l:prompt)
endfunction

function! s:suite.the_agent_may_write_there() abort
  call assert_match('--add-dir ' . s:comments, s:preview().line)
endfunction

function! s:suite.ai_comments_completes_the_reviews_written_there() abort
  call mkdir(s:comments, 'p')
  call writefile(['notes.txt:1: 1. [nit] say more'], s:comments . '/20260101-000000-1.txt')
  call assert_equal(['20260101-000000-1.txt'], getcompletion('AiComments ', 'cmdline'))
endfunction
