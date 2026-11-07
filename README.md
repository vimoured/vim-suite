# vim-suite

Integration tests that pin what [roumail/dotfiles](https://github.com/roumail/dotfiles)
uses of roumail's Vim plugins. Each spec loads the real dotfiles config with
every plugin on the runtimepath, then drives the plugins the way that config
reaches them.

The frozen plugins get no new features. Their code is cut back to the least
that keeps this suite green.

## Running it

Needs Vim 9.0 or newer and git.

```sh
bin/fetch     # shallow-clone everything in plugins.txt into deps/
bin/test      # every spec, then each live plugin's own test/run.vim
bin/test test/buffer-tools.vim     # one spec
```

`bin/fetch` clones each repository's default branch, and on a later run
updates it to that branch's latest commit. `deps/` is not committed.

### Environment

| Variable         | Effect                                                              |
| ---------------- | ------------------------------------------------------------------- |
| `SUITE_DEPS`     | where the checkouts are (default `deps/`)                           |
| `SUITE_SKIP`     | regex of startup files not to source, to find what breaks a spec    |
| `SUITE_PROFILE`  | a directory: write a `:profile` of the frozen plugins per spec      |

## What's in it

| Path                    | What                                                                   |
| ----------------------- | ---------------------------------------------------------------------- |
| `plugins.txt`           | every repository checked out, with its role (config, runner, upstream, frozen, live) |
| `bin/fetch`, `bin/pin`, `bin/test`, `bin/coverage` | check out, pin one plugin at a commit, run, list lines never run |
| `test/<plugin>.vim`     | the spec of one frozen plugin                                          |
| `test/dotfiles.vim`     | the config loads without an error                                      |
| `test/known-failures.txt` | tests failing because of a known, not yet fixed bug                  |
| `test/helper/env.vim`   | loads the dotfiles' `vim-rc/` and every plugin in a private `HOME`     |
| `test/helper/startup.vim` | starts Themis after Vim's startup, so `'autoread'` reloads happen    |
| `test/helper/autoload/` | a no-op vim-plug, and an `fzf#run` that records its spec in `g:suite.fzf` |
| `test/bin/`             | `fzf` and `gh` stand-ins                                               |
| `test/stub/`            | the colorscheme the dotfiles name                                      |

## Writing specs

A spec tests entrypoints, the way a real caller reaches the plugin:

- keys, as the dotfiles map them (`<leader>bc`), and the plugin's own default keys (`gb`)
- commands, including their completion
- `<Plug>` maps
- autocommand events
- autoload functions that the dotfiles or another plugin call, called the way that caller calls them

It asserts on what a user or caller can observe: buffers, windows, files,
registers, quickfix and location lists, messages. It doesn't call a function
that nothing outside the plugin calls. Coverage decides what code is removed,
so a spec that calls an internal function would keep that code alive.

When a spec finds a bug, it keeps asserting the right behaviour and the test
goes in `test/known-failures.txt` (`<suite> <test>`, as the TAP report names
it, under a comment naming the bug). `bin/test` still runs and reports it but
doesn't fail on it, so the gate stays usable. Any other failure, or a spec
that stops early, fails the run. A listed test that passes gets a warning: if
its bug is fixed, take it off the list.

### Coverage

`bin/coverage [plugin...]` runs the suite under Vim's `:profile` and lists the
frozen plugins' lines that never ran: the code no spec reaches, which is
what gets cut. Vim records only when a line runs, so an autocmd body, a
mapping's right-hand side or a command body written outside a function counts
as run once it's defined; those lines are listed apart, as not measured.
Check them, and any new spec, by breaking the feature in `deps/<plugin>` and
seeing a test that counts fail (a known failure guards nothing), then
`git -C deps/<plugin> checkout -- .`.

Each spec builds its own fixtures and doesn't rely on state another test left.
A spec that needs Vim started inside a project creates the project and `cd`s
into it before sourcing `env.vim`, because project-detect looks only once, at
`VimEnter`.

## CI

The suite gates every plugin's pull requests. Each plugin calls the reusable
workflow `.github/workflows/suite.yml` from its own:

```yaml
# .github/workflows/suite.yml in the plugin
on: pull_request
jobs:
  vim-suite:
    uses: vimoured/vim-suite/.github/workflows/suite.yml@main
```

It runs `bin/fetch`, then `bin/pin` to put that plugin at the pull request's
head commit, then `bin/test`. All the repositories are public, so it uses no
token.

Each plugin's repository has a ruleset made from `ruleset.json`: on the
default branch, a pull request and the `vim-suite / suite` check are
required, and force-pushes and deletion are blocked, with no bypass:

```sh
gh api -X POST repos/vimoured/<plugin>/rulesets --input ruleset.json
```

Pushes to this repository run nothing. Check changes locally with `bin/test`
before pushing them; to run CI by hand, against every plugin's `main`, use
*Run workflow* on the Actions tab.

To test a plugin commit locally the way CI does:

```sh
bin/fetch && bin/pin buffer-tools <commit> && bin/test
```
