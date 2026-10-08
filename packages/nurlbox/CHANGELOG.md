# Changelog

## [0.3.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.3.0 does
not compile under 0.71.0.

## [0.3.0] — 2026-10-03

Requires NURL 0.69.0.

Nothing is released by hand any more.

- Every `string_free`, `vec_free`, `vec_free_with`, `bx_opts_free`,
  `path_free`, `regex_free`, `tar_entries_free` and `rng_free` call is gone
  (525 calls), and so are the package's own release helpers (`bx_opts_free`,
  `bx_free_lines`, the `__*_free` functions of `ls`, `cut`, `grep`, `mount`,
  `sed`, `dd` and the shell): every one only released what the compiler now
  drops at the end of its owner's scope.
- The shell's state was a `nurl_alloc`'d block reached through a global and
  freed by hand. It is now a handle (`ShState`, over an rcbox) that `sh`
  owns; the global only points at the innermost running shell's state.
  Fixed: an in-process `sh -c …` run from a script (`sh -c 'sh -c "echo
  inner"; echo outer'`) set the outer shell's state pointer to null when it
  returned, and the outer shell crashed on its next command. Each run now
  gets its own state and hands the outer one back.
- `set` and function calls replaced the positional parameters with a store
  through the state pointer, which never dropped the old ones; they now
  empty the list in place.
- `tr`'s byte tables and the `waitpid` / `pipe` / `execvp` / `getgroups`
  scratch buffers are owned `Vec`s instead of `nurl_zalloc` blocks freed by
  hand; the applet-dispatch hook is an rcbox the global owns.
- `grep -i` lowers each line into one reused buffer instead of a fresh
  String per line: 6.4 % fewer instructions on a 200 000-line file. The other
  applets measured (`grep`, `sed`, `sort`, `uniq`, `wc`, `cut`, `tr`,
  `md5sum`, `find`, `du`, `ls -lR`, a `sh` loop) are within ±0.3 % or better
  (`sh` −1.3 %), with identical output.

## 0.2.1

The shell applet no longer reaches into the program's entry point, and the
free functions take a **`sink`**.

`src/sh.nu` called `bx_run_applet` — the dispatch table in `src/main.nu` that
names every applet there is. The publish gate typechecks every module ALONE,
and a library module cannot import the entry point without making a circle,
so this package could not be published at all. `main.nu` now hands the table
over as a value at startup (`bx_dispatch_set`) and the shell calls what it was
given; `bx_is_applet` and the applet-name list move to `bx.nu` beside it. Five
other modules gained the imports they were resolving through some other file's
`$` lines.

The `sink` half is the ownership hardening in toolchain 0.65.0 (#1107): a free
function must consume the handle it releases. That landed in the monorepo and
this package was never republished, so the registry has been serving 0.2.0
with different source ever since.

No behaviour changes: 348 tests pass, including the shell section that runs
applets through the new hook.
