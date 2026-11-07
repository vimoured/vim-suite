" Replaces junegunn/fzf's fzf#run once its plugin file is loaded: nothing is
" shown, and the spec is kept in g:suite.fzf for the specs to look at.
function! fzf#run(...) abort
  call add(g:suite.fzf, a:0 ? deepcopy(a:1) : {})
  return []
endfunction
