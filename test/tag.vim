" bin/tag, run where the tag workflow runs it: in a checkout of a plugin.
let s:suite = themis#suite('tag')

let s:bin = expand('<sfile>:p:h:h') . '/bin/tag'
let s:tmp = resolve(tempname())
let s:origin = s:tmp . '/origin.git'
let s:plugin = s:tmp . '/plugin'

function! s:git(dir, ...) abort
  let l:out = systemlist('git -C ' . shellescape(a:dir) . ' ' . join(map(copy(a:000), 'shellescape(v:val)')))
  call assert_equal(0, v:shell_error, join(a:000) . ': ' . join(l:out))
  return l:out
endfunction

function! s:commit() abort
  call s:git(s:plugin, '-c', 'user.name=suite', '-c', 'user.email=suite@example.com',
        \ '-c', 'commit.gpgsign=false', 'commit', '-q', '--allow-empty', '-m', 'change')
  call s:git(s:plugin, 'push', '-q', 'origin', 'HEAD:main')
endfunction

function! s:suite.after() abort
  call delete(s:tmp, 'rf')
endfunction

function! s:suite.tags_the_commit_with_the_next_patch_version() abort
  for [l:existing, l:next] in [
        \ [[], 'v1.0.0'],
        \ [['v1.0.0'], 'v1.0.1'],
        \ [['v1.2.3'], 'v1.2.4'],
        \ [['v1.0.9', 'v1.0.10'], 'v1.0.11'],
        \ ]
    call delete(s:tmp, 'rf')
    call mkdir(s:origin, 'p')
    call mkdir(s:plugin, 'p')
    call s:git(s:origin, 'init', '-q', '--bare', '-b', 'main')
    call s:git(s:plugin, 'init', '-q', '-b', 'main')
    call s:git(s:plugin, 'remote', 'add', 'origin', s:origin)
    call s:commit()
    for l:tag in l:existing
      call s:git(s:plugin, 'push', '-q', 'origin', 'HEAD:refs/tags/' . l:tag)
    endfor
    call s:commit()

    let l:out = systemlist('cd ' . shellescape(s:plugin) . ' && ' . shellescape(s:bin))

    call assert_equal(0, v:shell_error, join(l:out))
    call assert_equal(['tagged ' . l:next], l:out)
    call assert_equal(l:existing + [l:next], s:git(s:origin, 'tag', '--list', '--sort=version:refname'))
    call assert_equal([l:next], s:git(s:origin, 'tag', '--points-at', s:git(s:plugin, 'rev-parse', 'HEAD')[0]))
  endfor
endfunction
