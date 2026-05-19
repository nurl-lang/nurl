# DWARF Debug Info — Phased Implementation Plan

> **Status (2026-05-19): Phases 0, 1, 2+3, 4, 5, 6, 8, 9, 10 landed.**
> Phase 7 (generic + trait subprogram-line-number refinement) deferred —
> the basic generic path already produces per-instantiation
> `!DISubprogram` entries with mangled names via the existing
> `gen_fn_decl_concrete` path; only the original-decl source line is
> still pointed at `<generic>:1` instead of the source file.
> Composite-type rendering (`!DICompositeType` for `%Vec` / `%String`
> / user structs) is the open Phase 6 follow-up; base types
> (`i`/`u8`/`b`/`f`/`s`) render correctly today.
>
> Build a debug binary with `./nurl.sh --debug foo.nu`, then drive
> with `gdb` / `lldb`. End-to-end regression: `./tools/dwarf_test.sh`.

This document is the work-list for landing full DWARF debug-info
support in NURL. It is sized to be picked up across multiple sessions
— each phase is independently testable, leaves the tree green, and
documents what the previous phase needed to set up.

The goal: a `nurlc -g foo.nu` build whose binary works with `gdb` /
`lldb` for source-level breakpoints, single-stepping by `.nu` source
line, `backtrace` showing NURL function names and line numbers,
`print x` showing local variables by name and type, and ASan / panic
crash backtraces resolving to the actual `.nu` source location.

---

## Why this is bigger than it looks

LLVM's IR verifier is strict about debug info: emitting
`!DISubprogram` for a function makes per-call `!dbg` attributes
mandatory on EVERY `call` instruction in that function. Drop one and
the verifier rejects the whole module.

`compiler/nurlc.nu` (7700+ LOC) emits IR by direct
`( nurl_print \`call ...\` )` calls — about **211 instruction-level
emit sites** scattered across `gen_*` functions, of which ~9 are
calls and the rest are `alloca` / `store` / `load` / `getelementptr`
/ `br` / arithmetic / phi. Most don't strictly need `!dbg` (the
verifier is lenient on non-call non-terminator instructions), but the
ones that do need it have to be reachable from a central emitter
that knows the current source location.

So the first real prerequisite is a small refactor of the IR emit
pipeline, not DWARF metadata itself. **Phase 0 must land first.**

---

## Phase 0 — Compiler refactor: centralized emit

**Goal:** every `nurl_print \`call ...\`` site goes through a single
`emit_call` helper. Every non-call instruction goes through
`emit_inst`. Both ignore their `!dbg` argument when DWARF is disabled,
so this phase is a no-op behaviourally — bootstrap fixed point should
hold byte-for-byte.

**Why bother:** any later phase that wants to attach `!dbg !N` to a
call only has to update the helper, not chase 9+ scattered emit
sites. Same for stores (LLVM accepts non-call stores without `!dbg`
even under DISubprogram, but `llvm.dbg.declare` intrinsics are calls
that DO need `!dbg`).

**Scope:**

- New helpers in `compiler/nurlc.nu`:
  - `@ emit_call s call_form → v` — prepends `  ` and emits the
    instruction line. When `g_dbg_enabled` is set, appends
    `, !dbg !N` where N is the current location id.
  - `@ emit_inst s inst_form → v` — same shape but for non-call
    instructions (alloca, store, load, gep, br, icmp, phi,
    extractvalue, insertvalue, ret, …). Currently `emit_inst` is a
    thin wrapper around the existing `emiti`; later phases will
    decide which instruction families actually want `!dbg`.
  - `@ emit_call_term s inst_form → v` — for `ret` and conditional
    `br` (terminators), which MUST have `!dbg` under DISubprogram.

- Refactor all 211 instruction-level `nurl_print` sites to use one of
  the three helpers. Most are mechanical search-and-replace.

- Verification:
  - `./build.sh` — bootstrap fixed point holds byte-for-byte (no
    DWARF emitted yet, so IR is identical to pre-Phase-0).
  - `./build.sh --san` — sanitizer suite still green.
  - Run an example program: same `.ll` output diff = 0.

**Risk:** the bootstrap fixed point check is byte-comparison of IR.
Even cosmetic whitespace differences will break it. Drive each
mechanical change as a separate audit, then re-run the build.

**Estimated effort:** ~400 LOC moved, ~3-4h focused work.

**Acceptance:** bootstrap fixed point holds; sanitizer green;
nurlfmt round-trip green.

---

## Phase 1 — Module-level metadata (DICompileUnit + DIFile)

**Goal:** `nurlc -g foo.nu` emits the minimum DWARF top-matter so
`gdb foo` knows where `foo.nu` lives. No per-function or per-
instruction metadata yet; the verifier accepts a module that has a
`!llvm.dbg.cu` referencing a `DICompileUnit` without any
`DISubprogram` attached.

**Scope:**

- Global state in `nurlc.nu`:
  - `: i g_dbg_enabled 0` — flipped to 1 by a new `--g` / `-g` CLI
    flag in `main`.
  - `: i g_dbg_next_id 100` — metadata-id allocator. Starts at 100
    to avoid colliding with any existing module-flag ids the
    compiler might use later.
  - `: i g_dbg_blob_syms 0` — sym handle (in the existing
    `nurl_sym_*` style) buffering metadata lines that flush at
    end-of-module.
  - `: i g_dbg_file_id 0` — the !DIFile id for the source file, set
    once at startup.
  - `: i g_dbg_cu_id 0` — the !DICompileUnit id.

- Helpers:
  - `@ dbg_alloc_id → i` — increment + return.
  - `@ dbg_emit s line → v` — append the metadata line to the blob.
  - `@ dbg_emit_module_flags → v` — emit the `!llvm.module.flags`
    triple (Dwarf Version 4 + Debug Info Version 3 + wchar_size 4).
  - `@ dbg_emit_compile_unit s file s dir → i` — emit DIFile +
    DICompileUnit, return the CU id.
  - `@ dbg_flush → v` — emit the entire blob at end-of-module
    (called from `main` after `flush_deferred_instantiations`).

- CLI:
  - `nurlc --g foo.nu` toggles `g_dbg_enabled = 1`. Document the
    flag in `nurlc`'s usage line.
  - `nurl.sh` accepts `--debug` → passes `--g` to nurlc AND adds
    `-g` to the clang link line (clang's `-g` triggers DWARF
    line-table generation for runtime.o, which we DO want even
    when DWARF isn't yet generated for user code).

**Verification:**
- `nurlc --g examples/hello.nu | grep -c '!DICompileUnit'` = 1
- `nurlc examples/hello.nu` (no flag) → identical IR to v0.7.x
  (bootstrap fixed point holds).
- `nurlc --g examples/hello.nu > /tmp/h.ll && clang /tmp/h.ll ... -o /tmp/h && gdb -batch -ex 'info source' /tmp/h | grep hello.nu`
  should print the source file path.

**Acceptance:** module-level DWARF emits; bootstrap (without `--g`)
unchanged; `gdb info source` resolves the .nu file.

**Estimated effort:** ~200 LOC, 2h.

---

## Phase 2 — Per-function DISubprogram + Phase 3 per-call !dbg
**(must land together)**

**Goal:** every emitted function carries a `!DISubprogram` referencing
its source line; every call inside it carries `!dbg !N`. Line numbers
on backtraces ARE the function's first line (not per-statement; that's
phase 4). gdb `break my_fn` works at source-line granularity.

**Why fused:** as soon as ANY function has !DISubprogram, the verifier
demands `!dbg` on EVERY call in that function. So Phase 2 cannot ship
without Phase 3 unless we want to break the build.

**Scope:**

- `gen_fn_decl_concrete`:
  - At function-entry, allocate a DISubprogram id, emit the
    `!DISubprogram(name: "X", scope: !file, file: !file, line: N, …)`
    metadata line.
  - Append `!dbg !N` to the `define` line. The compiler currently
    emits `define <ret_ty> @<name>(<params>) {`; this becomes
    `define <ret_ty> @<name>(<params>) !dbg !N {`.
  - Set `g_dbg_current_subprogram` = N for the rest of the function
    body's emission.
  - Allocate an initial !DILocation pointing at the function's
    declaration line, set `g_dbg_current_loc` = M.

- `emit_call` (introduced in Phase 0) now appends `, !dbg !M` when
  `g_dbg_enabled` AND we're inside a function (i.e.
  `g_dbg_current_loc != 0`).

- `emit_call_term` (for `ret`, `br i1`) — same treatment. Required
  by the verifier.

- `gen_ret`: before emitting `ret`, refresh `g_dbg_current_loc` to
  the source line of the `^` token. (Lexer already exposes line/col;
  `( nurl_lex_line lex )` returns the current line. We need to
  snapshot it at the `^` token boundary, which is consumed in
  `gen_ret`'s first action.)

- Generic instantiations: each `@ id [T] ...` instantiation gets its
  OWN DISubprogram with a mangled name + the original source line.
  `emit_one_instantiation` is the integration point.

- Closures (`\ params → ret { body }`): each gets a DISubprogram too,
  named like `<enclosing_fn>::__closure_N`. Anonymous in source, so
  the name is synthetic.

**Verification:**
- `nurlc --g examples/hello.nu | clang -g - ... -o /tmp/h`
- `gdb -batch /tmp/h -ex 'break main' -ex 'run' -ex 'backtrace'` —
  hits the breakpoint, backtrace shows `main` at `hello.nu:N`.
- LLVM verifier (clang's `-S -emit-llvm` pipe) accepts the IR
  without errors.

**Risks:**
1. Closures + traits add complexity — closure synthesized fns are
   emitted via `defer_closure_def` in a deferred pass. Need to
   thread the `g_dbg_current_subprogram` through.
2. `--g` builds slower because every emit calls `nurl_str_int`.
   Acceptable cost.

**Acceptance:** `gdb break <fn> + run + backtrace` works on every
example in `examples/`. Bootstrap (without `--g`) byte-identical.

**Estimated effort:** ~400 LOC, 4-6h. This is the largest single
phase.

---

## Phase 4 — Per-statement DILocation

**Goal:** `gdb` `step` / `next` advances one NURL source line at a
time. `break foo.nu:42` puts a breakpoint on a specific line.
Backtrace shows the line where the call happened, not the function's
declaration line.

**Scope:**

- `gen_stmt` prologue: snapshot `( nurl_lex_line lex )` and
  `( nurl_lex_col lex )` for THIS statement's first token. Allocate
  a !DILocation id, emit
  `!DILocation(line: N, column: M, scope: !current_subprogram)`,
  update `g_dbg_current_loc`. This is the location every
  `emit_call` / `emit_call_term` inside this gen_stmt will see.

- `gen_block_expr` / `gen_block_stmts` / `gen_block_ret` — track
  lexical scope:
  - Each block gets its own `!DILexicalBlock(file: …, line: N,
    column: M, scope: <enclosing>)`.
  - DILocations inside the block point at this block's scope rather
    than the enclosing subprogram, so gdb knows that a `:`-binding
    introduced inside a `{ ... }` goes out of scope at `}`.

- `gen_match` / `gen_cond`: each arm gets its own DILexicalBlock so
  arm-local bindings are scoped correctly.

**Verification:**
- `gdb -batch /tmp/h -ex 'break hello.nu:5' -ex 'run' -ex 'where'`
  resolves to line 5 of the source.
- `step` advances exactly one source line; `next` skips over calls.
- `disas /m main` shows interleaved `.nu` source + LLVM IR.

**Acceptance:** every line in `examples/static_server.nu` is
breakable via `break static_server.nu:N`. `step` walks source
lines.

**Estimated effort:** ~300 LOC, 3-4h.

---

## Phase 5 — Local variables (`!DILocalVariable` + `llvm.dbg.declare`)

**Goal:** `gdb` `print x` shows local variables by NURL name with
their NURL type rendered. `info locals` lists everything in scope.

**Scope:**

- `gen_let_or_struct` (after the alloca + store):
  - Allocate a `!DILocalVariable(name: "x", arg: 0, scope: !block,
    file: !file, line: N, type: !T)` id. T comes from the type
    table (Phase 6).
  - Emit a `call void @llvm.dbg.declare(metadata <ptr-to-alloca>,
    metadata !V, metadata !DIExpression())` intrinsic right after
    the `store`.
  - Both have to go through `emit_call` because they're calls, and
    `llvm.dbg.declare` itself MUST carry `!dbg !current_loc`.

- `gen_fn_decl_concrete` parameter walk: for each function param,
  emit a `!DILocalVariable(name: "x", arg: K, scope: !subprogram,
  …)` and an `llvm.dbg.declare` against its alloca. (Function
  params already get allocas via `__alloca_struct_params` and the
  scalar-param alloca pass.)

- Mutable `:~`-bindings need special treatment under SSA: the
  alloca pattern already handles this (every mutable binding is a
  ptr-to-storage), so `llvm.dbg.declare` works as is.

- Declare the intrinsic in the compiler preamble:
  `declare void @llvm.dbg.declare(metadata, metadata, metadata)`.

**Verification:**
- `gdb -batch /tmp/h -ex 'break foo' -ex 'run' -ex 'info locals' -ex 'print x'`
  prints `x = 42` (or whatever).
- `print arg_name` for function parameters works.

**Acceptance:** every `:` and `:~` binding visible by name in gdb.
`print` returns the current value, not "no symbol".

**Estimated effort:** ~250 LOC, 3h. Type-id lookups (Phase 6) need
to be in place but can use a "fallback to i64" placeholder until
Phase 6 lands.

---

## Phase 6 — Types (`!DIBasicType` + `!DICompositeType`)

**Goal:** gdb prints variables with their NURL type names rendered
("i", "u8", "String", "( Vec u )", "HttpRequest"), and `ptype
HttpRequest` shows the struct field layout with names + types.

**Scope:**

- Type-id table: a sym handle keyed by LLVM type string
  (`i64` / `%String` / `%Vec__i8`) → metadata id. Created lazily on
  first use.

- Basic types — emitted once at module-init:
  - `i` (i64) → `!DIBasicType(name: "i", size: 64, encoding: DW_ATE_signed)`
  - `u`/`u8` (i8) → `... encoding: DW_ATE_unsigned, size: 8`
  - `u16` / `u32` / `u64` / `i8` / `i16` / `i32` — analogous.
  - `b` (i1) → `... encoding: DW_ATE_boolean, size: 1`
  - `f` (double) → `... encoding: DW_ATE_float, size: 64`
  - `f32` → `... size: 32`
  - `s` / `*u` / etc. (`i8*`) → `!DIDerivedType(tag:
    DW_TAG_pointer_type, baseType: !i8_basictype, size: 64)`
  - `v` (void) → no metadata; functions returning v just omit
    `retainedNodes` for the return.

- Composite types (structs):
  - When `gen_struct_decl` registers a struct, also emit a
    `!DICompositeType(tag: DW_TAG_structure_type, name: "Foo",
    size: <bits>, file: !F, line: N, elements: !{!F1, !F2, …})`.
  - Each field is a `!DIDerivedType(tag: DW_TAG_member,
    name: "x", baseType: !T, offset: …, size: …)`.
  - Generic struct instantiations get one composite type per
    monomorphisation, with the substituted type names in the
    `name` field.

- Closures (`{ fn_ptr, env_ptr }`) — a struct with two pointer
  members. Synthesize names like "closure_fn" and "closure_env".

- Update Phase 5's `gen_let_or_struct` to look up the binding's
  LLVM type in the type-id table and use the returned id in
  `!DILocalVariable.type`.

**Verification:**
- `gdb -ex 'ptype HttpRequest'` lists every field with NURL name.
- `gdb -ex 'print req'` renders the whole struct value, not as a
  raw blob.
- `gdb -ex 'print . r status'` works (or whatever the equivalent
  is for accessing fields from gdb's expression evaluator —
  realistically NURL's `.`-syntax won't parse, but `req.status`
  will if we lay out names right).

**Acceptance:** at least the primary stdlib types
(`HttpRequest`, `HttpResponse`, `String`, `Vec[u]`, `Json`,
`McpRegistry`) render with field names in `gdb ptype`.

**Estimated effort:** ~400 LOC, 4-6h. Biggest variable-cost phase
because of the per-struct-instantiation work.

---

## Phase 7 — Generic instantiations + traits + impls

**Goal:** monomorphisations of `vec_push [String]` show up as
distinct functions in backtraces, with the substituted type
visible. Trait method dispatches resolve to the concrete impl
in source.

**Scope:**

- `emit_one_instantiation`: thread `g_dbg_current_subprogram`
  through generic substitution. Each instantiation gets its own
  DISubprogram with a name like `vec_push__String` (the mangled
  name) and the original generic-decl's source line.

- Trait impl method emission: same treatment — each
  `method_for_Type` emit gets a DISubprogram pointing at the
  `% Trait { @ method ... }`-decl line.

**Verification:**
- A program calling `vec_push [String] v x` shows
  `vec_push__String at vec.nu:N` in backtraces, not just
  `vec_push`.

**Acceptance:** generic + trait calls aren't anonymized in
backtraces.

**Estimated effort:** ~150 LOC, 2h.

---

## Phase 8 — Frame info (`.eh_frame` / unwinding)

**Goal:** crash backtraces (segfault, abort, ASan report) resolve
to `.nu` source lines, not just hex addresses. NURL's `panic` +
`recover` infrastructure (runtime.c §20, setjmp/longjmp-based)
already works at the C level; we want the host process to print
NURL-source frames in the panic message.

**Scope:**

- clang's `-g` flag generates `.eh_frame` automatically when fed
  IR with DWARF debug info. Phase 1's `nurl.sh --debug` already
  adds `-g` to the link, so this phase is largely "verify it
  works end-to-end".

- runtime.c's `nurl_panic_print` (if it exists; otherwise add
  one) should call `backtrace_symbols_fd` or `libunwind` and dump
  the resulting frames to stderr. The frames will use DWARF info
  if present.

- ASan integration: ASan already uses DWARF for its own crash
  reports. After Phase 4 lands, ASan reports will start showing
  `.nu:N` source locations automatically.

**Verification:**
- `( nurl_print (. p -1) )` (deliberate null deref) under
  `--san` prints a backtrace with `.nu:N` frames, not just
  raw addresses.
- `panic` from NURL code surfaces in `recover`'s payload with
  the panicking-site source location.

**Acceptance:** every sanitizer report and panic in
`compiler/tests/` resolves to a `.nu:N` frame in the failing
test.

**Estimated effort:** ~100 LOC (mostly runtime.c), 1-2h. Likely
to need iteration on libunwind/backtrace-symbols compatibility.

---

## Phase 9 — Regression tests + CI

**Goal:** a `compiler/tests/dwarf_*.nu` suite that drives gdb in
batch mode and asserts the expected source-level behaviour. Runs as
part of the regular `run_tests.sh` when gdb is on `$PATH`.

**Scope:**

- `compiler/tests/dwarf_basic.nu` — a small program with one
  function, one local variable, one struct field access. Test
  harness shell script:
  - Builds with `nurlc --g`.
  - Runs `gdb -batch -ex 'break dwarf_basic.nu:N' -ex 'run' -ex
    'info locals' -ex 'print x' -ex 'backtrace' -ex 'quit'
    /tmp/dwarf_basic`.
  - Asserts the output contains the expected strings.

- `compiler/tests/dwarf_struct.nu` — exercises field-level
  rendering via `ptype` + nested struct printing.

- `compiler/tests/dwarf_generic.nu` — exercises monomorphised
  function names in backtraces.

- `compiler/tests/dwarf_panic.nu` — deliberately panics; asserts
  the recovered panic info includes a source-line frame.

- `tools/dwarf_dump_check.sh` — runs `llvm-dwarfdump --debug-info
  /tmp/dwarf_basic` and asserts it parses without errors. This
  catches malformed metadata that the LLVM verifier might miss
  (verifier is structural; dwarfdump is semantic).

**Verification:** all four tests pass on a host with gdb +
llvm-dwarfdump installed; gracefully skipped when those tools
aren't present.

**Acceptance:** baseline locks in the gdb-batch output strings;
future regressions surface as testresults-vs-correct diffs.

**Estimated effort:** ~300 LOC of tests + shell glue, 3h.

---

## Phase 10 — Documentation + integration

**Goal:** README has a "Debugging" section, examples show how to
use gdb + lldb on NURL binaries, and the workflow is friction-free
for someone new to the project.

**Scope:**

- `README.md` "Debugging" section:
  - `./nurl.sh --debug examples/foo.nu` builds with DWARF.
  - `gdb examples/foo` (after build) drops into source-level debug.
  - `lldb` should work too (LLVM toolchain shares DWARF).
  - ASan/UBSan crashes now resolve to `.nu` source.

- `docs/DEBUGGING.md` — longer-form: how to set breakpoints,
  inspect variables, walk a panic chain, attach to a running
  process.

- `nurl.sh` usage line updated to mention `--debug`.

- `nurlc` usage line mentions `--g`.

- CHANGELOG + ROADMAP entries.

- This file (`DWARF.md`) gets a "DONE" line at the top pointing at
  the final shipping commit.

**Estimated effort:** ~150 LOC of docs, 2h.

---

## Total effort budget

| Phase | Hours | LOC | Risk |
|---|---|---|---|
| 0 — emit refactor | 3-4 | ~400 | Low (mechanical) |
| 1 — module metadata | 2 | ~200 | Low |
| 2+3 — DISubprogram + per-call dbg | 4-6 | ~400 | Medium (verifier strictness) |
| 4 — DILocation per stmt | 3-4 | ~300 | Medium (scope tracking) |
| 5 — DILocalVariable | 3 | ~250 | Low |
| 6 — types | 4-6 | ~400 | Medium (struct layout details) |
| 7 — generics + traits | 2 | ~150 | Low |
| 8 — eh_frame | 1-2 | ~100 | Low (clang does most of it) |
| 9 — tests | 3 | ~300 | Low |
| 10 — docs | 2 | ~150 | None |
| **TOTAL** | **27-34h** | **~2650** | — |

**Realistic packaging:**

- Session A (8h): Phases 0 + 1 — refactor + module metadata. Tree
  stays green; nothing user-facing yet.
- Session B (10h): Phases 2 + 3 + 4 — the user-visible MVP. After
  this, `break / step / backtrace` works.
- Session C (8h): Phases 5 + 6 — `print x` shows names + types.
- Session D (8h): Phases 7 + 8 + 9 + 10 — polish + tests + docs.

Four sessions × 8-10h each.

---

## Things to watch

1. **Bootstrap fixed point.** Every phase MUST keep it byte-
   identical when `--g` is OFF (which is the default). Run
   `./build.sh` after every chunk of changes; the build itself
   verifies stage1 ≡ stage2 IR.

2. **Sanitizer suite.** Run `./build.sh --san && bash
   compiler/tests/run_san_tests.sh` periodically. The metadata
   emit pass adds string allocations that LSan would notice.

3. **LLVM version sensitivity.** Some DWARF metadata shapes
   changed between LLVM 14 and LLVM 17 (especially
   `!DICompileUnit` field names). Test against the clang version
   on the CI runners (currently host clang). Pin a minimum
   version in build.sh if needed.

4. **`generic` test in `compiler/tests/`.** Already covers
   generic monomorphisation; Phase 7 should preserve its baseline.

5. **`nurlfmt`.** Round-trips source via the same lexer; line
   numbers should match. If `nurlfmt` reformats whitespace in a
   way that shifts line numbers, the debug info points at the
   wrong line. Verify `nurlfmt`-formatted source produces the
   same DILocations as the original.

6. **WASM target.** `wasmnurl.sh` compiles to wasm32-wasi. WASM
   doesn't support DWARF the same way. Phase 1 should add a
   `--g` no-op for the wasm path (or refuse).

7. **The `--g` flag itself.** Two names in flight:
   `nurlc --g` (compiler-side) and `nurl.sh --debug` (driver-
   side). Use both names, OR pick one and document the other as
   an alias. Don't surprise users.

---

## Quick-start when starting a new session

1. `git log --oneline | head` — find the last DWARF-related commit.
2. Re-read this file's "Things to watch" section.
3. Re-read the changelog entries for any DWARF work already shipped.
4. Run `./build.sh` to confirm tree is green BEFORE starting.
5. Pick the next phase. Read its "Scope" + "Verification" sections.
6. After every chunk: `./build.sh` to verify bootstrap.
7. End of session: commit with a clear "DWARF Phase N: …" message,
   update this file's "DONE" marker (when added).

---

*Status: Phases 0/1/2+3/4/5/6/8/9/10 landed; Phase 7 deferred; Phase 6
composite types are the open follow-up. Last updated 2026-05-19.*
