" Stand-in for vim-plug: the vimrc's Plug lines do nothing, and env.vim puts
" on the runtimepath what they would have added.
function! plug#begin(...) abort
endfunction
function! plug#end() abort
endfunction
command! -nargs=+ Plug :
