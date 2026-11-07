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
| `SUITE_REPORTER` | Themis reporter (default `dot`; `spec` lists each test)             |
| `SUITE_SKIP`     | regex of startup files not to source, to find what breaks a spec    |
| `SUITE_PROFILE`  | a directory: write a `:profile` of the frozen plugins per spec      |

## What's in it

| Path                    | What                                                                   |
| ----------------------- | ---------------------------------------------------------------------- |
| `plugins.txt`           | every repository checked out, with its role (config, runner, upstream, frozen, live) |
| `bin/fetch`, `bin/test` | check out, run                                                         |
| `test/<plugin>.vim`     | the spec of one frozen plugin                                          |
| `test/dotfiles.vim`     | the config loads without an error                                      |
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

Each spec builds its own fixtures and doesn't rely on state another test left.
A spec that needs Vim started inside a project creates the project and `cd`s
into it before sourcing `env.vim`, because project-detect looks only once, at
`VimEnter`.

## CI

`.github/workflows/suite.yml` runs `bin/fetch` and `bin/test` on every push to
this repository and on demand, against every plugin's `main`. All the
repositories are public, so it uses no token.
