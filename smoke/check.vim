" Sourced by the smoke test once Vim has started with the dotfiles, on a
" terminal, editing a markdown file: writes what went wrong to /tmp/smoke.out
" and quits, with an error status if anything did.
let s:errors = []
if !empty(v:errmsg)
  call add(s:errors, 'v:errmsg: ' . v:errmsg)
endif
call extend(s:errors, filter(split(execute('messages'), "\n"), 'v:val =~# "^E\\d\\+:\\|^Error detected"'))
for [s:name, s:plug] in items(get(g:, 'plugs', {}))
  if !isdirectory(s:plug.dir)
    call add(s:errors, 'not installed: ' . s:name)
  endif
endfor

let s:out = ['vim: ' . matchstr(execute('version'), 'VIM - Vi IMproved \S\+') . ' patch ' . v:versionlong,
      \ 'plugins: ' . len(get(g:, 'plugs', {})) . ', scripts sourced: ' . len(getscriptinfo()),
      \ 'filetype: ' . &filetype]
call extend(s:out, empty(s:errors) ? ['smoke: no errors'] : ['smoke: FAILED'] + s:errors)
call writefile(s:out, '/tmp/smoke.out')
execute empty(s:errors) ? 'qall!' : 'cquit!'
