# ADR 0003 — The compiler stays one file

Status: accepted (2026-11-13)

## Context

`compiler/nurlc.nu` is the whole self-hosting compiler in one source
file. On 2026-11-13 (main `fb44b3092`) it was 99,201 lines: 2,877
functions, 1,763 of them file-private (`__`), and 807 mutable globals.
It grows fast (56,991 lines on 2026-10-15, 72,591 on 2026-11-01), so
"split it into modules: lexer, parser, types, borrows, codegen" keeps
suggesting itself. It was weighed against what a split would buy.

A split buys less than the word "modules" suggests:

- **A module would be a file, nothing more.** `$` is a textual include.
  There is no interface between files and no separate or incremental
  compilation: the same program, compiled in the same time.
- **There are no layers to cut along.** The compiler is one fused walk
  (`docs/dev/COMPILER_INTERNALS.md` §1): parsing a construct, checking
  it, deciding its drops and emitting its IR happen in the same
  functions. A cut into twelve files at the existing `// ──` section
  boundaries leaves about 700 file-private functions, 650 other
  functions and 650 globals and constants used across a file boundary,
  and more than a thousand references running from an earlier file into
  a later one. The boundaries would run through the call graph, not
  around parts of it.
- **Finding code is not the problem.** An agent reads the file through
  search and ranged reads just as it would read twelve files, and a
  person changing a rule follows the same calls through the same
  sections either way. Merge conflicts happen per hunk, not per file.

And it costs more than moving text:

- **Order is meaning.** A global must be declared above its first use,
  in include order just as in one file. A call to a function compiled
  later takes a different path from a call to one already compiled: its
  answer waits on a note settled at the end of the module. #1798 fixed a
  use-after-free that appeared only when a forwarder was declared above
  its callee. Grouping code by concern, the step that would make the
  files' names true, is a reordering, and a reordering can change the IR
  and the diagnostics.
- **File-private names stop resolving.** A `__` function is private to
  its file. Called from another file it raises a warning, and the
  bootstrap fails on warnings, so every one that crosses a cut has to be
  renamed first.
- **Everything else stops while it lands.** 387 of the 922 commits on
  main in the 30 days before this decision touched `compiler/nurlc.nu`.
  Every open branch that touches it conflicts with a split as a whole.
- **The toolchain assumes one file.** The bootstrap snapshot refresh
  (`build.sh --refresh-bootstrap`), `tools/tree_sweep.sh`'s export of a
  base commit, the wasm build through the API (`buildwasm.sh`), the
  unikernel self-host gates, the language server, the source gates
  (`tools/check_bck_writes.sh` and others) and the CI path filter of the
  compiler's leak gate all name the one file. Some of them would go on
  passing on a split compiler without checking it.
- **A partial split is the worst case.** The first file moved out pays
  all of the cost above and brings one file's worth of benefit.

## Decision

`compiler/nurlc.nu` stays one file. It is organised by its `// ──`
section headers, in source order (`grep -n '^// ──' compiler/nurlc.nu`
lists them), and mapped by `docs/dev/COMPILER_INTERNALS.md`.

## Consequences

- Tools, gates and CI may go on assuming one compiler file. They name
  it directly: `git grep -l 'compiler/nurlc.nu'` is the list to work
  through if this is ever reversed.
- Reopen this for a real reason, for example:
  - NURL gets separate or incremental compilation, so that a file is a
    unit a build can skip;
  - the compiler gets phases with a data structure between them (an AST
    between parsing and code generation, the long-term direction in
    `COMPILER_INTERNALS.md`); its modules then follow the phases instead
    of being cut out of one walk;
  - a tool the project depends on cannot handle the file's size.
- If it is reopened, the split comes in steps. First rename the `__`
  functions that would cross a cut, still in one file. Then make the
  tools and CI read several files. Then cut in source order with nothing
  moved, proven by the files, concatenated in import order, being the
  old file byte for byte, and by the IR being the same up to the file
  ids in file-private names (`__x__fpN`). Only after that regroup, one
  move per pull request.
