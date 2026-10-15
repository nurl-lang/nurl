# Changelog

## [0.4.0] — 2026-10-14

### Changed

- 8 `unsafe` functions left of 90, all of them process control the
  standard library has no safe form of: the shell's fork / pipe / exec
  and waitpid, `find -exec`, `xargs` and `env`'s exec.
- The shell's state is one value its `sh` run owns and lends `inout` to
  the interpreter, where it was a raw word in a global read back through
  `arc_ptr` — nothing tied it to the state's owner, and a nested `sh`
  (an applet run from a script) swapped it by hand.
- Strings are appended with `string_append` / `string_push_window` and
  written with `write_slice` (NUL-exact, checked) instead of a raw
  pointer and a length; `od`, `hexdump`, `xxd`, `strings` and `tr` read
  their input and tables through checked byte views.
- `whoami`, `id`, `groups`, `test -O/-G` and `ln` use the standard
  library's `proc_self_*` and `fs_link` instead of declaring libc's
  `getuid` / `getgroups` / `link` themselves; `getgroups` was read back four
  bytes at a time through a raw pointer.
- `grep -F` and `sed` hold a real `Regex` (compiled from `^`) in a slot
  that needs none, where a zero bit pattern posed as one.
- The applet hook (`bx_dispatch_set`) is a `Locked` global set at start; a
  dispatch copies the closure out and runs it unlocked, so an applet may
  dispatch again.

The busybox differential gives the same result as 0.3.5 (347 of 348, the
one difference `ls`'s exit status for a missing entry, 2 as GNU against
busybox's 1). `tr`, `grep -F`, `od` and `sed` on 32 MB run as fast or
faster (125/145/846/2827 ms against 127/154/893/2817).

## [0.3.5] — 2026-10-14

Requires NURL 0.73.0 (`slice_at`, `slice_put`, `rc_take`, `locked_take`).

### Changed

- Loops that read or wrote through `vec_data` pointers index slices (`slice_at` / `slice_put`, as fast as the pointers), and functions with nothing raw in them are no longer marked `unsafe`.
- 11 fewer functions are `unsafe` than in 0.3.4 (90 left).

## [0.3.4] — 2026-10-12

Requires NURL 0.73.0, in which a field written through a raw pointer
drops what it held, a mutable module global may own a `String`, a `Vec`
or a handle, and a foreign function may take an `inout` parameter.
The published 0.3.3 does not compile under it.

### Changed

- The zero `Regex` handles `sed` and `grep` keep until a pattern is
  compiled are built with the cast `# Regex # s 0`: a standard-library
  handle now holds its state in a `( Shared T )`.
- The dispatch table is a module global that owns it, where it was raw
  memory kept as an address.

## [0.3.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.3.2 does not compile under it.

### Changed

- `ShState` keeps its state in an `Arc` (stdlib/std/arc.nu) instead of an
  `rcbox`. The share and drop hooks are ordinary safe functions — the Arc
  does the counting — and so are the constructors that build one from a
  whole value; every copy is still the same state, and its last owner
  releases it.
- Its `--version` (or the version it reports) is read from `nurl.toml`
  with `( pkg_version )` instead of being written by hand, so it can no
  longer drift from the manifest.
- `bx_dispatch_set` is `unsafe`: it keeps the dispatch table in an `rcbox`
  behind a module global, which NURL 0.73.0 allows only in `unsafe` code.

## [0.3.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.3.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. Output is written with `write_string`, where
`nurl_print_bytes` took a raw pointer and a length. No change in
behaviour.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

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
