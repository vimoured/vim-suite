" project-detect: the project Vim starts in, as the plugins that build on it
" ask for it (fzf-utils, pytest.vim): project_detect#active(), #name(),
" #root(), #parts(), #part(), #is_test(), and #register() for more project
" types; and its README.
"
" It detects once a Vim, at VimEnter, so every case starts its own Vim (the
" suite's startup, test/helper/env.vim) in a project made for it, and reads
" what that Vim answers: s:started_in().
let g:suite_spec = expand('<sfile>')
let s:tmp = resolve(tempname())
call mkdir(s:tmp, 'p')
execute 'cd' fnameescape(s:tmp)
execute 'source' fnameescape(expand('<sfile>:p:h') . '/helper/env.vim')
let s:suite = themis#suite('project-detect')
let s:env = expand('<sfile>:p:h') . '/helper/env.vim'
let s:started = 0

function! s:suite.after() abort
  cd /
  call delete(s:tmp, 'rf')
endfunction

" Makes a project: {path: lines}; a path ending in / is a directory
function! s:project(name, files) abort
  let l:root = s:tmp . '/' . a:name
  call mkdir(l:root, 'p')
  for [l:path, l:lines] in items(a:files)
    if l:path =~# '/$'
      call mkdir(l:root . '/' . l:path, 'p')
    else
      call mkdir(fnamemodify(l:root . '/' . l:path, ':h'), 'p')
      call writefile(l:lines, l:root . '/' . l:path)
    endif
  endfor
  return l:root
endfunction

" language, sources and tests are the first part's
let s:first = 'get(project_detect#parts(), 0, {})'
let s:asked = {
      \ 'active': 'project_detect#active()',
      \ 'name': 'project_detect#name()',
      \ 'language': 'get(' . s:first . ', "language", "")',
      \ 'root': 'project_detect#root()',
      \ 'sources': 'get(' . s:first . ', "sources", [])',
      \ 'tests': 'get(' . s:first . ', "tests", [])',
      \ 'languages': 'map(project_detect#parts(), "v:val.language")',
      \ }

" What a Vim started in dir answers: s:asked, and opts.ask ({key: expr}).
" opts.before: lines run before startup, with project-detect already on the
" runtimepath, as a plugin or a vimrc loaded earlier would; opts.after: lines
" run after it. Also 'errors': startup's and the asking's.
function! s:started_in(dir, ...) abort
  let l:opts = get(a:000, 0, {})
  let s:started += 1
  let l:out = s:tmp . '/answer-' . s:started . '.json'
  let l:script = s:tmp . '/start-' . s:started . '.vim'
  let l:asked = extend(copy(s:asked), get(l:opts, 'ask', {}))
  let l:lines = [
        \ 'let g:suite_spec = ' . string('project-detect-' . s:started),
        \ 'set runtimepath^=' . fnameescape(g:suite.deps . '/project-detect'),
        \ ] + (empty($SUITE_PROFILE) ? [] : [
        \ '" Profiled from here, as env.vim would, for what runs before it',
        \ 'profile start ' . fnameescape($SUITE_PROFILE . '/project-detect-' . s:started . '.prof'),
        \ 'profile! file ' . fnameescape(resolve(g:suite.deps . '/project-detect')) . '/*',
        \ ]) + get(l:opts, 'before', []) + [
        \ 'source ' . fnameescape(s:env),
        \ ] + get(l:opts, 'after', []) + [
        \ 'let s:answer = {"errors": copy(g:suite.errors)}',
        \ 'for [s:key, s:expr] in items(' . string(l:asked) . ')',
        \ '  try',
        \ '    let s:answer[s:key] = eval(s:expr)',
        \ '  catch',
        \ '    call add(s:answer.errors, s:key . ": " . v:exception)',
        \ '  endtry',
        \ 'endfor',
        \ 'call writefile([json_encode(s:answer)], ' . string(l:out) . ')',
        \ 'qall!',
        \ ]
  call writefile(l:lines, l:script)
  let l:vim = system('cd ' . shellescape(a:dir) . ' && ' . shellescape(v:progpath)
        \ . ' -u NONE -i NONE -n -N -es -S ' . shellescape(l:script) . ' </dev/null')
  if !filereadable(l:out)
    throw 'the Vim started in ' . a:dir . ' answered nothing: ' . l:vim
  endif
  return json_decode(readfile(l:out)[0])
endfunction

" Asserts the answers in expected, and no errors
function! s:answers(expected, answer) abort
  call assert_equal([], a:answer.errors)
  for [l:key, l:value] in items(a:expected)
    call assert_equal(l:value, get(a:answer, l:key, '(not asked)'), l:key)
  endfor
endfunction

let s:python_tests = ['test_*.py', '*_test.py']

function! s:suite.python_named_in_project() abort
  let l:root = s:project('py-named', {
        \ 'pyproject.toml': ['[build-system]', 'requires = ["hatchling"]', '',
        \   '[tool.other]', 'name = "not-this"', '',
        \   '[project]', 'name = "my-proj"', 'version = "1"'],
        \ 'src/my_proj/__init__.py': [],
        \ 'src/other/__init__.py': [],
        \ 'tests/test_core.py': [],
        \ 'test/': [],
        \ })
  call s:answers({'active': 'python', 'name': 'my-proj', 'language': 'python',
        \ 'root': l:root, 'sources': ['src/my_proj/'],
        \ 'tests': ['tests/', 'test/'] + s:python_tests},
        \ s:started_in(l:root))
endfunction

function! s:suite.python_named_in_poetry_flat_layout() abort
  let l:root = s:project('py-poetry', {
        \ 'pyproject.toml': ['[tool.poetry]', "name = 'My.Pkg'"],
        \ 'my_pkg/__init__.py': [],
        \ 'extra/__init__.py': [],
        \ })
  call s:answers({'active': 'python', 'name': 'My.Pkg', 'root': l:root,
        \ 'sources': ['my_pkg/'], 'tests': s:python_tests},
        \ s:started_in(l:root))
endfunction

" The package's directory under the declared name, as it's written
function! s:suite.python_package_under_its_declared_name() abort
  let l:root = s:project('py-asis', {
        \ 'pyproject.toml': ['[project]', 'name = "Odd-Name"'],
        \ 'Odd-Name/__init__.py': [],
        \ 'helpers/__init__.py': [],
        \ })
  call s:answers({'name': 'Odd-Name', 'sources': ['Odd-Name/']}, s:started_in(l:root))
endfunction

" Started anywhere inside it: the root is where pyproject.toml is
function! s:suite.python_from_a_subdirectory() abort
  let l:root = s:project('py-sub', {
        \ 'pyproject.toml': ['[project]', 'name = "sub"'],
        \ 'src/sub/deep/x.py': [],
        \ })
  call s:answers({'active': 'python', 'name': 'sub', 'root': l:root, 'sources': ['src/sub/']},
        \ s:started_in(l:root . '/src/sub/deep'))
endfunction

" No name declared: the only package's, in src/ or the root (tests aren't one)
function! s:suite.python_named_after_its_only_package() abort
  let l:root = s:project('py-src-pkg', {
        \ 'pyproject.toml': ['[build-system]'],
        \ 'src/pkg_a/__init__.py': [],
        \ })
  call s:answers({'active': 'python', 'name': 'pkg_a', 'sources': ['src/pkg_a/']},
        \ s:started_in(l:root))
  let l:root = s:project('py-root-pkg', {
        \ 'pyproject.toml': [],
        \ 'pkg_b/__init__.py': [],
        \ 'tests/__init__.py': [],
        \ })
  call s:answers({'active': 'python', 'name': 'pkg_b', 'sources': ['pkg_b/'],
        \ 'tests': ['tests/'] + s:python_tests},
        \ s:started_in(l:root))
endfunction

" No name anywhere: the directory's, if Vim started in it. From below, the
" file found may not be this project's: not a project, until g:project_name
" names it
function! s:suite.python_without_a_name() abort
  let l:root = s:project('py-nameless', {
        \ 'pyproject.toml': [],
        \ 'src/__init__.py': [],
        \ 'a/__init__.py': [],
        \ 'b/__init__.py': [],
        \ })
  call s:answers({'active': 'python', 'name': 'py-nameless', 'root': l:root, 'language': 'python',
        \ 'sources': ['src/'], 'tests': s:python_tests},
        \ s:started_in(l:root))
  call s:answers({'active': '', 'name': '', 'root': '', 'language': '', 'sources': [], 'tests': []},
        \ s:started_in(l:root . '/a'))
  call s:answers({'active': 'python', 'name': 'named', 'root': l:root, 'sources': ['src/']},
        \ s:started_in(l:root, {'before': ['let g:project_name = "named"']}))
endfunction

" g:project_name over the declared name; its package is looked for too
function! s:suite.project_name_wins() abort
  let l:root = s:project('py-renamed', {
        \ 'pyproject.toml': ['[project]', 'name = "declared"'],
        \ 'mine/__init__.py': [],
        \ 'other/__init__.py': [],
        \ })
  call s:answers({'active': 'python', 'name': 'mine', 'sources': ['mine/'],
        \ 'g': 'mine'},
        \ s:started_in(l:root, {'before': ['let g:project_name = "mine"'],
        \   'ask': {'g': 'g:project_name'}}))
  " And the found name is stored there; no package under it, and more than one
  call s:answers({'name': 'declared', 'g': 'declared', 'sources': []},
        \ s:started_in(l:root, {'ask': {'g': 'g:project_name'}}))
endfunction

" Name and language are separate steps: nothing recognises this as any kind of
" project, and the name alone still makes it one
function! s:suite.project_name_alone_makes_a_project() abort
  let l:name = ['let g:project_name = "blog"']
  let l:root = s:project('name-only', {'blog/': [], 'tests/': []})
  call s:answers({'active': 'declared', 'name': 'blog', 'language': '', 'root': l:root,
        \ 'sources': ['blog/'], 'tests': ['tests/']},
        \ s:started_in(l:root, {'before': l:name}))
  let l:root = s:project('name-only-src', {'src/blog/': []})
  call s:answers({'active': 'declared', 'sources': ['src/blog/'], 'tests': []},
        \ s:started_in(l:root, {'before': l:name}))
endfunction

function! s:suite.project_name_alone_with_no_folder_is_an_error() abort
  let l:answer = s:started_in(s:project('name-only-typo', {'blog/': []}),
        \ {'before': ['let g:project_name = "blgo"'], 'ask': {'messages': 'execute("messages")'}})
  call s:answers({'active': 'declared', 'name': 'blgo', 'sources': []}, l:answer)
  call assert_match('g:project_name "blgo"', l:answer.messages)
endfunction

" Every language found is a part of one project, the first one's type and name
function! s:suite.more_than_one_language_is_one_project() abort
  let l:go = ['module example.com/app']
  for [l:name, l:files, l:expected] in [
        \ ['py-go', {'pyproject.toml': ['[project]', 'name = "p"'], 'go.mod': l:go},
        \   {'active': 'python', 'name': 'p', 'languages': ['python', 'go']}],
        \ ['req-go', {'requirements.txt': [], 'pkg/__init__.py': [], 'go.mod': l:go},
        \   {'active': 'python', 'name': 'pkg', 'sources': ['pkg/'], 'languages': ['python', 'go']}],
        \ ['py-vim', {'setup.py': [], 'pkg/__init__.py': [], 'plugin/a.vim': []},
        \   {'active': 'python', 'name': 'pkg', 'languages': ['python', 'vim']}],
        \ ['go-vim', {'go.mod': l:go, 'plugin/a.vim': []},
        \   {'active': 'go', 'name': 'app', 'languages': ['go', 'vim']}]]
    let l:root = s:project(l:name, l:files)
    let l:answer = s:started_in(l:root, {'ask': s:messages})
    call s:answers(extend({'root': l:root}, l:expected), l:answer)
    call assert_notmatch('more than one language', l:answer.messages, l:name)
  endfor
endfunction

" g:project_name still names it all, and is Python's folder and no other's
function! s:suite.project_name_names_every_language() abort
  let l:root = s:project('named-py-go', {'requirements.txt': [], 'blog/__init__.py': [],
        \ 'other/__init__.py': [], 'go.mod': ['module example.com/app']})
  let l:answer = s:started_in(l:root, {'before': ['let g:project_name = "blog"'], 'ask': extend({
        \ 'go_sources': 'project_detect#parts()[1].sources'}, s:messages)})
  call s:answers({'active': 'python', 'name': 'blog', 'sources': ['blog/'], 'go_sources': [],
        \ 'languages': ['python', 'go']}, l:answer)
  call assert_notmatch('project_name', l:answer.messages)
endfunction

" A language found further up is a project around this one
function! s:suite.deepest_root_wins() abort
  let l:root = s:project('nested', {'go.mod': ['module example.com/app'],
        \ 'tools/pyproject.toml': ['[project]', 'name = "tool"']})
  call s:answers({'active': 'python', 'name': 'tool', 'root': l:root . '/tools', 'languages': ['python']},
        \ s:started_in(l:root . '/tools'))
endfunction

" Beside each other at the root: a file's extension says which it's in
function! s:suite.a_files_part_by_extension() abort
  let l:root = s:project('py-go-files', {'requirements.txt': [], 'pkg/__init__.py': [],
        \ 'go.mod': ['module example.com/app']})
  call s:answers({'py': 'python', 'go': 'go', 'pyi': 'python', 'readme': {}, 'outside': {},
        \ 'go_test': 1, 'py_test': 1, 'go_named_like_py': 0, 'current': 'go'},
        \ s:started_in(l:root, {'after': ['edit cmd/main.go'], 'ask': {
        \   'py': 'project_detect#part("pkg/a.py").language',
        \   'go': 'project_detect#part("main.go").language',
        \   'pyi': 'project_detect#part("x.pyi").language',
        \   'readme': 'project_detect#part("README.md")',
        \   'outside': 'project_detect#part(' . string(s:tmp . '/x.py') . ')',
        \   'go_test': 'project_detect#is_test("a_test.go")',
        \   'py_test': 'project_detect#is_test("test_a.py")',
        \   'go_named_like_py': 'project_detect#is_test("test_a.go")',
        \   'current': 'project_detect#part().language'}}))
endfunction

" One language: every file is in its part, wherever it is
function! s:suite.one_part_has_every_file() abort
  let l:root = s:project('one-part', {'go.mod': ['module example.com/app']})
  call s:answers({'readme': 'go', 'outside': 'go', 'none': {}},
        \ extend(s:started_in(l:root, {'ask': {
        \   'readme': 'project_detect#part("README.md").language',
        \   'outside': 'project_detect#part("/elsewhere/x.txt").language'}}),
        \ {'none': s:started_in(s:project('no-part', {}), {'ask': {'none': 'project_detect#part()'}}).none}))
endfunction

" A strategy of your own is a part too, after the built-in ones
function! s:suite.registered_type_is_a_part() abort
  let l:answer = s:started_in(s:project('mine-py-one', {'.mine': [], 'pyproject.toml': ['[project]', 'name = "p"']}),
        \ {'before': [s:mine]})
  call s:answers({'active': 'python', 'name': 'p', 'languages': ['python', 'txt']}, l:answer)
endfunction

function! s:suite.rust_crate() abort
  let l:root = s:project('rust-crate', {
        \ 'Cargo.toml': ['[package]', 'name = "my-crate"', 'version = "1.0.0"', '',
        \   '[dependencies]', 'name = "not-this"'],
        \ 'src/lib.rs': [],
        \ 'tests/cli.rs': [],
        \ })
  call s:answers({'active': 'rust', 'name': 'my-crate', 'language': 'rust', 'root': l:root,
        \ 'sources': ['src/'], 'tests': ['tests/', 'tests.rs'],
        \ 'integration': 1, 'unit_file': 1, 'code': 0},
        \ s:started_in(l:root, {'ask': {
        \   'integration': 'project_detect#is_test("tests/cli.rs")',
        \   'unit_file': 'project_detect#is_test("src/parser/tests.rs")',
        \   'code': 'project_detect#is_test("src/lib.rs")'}}))
endfunction

" A workspace names no package: its directory does. Its members can be globs
" (one place to search) or crates, on one line or several
function! s:suite.rust_workspace() abort
  let l:root = s:project('rust-ws', {
        \ 'Cargo.toml': ['[workspace]', 'resolver = "2"', 'members = [', '  "tools/one", # a comment',
        \   '  "crates/*",', ']', '', '[workspace.package]', 'name = "not-this"'],
        \ 'crates/a/Cargo.toml': ['[package]', 'name = "a"'],
        \ 'crates/a/tests/it.rs': [],
        \ 'crates/b/Cargo.toml': ['[package]', 'name = "b"'],
        \ 'crates/notes/README.md': [],
        \ 'tools/one/Cargo.toml': ['[package]', 'name = "one"'],
        \ })
  call s:answers({'active': 'rust', 'name': 'rust-ws', 'root': l:root,
        \ 'sources': ['tools/one/', 'crates/'], 'tests': ['crates/a/tests/', 'tests.rs']},
        \ s:started_in(l:root))
  call s:answers({'sources': ['crates/']},
        \ s:started_in(s:project('rust-ws-line', {
        \   'Cargo.toml': ['[workspace]', 'members = ["crates/*"]'],
        \   'crates/a/Cargo.toml': ['[package]', 'name = "a"']})))
endfunction

" Like ruff: a Rust workspace with a Python package at maturin's python-source,
" and Python under crates/ that is the Rust crates' test data
let s:rust_and_python = {
      \ 'pyproject.toml': ['[project]', 'name = "ruff"', '', '[tool.maturin]',
      \   'manifest-path = "crates/ruff/Cargo.toml"', 'module-name = "ruff"', 'python-source = "python"'],
      \ 'Cargo.toml': ['[workspace]', 'members = ["crates/*"]', '', '[workspace.package]', 'edition = "2024"'],
      \ 'crates/ruff/Cargo.toml': ['[package]', 'name = "ruff"'],
      \ 'crates/ruff/src/main.rs': [],
      \ 'crates/ruff/tests/cli.rs': [],
      \ 'crates/ruff_linter/Cargo.toml': ['[package]', 'name = "ruff_linter"'],
      \ 'crates/ruff_linter/src/lib.rs': [],
      \ 'crates/ruff_linter/resources/test/fixtures/test_rule.py': [],
      \ 'python/ruff/__init__.py': [],
      \ 'python/ruff/__main__.py': [],
      \ 'scripts/add_rule.py': [],
      \ 'playground/package.json': [],
      \ 'README.md': [],
      \ }

function! s:suite.rust_and_python() abort
  let l:root = s:project('rust-py', s:rust_and_python)
  call s:answers({'active': 'python', 'name': 'ruff', 'root': l:root,
        \ 'parts': [['python', ['python/ruff/'], s:python_tests],
        \   ['rust', ['crates/'], ['crates/ruff/tests/', 'tests.rs']]]},
        \ s:started_in(l:root, {'ask': {
        \   'parts': 'map(project_detect#parts(), "[v:val.language, v:val.sources, v:val.tests]")'}}))
endfunction

" Where a file is decides before its extension
function! s:suite.rust_and_python_files() abort
  let l:root = s:project('rust-py-files', s:rust_and_python)
  let l:fixture = 'crates/ruff_linter/resources/test/fixtures/test_rule.py'
  call s:answers({'fixture': 'rust', 'package': 'python', 'script': 'python', 'crate': 'rust', 'readme': {},
        \ 'fixture_is_test': 0, 'integration_is_test': 1, 'current': 'rust'},
        \ s:started_in(l:root, {'after': ['edit ' . l:fixture], 'ask': {
        \   'fixture': 'project_detect#part(' . string(l:fixture) . ').language',
        \   'package': 'project_detect#part("python/ruff/__main__.py").language',
        \   'script': 'project_detect#part("scripts/add_rule.py").language',
        \   'crate': 'project_detect#part("crates/ruff/src/main.rs").language',
        \   'readme': 'project_detect#part("README.md")',
        \   'fixture_is_test': 'project_detect#is_test(' . string(l:fixture) . ')',
        \   'integration_is_test': 'project_detect#is_test("crates/ruff/tests/cli.rs")',
        \   'current': 'project_detect#part().language'}}))
endfunction

" python-source says where the code is, so the name needs no folder
function! s:suite.project_name_needs_no_folder_with_python_source() abort
  let l:root = s:project('rust-py-named', s:rust_and_python)
  let l:answer = s:started_in(l:root, {'before': ['let g:project_name = "chosen"'], 'ask': s:messages})
  call s:answers({'name': 'chosen', 'sources': ['python/ruff/']}, l:answer)
  call assert_notmatch('project_name', l:answer.messages)
endfunction

" python-source alone, and a dotted module-name, are in the same place
function! s:suite.python_source_without_a_module() abort
  let l:root = s:project('maturin-source', {'pyproject.toml': ['[project]', 'name = "x"', '[tool.maturin]', 'python-source = "py"'],
        \ 'py/x/__init__.py': []})
  call s:answers({'sources': ['py/']}, s:started_in(l:root))
  let l:root = s:project('maturin-dotted', {'pyproject.toml': ['[project]', 'name = "x"', '[tool.maturin]',
        \ 'python-source = "py"', 'module-name = "pkg._native"'], 'py/pkg/__init__.py': []})
  call s:answers({'sources': ['py/pkg/']}, s:started_in(l:root))
endfunction

" Recognised by more than pyproject.toml
function! s:suite.python_recognised_by_its_files() abort
  for l:file in ['setup.py', 'setup.cfg', 'Pipfile', 'requirements.txt', 'tox.ini', 'manage.py', 'wsgi.py', 'app.py']
    let l:root = s:project('py-by-' . l:file, {l:file: [], 'blog/__init__.py': [], 'scripts/__init__.py': []})
    call s:answers({'active': 'python', 'name': 'blog', 'language': 'python', 'root': l:root, 'sources': ['blog/']},
          \ s:started_in(l:root, {'before': ['let g:project_name = "blog"']}))
  endfor
endfunction

function! s:suite.python_without_pyproject_named_after_its_only_package() abort
  call s:answers({'active': 'python', 'name': 'pkg', 'sources': ['pkg/']},
        \ s:started_in(s:project('py-setup-only', {'setup.py': [], 'pkg/__init__.py': []})))
endfunction

" A requirements.txt in docs/ isn't the project: setup.py above it is
function! s:suite.python_root_is_the_strongest_file() abort
  let l:root = s:project('py-docs', {'setup.py': [], 'docs/requirements.txt': [], 'pkg/__init__.py': []})
  call s:answers({'active': 'python', 'root': l:root, 'sources': ['pkg/']},
        \ s:started_in(l:root . '/docs'))
endfunction

" A given name skips looking for the declared one, even with a folder of its own
function! s:suite.project_name_skips_the_declared_name() abort
  let l:root = s:project('py-both', {'pyproject.toml': ['[project]', 'name = "declared"'],
        \ 'declared/__init__.py': [], 'mine/__init__.py': []})
  call s:answers({'name': 'mine', 'sources': ['mine/']},
        \ s:started_in(l:root, {'before': ['let g:project_name = "mine"']}))
endfunction

let s:messages = {'messages': 'execute("messages")'}
let s:two_packages = {'pyproject.toml': [], 'blog/__init__.py': [], 'scripts/__init__.py': []}

" A project's .vim.custom names it, as the dotfiles load it
function! s:suite.project_name_from_vim_custom() abort
  let l:root = s:project('py-custom', extend({'.vim.custom': ['let g:project_name = "blog"']}, s:two_packages))
  let l:answer = s:started_in(l:root, {'ask': s:messages})
  call s:answers({'active': 'python', 'name': 'blog', 'root': l:root, 'sources': ['blog/']}, l:answer)
  call assert_notmatch('project_name', l:answer.messages)
endfunction

" The name says which folder is the code: one that isn't there is a typo
function! s:suite.project_name_with_no_folder_is_an_error() abort
  let l:root = s:project('py-typo', extend({'.vim.custom': ['let g:project_name = "blgo"']}, s:two_packages))
  let l:answer = s:started_in(l:root, {'ask': s:messages})
  call s:answers({'active': 'python', 'name': 'blgo', 'sources': []}, l:answer)
  call assert_match('g:project_name "blgo"', l:answer.messages)
endfunction

function! s:suite.project_name_found_is_no_error() abort
  for [l:name, l:given, l:package] in [['py-src', 'blog', 'src/blog/__init__.py'],
        \ ['py-import', 'my-blog', 'my_blog/__init__.py']]
    let l:answer = s:started_in(s:project(l:name, {'pyproject.toml': [], l:package: []}),
          \ {'before': ['let g:project_name = ' . string(l:given)], 'ask': s:messages})
    call assert_notmatch('project_name', l:answer.messages, l:name)
  endfor
endfunction

" Only a name you give: a declared one needs no folder
function! s:suite.declared_name_with_no_folder_is_no_error() abort
  let l:root = s:project('py-declared', {'pyproject.toml': ['[project]', 'name = "declared"'],
        \ 'a/__init__.py': [], 'b/__init__.py': []})
  call assert_notmatch('project_name', s:started_in(l:root, {'ask': s:messages}).messages)
endfunction

" Go and Vim plugin projects aren't looked for by name
function! s:suite.project_name_of_another_language_is_no_error() abort
  for l:files in [{'go.mod': ['module example.com/app']}, {'plugin/a.vim': []}]
    let l:answer = s:started_in(s:project('other-' . keys(l:files)[0][0], l:files),
          \ {'before': ['let g:project_name = "chosen"'], 'ask': s:messages})
    call s:answers({'name': 'chosen'}, l:answer)
    call assert_notmatch('project_name', l:answer.messages)
  endfor
endfunction

" Empty is not a name: the project is named as if it weren't set
function! s:suite.empty_project_name_names_nothing() abort
  let l:root = s:project('py-empty', s:two_packages)
  call s:answers({'active': 'python', 'name': 'py-empty'},
        \ s:started_in(l:root, {'before': ['let g:project_name = ""']}))
endfunction

function! s:suite.go_from_a_subdirectory() abort
  let l:root = s:project('go mod', {
        \ 'go.mod': ['// comment', 'module github.com/u/app/v2', '', 'go 1.22'],
        \ 'cmd/app/main.go': [],
        \ })
  call s:answers({'active': 'go', 'name': 'app', 'language': 'go', 'root': l:root,
        \ 'sources': [], 'tests': ['*_test.go'],
        \ 'test': 1, 'code': 0},
        \ s:started_in(l:root . '/cmd/app', {'ask': {
        \   'test': 'project_detect#is_test("main_test.go")',
        \   'code': 'project_detect#is_test("main.go")'}}))
endfunction

function! s:suite.vim_plugin_from_a_subdirectory() abort
  let l:root = s:project('my-plugin', {
        \ 'autoload/my/plugin.vim': [],
        \ 'syntax/my.vim': [],
        \ 'after/ftplugin/my.vim': [],
        \ 'test/': [],
        \ 'tests/': [],
        \ 'doc/my.txt': [],
        \ })
  call s:answers({'active': 'vim', 'name': 'my-plugin', 'language': 'vim', 'root': l:root,
        \ 'sources': ['autoload/', 'syntax/', 'after/'], 'tests': ['test/', 'tests/']},
        \ s:started_in(l:root . '/doc'))
endfunction

function! s:suite.vim_plugin_with_plugin_only() abort
  let l:root = s:project('plugin-only', {'plugin/p.vim': [], 'autoload/': []})
  call s:answers({'active': 'vim', 'name': 'plugin-only', 'sources': ['autoload/', 'plugin/'],
        \ 'tests': []},
        \ s:started_in(l:root))
  " An autoload/ or plugin/ without Vim script isn't one
  call s:answers({'active': ''},
        \ s:started_in(s:project('no-script', {'plugin/README': [], 'autoload/x.txt': []})))
endfunction

" Parts are in a fixed order, and the first with a name gives it
function! s:suite.languages_in_order() abort
  let l:root = s:project('all-four', {
        \ 'pyproject.toml': ['[project]', 'name = "py"'],
        \ 'go.mod': ['module go'],
        \ 'Cargo.toml': ['[package]', 'name = "rs"'],
        \ 'plugin/x.vim': [],
        \ })
  call s:answers({'active': 'python', 'name': 'py', 'languages': ['python', 'go', 'rust', 'vim']},
        \ s:started_in(l:root))
  call delete(l:root . '/pyproject.toml')
  call s:answers({'active': 'go', 'name': 'go', 'languages': ['go', 'rust', 'vim']},
        \ s:started_in(l:root))
endfunction

function! s:suite.is_test() abort
  let l:root = s:project('py-tests', {
        \ 'pyproject.toml': ['[project]', 'name = "t"'],
        \ 't/core.py': [],
        \ 't/test_core.py': [],
        \ 't/core_test.py': [],
        \ 'tests/helpers.py': [],
        \ })
  call mkdir(l:root . '-other', 'p')
  call s:answers({
        \ 'current': 1, 'code': 0, 'glob': 1, 'suffix': 1, 'in_tests': 1, 'relative': 1,
        \ 'outside': 0, 'sibling': 0},
        \ s:started_in(l:root, {'after': ['edit tests/helpers.py'], 'ask': {
        \   'current': 'project_detect#is_test()',
        \   'code': 'project_detect#is_test("t/core.py")',
        \   'glob': 'project_detect#is_test(' . string(l:root . '/t/test_core.py') . ')',
        \   'suffix': 'project_detect#is_test("t/core_test.py")',
        \   'in_tests': 'project_detect#is_test(' . string(l:root . '/tests/helpers.py') . ')',
        \   'relative': 'project_detect#is_test("tests/new.py")',
        \   'outside': 'project_detect#is_test(' . string(s:tmp . '/test_x.py') . ')',
        \   'sibling': 'project_detect#is_test(' . string(l:root . '-other/test_x.py') . ')',
        \ }}))
  " Outside a project, nothing is
  call s:answers({'test': 0},
        \ s:started_in(s:project('no-tests', {'tests/test_a.py': []}),
        \   {'ask': {'test': 'project_detect#is_test("tests/test_a.py")'}}))
endfunction

" Once, at startup: a :cd elsewhere doesn't change it
function! s:suite.detected_once() abort
  let l:root = s:project('py-once', {'pyproject.toml': ['[project]', 'name = "once"']})
  let l:go = s:project('go-once', {'go.mod': ['module once-go']})
  call s:answers({'active': 'python', 'name': 'once', 'root': l:root},
        \ s:started_in(l:root, {'after': ['cd ' . fnameescape(l:go)]}))
  " Nor does starting outside one and moving into one
  call s:answers({'active': ''},
        \ s:started_in(s:project('none-once', {}), {'after': ['cd ' . fnameescape(l:go)]}))
endfunction

" A plugin asking before VimEnter gets the project of where Vim is then
function! s:suite.detected_when_first_asked() abort
  let l:root = s:project('py-first', {
        \ 'pyproject.toml': ['[project]', 'name = "first"'],
        \ 'first/__init__.py': [],
        \ })
  let l:elsewhere = s:project('elsewhere', {})
  for l:fn in ['active', 'name', 'parts', 'part', 'root', 'is_test']
    call s:answers({'active': 'python', 'root': l:root},
          \ s:started_in(l:root, {'before': [
          \   'call project_detect#' . l:fn . '()',
          \   'cd ' . fnameescape(l:elsewhere)]}))
  endfor
endfunction

let s:mine = 'call project_detect#register("mine", {"detect": {-> filereadable(".mine")'
      \ . ' ? {"name": "mine-proj", "root": getcwd() . "/", "language": "txt", "sources": ["lib/"]} : ""}})'

" A plugin's strategy, registered before startup: tried after the built-in
" ones; root, language, sources and tests have defaults
function! s:suite.register_a_project_type() abort
  let l:root = s:project('mine', {'.mine': []})
  call s:answers({'active': 'mine', 'name': 'mine-proj', 'language': 'txt', 'root': l:root,
        \ 'sources': ['lib/'], 'tests': []},
        \ s:started_in(l:root, {'before': [s:mine]}))
  " A name alone
  call s:answers({'active': 'bare', 'name': 'bare-proj', 'language': '', 'root': l:root,
        \ 'sources': [], 'tests': []},
        \ s:started_in(l:root, {'before': [
        \   'call project_detect#register("bare", {"detect": {-> "bare-proj"}})']}))
  " Built-in ones first
  call s:answers({'active': 'python'},
        \ s:started_in(s:project('mine-py', {'.mine': [], 'pyproject.toml': ['[project]', 'name = "p"']}),
        \   {'before': [s:mine]}))
endfunction

" A strategy finding a project without a name: only g:project_name names it
function! s:suite.register_a_nameless_project_type() abort
  let l:nameless = 'call project_detect#register("nameless", {"detect": {-> {"name": "", "sources": ["s/"]}}})'
  let l:root = s:project('nameless', {})
  call s:answers({'active': ''}, s:started_in(l:root, {'before': [l:nameless]}))
  call s:answers({'active': 'nameless', 'name': 'given', 'sources': ['s/']},
        \ s:started_in(l:root, {'before': ['let g:project_name = "given"', l:nameless]}))
endfunction

" Registered under a built-in name: replaces it, in its place
function! s:suite.register_replaces_a_built_in() abort
  let l:root = s:project('replaced', {
        \ 'pyproject.toml': ['[project]', 'name = "py"'],
        \ 'go.mod': ['module go'],
        \ })
  call s:answers({'active': 'python', 'name': 'other', 'language': 'python3'},
        \ s:started_in(l:root, {'before': [
        \   'call project_detect#register("python", {"detect": {-> {"name": "other", "language": "python3"}}})']}))
  call s:answers({'active': 'go'},
        \ s:started_in(l:root, {'before': [
        \   'call project_detect#register("python", {"detect": {-> ""}})']}))
endfunction

" Registered after detection found nothing: detects again, from where Vim is
" then; after it found a project, the project stays
function! s:suite.register_after_startup() abort
  let l:late = s:project('late', {'.mine': []})
  call s:answers({'active': 'mine', 'name': 'mine-proj', 'root': l:late},
        \ s:started_in(s:project('late-none', {}), {'after': ['cd ' . fnameescape(l:late), s:mine]}))
  let l:py = s:project('late-py', {'pyproject.toml': ['[project]', 'name = "p"']})
  call s:answers({'active': 'python', 'root': l:py},
        \ s:started_in(l:py, {'after': ['cd ' . fnameescape(l:late), s:mine]}))
endfunction
