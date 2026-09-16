# Changelog

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
