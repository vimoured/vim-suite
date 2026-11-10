" vim-prompts with Copilot as the agent (a stand-in `copilot` on PATH): a
" one-off (-p) can't ask, so it approves as g:prompts_copilot_approval says
" (docs/agent.md); a session starts as Copilot's own config says.
"
" #Note: the flags are checked against `copilot --help` (1.0.103) only. On a
" machine with Copilot, check that a one-off with each value can read a file
" outside the repository and fetch a URL:
"   :let g:prompts_copilot_approval = 'assisted' | Ai! -- fetch https://example.com
let g:suite_spec = expand('<sfile>')
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('vim-prompts-copilot')

let s:tmp = resolve(tempname())
call mkdir(s:tmp . '/bin', 'p')
call writefile(['#!/bin/sh'], s:tmp . '/bin/copilot')
call setfperm(s:tmp . '/bin/copilot', 'rwxr-xr-x')
let $PATH = s:tmp . '/bin:' . $PATH
let g:prompts_agent = 'copilot'

function! s:suite.before_each() abort
  unlet! g:prompts_copilot_approval
  messages clear
endfunction

function! s:suite.after() abort
  silent! %bwipeout!
  call delete(s:tmp, 'rf')
endfunction

" The command line :AiPreview[!] -- hi would run
function! s:line(bang) abort
  silent! bwipeout ai-preview://
  execute 'AiPreview' . a:bang . ' -- hi'
  let l:line = &l:statusline
  wincmd p
  return l:line
endfunction

function! s:suite.oneoff_approves_with_the_judge_by_default() abort
  call assert_match('would run: copilot --experimental --assisted-approval --allow-all-tools'
        \ . ' --allow-all-urls --allow-all-paths -p <prompt>%=', s:line('!'))
endfunction

function! s:suite.oneoff_approves_everything_with_all() abort
  let g:prompts_copilot_approval = 'all'
  call assert_match('would run: copilot --allow-all -p <prompt>%=', s:line('!'))
endfunction

function! s:suite.unknown_approval_is_an_error_and_the_judge_approves() abort
  let g:prompts_copilot_approval = 'yolo'
  call assert_match('would run: copilot --experimental --assisted-approval --allow-all-tools'
        \ . ' --allow-all-urls --allow-all-paths -p <prompt>%=', s:line('!'))
  call assert_match('vim-prompts: g:prompts_copilot_approval is assisted or all, not yolo',
        \ execute('messages'))
endfunction

" Its own config decides; the dotfiles' auto mode has no flag
function! s:suite.session_starts_as_its_config_says() abort
  call assert_match('would run: copilot -i <prompt>%=', s:line(''))
endfunction
