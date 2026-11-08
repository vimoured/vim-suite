" Replaces junegunn/fzf's fzf#run once its plugin file is loaded: nothing is
" shown, and the spec is kept in g:suite.fzf for the specs to look at. A spec
" without a source lists what $FZF_DEFAULT_COMMAND does (fzf.vim's :Rg sets
" it): that command is kept as its 'default_command'.
function! fzf#run(...) abort
  let l:spec = a:0 ? deepcopy(a:1) : {}
  if !has_key(l:spec, 'source') && !empty($FZF_DEFAULT_COMMAND)
    let l:spec.default_command = $FZF_DEFAULT_COMMAND
  endif
  call add(g:suite.fzf, l:spec)
  return []
endfunction
