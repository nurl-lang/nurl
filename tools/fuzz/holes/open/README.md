# tools/fuzz/holes/open — soundness holes known open

**None.** Every probe this directory held is closed and graduated to the CI
gate in the parent directory. The most recent were `h288`–`h298`, found
building a multi-threaded database (`packages/nurldb`): a helper lending an
`Arc`'s payload unfrozen through a struct, a foreign write into a frozen
view, a lock guard held in a struct never released, drops a panic skipped
or kept registered, a temporary or a thread's message a panic leaked, and a
parameter's copy passed `inout` to a function that replaces one of its
fields, and a closure replaced through an `inout` parameter or handed a
captured binding to one.

A probe here is **safe code** (no `unsafe` function of its own, no raw
memory or FFI of its own) that the compiler still **accepts** and that then
leaks, frees memory it does not own, frees memory twice or reads freed
memory under ASan/LSan/UBSan: a known issue of the release, listed in
[`docs/MEMORY.md` §6.2](../../../../docs/MEMORY.md) beside the guarantee
until it is closed. Each file's header starts with `// OPEN in <version> —
…` and says what the program does, why it is unsound and what the sanitizer
reports.

Probes here are kept **out of the CI gate**: `../check.sh` with no arguments
runs only `h*.nu` (and `stdlib/h*.nu`) in the parent directory, where every
probe must be REJECTED or run clean. Run these by hand:

```sh
cd tools/fuzz/holes
./check.sh open/*.nu        # reports each as HOLE
```

A probe that prints REJECTED or ACCEPTED (ran clean) here has been closed —
graduate it (below).

## Closed

The 34 probes the 0.72.0 release review left open are closed and graduated
as h145–h178 (h178 under `stdlib/`: it must sit in a directory named
`stdlib`); h142–h144 were closed before them, and h179, a view stored into a
field of a struct that outlives it, was found and closed on the way:

| Class | Probes | How it is closed |
|---|---|---|
| raw string handed to `string_adopt` / a `sink s` | h161–h170 | In safe code only a declared `sink` takes a raw string over, and its callee releases it like a local; a caller hands over its own string, or a copy of anything else (MEMORY.md §1) |
| a view leaving through a call's result | h174–h177 | A returned call result that may lend a released string is the caller's own (the callee's string, or a copy); a call's result holds views of what the callee lends, stores or hands back inside it |
| a view stored into what the caller holds | h171–h173 | Storage the caller holds (a parameter, an alias of one, an `inout` struct) may not keep a view of a binding released here; a field store records the view |
| `mem_forget` / `mem_take` / `rcbox_*` in safe code | h151–h160 | `unsafe` only (spec §3.3d) |
| destructors | h146–h150 | A disposer's parameter drops by its drop glue; a value leaves the journal before its destructor runs, which journals its receiver's glue; a replaced receiver field is released; a closure in an impl has no destructor context |
| closure call with a fresh string | h145 | Released after the call |
| trust by `/stdlib/` path | stdlib/h178 | Only a file inside the real standard-library tree is trusted |

## Graduating a probe

When a fix makes a probe REJECTED, or makes it run clean under the
sanitizers, move it to `tools/fuzz/holes/` as the next free number
(`ls ../h*.nu` for the highest in use), with a one-line `// H<NNN>: …`
header in the style of the others. The CI step "Soundness hole probes"
(`./tools/fuzz/holes/check.sh`) then holds it: a later change that reopens
the hole fails the build. Then update this README and the open-hole lists in
`docs/MEMORY.md` §6.2 and `docs/LIMITATIONS.md`.
