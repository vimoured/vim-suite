" Starts Themis from -c, after Vim's startup, instead of from a VimEnter
" autocommand as its own bin/themis does. Inside an autocommand Vim puts off
" :checktime (and with it 'autoread'), so a test there can't see a file change
" the way you would. $THEMIS_HOME is vim-themis.
let &runtimepath = escape($THEMIS_HOME, '\,') . ',' . &runtimepath
let g:themis#cmdline = 1

function! s:main() abort
  " Normal mode, as Themis has it; and an error then sets the exit code
  visual
  let l:failed = 1
  try
    let l:args = argv()
    if !empty(l:args)
      execute '1,' . len(l:args) . 'argdelete'
      silent! %bwipeout!
    endif
    let l:failed = themis#command#start(l:args)
  catch
    $put ='ERROR: ' . v:exception . ' @ ' . v:throwpoint
    % print
  finally
    execute l:failed ? 'cquit' : 'qall!'
  endtry
endfunction
call s:main()
